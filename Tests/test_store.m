#import "LBHead.h"

// 执行独立数据库夹具语句。
static void tstsql(NSString *path, NSString *sql) {
    sqlite3 *db = NULL;
    assert((sqlite3_open(path.fileSystemRepresentation, &db) == SQLITE_OK));
    assert((sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL) == SQLITE_OK));
    assert((sqlite3_close(db) == SQLITE_OK));
}

// 独立读取单个SQLite验证值。
static id tstval(NSString *path, const char *sql) {
    sqlite3 *db = NULL;
    sqlite3_stmt *statement = NULL;
    assert((sqlite3_open(path.fileSystemRepresentation, &db) == SQLITE_OK));
    assert((sqlite3_prepare_v2(db, sql, -1, &statement, NULL) == SQLITE_OK));
    assert((sqlite3_step(statement) == SQLITE_ROW));
    id value = sqlite3_column_type(statement, 0) == SQLITE_TEXT ? [NSString stringWithUTF8String:(const char *)sqlite3_column_text(statement, 0)] : @(sqlite3_column_int64(statement, 0));
    assert((sqlite3_finalize(statement) == SQLITE_OK));
    assert((sqlite3_close(db) == SQLITE_OK));
    return value;
}

// 打开实际存储模块并检查错误输出。
static TaskStore *tstopn(NSString *path) {
    NSError *error = nil;
    TaskStore *store = [[TaskStore alloc] initAt:path error:&error];
    if (!store) NSLog(@"测试建库失败：%@", error);
    assert((store && !error));
    return store;
}

