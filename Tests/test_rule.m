#import "LBHead.h"

static NSUInteger rr_checks;

// 记录每项独立规则断言。
static void rr_chk(BOOL valid, NSString *name) {
    if (!valid) { NSLog(@"重复逻辑失败：%@", name); abort(); }
    rr_checks++;
}

// 读取指定时区的固定公历测试时刻。
static NSNumber *rr_tm(NSString *text, NSString *zone) {
    NSDateFormatter *format = [NSDateFormatter new]; format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    format.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    format.timeZone = [NSTimeZone timeZoneWithName:zone]; format.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSDate *date = [format dateFromString:text]; assert(date);
    return @(date.timeIntervalSince1970);
}

// 创建规则模块需要的稳定系列字段。
static NSMutableDictionary *rr_tsk(NSString *date, NSString *zone, NSArray *lines) {
    return [@{@"task_id":@"11111111-1111-4111-8111-111111111111",@"due_at":rr_tm(date,zone),
        @"timezone_id":zone,@"recurrence":lines,@"schedule_kind":@"timed",@"deadline_at":NSNull.null,
        @"deadline_kind":@"none",@"snooze_until":NSNull.null,@"status":@"needsAction",@"deleted":@0,@"reminder_version":@1} mutableCopy];
}

// 检查原始锚点展开的全部期望日期。
static void rr_cycl(NSString *date, NSString *zone, NSArray *lines, NSArray *expected) {
    NSDictionary *task = rr_tsk(date,zone,lines); NSError *error = nil;
    rr_chk([TaskRule vld:task error:&error] && !error,@"规则可用");
    NSArray *actual = [TaskRule cycles:task at:[task[@"due_at"] doubleValue] limit:expected.count error:&error];
    NSMutableArray *values = [NSMutableArray array]; for (NSString *text in expected) [values addObject:rr_tm(text,zone)];
    rr_chk(actual && !error && [actual isEqual:values],[lines description]);
}

// 分别测试不重复、每天、每周、每月和已有每年规则。
static void rr_base(void) {
    rr_cycl(@"2026-12-28 08:15:30",@"UTC",@[],@[@"2026-12-28 08:15:30"]);
    rr_cycl(@"2026-12-30 08:15:30",@"UTC",@[@"RRULE:FREQ=DAILY;COUNT=4"],
        @[@"2026-12-30 08:15:30",@"2026-12-31 08:15:30",@"2027-01-01 08:15:30",@"2027-01-02 08:15:30"]);
    rr_cycl(@"2026-12-28 08:15:30",@"UTC",@[@"RRULE:FREQ=WEEKLY;COUNT=3"],
        @[@"2026-12-28 08:15:30",@"2027-01-04 08:15:30",@"2027-01-11 08:15:30"]);
    rr_cycl(@"2026-12-28 08:15:30",@"UTC",@[@"RRULE:FREQ=MONTHLY;COUNT=3"],
        @[@"2026-12-28 08:15:30",@"2027-01-28 08:15:30",@"2027-02-28 08:15:30"]);
    rr_cycl(@"2026-12-28 08:15:30",@"UTC",@[@"RRULE:FREQ=YEARLY;COUNT=3"],
        @[@"2026-12-28 08:15:30",@"2027-12-28 08:15:30",@"2028-12-28 08:15:30"]);
    rr_cycl(@"2026-12-30 08:15:30",@"UTC",@[@"RRULE:FREQ=DAILY;INTERVAL=2;COUNT=3"],
        @[@"2026-12-30 08:15:30",@"2027-01-01 08:15:30",@"2027-01-03 08:15:30"]);
    rr_cycl(@"2026-12-28 08:15:30",@"UTC",@[@"RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=3"],
        @[@"2026-12-28 08:15:30",@"2027-01-11 08:15:30",@"2027-01-25 08:15:30"]);
    rr_cycl(@"2026-01-31 08:15:30",@"UTC",@[@"RRULE:FREQ=MONTHLY;INTERVAL=2;COUNT=3"],
        @[@"2026-01-31 08:15:30",@"2026-03-31 08:15:30",@"2026-05-31 08:15:30"]);
    rr_cycl(@"2026-12-31 23:15:30",@"UTC",@[@"RRULE:FREQ=HOURLY;COUNT=2"],@[@"2026-12-31 23:15:30",@"2027-01-01 00:15:30"]);
    rr_cycl(@"2026-12-31 23:59:30",@"UTC",@[@"RRULE:FREQ=MINUTELY;COUNT=2"],@[@"2026-12-31 23:59:30",@"2027-01-01 00:00:30"]);
    rr_cycl(@"2026-12-31 23:59:59",@"UTC",@[@"RRULE:FREQ=SECONDLY;COUNT=2"],@[@"2026-12-31 23:59:59",@"2027-01-01 00:00:00"]);
}

