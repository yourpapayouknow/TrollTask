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
        sc_req([occ[@"status"] isEqual:@"triggered"] && [occ[@"scheduled_at"] isEqual:task[@"due_at"]],@"Occurrence保留原始绝对时刻");
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
int main(void) {
    @autoreleasepool {
        char folder[]="/tmp/trolltask-scheduler.XXXXXX"; assert(mkdtemp(folder));
        NSString *path=[@(folder) stringByAppendingPathComponent:@"tasks.sqlite3"];
        ScStore *reader=[[ScStore alloc] initAt:path error:nil]; TaskStore *writer=[[TaskStore alloc] initAt:path error:nil]; assert(reader && writer);
        sc_delays=[NSMutableArray array]; sc_records=[NSMutableArray array]; sc_idle(reader,writer); sc_due(reader,writer); sc_restart(reader,writer); sc_fault(reader,writer);
        double max=0,sum=0; for (NSNumber *delay in sc_delays) { max=fmax(max,delay.doubleValue); sum+=delay.doubleValue; }
        printf("TaskScheduler: %lu checks passed; %lu actual triggers, max lateness %.6fs, mean %.6fs; idle/future/active DB reads unchanged\n",(unsigned long)sc_checks,(unsigned long)sc_delays.count,max,sum/sc_delays.count);
        NSData *report=[NSJSONSerialization dataWithJSONObject:@{@"checks":@(sc_checks),@"records":sc_records,@"max_lateness":@(max),@"mean_lateness":@(sum/sc_delays.count)} options:NSJSONWritingPrettyPrinted error:nil];
        assert([report writeToFile:@"build/TaskSchedulerReport.json" atomically:YES]);
        assert([NSFileManager.defaultManager removeItemAtPath:@(folder) error:nil]); return 0;
    }
}