// 验证完整任务、跨天日期、UUID、清单和子任务。
static void tstdata(NSString *path) {
    TaskStore *store = tstopn(path);
    assert(([store schver:nil] == TS_SCH_VER));
    assert(([store lsLsts:nil].count == 1 && [store lsTsks:nil].count == 0));
    NSDictionary *list = [store crtLst:@"研究" error:nil];
    assert((list && [store updLst:list[@"list_id"] title:@"项目" error:nil]));
    assert(([store lsLsts:nil].count == 2));
    NSArray *rule = @[@"RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR;COUNT=10", @"EXDATE:20261102T010000Z", @"RDATE:20261103T010000Z"];
    NSDictionary *task = [store crtTsk:@{@"title": @"跨天研究", @"notes": @"第一天调研\n第二天整理 ' OR 1=1 --",
        @"due_at": @1700000000.125, @"deadline_at": @1700259200.5, @"timezone_id": @"Asia/Shanghai",
        @"planned_duration": @172800, @"starred": @YES, @"urgency": @3, @"difficulty": @2,
        @"list_id": list[@"list_id"], @"position": @12, @"recurrence_type": @"weekly", @"recurrence_interval": @2,
        @"recurrence": rule} error:nil];
    assert((task && [[NSUUID alloc] initWithUUIDString:task[@"task_id"]]));
    NSString *taskID = task[@"task_id"];
    NSDictionary *read = [store rdTsk:taskID.uppercaseString error:nil];
    assert(([read isEqual:task]));
    assert(([read[@"due_at"] doubleValue] == 1700000000.125 && [read[@"planned_duration"] doubleValue] > 86400));
    assert(([read[@"status"] isEqual:@"needsAction"] && [read[@"recurrence"] isEqual:rule]));
    assert((![store updTsk:taskID fields:@{@"recurrence_interval": @3} error:nil]));
    assert((![store updTsk:taskID fields:@{@"list_id": TS_DFLT_LST} error:nil]));
    NSDictionary *group = [store crtTsk:@{@"title": @"分组", @"list_id": list[@"list_id"]} error:nil];
    NSString *groupID = group[@"task_id"];
    NSDictionary *child = [store crtTsk:@{@"title": @"整理资料", @"list_id": list[@"list_id"], @"parent_id": groupID} error:nil];
    assert((child));
    assert((![store updTsk:groupID fields:@{@"parent_id": child[@"task_id"]} error:nil]));
    assert((![store updTsk:groupID fields:@{@"due_at": @1700000000, @"recurrence_type": @"daily"} error:nil]));
    assert(([store updTsk:groupID fields:@{@"list_id": TS_DFLT_LST} error:nil]));
    assert(([[store rdTsk:child[@"task_id"] error:nil][@"list_id"] isEqual:TS_DFLT_LST]));
    assert(([store updTsk:taskID fields:@{@"status": @"completed"} error:nil]));
    NSDictionary *completed = [store rdTsk:taskID error:nil];
    assert(([completed[@"completed_at"] isKindOfClass:NSNumber.class]));
    assert(([completed[@"created_at"] isEqual:task[@"created_at"]]));
    assert(([store updTsk:taskID fields:@{@"status": @"needsAction", @"snooze_until": @1700500000} error:nil]));
    read = [store rdTsk:taskID error:nil];
    assert((read[@"completed_at"] == NSNull.null && [read[@"deadline_at"] isEqual:task[@"deadline_at"]]));
    assert(([read[@"due_at"] isEqual:task[@"due_at"]] && [read[@"recurrence"] isEqual:rule]));
    assert(([store updTsk:taskID fields:@{@"deleted": @YES} error:nil]));
    assert(([store rdTsk:taskID error:nil] && [store lsTsks:nil].count == 3));
    NSDictionary *occ = [store crtOcc:taskID at:@1700000000.125 error:nil];
    assert((occ && [[store crtOcc:taskID at:@1700000000.125 error:nil][@"occurrence_id"] isEqual:occ[@"occurrence_id"]]));
    assert(([store lsOcc:taskID error:nil].count == 1));
    assert(([store updOcc:occ[@"occurrence_id"] fields:@{@"status": @"presented", @"triggered_at": @1700000001.25} error:nil]));
    assert(([store updOcc:occ[@"occurrence_id"] fields:@{@"status": @"snoozed", @"handled_at": @1700000002.25,
        @"action": @"snooze", @"next_fire_at": @1700000300} error:nil]));
    assert(([[store lsOcc:taskID error:nil].firstObject[@"action"] isEqual:@"snooze"]));
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[read[@"due_at"] doubleValue]];
    NSString *local = [formatter stringFromDate:date];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    assert((![[formatter stringFromDate:date] isEqual:local]));
    assert(([[store rdTsk:taskID error:nil][@"due_at"] isEqual:read[@"due_at"]]));
    assert(([tstval(path, "PRAGMA journal_mode") isEqual:@"delete"]));
    assert(([tstval(path, "PRAGMA integrity_check") isEqual:@"ok"]));
    struct stat info;
    assert((stat(path.fileSystemRepresentation, &info) == 0 && (info.st_mode & 0777) == 0600));
    assert((stat(path.stringByDeletingLastPathComponent.fileSystemRepresentation, &info) == 0 && (info.st_mode & 0777) == 0700));
}

// 验证仅日期与截止边界在夏令时跨天时保存为绝对时间。
static void tstdates(NSString *path) {
    TaskStore *store = tstopn(path);
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
    NSNumber *start = @([formatter dateFromString:@"2026-11-01 00:00:00"].timeIntervalSince1970);
    NSNumber *end = @([formatter dateFromString:@"2026-11-02 00:00:00"].timeIntervalSince1970);
    assert((end.doubleValue - start.doubleValue == 25 * 3600));
    NSDictionary *task = [store crtTsk:@{@"title": @"日期任务", @"due_at": start, @"schedule_kind": @"date",
        @"deadline_at": end, @"deadline_kind": @"date", @"timezone_id": @"America/New_York"} error:nil];
    assert((task && [[store rdTsk:task[@"task_id"] error:nil][@"deadline_at"] isEqual:end]));
    assert((![store updTsk:task[@"task_id"] fields:@{@"deadline_at": @(end.doubleValue + 3600), @"deadline_kind": @"date"} error:nil]));
    assert((![store crtTsk:@{@"title": @"错误日界", @"due_at": @1700000000, @"schedule_kind": @"date"} error:nil]));
}

