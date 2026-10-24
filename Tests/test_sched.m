#import "LBHead.h"

static NSUInteger sc_checks;
static NSDictionary *sc_alert;
static NSMutableArray *sc_events;
static TaskScheduler *sc_sched;
static NSMutableArray *sc_delays;
static NSMutableArray *sc_records;

// 统计真实数据库读取并提供一次可恢复失败。
@interface ScStore : TaskStore
@property(atomic) NSUInteger plans;
@property(atomic) NSUInteger revisions;
@property(atomic) NSUInteger failReads;
@end
@implementation ScStore
// 统计计划读取及注入明确IO错误。
- (NSDictionary *)planAt:(NSTimeInterval)stamp error:(NSError **)error {
    self.plans++;
    if (self.failReads) { self.failReads--; if (error) *error = [NSError errorWithDomain:@"scheduler-test" code:SQLITE_IOERR userInfo:@{NSLocalizedDescriptionKey:@"单次读取失败"}]; return nil; }
    return [super planAt:stamp error:error];
}
// 统计修订号读取，区分事件重读和固定轮询。
- (long long)revision:(NSError **)error { self.revisions++; return [super revision:error]; }
@end

// 保存明确断言和失败名称。
static void sc_req(BOOL valid, NSString *name) {
    if (!valid) { NSLog(@"调度失败：%@",name); abort(); } sc_checks++;
}
// 运行主线程展示队列，保留有界等待。
static void sc_wait(NSTimeInterval seconds, BOOL (^check)(void), NSString *name) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!check() && end.timeIntervalSinceNow > 0) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.01,true);
    sc_req(check(),name);
}
// 等待真实时间推进而不阻塞调度队列。
static void sc_span(NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (end.timeIntervalSinceNow > 0) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.01,true);
}
// 通过独立写入连接创建真实绝对时间任务。
static NSDictionary *sc_mk(TaskStore *writer, NSTimeInterval stamp) {
    NSDictionary *task = [writer crtTsk:@{@"title":@"调度验收",@"due_at":@(stamp),@"timezone_id":@"UTC"} error:nil]; sc_req(task!=nil,@"测试任务写入"); return task;
}
// 运行唯一生产调度实现并保留实际回调。
static void sc_start(ScStore *reader) {
    sc_alert = nil; sc_events = [NSMutableArray array];
    sc_sched = [[TaskScheduler alloc] initStore:reader handler:^(NSDictionary *alert, NSError *error) {
        sc_alert = alert; [sc_events addObject:@{@"alert":alert ?: (id)NSNull.null,@"error":error ?: (id)NSNull.null,@"at":@(NSDate.date.timeIntervalSince1970)}];
    }]; sc_req([sc_sched start:nil],@"原生调度启动");
}
// 验证空闲、远期等待、编辑删除打断及系统通知。
static void sc_idle(ScStore *reader, TaskStore *writer) {
    sc_start(reader); sc_req([sc_sched start:nil],@"重复启动幂等");
    sc_wait(1,^BOOL { return reader.plans>0; },@"启动读取一致计划"); sc_span(0.1);
    NSUInteger plans=reader.plans, revisions=reader.revisions; sc_span(1.3);
    sc_req(reader.plans==plans && reader.revisions==revisions,@"空任务不能周期性读取计划或修订号");
    sc_req(sc_sched.nextFireAt==nil,@"空任务无待触发时刻");
    NSDictionary *task = sc_mk(writer,NSDate.date.timeIntervalSince1970+60); NSString *uuid=task[@"task_id"];
    sc_wait(1,^BOOL { return fabs(sc_sched.nextFireAt.timeIntervalSince1970-[task[@"due_at"] doubleValue])<0.001; },@"新建立即打断空闲并设置nextFireAt");
    sc_span(0.1); plans=reader.plans; revisions=reader.revisions; sc_span(1.2);
    sc_req(reader.plans==plans && reader.revisions==revisions,@"远期任务等待不扫描数据库");
    NSTimeInterval old=NSDate.date.timeIntervalSince1970+0.7, future=old+2;
    sc_req([writer updTsk:uuid fields:@{@"due_at":@(old)} error:nil],@"编辑临近绝对时间");
    sc_wait(1,^BOOL { return fabs(sc_sched.nextFireAt.timeIntervalSince1970-old)<0.001; },@"编辑立即替换原计时");
    [sc_sched refresh]; sc_span(0.1); sc_req([writer lsOcc:uuid error:nil].count==0,@"到期前重读不会提前生成Occurrence");
    sc_req([writer updTsk:uuid fields:@{@"due_at":@(future)} error:nil],@"将临近任务延期");
    sc_wait(1,^BOOL { return fabs(sc_sched.nextFireAt.timeIntervalSince1970-future)<0.001; },@"新绝对时刻替换旧时刻");
    sc_span(0.8); sc_req([writer lsOcc:uuid error:nil].count==0,@"跨过旧时刻没有旧触发");
    plans=reader.plans; [NSNotificationCenter.defaultCenter postNotificationName:NSSystemClockDidChangeNotification object:nil];
    sc_wait(1,^BOOL { return reader.plans>plans; },@"系统时钟变化重建绝对计划");
    plans=reader.plans; [NSNotificationCenter.defaultCenter postNotificationName:NSSystemTimeZoneDidChangeNotification object:nil];
    sc_wait(1,^BOOL { return reader.plans>plans; },@"系统时区变化重建计划");
    sc_req([writer delTsk:uuid error:nil],@"删除待触发任务");
    sc_wait(1,^BOOL { return sc_sched.nextFireAt==nil; },@"删除立即取消未来计时");
    sc_span(2.1); sc_req([writer lsOcc:uuid error:nil].count==0,@"删除后跨过到期仍无触发");
    [sc_sched stop]; sc_span(0.05);
}
// 验证全部到期轮次、误差上限及处理后立即推进。
static void sc_due(ScStore *reader, TaskStore *writer) {
    sc_start(reader); NSMutableArray *tasks=[NSMutableArray array]; NSTimeInterval base=NSDate.date.timeIntervalSince1970+0.5;
    for (NSUInteger index=0; index<20; index++) [tasks addObject:sc_mk(writer,base+index*0.07)];
    sc_wait(4,^BOOL { for (NSDictionary *task in tasks) if ([writer lsOcc:task[@"task_id"] error:nil].count!=1) return NO; return YES; },@"当前HUD未处理也按时生成其他到期Occurrence");
    for (NSDictionary *task in tasks) {
        NSDictionary *occ=[writer lsOcc:task[@"task_id"] error:nil].firstObject;
        double delay=[occ[@"triggered_at"] doubleValue]-[task[@"due_at"] doubleValue]; [sc_delays addObject:@(delay)];
        [sc_records addObject:@{@"task_id":task[@"task_id"],@"due_at":task[@"due_at"],@"occurrence":occ,@"lateness":@(delay)}];
        sc_req(delay>=0 && delay<2,@"正常到期误差小于两秒且不提前触发");
        sc_req([occ[@"status"] isEqual:@"presented"] && [occ[@"scheduled_at"] isEqual:task[@"due_at"]],@"Occurrence保留原始绝对时刻");
    }
    sc_wait(1,^BOOL { return [sc_alert[@"task_id"] isEqual:tasks.firstObject[@"task_id"]]; },@"HUD按最早任务逐条展示");
    sc_span(0.1); NSUInteger plans=reader.plans,revisions=reader.revisions; sc_span(1.2);
    sc_req(reader.plans==plans && reader.revisions==revisions && sc_sched.nextFireAt==nil,@"已触发队列等待处理时无周期性查询");
    for (NSUInteger index=0; index<tasks.count; index++) {
        NSString *id=tasks[index][@"task_id"];
        sc_wait(1,^BOOL { return [sc_alert[@"task_id"] isEqual:id]; },@"当前任务按到期顺序呈现");
        [sc_sched act:@"complete" until:nil occID:sc_alert[@"occurrence_id"]];
        sc_wait(0.8,^BOOL { return index+1==tasks.count ? sc_alert==nil : [sc_alert[@"task_id"] isEqual:tasks[index+1][@"task_id"]]; },@"处理完成立即推进下一待办");
    }
    sc_req([writer lsPnd:nil].count==0,@"队列全部处理完进入空闲"); [sc_sched stop]; sc_span(0.05);
}
// 验证停止重启恢复已触发轮次且不会再次认领。
static void sc_restart(ScStore *reader, TaskStore *writer) {
    NSDictionary *task=sc_mk(writer,NSDate.date.timeIntervalSince1970-1); NSString *id=task[@"task_id"];
    sc_start(reader); sc_wait(1,^BOOL { return [sc_alert[@"task_id"] isEqual:id]; },@"启动立即认领已到期任务");
    NSDictionary *occ=[writer lsOcc:id error:nil].firstObject; [sc_sched stop]; [sc_sched start:nil];
    sc_wait(1,^BOOL { return [sc_alert[@"occurrence_id"] isEqual:occ[@"occurrence_id"]]; },@"停止重启复用原Occurrence");
    sc_span(0.1); sc_req([writer lsOcc:id error:nil].count==1 && [[writer lsOcc:id error:nil].firstObject[@"triggered_at"] isEqual:occ[@"triggered_at"]],@"重启不重复认领或修改原触发记录");
    sc_req([writer delTsk:id error:nil],@"外部删除当前展示任务");
    sc_wait(1,^BOOL { return sc_alert==nil; },@"外部删除立即撤下当前提醒"); [sc_sched stop]; sc_span(0.05);
    NSError *error=nil; TaskScheduler *missing=[[TaskScheduler alloc] initStore:nil handler:^(__unused NSDictionary *a,__unused NSError *e){}];
    sc_req(![missing start:&error] && error.code==SQLITE_CANTOPEN,@"存储缺失明确启动失败");
}
// 验证数据库失败退避恢复且恢复后再次静默等待。
static void sc_fault(ScStore *reader, TaskStore *writer) {
    NSDictionary *task=sc_mk(writer,NSDate.date.timeIntervalSince1970+60); reader.failReads=1; sc_start(reader);
    sc_wait(1,^BOOL { return [sc_events.lastObject[@"error"] isKindOfClass:NSError.class]; },@"数据库读取失败有明确错误");
    sc_req(sc_sched.nextFireAt==nil,@"失败不保留旧触发时刻");
    sc_wait(2,^BOOL { return fabs(sc_sched.nextFireAt.timeIntervalSince1970-[task[@"due_at"] doubleValue])<0.001; },@"单次故障通过有界退避恢复");
    sc_span(0.1); NSUInteger plans=reader.plans,revisions=reader.revisions; sc_span(1.2);
    sc_req(reader.plans==plans && reader.revisions==revisions,@"故障恢复后取消周期性恢复读取");
    sc_req([writer delTsk:task[@"task_id"] error:nil],@"清理故障测试任务"); [sc_sched stop]; sc_span(0.05);
}
// 独立运行真实调度器与隔离数据库，不访问生产数据。
// 当前附件未提交时后续到期排队，失败保留原轮次，重试只推进一次。
static void sc_overlap(ScStore *reader, TaskStore *writer) {
    NSDictionary *a=sc_mk(writer,NSDate.date.timeIntervalSince1970-1);
    sc_start(reader);sc_wait(1,^BOOL{return [sc_alert[@"task_id"] isEqual:a[@"task_id"]];},@"先展示A");
    NSString *aid=sc_alert[@"occurrence_id"];
    NSDictionary *b=sc_mk(writer,NSDate.date.timeIntervalSince1970+0.2);
    for (NSUInteger i=0;i<30;i++) notify_post(reader.changeNote.UTF8String);
    sc_wait(1,^BOOL{return [writer lsOcc:b[@"task_id"] error:nil].count==1;},@"A未提交时B照常登记到期");
    sc_req([sc_alert[@"occurrence_id"] isEqual:aid],@"B到期不替换A");
    for (NSDictionary *event in sc_events) sc_req(![event[@"alert"] isKindOfClass:NSDictionary.class] || ![event[@"alert"][@"task_id"] isEqual:b[@"task_id"]],@"等待期间B不抢占");
    [sc_sched check:aid attachments:@[]];
    sc_wait(1,^BOOL{return [sc_events.lastObject[@"error"] isKindOfClass:NSError.class];},@"无效提交回报失败");
    sc_req([sc_alert[@"occurrence_id"] isEqual:aid],@"提交失败仍保留A并继续等待");
    NSDictionary *file=@{@"method":@"file",@"image":[@"proof" dataUsingEncoding:NSUTF8StringEncoding],@"name":@"a.txt",@"content_type":@"public.plain-text"};
    for (NSUInteger i=0;i<30;i++) {[sc_sched check:aid attachments:@[file]];notify_post(reader.changeNote.UTF8String);}
    sc_wait(1,^BOOL{return [sc_alert[@"task_id"] isEqual:b[@"task_id"]];},@"A提交成功立即推进B");
    sc_req([writer lsChk:aid images:YES error:nil].count==1 && [[writer rdTsk:b[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"],@"重复A提交不重复写附件或误完成B");
    NSUInteger firstB=0;for (;firstB<sc_events.count;firstB++) if ([sc_events[firstB][@"alert"] isKindOfClass:NSDictionary.class] && [sc_events[firstB][@"alert"][@"task_id"] isEqual:b[@"task_id"]]) break;
    sc_req(firstB>0 && sc_events[firstB-1][@"alert"]==NSNull.null,@"推进B前解除A全屏窗口");
    [sc_sched act:@"complete" until:nil occID:aid];sc_span(0.05);
    sc_req([sc_alert[@"task_id"] isEqual:b[@"task_id"]],@"过时A动作不能处理B");
    [sc_sched act:@"complete" until:nil occID:sc_alert[@"occurrence_id"]];sc_wait(1,^BOOL{return sc_alert==nil;},@"B完成后进入空闲");
    [sc_sched stop];sc_span(0.05);
}
// 同刻任务按原时间和UUID稳定排队，通知风暴不重复呈现。
static void sc_queue(ScStore *reader, TaskStore *writer) {
    NSTimeInterval stamp=NSDate.date.timeIntervalSince1970-2;
    NSMutableArray *tasks=[NSMutableArray array];
    for (NSUInteger i=0;i<5;i++) [tasks addObject:sc_mk(writer,stamp)];
    [tasks sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"task_id"] compare:b[@"task_id"]];}];
    sc_start(reader);sc_wait(1,^BOOL{return [sc_alert[@"task_id"] isEqual:tasks[0][@"task_id"]];},@"同刻任务以UUID稳定决定队首");
    sc_wait(1,^BOOL{for (NSDictionary *task in tasks) if ([writer lsOcc:task[@"task_id"] error:nil].count!=1) return NO;return YES;},@"同刻五任务各有一个持久轮次");
    sc_req([sc_alert[@"occurrence_at"] isEqual:@(stamp)],@"单次身份保留原定occurrence_at");
    sc_span(0.1);NSUInteger events=sc_events.count;NSString *first=sc_alert[@"occurrence_id"];
    for (NSUInteger i=0;i<100;i++) {
        notify_post(reader.changeNote.UTF8String);[sc_sched refresh];
        [NSNotificationCenter.defaultCenter postNotificationName:NSSystemClockDidChangeNotification object:nil];
        [NSNotificationCenter.defaultCenter postNotificationName:NSSystemTimeZoneDidChangeNotification object:nil];
    }
    sc_span(0.3);sc_req(sc_events.count==events,@"重复timer重读数据库和时钟事件不重复呈现HUD");
    for (NSDictionary *task in tasks) sc_req([writer lsOcc:task[@"task_id"] error:nil].count==1,@"通知风暴不新增同次轮次");
    for (NSUInteger i=0;i<20;i++) [sc_sched hold:@"snooze" occID:first];
    sc_wait(1,^BOOL{return [sc_alert[@"task_id"] isEqual:tasks[1][@"task_id"]];},@"五分钟延后后立即展示下一项");
    NSDictionary *held=[writer lsOcc:tasks[0][@"task_id"] error:nil].firstObject;
    sc_req([held[@"status"] isEqual:@"snoozed"] && [held[@"defer_count"] intValue]==1 && [held[@"scheduled_at"] isEqual:@(stamp)],@"连续延后只消耗一次且原身份不变");
    sc_req([writer rsmOcc:first error:nil],@"模拟边栏主动恢复旧轮次");sc_span(0.1);
    sc_req([sc_alert[@"task_id"] isEqual:tasks[1][@"task_id"]],@"已恢复早期轮次不抢占当前任务");
    [sc_sched stop];sc_span(0.05);sc_start(reader);
    sc_wait(1,^BOOL{return [sc_alert[@"occurrence_id"] isEqual:first];},@"重建队列按原时间恢复稳定次序");
    for (NSDictionary *task in tasks) {
        sc_wait(1,^BOOL{return [sc_alert[@"task_id"] isEqual:task[@"task_id"]];},@"同刻队列逐一稳定推进");
        NSString *current=sc_alert[@"occurrence_id"];
        for (NSUInteger i=0;i<15;i++) [sc_sched act:@"complete" until:nil occID:current];
        sc_wait(1,^BOOL{return ![sc_alert[@"occurrence_id"] isEqual:current];},@"重复操作只退出本条一次");
    }
    sc_req(sc_alert==nil,@"全部同刻轮次完成后没有残留窗口");
    [sc_sched stop];sc_span(0.05);sc_start(reader);sc_span(0.1);
    sc_req(sc_alert==nil,@"重启后所有Resolved均不得重现");[sc_sched stop];sc_span(0.05);
}
// 子进程运行生产调度器并立即写出真实呈现身份。
static int sc_child(NSString *path,NSString *log) {
    TaskStore *store=[[TaskStore alloc] initAt:path error:nil];assert(store);
    TaskScheduler *scheduler=[[TaskScheduler alloc] initStore:store handler:^(NSDictionary *alert,NSError *error){
        assert(!error);if (!alert) return;
        NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"task_id":alert[@"task_id"],@"occurrence_id":alert[@"occurrence_id"]} options:0 error:nil];
        [data writeToFile:log atomically:YES];
    }];assert([scheduler start:nil]);CFRunLoopRun();return 0;
}
// 强杀真实调度进程后使用同库恢复，不重写触发记录或复活已完成项。
static void sc_crash(TaskStore *writer,NSString *path,NSString *root) {
    NSDictionary *a=sc_mk(writer,NSDate.date.timeIntervalSince1970-2),*b=sc_mk(writer,NSDate.date.timeIntervalSince1970-1);
    NSString *log=[root stringByAppendingPathComponent:@"child.json"];
    NSString *occID=nil;NSNumber *triggered=nil;
    for (NSUInteger run=0;run<3;run++) {
        [NSFileManager.defaultManager removeItemAtPath:log error:nil];
        NSTask *child=[NSTask new];child.executableURL=[NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];child.arguments=@[@"--child",path,log];
        sc_req([child launchAndReturnError:nil],@"隔离调度子进程启动");
        sc_wait(2,^BOOL{return [NSFileManager.defaultManager fileExistsAtPath:log];},@"子进程持久认领后实际呈现");
        NSDictionary *seen=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:log] options:0 error:nil];
        NSDictionary *row=[writer lsOcc:(run==2?b:a)[@"task_id"] error:nil].firstObject;
        sc_req([seen[@"task_id"] isEqual:(run==2?b:a)[@"task_id"]],@"崩溃重启恢复未处理队首且跳过Resolved");
        if (run==0) {occID=row[@"occurrence_id"];triggered=row[@"triggered_at"];}
        if (run==1) sc_req([row[@"occurrence_id"] isEqual:occID] && [row[@"triggered_at"] isEqual:triggered],@"SIGKILL恢复复用原身份和触发时间");
        kill(child.processIdentifier,SIGKILL);[child waitUntilExit];
        sc_req(child.terminationReason==NSTaskTerminationReasonUncaughtSignal,@"确认为进程异常终止");
        if (run==1) sc_req([writer actOcc:occID action:@"complete" until:nil error:nil],@"完成已恢复的第一项");
    }
    sc_req([writer actOcc:[writer lsOcc:b[@"task_id"] error:nil].firstObject[@"occurrence_id"] action:@"complete" until:nil error:nil],@"清理第二个异常恢复测试项");
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if (argc==4 && strcmp(argv[1],"--child")==0) return sc_child(@(argv[2]),@(argv[3]));
        char folder[]="/tmp/trolltask-scheduler.XXXXXX"; assert(mkdtemp(folder));
        NSString *path=[@(folder) stringByAppendingPathComponent:@"tasks.sqlite3"];
        ScStore *reader=[[ScStore alloc] initAt:path error:nil]; TaskStore *writer=[[TaskStore alloc] initAt:path error:nil]; assert(reader && writer);
        sc_delays=[NSMutableArray array]; sc_records=[NSMutableArray array]; sc_idle(reader,writer); sc_due(reader,writer); sc_restart(reader,writer); sc_fault(reader,writer);sc_overlap(reader,writer);sc_queue(reader,writer);sc_crash(writer,path,@(folder));
        double max=0,sum=0; for (NSNumber *delay in sc_delays) { max=fmax(max,delay.doubleValue); sum+=delay.doubleValue; }
        printf("TaskScheduler: %lu checks passed; %lu actual triggers, max lateness %.6fs, mean %.6fs; idle/future/active DB reads unchanged\n",(unsigned long)sc_checks,(unsigned long)sc_delays.count,max,sum/sc_delays.count);
        NSData *report=[NSJSONSerialization dataWithJSONObject:@{@"checks":@(sc_checks),@"records":sc_records,@"max_lateness":@(max),@"mean_lateness":@(sum/sc_delays.count)} options:NSJSONWritingPrettyPrinted error:nil];
        assert([report writeToFile:@"build/TaskSchedulerReport.json" atomically:YES]);
        assert([NSFileManager.defaultManager removeItemAtPath:@(folder) error:nil]); return 0;
    }
}
