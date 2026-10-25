#import "LBHead.h"

NSString *lb_tstpath;
const char *lb_tstlock;
static NSString *rm_root;
static NSUInteger rm_checks;

// 记录服务断言并保留明确失败名称。
static void rm_req(BOOL valid, NSString *name) { if (!valid) { NSLog(@"服务失败：%@",name); abort(); } rm_checks++; }
// 仅等待本次隔离进程和数据，保留有界超时。
static void rm_wt(NSTimeInterval duration, BOOL (^check)(void), NSString *name) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:duration];
    while (!check() && end.timeIntervalSinceNow>0) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.01,true);
    rm_req(check(),name);
}
// 解析隔离进程留下的逐条JSON证据。
static NSArray *rm_rows(NSString *name) {
    NSString *text=[NSString stringWithContentsOfFile:[rm_root stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *rows=[NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) if (line.length) {
        id row=[NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]; if (row) [rows addObject:row];
    } return rows;
}
// 追加真实服务启动、提醒和停止记录。
static void rm_evt(NSString *name, NSDictionary *row) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:row options:0 error:nil];
    int handle=open([rm_root stringByAppendingPathComponent:name].fileSystemRepresentation,O_WRONLY|O_CREAT|O_APPEND|O_CLOEXEC,0600);
    assert(handle>=0 && write(handle,data.bytes,data.length)==(ssize_t)data.length && write(handle,"\n",1)==1); close(handle);
}
// 检查数据库连接在进程退出前已经全部关闭。
static NSUInteger rm_fd(NSString *path) {
    NSUInteger count=0;
    for (int fd=0;fd<getdtablesize();fd++) { char name[PATH_MAX]={0}; if (fcntl(fd,F_GETPATH,name)==0 && [@(name) hasPrefix:path]) count++; }
    return count;
}
// 仅在隔离夹具中把已选图片交给独立服务的生产提交入口。
static void rm_sub(TaskReminder *service,NSDictionary *alert) {
        if (alert) {
            NSString *file=[rm_root stringByAppendingPathComponent:[NSString stringWithFormat:@"submit-%@.png",alert[@"occurrence_id"]]];
            NSData *image=[NSData dataWithContentsOfFile:file];
            if (image) {
                assert(unlink(file.fileSystemRepresentation)==0);
                rm_evt(@"checkins.jsonl",@{@"pid":@(getpid()),@"parent":@(getppid()),@"occurrence_id":alert[@"occurrence_id"],@"bytes":@(image.length)});
                NSMutableArray *attachments=[NSMutableArray array];
                for (NSUInteger index=0;index<TS_ATT_MAX;index++) [attachments addObject:@{@"method":@"image",@"image":image}];
                [service check:alert[@"occurrence_id"] attachments:attachments];
            }
        }
}
// 在独立子进程运行生产TaskReminder，不连接生产路径或私有窗口。
static int rm_svc(NSString *path) {
    for (int descriptor=0;descriptor<3;descriptor++) assert(fcntl(descriptor,F_GETFD)>=0);
    __block __weak TaskReminder *weakService;
    __block NSDictionary *current;
    TaskReminder *service=[[TaskReminder alloc] initAt:path handler:^(NSDictionary *alert,NSError *error) {
        assert(!error); current=alert; rm_evt(@"events.jsonl",@{@"task_id":alert[@"task_id"] ?: (id)NSNull.null,@"at":@(NSDate.date.timeIntervalSince1970)});
    } cleanup:^{
        rm_evt(@"cleanup.jsonl",@{@"pid":@(getpid()),@"lock_held":@(lb_svcup()),@"db_fds":@(rm_fd(path))});
        NSString *again=[rm_root stringByAppendingPathComponent:@"reenable"];
        if ([NSFileManager.defaultManager fileExistsAtPath:again]) { unlink(again.fileSystemRepresentation); assert(lb_svcfg(@{@"enabled":@YES}) && lb_spawn()); }
    }
       finish:^(BOOL restart) { rm_evt(@"stops.jsonl",@{@"pid":@(getpid()),@"lock_held":@(lb_svcup()),@"db_fds":@(rm_fd(path)),@"at":@(NSDate.date.timeIntervalSince1970),@"restart":@(restart)}); if (restart) assert(lb_spawn()); exit(0); }];
    weakService=service; NSError *error=nil;
    if (![service open:&error]) return error.code==EWOULDBLOCK || error.code==ECANCELED ? 0 : 1;
    assert([service start:&error]);
    // 提交输入独立于展示回调，不要求重复呈现同一个HUD。
    int token=-1;
    NSString *input=[@"com.iwmei.taskforiwmei.test.submit." stringByAppendingString:rm_root.lastPathComponent];
    assert(notify_register_dispatch(input.UTF8String,&token,dispatch_get_main_queue(),^(__unused int value){rm_sub(weakService,current);})==NOTIFY_STATUS_OK);
    rm_evt(@"starts.jsonl",@{@"pid":@(getpid()),@"pgid":@(getpgrp()),@"parent":@(getppid())});
    CFRunLoopRun(); notify_cancel(token); [service stop]; return 0;
}
// 启动同一可执行程序的隔离主App或重复启动入口。
static NSTask *rm_chld(NSString *arg) {
    NSTask *child=[NSTask new]; child.executableURL=[NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]]; child.arguments=@[arg];
    rm_req([child launchAndReturnError:nil],@"隔离启动入口运行"); return child;
}
// 返回唯一实际启动服务的进程号。
static pid_t rm_pid(void) { return [rm_rows(@"starts.jsonl").lastObject[@"pid"] intValue]; }
// 校验每次停止的资源顺序和进程退出前数据库状态。
static void rm_end(NSUInteger count) {
    rm_wt(3,^BOOL { return rm_rows(@"stops.jsonl").count==count && !lb_svcup(); },@"服务停止并释放真实flock");
    NSDictionary *cleanup=rm_rows(@"cleanup.jsonl").lastObject,*stop=rm_rows(@"stops.jsonl").lastObject;
    rm_req([cleanup[@"lock_held"] boolValue] && ![stop[@"lock_held"] boolValue],@"窗口清理在释放单实例锁之前");
    rm_req([cleanup[@"db_fds"] unsignedIntegerValue]==0 && [stop[@"db_fds"] unsignedIntegerValue]==0,@"进程退出前SQLite及WAL连接已关闭");
}
// 验证锁竞争、显式关闭、缺失存储与禁用状态。
static void rm_unit(void) {
    NSString *path=[rm_root stringByAppendingPathComponent:@"owned.sqlite3"]; __block NSUInteger cleanup=0;
    TaskReminder *service=[[TaskReminder alloc] initAt:path handler:^(__unused NSDictionary *a,__unused NSError *e){} cleanup:^{ cleanup++; rm_req(lb_svcup() && rm_fd(path)==0,@"服务清理仍持锁且数据库已关闭"); } finish:^(__unused BOOL r){}];
    rm_req([service open:nil] && !service.running && lb_svcup(),@"窗口启动前加载存储和锁");
    rm_req([service start:nil] && [service start:nil] && service.running,@"同一服务重复启动幂等");
    NSError *error=nil;
    TaskReminder *duplicate=[[TaskReminder alloc] initAt:path handler:^(__unused NSDictionary *a,__unused NSError *e){} cleanup:^{} finish:^(__unused BOOL r){}];
    rm_req(![duplicate start:&error] && error.code==EWOULDBLOCK,@"锁竞争不会初始化第二个调度服务"); duplicate=nil;
    rm_req(lb_svcup() && service.running,@"失败竞争者不释放既有锁");
    [service stop]; [service stop]; rm_req(!service.running && !lb_svcup() && cleanup==1,@"重复停止仅清理一次"); service=nil;
    TaskReminder *missing=[[TaskReminder alloc] initAt:@"relative.sqlite3" handler:^(__unused NSDictionary *a,__unused NSError *e){} cleanup:^{} finish:^(__unused BOOL r){}];
    rm_req(![missing start:&error] && !lb_svcup(),@"数据库失败清除已取得锁"); missing=nil;
    rm_req([lb_rdstat()[@"state"] isEqual:@"数据库不可用"] && ![lb_rdstat()[@"running"] boolValue],@"真实数据库启动失败向App保留可理解状态");
    rm_req(lb_svcfg(@{@"enabled":@NO}),@"保存服务停用状态");
    TaskReminder *disabled=[[TaskReminder alloc] initAt:path handler:^(__unused NSDictionary *a,__unused NSError *e){} cleanup:^{} finish:^(__unused BOOL r){}];
    rm_req(![disabled start:&error] && error.code==ECANCELED && !lb_spawn(),@"服务禁用时拒绝创建后台进程"); disabled=nil;
    rm_req(lb_svcfg(@{@"enabled":@YES}),@"恢复隔离测试配置");
}
// 验证主App退出后，独立服务提交图片且新连接能读取完成记录。
static void rm_chk(TaskStore *writer, NSDictionary *task) {
    NSString *taskID=task[@"task_id"];
    rm_wt(3,^BOOL { return [writer lsOcc:taskID error:nil].count==1 && [rm_rows(@"events.jsonl").lastObject[@"task_id"] isEqual:taskID]; },@"退出后的服务已呈现图片打卡任务");
    NSString *id=[writer lsOcc:taskID error:nil].firstObject[@"occurrence_id"];
    rm_req([[writer rdTsk:taskID error:nil][@"status"] isEqual:@"needsAction"] && ![writer rdChk:id image:NO error:nil],@"发送附件前任务未完成且无图片记录");
    NSData *image=[NSData dataWithContentsOfFile:@"Resources/MingCute/check_circle.png"];
    NSString *file=[rm_root stringByAppendingPathComponent:[NSString stringWithFormat:@"submit-%@.png",id]];
    rm_req(image.length>0 && [image writeToFile:file atomically:YES],@"准备隔离图片输入");
    notify_post([@"com.iwmei.taskforiwmei.test.submit." stringByAppendingString:rm_root.lastPathComponent].UTF8String);
    rm_wt(3,^BOOL { return [[writer rdTsk:taskID error:nil][@"status"] isEqual:@"completed"] && [[writer rdChk:id image:YES error:nil][@"image"] isEqual:image] && [writer lsChk:id images:NO error:nil].count==TS_ATT_MAX; },@"主App退出后服务原子保存图片并完成任务");
    NSDictionary *event=rm_rows(@"checkins.jsonl").lastObject;
    rm_req([event[@"pid"] intValue]==rm_pid() && [event[@"occurrence_id"] isEqual:id],@"图片提交确实发生于独立服务进程");
    TaskStore *reopened=[[TaskStore alloc] initAt:writer.path error:nil];
    rm_req([[reopened rdTsk:taskID error:nil][@"status"] isEqual:@"completed"] && [[reopened rdChk:id image:YES error:nil][@"image"] isEqual:image] && [[reopened rdChk:id image:NO error:nil][@"method"] isEqual:@"image"] && [reopened lsChk:id images:YES error:nil].count==TS_ATT_MAX,@"新连接读到相同附件及完成状态");
}