// 验证输入异常、失败事务、外键与稳定字段保护。
static void tstedges(NSString *path) {
    TaskStore *store = tstopn(path);
    NSDictionary *task = [store crtTsk:@{@"title": @"边界"} error:nil];
    NSString *taskID = task[@"task_id"];
    NSArray *badFields = @[@{}, @{@"title": @" "}, @{@"title": NSNull.null}, @{@"title": @42},
        @{@"title": @"x", @"notes": NSNull.null}, @{@"title": @"x", @"timezone_id": @"invalid/zone"},
        @{@"title": @"x", @"status": @"cancelled"}, @{@"title": @"x", @"urgency": @4},
        @{@"title": @"x", @"difficulty": @(-1)}, @{@"title": @"x", @"difficulty": @1.5},
        @{@"title": @"x", @"recurrence_interval": @0}, @{@"title": @"x", @"due_at": @(NAN)},
        @{@"title": @"x", @"planned_duration": @0}, @{@"title": @"x", @"task_id": taskID},
        @{@"title": @"x", @"due_at": @YES}, @{@"title": @"x", @"deadline_kind": @"date"},
        @{@"title": @"x", @"parent_id": @"invalid"}, @{@"title": @"x", @"recurrence": @[@"DTSTART:20260101T000000Z"]}];
    for (NSDictionary *fields in badFields) {
        NSError *error = nil;
        assert((![store crtTsk:fields error:&error] && error));
    }
    assert((![store crtTsk:(NSDictionary *)(id)@[] error:nil]));
    assert((![store rdTsk:@"not-a-uuid" error:nil]));
    assert((![store updTsk:taskID fields:@{@"created_at": @1} error:nil]));
    assert((![store updTsk:NSUUID.UUID.UUIDString fields:@{@"title": @"missing"} error:nil]));
    assert((![store crtOcc:NSUUID.UUID.UUIDString at:@1 error:nil]));
    assert((![store crtOcc:taskID at:@(INFINITY) error:nil]));
    assert(([store lsTsks:nil].count == 1));
    assert((![store wrTxn:^BOOL(NSError **failure) {
        assert(([store updTsk:taskID fields:@{@"notes": @"应回滚"} error:failure]));
        assert(([store crtOcc:taskID at:@1 error:failure]));
        [store updTsk:taskID fields:@{@"title": @""} error:nil];
        return YES;
    } error:nil]));
    assert(([[store rdTsk:taskID error:nil][@"notes"] isEqual:@""] && [store lsOcc:taskID error:nil].count == 0));
    @try {
        [store wrTxn:^BOOL(NSError **failure) {
            assert(([store updTsk:taskID fields:@{@"notes": @"异常回滚"} error:failure]));
            [NSException raise:@"expected-test" format:@"测试事务异常"];
            return YES;
        } error:nil];
        assert((NO));
    } @catch (NSException *exception) { assert(([exception.name isEqual:@"expected-test"])); }
    assert(([[store rdTsk:taskID error:nil][@"notes"] isEqual:@""]));
    NSDictionary *occ = [store crtOcc:taskID at:@1 error:nil];
    assert((![store updOcc:occ[@"occurrence_id"] fields:@{@"status": @"presented"} error:nil]));
    assert(([[store lsOcc:taskID error:nil].firstObject[@"status"] isEqual:@"pending"]));
    assert(([tstval(path, "PRAGMA integrity_check") isEqual:@"ok"]));
}