// 测试月末、闰日和夏令时的确定性处理。
static void rr_bnd(void) {
    rr_cycl(@"2026-01-31 08:15:30",@"UTC",@[@"RRULE:FREQ=MONTHLY;COUNT=5"],
        @[@"2026-01-31 08:15:30",@"2026-03-31 08:15:30",@"2026-05-31 08:15:30",@"2026-07-31 08:15:30",@"2026-08-31 08:15:30"]);
    rr_cycl(@"2026-01-30 08:15:30",@"UTC",@[@"RRULE:FREQ=MONTHLY;COUNT=2"],@[@"2026-01-30 08:15:30",@"2026-03-30 08:15:30"]);
    rr_cycl(@"2024-01-29 08:15:30",@"UTC",@[@"RRULE:FREQ=MONTHLY;COUNT=3"],@[@"2024-01-29 08:15:30",@"2024-02-29 08:15:30",@"2024-03-29 08:15:30"]);
    rr_cycl(@"2026-01-29 08:15:30",@"UTC",@[@"RRULE:FREQ=MONTHLY;COUNT=2"],@[@"2026-01-29 08:15:30",@"2026-03-29 08:15:30"]);
    rr_cycl(@"2026-12-31 08:15:30",@"UTC",@[@"RRULE:FREQ=MONTHLY;COUNT=3"],@[@"2026-12-31 08:15:30",@"2027-01-31 08:15:30",@"2027-03-31 08:15:30"]);
    rr_cycl(@"2024-02-29 08:15:30",@"UTC",@[@"RRULE:FREQ=YEARLY;COUNT=3"],
        @[@"2024-02-29 08:15:30",@"2028-02-29 08:15:30",@"2032-02-29 08:15:30"]);
    rr_cycl(@"2024-02-28 08:15:30",@"UTC",@[@"RRULE:FREQ=DAILY;COUNT=3"],
        @[@"2024-02-28 08:15:30",@"2024-02-29 08:15:30",@"2024-03-01 08:15:30"]);
    rr_cycl(@"2026-02-28 08:15:30",@"UTC",@[@"RRULE:FREQ=DAILY;COUNT=2"],
        @[@"2026-02-28 08:15:30",@"2026-03-01 08:15:30"]);
    rr_cycl(@"2026-03-07 09:00:00",@"America/New_York",@[@"RRULE:FREQ=DAILY;COUNT=3"],
        @[@"2026-03-07 09:00:00",@"2026-03-08 09:00:00",@"2026-03-09 09:00:00"]);
    rr_chk([rr_tm(@"2026-03-08 09:00:00",@"America/New_York") doubleValue]-[rr_tm(@"2026-03-07 09:00:00",@"America/New_York") doubleValue]==23*3600,@"春季不能加86400秒");
    rr_cycl(@"2026-10-31 09:00:00",@"America/New_York",@[@"RRULE:FREQ=DAILY;COUNT=3"],
        @[@"2026-10-31 09:00:00",@"2026-11-01 09:00:00",@"2026-11-02 09:00:00"]);
    rr_chk([rr_tm(@"2026-11-01 09:00:00",@"America/New_York") doubleValue]-[rr_tm(@"2026-10-31 09:00:00",@"America/New_York") doubleValue]==25*3600,@"秋季不能加86400秒");
    rr_cycl(@"2026-03-07 02:30:00",@"America/New_York",@[@"RRULE:FREQ=DAILY;COUNT=3"],
        @[@"2026-03-07 02:30:00",@"2026-03-09 02:30:00",@"2026-03-10 02:30:00"]);
}