// 证明主App退出、重复启动、实时数据同步及三种正常停止。
static void rm_proc(NSString *path) {
    NSTask *app=rm_chld(@"--app"); [app waitUntilExit]; rm_req(app.terminationStatus==0,@"主App启动服务后已经退出");
    rm_wt(3,^BOOL { return rm_rows(@"starts.jsonl").count==1 && lb_svcup(); },@"父App退出后独立服务保持运行");
    pid_t pid=rm_pid(); rm_req(pid!=app.processIdentifier && kill(pid,0)==0,@"提醒服务为独立存活进程");
    rm_req([rm_rows(@"starts.jsonl").lastObject[@"pgid"] intValue]==pid,@"服务使用独立进程组");
    TaskStore *writer=[[TaskStore alloc] initAt:path error:nil]; NSDictionary *task=[writer lsPnd:nil].firstObject;
    rm_req(task!=nil,@"已退出主App的任务持久化");
    rm_wt(5,^BOOL { return [writer lsOcc:task[@"task_id"] error:nil].count==1; },@"主App退出后真实绝对计时仍触发");
    NSDictionary *occ=[writer lsOcc:task[@"task_id"] error:nil].firstObject;
    NSTimeInterval delay=[occ[@"triggered_at"] doubleValue]-[task[@"due_at"] doubleValue];
    rm_req(delay>=0 && delay<2,@"独立进程触发误差小于两秒");
    rm_wt(1,^BOOL { return [rm_rows(@"events.jsonl").lastObject[@"task_id"] isEqual:task[@"task_id"]]; },@"独立进程真实展示回调");
    for (NSUInteger index=0;index<8;index++) { NSTask *again=rm_chld(@"--launch"); [again waitUntilExit]; rm_req(again.terminationStatus==0,@"重复打开主App启动入口成功"); }
    rm_req(rm_rows(@"starts.jsonl").count==1 && rm_pid()==pid,@"八次重复启动没有创建第二个服务");
    rm_req([writer delTsk:task[@"task_id"] error:nil],@"主App删除当前提醒提交");
    rm_wt(1,^BOOL { return rm_rows(@"events.jsonl").lastObject[@"task_id"]==NSNull.null; },@"跨进程Darwin删除立即撤下提醒");
    NSDictionary *check=[writer crtTsk:@{@"title":@"正常退出后图片打卡",@"due_at":@(NSDate.date.timeIntervalSince1970-1)} error:nil];
    rm_req(check!=nil,@"正常退出后建立独立提交任务"); rm_chk(writer,check);
    NSTimeInterval old=NSDate.date.timeIntervalSince1970+1;
    NSDictionary *future=[writer crtTsk:@{@"title":@"修改服务计划",@"due_at":@(old)} error:nil]; rm_req(future!=nil,@"服务运行时创建任务");
    rm_req([writer updTsk:future[@"task_id"] fields:@{@"due_at":@(old+60)} error:nil],@"临近提醒改时提交");
    rm_wt(1,^BOOL { return [lb_rdstat()[@"running"] boolValue] && fabs([lb_rdstat()[@"next_fire_at"] doubleValue]-(old+60))<0.001; },@"独立生产调度器发布编辑后的真实下一提醒时间");
    while (NSDate.date.timeIntervalSince1970<old+0.2) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.02,true);
    rm_req([writer lsOcc:future[@"task_id"] error:nil].count==0,@"独立服务跨过旧时刻没有旧触发");
    rm_req([writer updTsk:future[@"task_id"] fields:@{@"due_at":@(NSDate.date.timeIntervalSince1970-1)} error:nil],@"编辑为到期时刻");
    rm_wt(1,^BOOL { return [writer lsOcc:future[@"task_id"] error:nil].count==1; },@"修改通知立即打断远期等待并触发");
    rm_req([writer delTsk:future[@"task_id"] error:nil],@"清理当前服务任务");
    NSDictionary *cancel=[writer crtTsk:@{@"title":@"停止前的任务",@"due_at":@(NSDate.date.timeIntervalSince1970+1)} error:nil]; rm_req(cancel!=nil,@"停止前设置真实计时");
    notify_post(LB_STOP_NOTE); rm_end(1);
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:1.2]; while (end.timeIntervalSinceNow>0) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.02,true);
    rm_req([writer lsOcc:cancel[@"task_id"] error:nil].count==0,@"服务停止后旧计时不会继续认领");
    NSMutableArray *burst=[NSMutableArray array]; for (NSUInteger index=0;index<8;index++) [burst addObject:rm_chld(@"--launch")];
    for (NSTask *child in burst) { [child waitUntilExit]; rm_req(child.terminationStatus==0,@"并发启动入口成功"); }
    rm_wt(3,^BOOL { return rm_rows(@"starts.jsonl").count==2 && lb_svcup(); },@"冷启动竞争只有一个新服务");
    rm_req(rm_pid()!=pid,@"停止后可恢复真实新进程");
    rm_wt(2,^BOOL { return [writer lsOcc:cancel[@"task_id"] error:nil].count==1; },@"重启恢复停用期间到期任务");
    rm_req(lb_svcfg(@{@"enabled":@NO}),@"主App关闭服务保存配置"); rm_end(2);
    rm_req(lb_svcfg(@{@"enabled":@YES}) && lb_spawn(),@"停用后允许重新启用");
    rm_wt(3,^BOOL { return rm_rows(@"starts.jsonl").count==3 && lb_svcup(); },@"启用后唯一服务就绪");
    pid=rm_pid(); rm_req(pid>1 && pid!=getpid() && kill(pid,SIGTERM)==0,@"向本次服务发送正常终止信号"); rm_end(3);
    // 清理已验证的旧提醒，隔离强退后的图片提交目标。
    rm_req([writer delTsk:cancel[@"task_id"] error:nil],@"清理重启验证任务");
    NSTask *forced=rm_chld(@"--hold");
    rm_wt(3,^BOOL { return rm_rows(@"starts.jsonl").count==4 && lb_svcup(); },@"主App保持打开时独立服务就绪");
    pid=rm_pid(); pid_t parent=forced.processIdentifier;
    rm_req(parent>1 && parent!=getpid() && parent!=pid && kill(parent,SIGKILL)==0,@"仅强制终止本次隔离主App");
    [forced waitUntilExit]; rm_req(forced.terminationReason==NSTaskTerminationReasonUncaughtSignal && forced.terminationStatus==SIGKILL,@"主App被强制终止而非正常退出");
    __block NSDictionary *after;
    rm_wt(1,^BOOL { for (NSDictionary *item in [writer lsPnd:nil]) if ([item[@"title"] isEqual:@"强制退出后提醒"]) { after=item; return YES; } return NO; },@"强制退出前任务已经提交");
    rm_wt(4,^BOOL { return [writer lsOcc:after[@"task_id"] error:nil].count==1; },@"主App被强制结束后服务仍按时触发");
    double forcedDelay=[[writer lsOcc:after[@"task_id"] error:nil].firstObject[@"triggered_at"] doubleValue]-[after[@"due_at"] doubleValue];
    rm_req(kill(pid,0)==0 && forcedDelay>=0 && forcedDelay<2,@"强制关闭主App不终止服务或破坏计时");
    rm_chk(writer,after);
    notify_post(LB_STOP_NOTE); rm_end(4);
    rm_req(lb_spawn(),@"快速切换前服务启动"); rm_wt(3,^BOOL { return rm_rows(@"starts.jsonl").count==5 && lb_svcup(); },@"快速切换前服务就绪");
    rm_req([@"1" writeToFile:[rm_root stringByAppendingPathComponent:@"reenable"] atomically:YES encoding:NSUTF8StringEncoding error:nil] && lb_svcfg(@{@"enabled":@NO}),@"清理仍持锁期间模拟主App重新启用");
    rm_wt(3,^BOOL { return rm_rows(@"starts.jsonl").count==6 && lb_svcup(); },@"关开竞争后最新启用意图仍有唯一服务");
    notify_post(LB_STOP_NOTE); rm_end(6);
    rm_req(lb_spawn(),@"休眠恢复测试启动唯一服务");
    rm_wt(3,^BOOL { return rm_rows(@"starts.jsonl").count==7 && lb_svcup(); },@"暂停前服务就绪");
    pid=rm_pid();rm_req(kill(pid,SIGSTOP)==0,@"实际暂停调度进程");
    NSDictionary *missed=[writer crtTsk:@{@"title":@"暂停期间到期",@"due_at":@(NSDate.date.timeIntervalSince1970+0.2)} error:nil];
    NSDate *wake=[NSDate dateWithTimeIntervalSinceNow:0.5];
    while (wake.timeIntervalSinceNow>0) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.01,true);
    rm_req([writer lsOcc:missed[@"task_id"] error:nil].count==0,@"暂停期间不会执行尚未运行的timer");
    notify_post(TS_DISPLAY_ON);rm_req(kill(pid,SIGCONT)==0,@"恢复执行并投递唤醒事件");
    rm_wt(2,^BOOL { return [writer lsOcc:missed[@"task_id"] error:nil].count==1; },@"暂停错过的任务立即补弹");
    NSDictionary *missedOcc=[writer lsOcc:missed[@"task_id"] error:nil].firstObject;
    rm_req([missedOcc[@"triggered_at"] doubleValue]>=[missed[@"due_at"] doubleValue],@"补弹使用恢复后的当前时间");
    for (NSUInteger i=0;i<30;i++) notify_post(TS_SB_LAUNCH);
    rm_wt(3,^BOOL { return rm_rows(@"starts.jsonl").count==8 && rm_rows(@"stops.jsonl").count==7 && rm_pid()!=pid && lb_svcup(); },@"原SpringBoard通知路径只重建一个新服务");
    rm_wt(1,^BOOL { return [rm_rows(@"events.jsonl").lastObject[@"task_id"] isEqual:missed[@"task_id"]]; },@"新服务恢复仍未Resolved的轮次");
    NSDictionary *recovered=[writer lsOcc:missed[@"task_id"] error:nil].firstObject;
    rm_req([recovered[@"occurrence_id"] isEqual:missedOcc[@"occurrence_id"]] && [recovered[@"triggered_at"] isEqual:missedOcc[@"triggered_at"]],@"SpringBoard重建不新建或重触发同轮次");
    NSDictionary *clean=rm_rows(@"cleanup.jsonl").lastObject,*stopped=rm_rows(@"stops.jsonl").lastObject;
    rm_req([clean[@"lock_held"] boolValue] && ![stopped[@"lock_held"] boolValue] && [clean[@"db_fds"] unsignedIntegerValue]==0,@"原窗口及数据库先清理再释放锁和spawn");
    rm_req([writer actOcc:recovered[@"occurrence_id"] action:@"complete" until:nil error:nil],@"完成补弹测试项");
    notify_post(LB_STOP_NOTE);rm_end(8);
    NSDictionary *report=@{@"checks":@(rm_checks),@"app_pid":@(app.processIdentifier),@"forced_app_pid":@(parent),@"trigger_lateness":@(delay),@"forced_trigger_lateness":@(forcedDelay),@"checkins":rm_rows(@"checkins.jsonl"),@"starts":rm_rows(@"starts.jsonl"),@"cleanups":rm_rows(@"cleanup.jsonl"),@"stops":rm_rows(@"stops.jsonl")};
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]; assert([data writeToFile:@"build/TaskReminderReport.json" atomically:YES]);
}
// 为所有真实子进程注入同一隔离目录，不触及手机服务。
int main(void) {
    @autoreleasepool {
        const char *provided=getenv("TROLLTASK_SERVICE_TEST"); char folder[]="/tmp/trolltask-service.XXXXXX";
        if (!provided) { assert(mkdtemp(folder)); assert(setenv("TROLLTASK_SERVICE_TEST",folder,1)==0); provided=folder; }
        rm_root=@(provided); lb_tstpath=[rm_root stringByAppendingPathComponent:@"preferences.plist"]; NSString *lock=[rm_root stringByAppendingPathComponent:@"hud.lock"]; lb_tstlock=lock.fileSystemRepresentation;
        NSString *path=[rm_root stringByAppendingPathComponent:@"tasks.sqlite3"]; NSArray *args=NSProcessInfo.processInfo.arguments;
        if (args.count==2 && [args[1] isEqual:@"--hud"]) return rm_svc(path);
        if (args.count==2 && [args[1] isEqual:@"--launch"]) return lb_spawn() ? 0 : 1;
        if (args.count==2 && [args[1] isEqual:@"--app"]) { TaskStore *writer=[[TaskStore alloc] initAt:path error:nil]; assert(([writer crtTsk:@{@"title":@"主App退出后提醒",@"due_at":@(NSDate.date.timeIntervalSince1970+2)} error:nil])); return lb_spawn() ? 0 : 1; }
        if (args.count==2 && [args[1] isEqual:@"--hold"]) { TaskStore *writer=[[TaskStore alloc] initAt:path error:nil]; assert(([writer crtTsk:@{@"title":@"强制退出后提醒",@"due_at":@(NSDate.date.timeIntervalSince1970+2)} error:nil])); assert(lb_spawn()); CFRunLoopRun(); return 1; }
        rm_unit(); rm_proc(path);
        printf("TaskReminder: %lu checks passed; normal/SIGKILL parent exit, post-exit image check-in, repeat/concurrent starts, live Darwin CRUD, lock/DB/timer cleanup and Darwin/config/SIGTERM shutdown passed\n",(unsigned long)rm_checks);
        assert([NSFileManager.defaultManager removeItemAtPath:rm_root error:nil]); return 0;
    }
}