// 验证旧版本迁移、迁移失败回滚和拒绝未知版本。
static void tstmgrt(NSString *root) {
    NSString *fixture = [NSString stringWithContentsOfFile:@"Tests/Fixtures/store-v1.sql" encoding:NSUTF8StringEncoding error:nil];
    assert((fixture));
    NSString *path = [root stringByAppendingPathComponent:@"migration.sqlite3"];
    tstsql(path, fixture);
    TaskStore *store = tstopn(path);
    assert(([store schver:nil] == TS_SCH_VER));
    NSDictionary *task = [store rdTsk:@"11111111-1111-4111-8111-111111111111" error:nil];
    assert(([task[@"title"] isEqual:@"跨天报告"] && [task[@"notes"] isEqual:@"必须保留"]));
    assert(([task[@"due_at"] doubleValue] == 1700000000.125 && [task[@"urgency"] intValue] == 0));
    assert(([task[@"planned_duration"] intValue] == 172800 && [store lsOcc:task[@"task_id"] error:nil].count == 1));
    store = nil;
    assert(([tstopn(path) lsTsks:nil].count == 1));
    NSString *v2 = [fixture stringByAppendingString:@"ALTER TABLE tasks ADD COLUMN urgency INTEGER NOT NULL DEFAULT 0;"
        "ALTER TABLE tasks ADD COLUMN difficulty INTEGER NOT NULL DEFAULT 0;"
        "CREATE INDEX occurrences_due ON reminder_occurrences(status,scheduled_at);"
        "UPDATE tasks SET urgency=3,difficulty=2;UPDATE store_meta SET schema_version=2;"];
    NSString *upgrade = [root stringByAppendingPathComponent:@"version2.sqlite3"];
    tstsql(upgrade, v2); store = tstopn(upgrade);
    task = [store rdTsk:@"11111111-1111-4111-8111-111111111111" error:nil];
    NSDictionary *occ = [store lsOcc:task[@"task_id"] error:nil].firstObject;
    assert(([store schver:nil] == TS_SCH_VER && [task[@"urgency"] intValue] == 3 && [task[@"difficulty"] intValue] == 2));
    assert(([occ[@"occurrence_id"] isEqual:@"22222222-2222-4222-8222-222222222222"] && [occ[@"cycle_at"] isEqual:task[@"due_at"]]));
    assert(([occ[@"generation"] intValue] == 1 && [task[@"reminder_version"] intValue] == 1));
    assert(([tstval(upgrade, "PRAGMA integrity_check") isEqual:@"ok"]));
    NSString *v2failed = [root stringByAppendingPathComponent:@"version2-failed.sqlite3"];
    tstsql(v2failed, [v2 stringByAppendingString:@"ALTER TABLE tasks ADD COLUMN reminder_version INTEGER;"]);
    assert((![[TaskStore alloc] initAt:v2failed error:nil]));
    assert(([tstval(v2failed, "SELECT schema_version FROM store_meta") intValue] == 2));
    assert(([tstval(v2failed, "SELECT count(*) FROM pragma_table_info('store_meta') WHERE name='data_revision'") intValue] == 0));
    assert(([tstval(v2failed, "SELECT occurrence_id FROM reminder_occurrences") isEqual:@"22222222-2222-4222-8222-222222222222"]));
    NSString *failed = [root stringByAppendingPathComponent:@"failed.sqlite3"];
    tstsql(failed, [fixture stringByAppendingString:@"ALTER TABLE tasks ADD COLUMN difficulty INTEGER;"]);
    NSError *error = nil;
    assert((![[TaskStore alloc] initAt:failed error:&error] && error));
    assert(([tstval(failed, "SELECT schema_version FROM store_meta") intValue] == 1));
    assert(([tstval(failed, "SELECT count(*) FROM pragma_table_info('tasks') WHERE name='urgency'") intValue] == 0));
    assert(([tstval(failed, "SELECT notes FROM tasks") isEqual:@"必须保留"]));
    NSString *future = [root stringByAppendingPathComponent:@"future.sqlite3"];
    tstsql(future, [fixture stringByAppendingString:@"UPDATE store_meta SET schema_version=99;"]);
    assert((![[TaskStore alloc] initAt:future error:nil]));
    assert(([tstval(future, "SELECT schema_version FROM store_meta") intValue] == 99));
    NSString *corrupt = [root stringByAppendingPathComponent:@"corrupt.sqlite3"];
    NSData *bytes = [@"not a database" dataUsingEncoding:NSUTF8StringEncoding];
    assert(([bytes writeToFile:corrupt atomically:YES]));
    assert((![[TaskStore alloc] initAt:corrupt error:nil]));
    assert(([[NSData dataWithContentsOfFile:corrupt] isEqual:bytes]));
    assert((![[TaskStore alloc] initAt:@"relative.sqlite3" error:nil]));
}