// 保留自定义星期、结束边界、日期集合和例外功能。
static void rr_ext(void) {
    rr_cycl(@"2026-12-28 08:15:30",@"UTC",@[@"RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=4"],
        @[@"2026-12-28 08:15:30",@"2026-12-30 08:15:30",@"2027-01-01 08:15:30",@"2027-01-04 08:15:30"]);
    rr_cycl(@"2026-01-30 08:15:30",@"UTC",@[@"RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3"],
        @[@"2026-01-30 08:15:30",@"2026-02-27 08:15:30",@"2026-03-31 08:15:30"]);
    rr_cycl(@"2026-12-30 08:15:30",@"UTC",@[@"RRULE:FREQ=DAILY;UNTIL=20270101T081530Z"],
        @[@"2026-12-30 08:15:30",@"2026-12-31 08:15:30",@"2027-01-01 08:15:30"]);
    rr_cycl(@"2026-10-01 08:15:30",@"UTC",@[@"RRULE:FREQ=DAILY;COUNT=3",@"RDATE:20261005T081530Z,20261005T081530Z",@"EXDATE:20261002T081530Z"],
        @[@"2026-10-01 08:15:30",@"2026-10-03 08:15:30",@"2026-10-05 08:15:30"]);
    rr_cycl(@"2026-09-28 08:15:30",@"UTC",@[@"RRULE:FREQ=DAILY;COUNT=8",@"EXRULE:FREQ=WEEKLY;BYDAY=SA,SU"],
        @[@"2026-09-28 08:15:30",@"2026-09-29 08:15:30",@"2026-09-30 08:15:30",@"2026-10-01 08:15:30",@"2026-10-02 08:15:30",@"2026-10-05 08:15:30"]);
}

// 创建一次完成或稍后提醒历史。
static NSDictionary *rr_hst(NSDictionary *task, NSNumber *cycle, NSString *action, NSNumber *until) {
    return @{@"task_id":task[@"task_id"],@"occurrence_id":NSUUID.UUID.UUIDString.lowercaseString,
        @"generation":task[@"reminder_version"],@"cycle_at":cycle,@"scheduled_at":cycle,@"kind":@"plan",
        @"status":[action isEqual:@"snooze"] ? @"snoozed" : @"resolved",@"action":action,@"next_fire_at":until ?: NSNull.null,@"handled_at":@1791663600};
}

