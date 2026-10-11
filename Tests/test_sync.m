#import "LBHead.h"

// 读取指定时区的绝对测试时间。
static NSNumber *tststamp(NSString *text, NSString *zone) {
    NSDateFormatter *format = [NSDateFormatter new]; format.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    format.timeZone = [NSTimeZone timeZoneWithName:zone];
    return @([format dateFromString:text].timeIntervalSince1970);
}

// 打开实际原生存储模块。
static TaskStore *tstopen(NSString *path) {
    NSError *error = nil; TaskStore *store = [[TaskStore alloc] initAt:path error:&error];
    assert((store && !error)); return store;
}

// 读取并清除Darwin通知变化位。
static BOOL tstnote(int token) {
    int changed = 0; assert((notify_check(token, &changed) == NOTIFY_STATUS_OK)); return changed != 0;
}

// 验证完整CRUD、排序、明确错误与提交后通知。
static void tstcrud(NSString *path) {
    TaskStore *store = tstopen(path), *reader = tstopen(path);
    int token = -1; assert((notify_register_check(store.changeNote.UTF8String, &token) == NOTIFY_STATUS_OK));
    (void)tstnote(token);
    NSError *textError = nil;
    assert(([TaskStore vldTxt:@"合法标题" notes:@"第一行\n第二行" error:&textError] && !textError));
    assert((![TaskStore vldTxt:@" \n " notes:@"" error:&textError] && [textError.userInfo[@"kind"] isEqual:@"invalid_fields"]));
    assert((![TaskStore vldTxt:[@"a" stringByPaddingToLength:1025 withString:@"a" startingAtIndex:0] notes:@"" error:nil]));
    assert((![TaskStore vldTxt:@"标题" notes:[@"a" stringByPaddingToLength:8193 withString:@"a" startingAtIndex:0] error:nil]));
    assert(([TaskStore vldTxt:[@"a" stringByPaddingToLength:1024 withString:@"a" startingAtIndex:0]
        notes:[@"a" stringByPaddingToLength:8192 withString:@"a" startingAtIndex:0] error:nil]));
    assert(([store revision:nil] == 0 && !tstnote(token)));
    __block NSDictionary *task = nil;
    assert(([store wrTxn:^BOOL(NSError **error) {
        task = [store crtTsk:@{@"title": @"计划", @"due_at": @200, @"deadline_at": @100, @"snooze_until": @300} error:error];
        assert((task && !tstnote(token)));
        assert(([reader lsTsks:nil].count == 0));
        return [store updTsk:task[@"task_id"] fields:@{@"notes": @"已提交"} error:error];
    } error:nil]));
    NSDate *delivery = [NSDate dateWithTimeIntervalSinceNow:1];
    BOOL delivered = NO;
    while (!delivered && delivery.timeIntervalSinceNow > 0) { delivered = tstnote(token); if (!delivered) [NSThread sleepForTimeInterval:0.01]; }
    assert((delivered && !tstnote(token)));
    assert(([[reader rdTsk:task[@"task_id"] error:nil][@"notes"] isEqual:@"已提交"]));
    long long revision = [store revision:nil];
    NSDictionary *before = [store rdTsk:task[@"task_id"] error:nil];
    assert((![store wrTxn:^BOOL(NSError **error) {
        assert(([store updTsk:task[@"task_id"] fields:@{@"title": @"必须回滚"} error:error]));
        [store updTsk:task[@"task_id"] fields:@{@"status": @"wrong"} error:error];
        return YES;
    } error:nil]));
    assert((!tstnote(token) && [store revision:nil] == revision));
    assert(([[store rdTsk:task[@"task_id"] error:nil] isEqual:before]));
    NSError *failure = nil;
    assert((![store crtTsk:@{@"title": @"冲突"} uuid:[task[@"task_id"] uppercaseString] error:&failure]));
    assert(([failure.userInfo[@"kind"] isEqual:@"duplicate_uuid"] && !tstnote(token)));
    failure = nil;
    assert((![store crtTsk:@{@"title": NSNull.null} error:&failure] && [failure.userInfo[@"kind"] isEqual:@"invalid_fields"]));
    NSDictionary *second = [store crtTsk:@{@"title": @"更晚", @"due_at": @150} error:nil];
    NSDictionary *floating = [store crtTsk:@{@"title": @"无时间"} error:nil];
    NSArray *pending = [store lsPnd:nil];
    assert((pending.count == 3 && [pending[0][@"task_id"] isEqual:task[@"task_id"]]));
    assert(([pending[0][@"remind_at"] isEqual:@100] && [pending[2][@"task_id"] isEqual:floating[@"task_id"]]));
    assert(([store cmplTsk:task[@"task_id"] error:nil] && [store lsCmpl:nil].count == 1 && [store lsPnd:nil].count == 2));
    assert(([store rstrTsk:task[@"task_id"] error:nil] && [store lsCmpl:nil].count == 0));
    NSDictionary *child = [store crtTsk:@{@"title": @"子任务", @"parent_id": second[@"task_id"]} error:nil];
    assert(([store cmplTsk:second[@"task_id"] error:nil]));
    assert(([[store rdTsk:child[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"]));
    assert(([store delTsk:second[@"task_id"] error:nil]));
    assert(([[store rdTsk:child[@"task_id"] error:nil][@"deleted"] boolValue]));
    assert(([store lsCmpl:nil].count == 0));
    notify_cancel(token);
}

// 建立UTC或当地时间的完整重复任务。
static NSDictionary *tstrule(NSNumber *base, NSString *zone, NSArray *rules) {
    return @{@"task_id": @"11111111-1111-4111-8111-111111111111", @"title": @"重复", @"due_at": base,
        @"timezone_id": zone, @"schedule_kind": @"timed", @"recurrence_type": @"custom", @"recurrence": rules,
        @"deadline_at": NSNull.null, @"deadline_kind": @"none", @"snooze_until": NSNull.null,
        @"status": @"needsAction", @"deleted": @0, @"reminder_version": @1};
}

// 验证完整重复属性、结束、例外及DST绝对时间。
static void tstrecur(void) {
    NSNumber *base = tststamp(@"2026-11-02 09:00:00", @"UTC");
    NSDictionary *task = tstrule(base, @"UTC", @[@"RRULE:FREQ=DAILY;COUNT=3", @"RRULE:FREQ=WEEKLY;COUNT=2",
        @"EXRULE:FREQ=DAILY;COUNT=1", @"RDATE:20261110T090000Z", @"EXDATE:20261104T090000Z"]);
    NSError *error = nil;
    NSArray *cycles = [TaskRule cycles:task at:base.doubleValue - 1 limit:20 error:&error];
    assert((cycles && !error && cycles.count == 3));
    assert(([cycles[0] isEqual:tststamp(@"2026-11-03 09:00:00", @"UTC")]));
    assert(([cycles[1] isEqual:tststamp(@"2026-11-09 09:00:00", @"UTC")]));
    task = tstrule(tststamp(@"2026-10-30 09:00:00", @"UTC"), @"UTC", @[@"RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3"]);
    cycles = [TaskRule cycles:task at:0 limit:20 error:nil];
    assert((cycles.count == 3 && [cycles[1] isEqual:tststamp(@"2026-11-30 09:00:00", @"UTC")]));
    task = tstrule(tststamp(@"2024-02-29 09:00:00", @"UTC"), @"UTC", @[@"RRULE:FREQ=YEARLY;COUNT=3"]);
    cycles = [TaskRule cycles:task at:0 limit:20 error:nil];
    assert((cycles.count == 3 && [cycles[1] isEqual:tststamp(@"2028-02-29 09:00:00", @"UTC")]));
    task = tstrule(tststamp(@"2026-03-07 09:00:00", @"America/New_York"), @"America/New_York", @[@"RRULE:FREQ=DAILY;COUNT=3"]);
    cycles = [TaskRule cycles:task at:0 limit:20 error:nil];
    assert((cycles.count == 3 && [cycles[1] doubleValue] - [cycles[0] doubleValue] == 23 * 3600));
    task = tstrule(tststamp(@"2026-10-31 09:00:00", @"America/New_York"), @"America/New_York", @[@"RRULE:FREQ=DAILY;UNTIL=20261102T140000Z"]);
    cycles = [TaskRule cycles:task at:0 limit:20 error:nil];
    assert((cycles.count == 3 && [cycles[1] doubleValue] - [cycles[0] doubleValue] == 25 * 3600));
    task = tstrule(base, @"UTC", @[@"RRULE:FREQ=DAILY;COUNT=2", @"RDATE;TZID=Asia/Shanghai:20261104T170000,20261105T170000", @"EXDATE;VALUE=DATE:20261103"]);
    cycles = [TaskRule cycles:task at:0 limit:20 error:nil];
    assert((cycles.count == 3 && [cycles[1] isEqual:tststamp(@"2026-11-04 09:00:00", @"UTC")]));
    task = tstrule(base, @"UTC", @[@"RRULE:FREQ=DAILY;COUNT=3", @"EXDATE;TZID=Asia/Shanghai:20261103T170000"]);
    cycles = [TaskRule cycles:task at:0 limit:20 error:nil];
    assert((cycles.count == 2 && [cycles[1] isEqual:tststamp(@"2026-11-04 09:00:00", @"UTC")]));
    task = tstrule(base, @"UTC", @[@"RRULE:FREQ=DAILY"]);
    cycles = [TaskRule cycles:task at:base.doubleValue + 1 limit:2 error:nil];
    assert((cycles.count == 3 && [cycles[0] isEqual:base]));
    task = tstrule(base, @"UTC", @[@"RRULE:FREQ=DAILY;UNTIL=20261104T090000Z"]);
    cycles = [TaskRule cycles:task at:tststamp(@"2026-11-05 09:00:00", @"UTC").doubleValue limit:2 error:nil];
    assert((cycles.count == 1 && [cycles[0] isEqual:tststamp(@"2026-11-04 09:00:00", @"UTC")]));
    task = tstrule(tststamp(@"2026-03-07 02:30:00", @"America/New_York"), @"America/New_York", @[@"RRULE:FREQ=DAILY;COUNT=3"]);
    cycles = [TaskRule cycles:task at:0 limit:20 error:nil];
    assert((cycles.count == 3 && [cycles[1] isEqual:tststamp(@"2026-03-09 02:30:00", @"America/New_York")]));
    cycles = [TaskRule cycles:tstrule(@(-0.5), @"UTC", @[@"RRULE:FREQ=DAILY;COUNT=2"]) at:-1 limit:3 error:nil];
    assert((cycles.count == 2 && [cycles[0] doubleValue] == -0.5 && [cycles[1] doubleValue] == 86399.5));
    NSMutableDictionary *dateOnly = [tstrule(tststamp(@"2026-03-07 00:00:00", @"America/New_York"), @"America/New_York", @[@"RRULE:FREQ=DAILY;COUNT=3"]) mutableCopy];
    dateOnly[@"schedule_kind"] = @"date";
    cycles = [TaskRule cycles:dateOnly at:0 limit:20 error:nil];
    assert((cycles.count == 3 && [cycles[1] isEqual:tststamp(@"2026-03-08 00:00:00", @"America/New_York")]));
    assert(([[TaskRule alerts:dateOnly history:@[] at:0 error:nil][1][@"remind_at"] isEqual:tststamp(@"2026-03-08 09:00:00", @"America/New_York")]));
    for (NSString *rule in @[@"RRULE:FREQ=WRONG", @"RRULE:FREQ=DAILY;COUNT=2;UNTIL=20261102T140000Z", @"RRULE:FREQ=DAILY;INTERVAL=0"]) {
        error = nil; assert((![TaskRule vld:tstrule(base, @"UTC", @[rule]) error:&error] && error));
    }
}

// 验证双提醒、旧版本失效、延后与重复完成。
static void tstalerts(NSString *path) {
    TaskStore *store = tstopen(path);
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSDictionary *task = [store crtTsk:@{@"title": @"双提醒", @"due_at": @(now - 2), @"deadline_at": @(now + 20)} error:nil];
    NSDictionary *plan = [store planAt:now error:nil]; assert(([plan[@"alerts"] count] == 2));
    NSDictionary *old = [plan[@"alerts"] firstObject];
    assert(([store updTsk:task[@"task_id"] fields:@{@"due_at": @(now + 40)} error:nil]));
    assert((![store claim:old revision:[plan[@"revision"] longLongValue] at:now error:nil]));
    assert(([store lsOcc:task[@"task_id"] error:nil].count == 0));
    assert(([store updTsk:task[@"task_id"] fields:@{@"due_at": @(now - 1), @"deadline_at": @(now - 1)} error:nil]));
    plan = [store planAt:now error:nil]; assert(([plan[@"alerts"] count] == 1));
    NSDictionary *alert = [store claim:[plan[@"alerts"] firstObject] revision:[plan[@"revision"] longLongValue] at:now error:nil];
    assert((alert && [alert[@"kind"] isEqual:@"both"]));
    assert(([store actOcc:alert[@"occurrence_id"] action:@"snooze" until:@(now + 300) error:nil]));
    plan = [store planAt:now error:nil]; assert(([[plan[@"alerts"] firstObject][@"remind_at"] isEqual:@(now + 300)]));
    assert(([[store rdTsk:task[@"task_id"] error:nil][@"deadline_at"] isEqual:@(now - 1)]));
    NSError *failure = nil;
    alert = [store claim:[plan[@"alerts"] firstObject] revision:[plan[@"revision"] longLongValue] at:now + 301 error:&failure];
    if (!alert) NSLog(@"延后重触发失败：%@，计划%@，记录%@", failure, plan, [store lsOcc:task[@"task_id"] error:nil]);
    assert((alert));
    BOOL completed = [store actOcc:alert[@"occurrence_id"] action:@"complete" until:nil error:&failure];
    if (!completed) NSLog(@"提醒完成失败：%@", failure);
    assert((completed));
    assert(([store lsCmpl:nil].count == 1 && [[store planAt:now error:nil][@"alerts"] count] == 0));
    task = [store crtTsk:@{@"title": @"重复完成", @"due_at": @(floor(now) - 2), @"timezone_id": @"UTC", @"recurrence_type": @"daily"} error:nil];
    plan = [store planAt:now error:nil];
    alert = [store claim:[plan[@"alerts"] firstObject] revision:[plan[@"revision"] longLongValue] at:now error:nil];
    if (!alert) NSLog(@"重复首轮认领失败：%@", plan);
    assert((alert && [store actOcc:alert[@"occurrence_id"] action:@"complete" until:nil error:nil]));
    assert(([[store rdTsk:task[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"]));
    plan = [store planAt:now error:nil]; assert(([[plan[@"alerts"] firstObject][@"remind_at"] doubleValue] > now));
    assert(([store delTsk:task[@"task_id"] error:nil] && [[store planAt:now error:nil][@"alerts"] count] == 0));
    NSMutableDictionary *dateTask = [tstrule(tststamp(@"2026-10-31 09:00:00", @"America/New_York"), @"America/New_York", @[@"RRULE:FREQ=DAILY;COUNT=3"]) mutableCopy];
    dateTask[@"deadline_at"] = tststamp(@"2026-11-02 00:00:00", @"America/New_York"); dateTask[@"deadline_kind"] = @"date";
    assert(([[TaskRule ddl:dateTask cycle:nil] isEqual:tststamp(@"2026-11-01 09:00:00", @"America/New_York")]));
    assert(([[TaskRule ddl:dateTask cycle:tststamp(@"2026-11-01 09:00:00", @"America/New_York")] isEqual:tststamp(@"2026-11-02 09:00:00", @"America/New_York")]));
}

// 在独立接收进程实际运行HUD使用的调度器。
static int tstmonitor(NSString *path) {
    TaskSched *scheduler = [[TaskSched alloc] initStore:tstopen(path) handler:^(NSDictionary *alert, NSError *error) {
        assert((!error));
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"task_id": alert[@"task_id"] ?: (id)NSNull.null} options:0 error:nil];
        fwrite(data.bytes, 1, data.length, stdout); putchar('\n'); fflush(stdout);
    }];
    assert(([scheduler start:nil]));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [scheduler stop]; CFRunLoopStop(CFRunLoopGetMain()); });
    CFRunLoopRun(); return 0;
}

// 验证跨进程修改取消旧计时、立即触发新时间、删除隐藏。
static void tstsched(NSString *path) {
    TaskStore *writer = tstopen(path);
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSDictionary *task = [writer crtTsk:@{@"title": @"旧时间", @"due_at": @(now + 2)} error:nil];
    NSTask *child = [NSTask new]; NSPipe *pipe = [NSPipe pipe]; child.standardOutput = pipe;
    child.executableURL = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]]; child.arguments = @[@"--monitor", path];
    assert(([child launchAndReturnError:nil]));
    [NSThread sleepForTimeInterval:0.4];
    assert(([writer updTsk:task[@"task_id"] fields:@{@"due_at": @(now + 30), @"title": @"新时间"} error:nil]));
    [NSThread sleepForTimeInterval:2.3];
    assert(([writer lsOcc:task[@"task_id"] error:nil].count == 0));
    assert(([writer updTsk:task[@"task_id"] fields:@{@"due_at": @(NSDate.date.timeIntervalSince1970 - 1)} error:nil]));
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:2];
    while ([writer lsOcc:task[@"task_id"] error:nil].count == 0 && end.timeIntervalSinceNow > 0) [NSThread sleepForTimeInterval:0.05];
    assert(([writer lsOcc:task[@"task_id"] error:nil].count == 1));
    [NSThread sleepForTimeInterval:0.2]; assert(([writer delTsk:task[@"task_id"] error:nil]));
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile]; [child waitUntilExit]; assert((child.terminationStatus == 0));
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    assert(([text containsString:task[@"task_id"]] && [text containsString:@"null"]));
}

// 执行第三阶段实际原生同步和调度验收。
int main(void) {
    @autoreleasepool {
        NSArray *args = NSProcessInfo.processInfo.arguments;
        if (args.count == 3 && [args[1] isEqual:@"--monitor"]) return tstmonitor(args[2]);
        char folder[] = "/tmp/trolltask-sync.XXXXXX"; assert((mkdtemp(folder)));
        NSString *root = @(folder);
        tstcrud([root stringByAppendingPathComponent:@"crud.sqlite3"]); tstrecur();
        tstalerts([root stringByAppendingPathComponent:@"alerts.sqlite3"]); tstsched([root stringByAppendingPathComponent:@"scheduler.sqlite3"]);
        assert(([NSFileManager.defaultManager removeItemAtPath:root error:nil]));
        puts("Task sync: commit-only Darwin, rollback, UUID conflict, CRUD/order, full recurrence/DST, stale claims, snooze and real cross-process scheduling passed");
        return 0;
    }
}