// 启动新的测试进程，禁止跨fork继承SQLite连接。
static NSTask *tstproc(NSArray *arguments) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];
    task.arguments = arguments;
    NSError *error = nil;
    assert(([task launchAndReturnError:&error] && !error));
    return task;
}

// 在独立进程中写入事务或模拟事务中断。
static int tstchild(NSArray *arguments) {
    TaskStore *store = tstopn(arguments[2]);
    NSString *taskID = arguments[3];
    NSString *mode = arguments[1];
    if ([mode isEqual:@"--crash"]) {
        [store wrTxn:^BOOL(NSError **error) {
            assert(([store updTsk:taskID fields:@{@"notes": @"半写入", @"urgency": @3} error:error]));
            assert(([store crtOcc:taskID at:@42 error:error]));
            _exit(77);
        } error:nil];
        return 1;
    }
    if ([mode isEqual:@"--reader"]) {
        for (int index = 0; index < 50; index++) {
            assert(([store wrTxn:^BOOL(NSError **error) {
                NSDictionary *task = [store rdTsk:taskID error:error];
                NSArray *occurrences = [store lsOcc:taskID error:error];
                return task && occurrences && [task[@"notes"] integerValue] == (NSInteger)occurrences.count;
            } error:nil]));
        }
        return 0;
    }
    int writer = [arguments[4] intValue];
    for (int index = 0; index < 40; index++) {
        assert(([store wrTxn:^BOOL(NSError **error) {
            NSDictionary *task = [store rdTsk:taskID error:error];
            NSString *notes = [NSString stringWithFormat:@"%ld", (long)[task[@"notes"] integerValue] + 1];
            return task && [store updTsk:taskID fields:@{@"notes": notes, @"title": notes} error:error]
                && [store crtOcc:taskID at:@(writer * 1000 + index) error:error] != nil;
        } error:nil]));
    }
    return 0;
}

// 验证多进程竞争、提交完整性和中断后自动恢复。
static void tstprocs(NSString *path) {
    TaskStore *store = tstopn(path);
    NSDictionary *task = [store crtTsk:@{@"title": @"0", @"notes": @"0"} error:nil];
    NSString *taskID = task[@"task_id"];
    NSTask *first = tstproc(@[@"--writer", path, taskID, @"1"]);
    NSTask *second = tstproc(@[@"--writer", path, taskID, @"2"]);
    NSTask *reader = tstproc(@[@"--reader", path, taskID]);
    for (NSTask *process in @[first, second, reader]) {
        [process waitUntilExit];
        assert((process.terminationStatus == 0));
    }
    NSDictionary *read = [store rdTsk:taskID error:nil];
    assert(([read[@"notes"] intValue] == 80 && [read[@"title"] isEqual:read[@"notes"]]));
    assert(([store lsOcc:taskID error:nil].count == 80));
    NSTask *crash = tstproc(@[@"--crash", path, taskID]);
    [crash waitUntilExit];
    assert((crash.terminationStatus == 77));
    assert(([[store rdTsk:taskID error:nil] isEqual:read]));
    assert(([store lsOcc:taskID error:nil].count == 80));
    assert(([tstval(path, "PRAGMA integrity_check") isEqual:@"ok"]));
    assert(([tstval(path, "SELECT count(*) FROM pragma_foreign_key_check") intValue] == 0));
}