// 验证完成时间与单次延后均不改变系列锚点。
static void rr_act(void) {
    NSDictionary *task = rr_tsk(@"2026-10-10 09:00:00",@"UTC",@[@"RRULE:FREQ=DAILY"]), *original = [task copy];
    NSDictionary *done = rr_hst(task,task[@"due_at"],@"complete",nil);
    NSArray *next = [TaskRule alerts:task history:@[done] at:[rr_tm(@"2026-10-10 18:35:00",@"UTC") doubleValue] error:nil];
    rr_chk([next.firstObject[@"cycle_at"] isEqual:rr_tm(@"2026-10-11 09:00:00",@"UTC")],@"完成点击时间不作为下一轮锚点");
    NSDictionary *monthly = rr_tsk(@"2026-01-31 08:15:30",@"UTC",@[@"RRULE:FREQ=MONTHLY"]);
    next = [TaskRule alerts:monthly history:@[rr_hst(monthly,monthly[@"due_at"],@"complete",nil)] at:[rr_tm(@"2026-02-05 18:35:00",@"UTC") doubleValue] error:nil];
    rr_chk([next.firstObject[@"cycle_at"] isEqual:rr_tm(@"2026-03-31 08:15:30",@"UTC")],@"延迟完成仍从原月末推进");
    NSNumber *until = rr_tm(@"2026-10-12 18:00:00",@"UTC");
    next = [TaskRule alerts:task history:@[rr_hst(task,task[@"due_at"],@"snooze",until)] at:[task[@"due_at"] doubleValue] error:nil];
    BOOL pinned = NO, future = NO;
    for (NSDictionary *item in next) {
        if ([item[@"cycle_at"] isEqual:task[@"due_at"]]) pinned = [item[@"remind_at"] isEqual:until] && [item[@"scheduled_at"] isEqual:task[@"due_at"]];
        if ([item[@"cycle_at"] isEqual:rr_tm(@"2026-10-11 09:00:00",@"UTC")]) future = [item[@"remind_at"] isEqual:item[@"cycle_at"]];
    }
    rr_chk(pinned,@"稍后仅覆盖单次提醒时间"); rr_chk(future,@"稍后不污染下一轮"); rr_chk([task isEqual:original],@"计算不修改系列对象");
    // 延期到期认领后，重读保持实际提醒时刻，原计划身份独立保留。
    NSMutableDictionary *presented = [rr_hst(task,task[@"due_at"],@"snooze",until) mutableCopy];
    presented[@"status"] = @"presented"; presented[@"action"] = NSNull.null;
    NSArray *again = [TaskRule alerts:task history:@[presented] at:until.doubleValue error:nil];
    BOOL stable = NO;
    for (NSDictionary *item in again) if ([item[@"cycle_at"] isEqual:task[@"due_at"]]) stable = [item[@"remind_at"] isEqual:until] && [item[@"scheduled_at"] isEqual:task[@"due_at"]];
    rr_chk(stable,@"延期重弹后的重复事件保持实际提醒时刻");
    next = [TaskRule alerts:task history:@[rr_hst(task,task[@"due_at"],@"snooze",until)] at:[rr_tm(@"2026-10-13 10:00:00",@"UTC") doubleValue] error:nil];
    pinned = NO; for (NSDictionary *item in next) if ([item[@"cycle_at"] isEqual:task[@"due_at"]]) pinned = YES;
    rr_chk(pinned,@"跨过后续日期也不丢失延后轮次");
    NSMutableDictionary *old = [done mutableCopy]; old[@"generation"] = @0;
    next = [TaskRule alerts:task history:@[old] at:[task[@"due_at"] doubleValue] error:nil];
    rr_chk([next.firstObject[@"cycle_at"] isEqual:task[@"due_at"]],@"旧版本完成不影响新系列");
    NSDictionary *single = rr_tsk(@"2026-10-10 09:00:00",@"UTC",@[]);
    rr_chk([TaskRule alerts:single history:@[rr_hst(single,single[@"due_at"],@"complete",nil)] at:[single[@"due_at"] doubleValue] error:nil].count==0,@"不重复完成后没有下一轮");
    NSDictionary *finite = rr_tsk(@"2026-10-10 09:00:00",@"UTC",@[@"RRULE:FREQ=DAILY;COUNT=1"]);
    rr_chk([TaskRule alerts:finite history:@[rr_hst(finite,finite[@"due_at"],@"complete",nil)] at:[finite[@"due_at"] doubleValue] error:nil].count==0,@"明确次数结束不制造轮次");
}

// 提前完成超过预取窗口后仍继续无限系列。
static void rr_lng(void) {
    for (NSArray *lines in @[@[@"RRULE:FREQ=DAILY"],@[@"RRULE:FREQ=WEEKLY"],@[@"RRULE:FREQ=MONTHLY"],
        @[@"RRULE:FREQ=YEARLY"],@[@"RRULE:FREQ=WEEKLY;BYDAY=TH,FR"],@[@"RRULE:FREQ=DAILY;COUNT=16"]]) {
        NSDictionary *task = rr_tsk(@"2026-10-01 08:15:30",@"UTC",lines);
        NSArray *cycles = [TaskRule cycles:task at:[task[@"due_at"] doubleValue] limit:16 error:nil];
        NSMutableArray *history = [NSMutableArray array];
        for (NSUInteger index=0; index<12; index++) [history addObject:rr_hst(task,cycles[index],@"complete",nil)];
        NSArray *alerts = [TaskRule alerts:task history:history at:[task[@"due_at"] doubleValue]-3600 error:nil];
        rr_chk([alerts.firstObject[@"cycle_at"] isEqual:cycles[12]],@"未来4条预取不是系列完成次数上限");
    }
}