// 验证首次建库的多进程竞争。
static void tstfirst(NSString *path) {
    NSTask *first = tstproc(@[@"--init", path]);
    NSTask *second = tstproc(@[@"--init", path]);
    for (NSTask *process in @[first, second]) { [process waitUntilExit]; assert((process.terminationStatus == 0)); }
    assert(([tstval(path, "SELECT schema_version FROM store_meta") intValue] == TS_SCH_VER));
    assert(([tstval(path, "SELECT count(*) FROM task_lists") intValue] == 1));
}

// 验证加星时间、清单清理、单次完成和过时意图。
static void tstlst(NSString *path) {
    TaskStore *store = tstopn(path); NSError *error = nil;
    NSDictionary *list = [store crtLst:@"扩展清单" error:nil]; NSString *listID = list[@"list_id"];
    NSDictionary *parent = [store crtTsk:@{@"title":@"父任务",@"list_id":listID,@"starred":@1} error:nil];
    NSString *uuid = parent[@"task_id"]; NSNumber *star = parent[@"starred_at"];
    assert((ts_num(star) && [store updTsk:uuid fields:@{@"title":@"修改标题"} error:nil]));
    assert(([[store rdTsk:uuid error:nil][@"starred_at"] isEqual:star]));
    assert(([store updTsk:uuid fields:@{@"starred":@0} error:nil] && [store rdTsk:uuid error:nil][@"starred_at"] == NSNull.null));
    assert(([store updTsk:uuid fields:@{@"starred":@1} error:nil] && ts_num([store rdTsk:uuid error:nil][@"starred_at"])));
    assert((![store updTsk:uuid fields:@{@"starred_at":@0} error:&error] && [error.userInfo[@"kind"] isEqual:@"invalid_fields"]));
    NSDictionary *child = [store crtTsk:@{@"title":@"子任务",@"list_id":listID,@"parent_id":uuid} error:nil];
    NSDictionary *keep = [store crtTsk:@{@"title":@"保留任务",@"list_id":listID} error:nil];
    NSDictionary *other = [store crtTsk:@{@"title":@"其他清单"} error:nil];
    assert(([store cmplTsk:uuid error:nil] && [store cmplTsk:child[@"task_id"] error:nil] && [store cmplTsk:other[@"task_id"] error:nil]));
    long long revision = [store revision:nil];
    assert((![store wrTxn:^BOOL(NSError **failure) { return [store clrCmpl:listID error:failure] && [store updTsk:keep[@"task_id"] fields:@{@"urgency":@9} error:failure]; } error:nil]));
    assert(([store revision:nil] == revision && ![[store rdTsk:uuid error:nil][@"deleted"] boolValue]));
    assert(([store clrCmpl:listID error:nil]));
    assert(([[store rdTsk:uuid error:nil][@"deleted"] boolValue] && [[store rdTsk:child[@"task_id"] error:nil][@"deleted"] boolValue]));
    assert((![[store rdTsk:keep[@"task_id"] error:nil][@"deleted"] boolValue] && ![[store rdTsk:other[@"task_id"] error:nil][@"deleted"] boolValue]));
    assert((![store delLst:TS_DFLT_LST error:&error] && [error.userInfo[@"kind"] isEqual:@"invalid_fields"]));
    NSDictionary *occ = [store crtOcc:keep[@"task_id"] at:@1 error:nil];
    assert(([store delLst:listID error:nil] && [store lsLsts:nil].count == 1));
    assert(([[store rdTsk:keep[@"task_id"] error:nil][@"deleted"] boolValue] && [[[store lsOcc:keep[@"task_id"] error:nil] firstObject][@"action"] isEqual:@"invalidated"]));
    assert((occ && ![store crtTsk:@{@"title":@"失效清单",@"list_id":listID} error:&error] && [error.userInfo[@"kind"] isEqual:@"not_found"]));
    assert((![store clrCmpl:listID error:&error] && [error.userInfo[@"kind"] isEqual:@"not_found"]));
    assert((![store updLst:listID title:@"已删除" error:&error] && [error.userInfo[@"kind"] isEqual:@"not_found"]));
    NSNumber *due = @(NSDate.date.timeIntervalSince1970 + 3600);
    NSDictionary *repeat = [store crtTsk:@{@"title":@"重复",@"due_at":due,@"timezone_id":@"UTC",@"recurrence_type":@"daily"} error:nil];
    NSString *repeatID = repeat[@"task_id"]; NSDictionary *display = [store lsPnd:nil].firstObject;
    assert(([display[@"task_id"] isEqual:repeatID] && [display[@"next_cycle_at"] isEqual:due]));
    assert(([store cmplNxt:repeatID cycle:due generation:repeat[@"reminder_version"] error:nil]));
    assert(([[store rdTsk:repeatID error:nil][@"status"] isEqual:@"needsAction"] && [store lsOcc:repeatID error:nil].count == 2));
    NSNumber *next = [store lsPnd:nil].firstObject[@"next_cycle_at"]; assert((next.doubleValue > due.doubleValue));
    revision = [store revision:nil];
    assert(([store cmplNxt:repeatID cycle:due generation:repeat[@"reminder_version"] error:nil] && [store revision:nil] == revision));
    assert(([store lsOcc:repeatID error:nil].count == 2));
    assert(([store updTsk:repeatID fields:@{@"due_at":@(due.doubleValue+7200)} error:nil]));
    assert(([store cmplNxt:repeatID cycle:next generation:repeat[@"reminder_version"] error:nil] && [store lsOcc:repeatID error:nil].count == 2));
    assert((![store cmplNxt:repeatID cycle:due generation:@1.5 error:&error] && [error.userInfo[@"kind"] isEqual:@"invalid_fields"]));
    assert(([store cmplNxt:repeatID error:nil] && [store lsOcc:repeatID error:nil].count == 4));
    assert(([store cmplTsk:repeatID error:nil] && [store rstrTsk:repeatID error:nil]));
    // 已软删除的子任务不再阻止父任务使用重复规则。
    NSDictionary *former = [store crtTsk:@{@"title":@"原父任务",@"due_at":due} error:nil];
    NSDictionary *removed = [store crtTsk:@{@"title":@"已删子任务",@"parent_id":former[@"task_id"]} error:nil];
    assert((![store updTsk:former[@"task_id"] fields:@{@"recurrence_type":@"daily"} error:nil]));
    assert(([store delTsk:removed[@"task_id"] error:nil]));
    assert(([store updTsk:former[@"task_id"] fields:@{@"recurrence_type":@"daily"} error:nil]));
    assert(([[store rdTsk:removed[@"task_id"] error:nil][@"deleted"] boolValue]));
    assert(([tstval(path,"PRAGMA integrity_check") isEqual:@"ok"]));
}

// 验证第三版数据升级及失败时完整回滚。
static void tstv3(NSString *root) {
    for (NSNumber *fail in @[@NO,@YES]) {
        NSString *path = [root stringByAppendingPathComponent:fail.boolValue ? @"v3-failed.sqlite3" : @"v3.sqlite3"];
        __block NSString *uuid; __block NSNumber *updated;
        @autoreleasepool { TaskStore *store = tstopn(path); NSDictionary *task = [store crtTsk:@{@"title":@"第三版数据",@"starred":@1} error:nil]; uuid = task[@"task_id"]; updated = task[@"updated_at"]; }
        // 降级夹具先移除新版专有结构，保留真实第三版形态。
        tstsql(path,@"DROP TABLE task_reviews;ALTER TABLE tasks DROP COLUMN planning_mode;DROP TABLE agenda_slots;DROP TABLE routine_documents;DROP INDEX routine_source_unique;ALTER TABLE tasks DROP COLUMN routine_kind;ALTER TABLE tasks DROP COLUMN routine_end;ALTER TABLE tasks DROP COLUMN routine_enabled;ALTER TABLE tasks DROP COLUMN routine_source;");
        NSString *fixture=[NSString stringWithContentsOfFile:@"Tests/Fixtures/occurrence-v8.sql" encoding:NSUTF8StringEncoding error:nil];
        for (NSString *line in [fixture componentsSeparatedByString:@"\n"]) if ([line hasPrefix:@"CREATE TABLE reminder_occurrences "])
            tstsql(path,[@"DROP TABLE reminder_occurrences;" stringByAppendingString:line]);
        tstsql(path,@"DROP TABLE capture_request; DROP TABLE reminder_checkins; ALTER TABLE reminder_occurrences DROP COLUMN defer_count; ALTER TABLE reminder_occurrences DROP COLUMN hold_reason; ALTER TABLE reminder_occurrences DROP COLUMN hold_until; ALTER TABLE tasks DROP COLUMN starred_at; ALTER TABLE task_lists DROP COLUMN deleted; UPDATE store_meta SET schema_version=3;");
        if (fail.boolValue) tstsql(path,@"CREATE TRIGGER migrate_fail BEFORE UPDATE ON store_meta BEGIN SELECT RAISE(ABORT,'blocked'); END;");
        NSError *error = nil; TaskStore *store = [[TaskStore alloc] initAt:path error:&error];
        if (fail.boolValue) {
            assert((!store && error));
            assert(([tstval(path,"SELECT schema_version FROM store_meta") intValue] == 3));
            assert(([tstval(path,"SELECT count(*) FROM pragma_table_info('tasks') WHERE name='starred_at'") intValue] == 0));
            assert(([tstval(path,"SELECT count(*) FROM pragma_table_info('task_lists') WHERE name='deleted'") intValue] == 0));
            tstsql(path,@"DROP TRIGGER migrate_fail;"); store = tstopn(path);
        }
        assert(([store schver:nil] == TS_SCH_VER && [store lsLsts:nil].count == 1));
        NSDictionary *task = [store rdTsk:uuid error:nil];
        assert(([task[@"title"] isEqual:@"第三版数据"] && [task[@"starred_at"] isEqual:updated]));
    }
}