// 规则错误返回明确字段错误。
static void rr_bad(void) {
    for (NSString *line in @[@"RRULE:FREQ=UNKNOWN",@"RRULE:FREQ=DAILY;INTERVAL=0",@"RRULE:FREQ=DAILY;COUNT=2;UNTIL=20261003T081530Z"]) {
        NSDictionary *task = rr_tsk(@"2026-10-01 08:15:30",@"UTC",@[line]); NSError *error = nil;
        rr_chk(![TaskRule vld:task error:&error] && [error.userInfo[@"kind"] isEqual:@"invalid_fields"],@"无效规则明确拒绝");
    }
    // 结束边界早于计划起点会产生永远不会提醒的系列。
    NSDictionary *empty = rr_tsk(@"2026-11-01 09:00:00",@"UTC",@[@"RRULE:FREQ=DAILY;UNTIL=20261025T235959Z"]);
    NSError *range = nil;
    rr_chk(![TaskRule vld:empty error:&range] && [range.userInfo[@"kind"] isEqual:@"invalid_fields"],@"拒绝结束早于起点的重复规则");
    rr_chk([TaskRule vld:rr_tsk(@"2026-11-01 09:00:00",@"Asia/Shanghai",@[@"RRULE:FREQ=DAILY;UNTIL=20261101T010000Z"]) error:nil],@"跨时区相同绝对时刻允许最后一轮");
    rr_chk([TaskRule vld:rr_tsk(@"2026-11-01 09:00:00",@"UTC",@[@"RRULE:FREQ=DAILY",@"EXRULE:FREQ=DAILY;UNTIL=20261025T235959Z"]) error:nil],@"过期例外不等于重复系列结束");
    NSMutableDictionary *day = rr_tsk(@"2026-11-01 00:00:00",@"Asia/Shanghai",@[@"RRULE:FREQ=DAILY;UNTIL=20261031T155959Z"]); day[@"schedule_kind"] = @"date";
    rr_chk(![TaskRule vld:day error:nil],@"仅日期按任务时区核对结束边界");
    day[@"recurrence"] = @[@"RRULE:FREQ=DAILY;UNTIL=20261031T160000Z"];
    rr_chk([TaskRule vld:day error:nil],@"仅日期结束与当地日界相同允许首轮");
    NSMutableDictionary *legacy = [empty mutableCopy]; legacy[@"deleted"] = @1;
    rr_chk([TaskRule vld:legacy error:nil],@"旧的无效边界记录仍可删除");
    legacy[@"deleted"] = @0; legacy[@"status"] = @"completed";
    rr_chk([TaskRule vld:legacy error:nil],@"旧的无效边界记录仍可完成");
    NSMutableDictionary *disabled = rr_tsk(@"2026-10-01 08:15:30",@"UTC",@[@"RRULE:FREQ=DAILY"]);
    disabled[@"status"] = @"completed"; rr_chk([TaskRule alerts:disabled history:@[] at:0 error:nil].count==0,@"完成整个系列停止提醒");
    disabled[@"status"] = @"needsAction"; disabled[@"deleted"] = @1; rr_chk([TaskRule alerts:disabled history:@[] at:0 error:nil].count==0,@"已删除系列停止提醒");
}

// 仅运行TaskRule与原生日历库，不连接数据库或启动调度器。
int main(void) {
    @autoreleasepool {
        rr_base(); rr_bnd(); rr_ext(); rr_act(); rr_lng(); rr_bad();
        printf("Independent TaskRule: %lu checks passed (basic, custom, boundaries, completion, occurrence snooze)\n",(unsigned long)rr_checks);
        return 0;
    }
}