// 执行真实原生SQLite存储验收。
int main(void) {
    @autoreleasepool {
        NSArray *arguments = NSProcessInfo.processInfo.arguments;
        if (arguments.count > 1) {
            if ([arguments[1] isEqual:@"--init"]) return [tstopn(arguments[2]) schver:nil] == TS_SCH_VER ? 0 : 1;
            return tstchild(arguments);
        }
        char directory[] = "/tmp/trolltask-store.XXXXXX";
        assert((mkdtemp(directory)));
        NSString *root = @(directory);
        tstdata([root stringByAppendingPathComponent:@"private/data.sqlite3"]);
        tstdates([root stringByAppendingPathComponent:@"dates.sqlite3"]);
        tstedges([root stringByAppendingPathComponent:@"edges.sqlite3"]);
        tstmgrt(root);
        tstv3(root);
        tstlst([root stringByAppendingPathComponent:@"lists.sqlite3"]);
        tstprocs([root stringByAppendingPathComponent:@"parallel.sqlite3"]);
        tstfirst([root stringByAppendingPathComponent:@"first.sqlite3"]);
        assert(([NSFileManager.defaultManager removeItemAtPath:root error:nil]));
        puts("TaskStore: models, UUIDs, absolute times, constraints, migration rollback, concurrent processes and interrupted transaction recovery passed");
    }
    return 0;
}
