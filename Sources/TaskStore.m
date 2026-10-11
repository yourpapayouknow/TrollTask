#import "LBHead.h"

// 生成结构化存储错误。
static BOOL ts_err(NSError **error, NSInteger code, NSString *message) {
    NSString *kind = @"database_failure";
    if (code == SQLITE_CONSTRAINT_PRIMARYKEY) { kind = @"duplicate_uuid"; message = @"UUID已存在"; }
    else if ((code & 255) == SQLITE_NOTFOUND) kind = @"not_found";
    else if ((code & 255) == SQLITE_BUSY || (code & 255) == SQLITE_LOCKED) kind = @"database_busy";
    else if ([@[@(SQLITE_MISMATCH), @(SQLITE_MISUSE), @(SQLITE_CONSTRAINT)] containsObject:@(code & 255)]) kind = @"invalid_fields";
    if (error) *error = [NSError errorWithDomain:@"com.iwmei.taskforiwmei.store" code:code
                                      userInfo:@{NSLocalizedDescriptionKey: message, @"kind": kind}];
    return NO;
}

// 检查有限绝对时间或正数时长。
BOOL ts_num(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()
        && isfinite([value doubleValue]);
}

// 检查稳定UUID字符串。
static BOOL ts_uuid(id value) {
    return [value isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:value] != nil;
}

// 检查非空短文本。
static BOOL ts_txt(id value, NSUInteger limit) {
    return [value isKindOfClass:NSString.class] && [value length] <= limit
        && [[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] > 0;
}

// 检查仅日期字段是否采用该时区的日界时间。
static BOOL ts_day(NSNumber *stamp, NSString *zone) {
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:zone];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:stamp.doubleValue];
    return fabs([calendar startOfDayForDate:date].timeIntervalSince1970 - stamp.doubleValue) < 0.000001;
}

// 创建私有共享目录与mobile所有的数据库文件。
static BOOL ts_pth(NSString *path, NSError **error) {
    if (![path isKindOfClass:NSString.class] || !path.isAbsolutePath)
        return ts_err(error, SQLITE_MISUSE, @"数据库路径必须为绝对路径");
    NSString *directory = path.stringByDeletingLastPathComponent;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions: @0700} error:error]) return NO;
    struct passwd *mobile = NULL;
    BOOL production = [path isEqualToString:TS_DB_PATH];
    if (production && geteuid() == 0) {
        mobile = getpwnam("mobile");
        if (!mobile || chown(directory.fileSystemRepresentation, mobile->pw_uid, mobile->pw_gid) != 0
            || chmod(directory.fileSystemRepresentation, 0700) != 0)
            return ts_err(error, SQLITE_CANTOPEN, @"共享目录权限设置失败");
    }
    int descriptor = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (descriptor >= 0) {
        BOOL owned = !mobile || fchown(descriptor, mobile->pw_uid, mobile->pw_gid) == 0;
        close(descriptor);
        if (!owned) return ts_err(error, SQLITE_CANTOPEN, @"数据库所有者设置失败");
    } else if (errno != EEXIST) {
        return ts_err(error, SQLITE_CANTOPEN, @"数据库文件创建失败");
    }
    if (mobile && (chown(path.fileSystemRepresentation, mobile->pw_uid, mobile->pw_gid) != 0
        || chmod(path.fileSystemRepresentation, 0600) != 0))
        return ts_err(error, SQLITE_CANTOPEN, @"数据库权限设置失败");
    return YES;
}

@interface TaskStore () {
    sqlite3 *_db;
    BOOL _inTxn;
    NSError *_txErr;
    BOOL _dirty;
}
@property(nonatomic, readwrite, copy) NSString *path;
@property(nonatomic, readwrite, copy) NSString *changeNote;
@property(nonatomic, readwrite, strong) NSError *syncError;
@end

@implementation TaskStore

// 共用标题与说明规则，不开启事务或修改数据库。
+ (BOOL)vldTxt:(NSString *)title notes:(NSString *)notes error:(NSError **)error {
    if (!ts_txt(title, 1024)) return ts_err(error, SQLITE_CONSTRAINT, @"任务标题无效");
    if (![notes isKindOfClass:NSString.class] || notes.length > 8192) return ts_err(error, SQLITE_CONSTRAINT, @"详细说明过长或无效");
    return YES;
}

// 打开当前进程的共享存储，失败后允许重试。
+ (instancetype)shrd:(NSError **)error {
    static TaskStore *store;
    @synchronized(self) {
        if (!store) store = [[self alloc] initAt:TS_DB_PATH error:error];
        return store;
    }
}

// 保存SQLite错误并阻止失败事务继续提交。
- (BOOL)dbErr:(NSInteger)code message:(NSString *)message error:(NSError **)error {
    NSError *failure = nil;
    ts_err(&failure, code, message);
    if (_inTxn && !_txErr) _txErr = failure;
    if (error) *error = failure;
    return NO;
}

// 执行内部固定SQL语句。
- (BOOL)exec:(const char *)sql error:(NSError **)error {
    int code = sqlite3_exec(_db, sql, NULL, NULL, NULL);
    return code == SQLITE_OK || [self dbErr:code message:@(sqlite3_errmsg(_db)) error:error];
}

// 绑定参数并读取完整结果，所有语句均在返回前结束。
- (NSArray *)qry:(const char *)sql values:(NSArray *)values error:(NSError **)error {
    sqlite3_stmt *statement = NULL;
    int code = sqlite3_prepare_v2(_db, sql, -1, &statement, NULL);
    BOOL writing = statement && !sqlite3_stmt_readonly(statement);
    for (NSUInteger index = 0; code == SQLITE_OK && index < values.count; index++) {
        id value = values[index];
        int slot = (int)index + 1;
        if (value == NSNull.null) code = sqlite3_bind_null(statement, slot);
        else if ([value isKindOfClass:NSString.class]) {
            NSData *text = [value dataUsingEncoding:NSUTF8StringEncoding];
            code = sqlite3_bind_text(statement, slot, [value UTF8String], (int)text.length, SQLITE_TRANSIENT);
        } else if ([value isKindOfClass:NSNumber.class]) {
            const char *type = [value objCType];
            code = (*type == 'd' || *type == 'f') ? sqlite3_bind_double(statement, slot, [value doubleValue])
                : sqlite3_bind_int64(statement, slot, [value longLongValue]);
        } else code = SQLITE_MISMATCH;
    }
    NSMutableArray *rows = [NSMutableArray array];
    while (code == SQLITE_OK && (code = sqlite3_step(statement)) == SQLITE_ROW) {
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        for (int column = 0; column < sqlite3_column_count(statement); column++) {
            id value = NSNull.null;
            int type = sqlite3_column_type(statement, column);
            if (type == SQLITE_INTEGER) value = @(sqlite3_column_int64(statement, column));
            else if (type == SQLITE_FLOAT) value = @(sqlite3_column_double(statement, column));
            else if (type == SQLITE_TEXT) value = [[NSString alloc] initWithBytes:sqlite3_column_text(statement, column)
                length:sqlite3_column_bytes(statement, column) encoding:NSUTF8StringEncoding];
            if (!value) { code = SQLITE_MISMATCH; break; }
            row[@(sqlite3_column_name(statement, column))] = value;
        }
        if (code != SQLITE_MISMATCH) { [rows addObject:row]; code = SQLITE_OK; }
    }
    if (code != SQLITE_DONE) [self dbErr:code message:@(sqlite3_errmsg(_db)) error:error];
    if (code == SQLITE_DONE && writing && sqlite3_changes(_db) > 0) _dirty = YES;
    sqlite3_finalize(statement);
    return code == SQLITE_DONE ? rows : nil;
}

// 串行化连接使用并原子提交多步操作。
- (BOOL)wrTxn:(BOOL (NS_NOESCAPE ^)(NSError **))work error:(NSError **)error {
    @synchronized(self) {
        if (!work) return [self dbErr:SQLITE_MISUSE message:@"缺少事务操作" error:error];
        if (_inTxn) {
            NSError *failure = nil;
            BOOL success = work(&failure);
            if (!success && !_txErr) {
                _txErr = failure ?: [NSError errorWithDomain:@"com.iwmei.taskforiwmei.store" code:SQLITE_ABORT
                    userInfo:@{NSLocalizedDescriptionKey: @"事务操作失败"}];
            }
            if (!success && error) *error = _txErr;
            return success;
        }
        if (![self exec:"BEGIN IMMEDIATE" error:error]) return NO;
        _inTxn = YES;
        _txErr = nil;
        _dirty = NO;
        BOOL committed = NO;
        BOOL publish = NO;
        @try {
            NSError *failure = nil;
            BOOL success = work(&failure);
            publish = success && !_txErr && _dirty;
            if (publish) success = [self exec:"UPDATE store_meta SET data_revision=data_revision+1 WHERE singleton=1" error:&failure];
            if (success && !_txErr) committed = [self exec:"COMMIT" error:&failure];
            if (!committed && error) *error = _txErr ?: failure ?: [NSError errorWithDomain:
                @"com.iwmei.taskforiwmei.store" code:SQLITE_ABORT userInfo:@{NSLocalizedDescriptionKey: @"事务已回滚"}];
        } @finally {
            if (!committed) sqlite3_exec(_db, "ROLLBACK", NULL, NULL, NULL);
            _inTxn = NO;
            _txErr = nil;
            _dirty = NO;
        }
        if (committed && publish) {
            uint32_t status = notify_post(self.changeNote.UTF8String);
            self.syncError = status == NOTIFY_STATUS_OK ? nil : [NSError errorWithDomain:@"com.iwmei.taskforiwmei.sync" code:status
                userInfo:@{NSLocalizedDescriptionKey: @"数据已提交，通知发送失败", @"kind": @"notification_failure"}];
        }
        return committed;
    }
}

// 按版本逐级迁移，DDL和版本号在同一事务中提交。
- (BOOL)mgrt:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        if (![self exec:"CREATE TABLE IF NOT EXISTS store_meta (singleton INTEGER PRIMARY KEY CHECK(singleton=1),"
            "schema_version INTEGER NOT NULL CHECK(schema_version>=0));"
            "INSERT OR IGNORE INTO store_meta(singleton,schema_version) VALUES(1,0);" error:failure]) return NO;
        NSInteger version = [self schver:failure];
        if (version < 0) return NO;
        if (version > TS_SCH_VER) return [self dbErr:SQLITE_ERROR message:@"数据库版本高于当前App" error:failure];
        if (version == 0) {
            if (![self exec:
                "CREATE TABLE task_lists (list_id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL CHECK(length(title) BETWEEN 1 AND 1024),"
                "created_at REAL NOT NULL, updated_at REAL NOT NULL);"
                "INSERT INTO task_lists VALUES('00000000-0000-4000-8000-000000000001','我的任务',strftime('%s','now'),strftime('%s','now'));"
                "CREATE TABLE tasks (task_id TEXT PRIMARY KEY NOT NULL, title TEXT NOT NULL CHECK(length(title) BETWEEN 1 AND 1024),"
                "notes TEXT NOT NULL DEFAULT '' CHECK(length(notes)<=8192), due_at REAL, timezone_id TEXT NOT NULL,"
                "recurrence_type TEXT NOT NULL DEFAULT 'none' CHECK(recurrence_type IN ('none','daily','weekly','monthly','yearly','custom')),"
                "recurrence_interval INTEGER NOT NULL DEFAULT 1 CHECK(typeof(recurrence_interval)='integer' AND recurrence_interval>=1),"
                "status TEXT NOT NULL DEFAULT 'needsAction' CHECK(status IN ('needsAction','completed')), snooze_until REAL,"
                "created_at REAL NOT NULL, updated_at REAL NOT NULL,"
                "list_id TEXT NOT NULL REFERENCES task_lists(list_id), parent_id TEXT REFERENCES tasks(task_id),"
                "position INTEGER NOT NULL DEFAULT 0 CHECK(typeof(position)='integer'), starred INTEGER NOT NULL DEFAULT 0 CHECK(starred IN (0,1)),"
                "schedule_kind TEXT NOT NULL DEFAULT 'none' CHECK(schedule_kind IN ('none','date','timed')),"
                "planned_duration REAL CHECK(planned_duration>0), deadline_at REAL,"
                "deadline_kind TEXT NOT NULL DEFAULT 'none' CHECK(deadline_kind IN ('none','date','timed')),"
                "recurrence_json TEXT NOT NULL DEFAULT '[]', completed_at REAL, deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1)),"
                "CHECK((status='completed' AND completed_at IS NOT NULL) OR (status='needsAction' AND completed_at IS NULL)),"
                "CHECK((schedule_kind='none' AND due_at IS NULL) OR (schedule_kind!='none' AND due_at IS NOT NULL)),"
                "CHECK((deadline_kind='none' AND deadline_at IS NULL) OR (deadline_kind!='none' AND deadline_at IS NOT NULL)),"
                "CHECK(parent_id IS NULL OR parent_id!=task_id));"
                "CREATE TABLE reminder_occurrences (occurrence_id TEXT PRIMARY KEY NOT NULL,"
                "task_id TEXT NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE, scheduled_at REAL NOT NULL,"
                "triggered_at REAL, handled_at REAL, status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','triggered','handled')),"
                "action TEXT, snooze_until REAL, created_at REAL NOT NULL, updated_at REAL NOT NULL, UNIQUE(task_id,scheduled_at),"
                "CHECK((status='pending' AND triggered_at IS NULL AND handled_at IS NULL) OR "
                "(status='triggered' AND triggered_at IS NOT NULL AND handled_at IS NULL) OR (status='handled' AND handled_at IS NOT NULL)));"
                "UPDATE store_meta SET schema_version=1 WHERE singleton=1;" error:failure]) return NO;
            version = 1;
        }
        if (version == 1) {
          if (![self exec:
            "ALTER TABLE tasks ADD COLUMN urgency INTEGER NOT NULL DEFAULT 0 CHECK(urgency BETWEEN 0 AND 3 AND typeof(urgency)='integer');"
            "ALTER TABLE tasks ADD COLUMN difficulty INTEGER NOT NULL DEFAULT 0 CHECK(difficulty BETWEEN 0 AND 3 AND typeof(difficulty)='integer');"
            "CREATE INDEX tasks_due ON tasks(deleted,status,due_at);"
            "CREATE INDEX tasks_deadline ON tasks(deleted,status,deadline_at);"
            "CREATE INDEX tasks_list ON tasks(list_id,parent_id,position);"
            "CREATE INDEX occurrences_due ON reminder_occurrences(status,scheduled_at);"
            "UPDATE store_meta SET schema_version=2 WHERE singleton=1;" error:failure]) return NO;
          version = 2;
        }
        if (version == 2 && ![self exec:
            "ALTER TABLE store_meta ADD COLUMN data_revision INTEGER NOT NULL DEFAULT 0;"
            "ALTER TABLE tasks ADD COLUMN reminder_version INTEGER NOT NULL DEFAULT 1;"
            "ALTER TABLE reminder_occurrences RENAME TO old_occurrences;"
            "CREATE TABLE reminder_occurrences (occurrence_id TEXT PRIMARY KEY NOT NULL, task_id TEXT NOT NULL REFERENCES tasks(task_id),"
            "scheduled_at REAL NOT NULL, triggered_at REAL, handled_at REAL, status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','triggered','handled')),"
            "action TEXT,snooze_until REAL,created_at REAL NOT NULL,updated_at REAL NOT NULL,"
            "generation INTEGER NOT NULL DEFAULT 1,kind TEXT NOT NULL DEFAULT 'plan' CHECK(kind IN ('plan','deadline','both')),cycle_at REAL NOT NULL,"
            "UNIQUE(task_id,generation,kind,cycle_at),"
            "CHECK((status='pending' AND triggered_at IS NULL AND handled_at IS NULL) OR (status='triggered' AND triggered_at IS NOT NULL AND handled_at IS NULL) OR (status='handled' AND handled_at IS NOT NULL)));"
            "INSERT INTO reminder_occurrences(occurrence_id,task_id,scheduled_at,triggered_at,handled_at,status,action,snooze_until,created_at,updated_at,cycle_at) "
            "SELECT occurrence_id,task_id,scheduled_at,triggered_at,handled_at,status,action,snooze_until,created_at,updated_at,scheduled_at FROM old_occurrences;"
            "DROP TABLE old_occurrences;CREATE INDEX occurrences_due ON reminder_occurrences(status,scheduled_at);"
            "UPDATE store_meta SET schema_version=3 WHERE singleton=1;" error:failure]) return NO;
        if (version <= 3 && ![self exec:
            "ALTER TABLE tasks ADD COLUMN starred_at REAL;"
            "UPDATE tasks SET starred_at=updated_at WHERE starred=1;"
            "ALTER TABLE task_lists ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0 CHECK(deleted IN (0,1));"
            "UPDATE store_meta SET schema_version=4 WHERE singleton=1;" error:failure]) return NO;
        return YES;
    } error:error];
}

// 打开系统SQLite连接并自动建库或迁移。
- (instancetype)initAt:(NSString *)path error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    @synchronized(TaskStore.class) {
        if (!ts_pth(path, error)) return nil;
        self.path = path;
        unsigned long long hash = 14695981039346656037ULL;
        NSData *bytes = [path dataUsingEncoding:NSUTF8StringEncoding];
        for (NSUInteger index = 0; index < bytes.length; index++) hash = (hash ^ ((const unsigned char *)bytes.bytes)[index]) * 1099511628211ULL;
        self.changeNote = [path isEqual:TS_DB_PATH] ? @TS_DATA_NOTE : [NSString stringWithFormat:@"%s.%016llx", TS_DATA_NOTE, hash];
        int code = sqlite3_open_v2(path.fileSystemRepresentation, &_db,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL);
        if (code != SQLITE_OK) { [self dbErr:code message:@(sqlite3_errmsg(_db)) error:error]; return nil; }
        sqlite3_extended_result_codes(_db, 1);
        code = sqlite3_busy_timeout(_db, 5000);
        if (code != SQLITE_OK) { [self dbErr:code message:@(sqlite3_errmsg(_db)) error:error]; return nil; }
        if (![self exec:"PRAGMA foreign_keys=ON; PRAGMA synchronous=EXTRA;" error:error]
            || ![self mgrt:error]) return nil;
        NSArray *mode = [self qry:"PRAGMA journal_mode=DELETE" values:@[] error:error];
        if (![mode.firstObject[@"journal_mode"] isEqual:@"delete"]) {
            if (mode) [self dbErr:SQLITE_ERROR message:@"数据库日志模式不可用" error:error];
            return nil;
        }
    }
    return self;
}

// 读取应用版本而不修改SQLite内部schema_version。
- (NSInteger)schver:(NSError **)error {
    @synchronized(self) {
        NSArray *rows = [self qry:"SELECT schema_version FROM store_meta WHERE singleton=1" values:@[] error:error];
        if (rows && rows.count != 1) [self dbErr:SQLITE_CORRUPT message:@"缺少数据模型版本" error:error];
        return rows.count == 1 ? [rows.firstObject[@"schema_version"] integerValue] : -1;
    }
}

// 校验任务字段及跨字段关系。
- (BOOL)vldTsk:(NSDictionary *)task error:(NSError **)error {
    NSError *textError = nil;
    if (![TaskStore vldTxt:task[@"title"] notes:task[@"notes"] error:&textError])
        return [self dbErr:textError.code message:textError.localizedDescription error:error];
    if (![task[@"timezone_id"] isKindOfClass:NSString.class] || ![NSTimeZone timeZoneWithName:task[@"timezone_id"]]
        || ![@[@"needsAction", @"completed"] containsObject:task[@"status"]]
        || ![@[@"none", @"daily", @"weekly", @"monthly", @"yearly", @"custom"] containsObject:task[@"recurrence_type"]])
        return [self dbErr:SQLITE_CONSTRAINT message:@"任务文本、时区或类型无效" error:error];
    for (NSString *key in @[@"due_at", @"deadline_at", @"snooze_until", @"planned_duration"])
        if (task[key] != NSNull.null && (!ts_num(task[key]) || ([key isEqual:@"planned_duration"] && [task[key] doubleValue] <= 0)
            || (![key isEqual:@"planned_duration"] && fabs([task[key] doubleValue]) >= 253402300800.0)))
            return [self dbErr:SQLITE_CONSTRAINT message:@"时间或时长无效" error:error];
    for (NSString *key in @[@"recurrence_interval", @"position", @"starred", @"deleted", @"urgency", @"difficulty"]) {
        id value = task[key];
        if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])
            || (![@[@"starred", @"deleted"] containsObject:key] && !ts_num(value))
            || [value doubleValue] != (double)[value longLongValue]
            || ([key isEqual:@"recurrence_interval"] && [value longLongValue] < 1)
            || ([@[@"starred", @"deleted"] containsObject:key] && ([value longLongValue] < 0 || [value longLongValue] > 1))
            || ([@[@"urgency", @"difficulty"] containsObject:key] && ([value longLongValue] < 0 || [value longLongValue] > 3)))
            return [self dbErr:SQLITE_CONSTRAINT message:@"分档、顺序或重复间隔无效" error:error];
    }
    for (NSString *prefix in @[@"schedule", @"deadline"]) {
        NSString *kind = task[[prefix stringByAppendingString:@"_kind"]];
        id stamp = task[[prefix isEqual:@"schedule"] ? @"due_at" : @"deadline_at"];
        if (![@[@"none", @"date", @"timed"] containsObject:kind] || ([kind isEqual:@"none"] != (stamp == NSNull.null)))
            return [self dbErr:SQLITE_CONSTRAINT message:@"日期模式与时间不匹配" error:error];
        if ([kind isEqual:@"date"] && !ts_day(stamp, task[@"timezone_id"]))
            return [self dbErr:SQLITE_CONSTRAINT message:@"仅日期字段应使用当地日界" error:error];
    }
    if (!ts_uuid(task[@"list_id"]) || (task[@"parent_id"] != NSNull.null && !ts_uuid(task[@"parent_id"])))
        return [self dbErr:SQLITE_CONSTRAINT message:@"清单或父任务标识无效" error:error];
    NSArray *recurrence = task[@"recurrence"];
    if (![recurrence isKindOfClass:NSArray.class]) return [self dbErr:SQLITE_CONSTRAINT message:@"重复规则必须为数组" error:error];
    for (id line in recurrence) {
        if (![line isKindOfClass:NSString.class] || [line length] > 8192 || [line rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound
            || !([line hasPrefix:@"RRULE:"] || [line hasPrefix:@"EXRULE:"] || [line hasPrefix:@"RDATE:"] || [line hasPrefix:@"RDATE;"]
                 || [line hasPrefix:@"EXDATE:"] || [line hasPrefix:@"EXDATE;"]))
            return [self dbErr:SQLITE_CONSTRAINT message:@"重复属性格式无效" error:error];
        NSRange separator = [line rangeOfString:@":"];
        if (separator.location == NSNotFound || separator.location + 1 == [line length])
            return [self dbErr:SQLITE_CONSTRAINT message:@"重复属性缺少内容" error:error];
    }
    if (([task[@"recurrence_type"] isEqual:@"none"] != (recurrence.count == 0))
        || (recurrence.count > 0 && task[@"due_at"] == NSNull.null))
        return [self dbErr:SQLITE_CONSTRAINT message:@"重复任务需要计划日期和规则" error:error];
    if ([task[@"recurrence_type"] isEqual:@"none"] && [task[@"recurrence_interval"] integerValue] != 1)
        return [self dbErr:SQLITE_CONSTRAINT message:@"不重复任务的间隔应为1" error:error];
    if (task[@"parent_id"] != NSNull.null && recurrence.count)
        return [self dbErr:SQLITE_CONSTRAINT message:@"子任务不能设置重复" error:error];
    return [TaskRule vld:task error:error];
}

// 生成可写字段名列表。
- (NSArray *)tskFlds {
    return @[@"title", @"notes", @"due_at", @"timezone_id", @"recurrence_type", @"recurrence_interval", @"status", @"snooze_until",
        @"list_id", @"parent_id", @"position", @"starred", @"schedule_kind", @"planned_duration", @"deadline_at", @"deadline_kind",
        @"recurrence", @"deleted", @"urgency", @"difficulty"];
}

// 合并任务补丁并维护时间模式及标准重复快捷规则。
- (NSDictionary *)mrg:(NSDictionary *)fields into:(NSDictionary *)task error:(NSError **)error {
    if (![fields isKindOfClass:NSDictionary.class]) { [self dbErr:SQLITE_MISMATCH message:@"任务字段必须为对象" error:error]; return nil; }
    for (NSString *key in fields) if (![[self tskFlds] containsObject:key]) {
        [self dbErr:SQLITE_MISUSE message:@"任务字段不可修改或未知" error:error]; return nil;
    }
    NSMutableDictionary *result = [task mutableCopy];
    [result addEntriesFromDictionary:fields];
    if (fields[@"due_at"] && !fields[@"schedule_kind"]) result[@"schedule_kind"] = fields[@"due_at"] == NSNull.null ? @"none" : @"timed";
    if (fields[@"deadline_at"] && !fields[@"deadline_kind"]) result[@"deadline_kind"] = fields[@"deadline_at"] == NSNull.null ? @"none" : @"timed";
    if (!fields[@"recurrence"] && (fields[@"recurrence_type"] || fields[@"recurrence_interval"])) {
        NSString *type = result[@"recurrence_type"];
        if ([type isEqual:@"none"]) result[@"recurrence"] = @[];
        else if ([@[@"daily", @"weekly", @"monthly", @"yearly"] containsObject:type]) {
            NSArray *previous = task[@"recurrence"];
            NSString *simple = [NSString stringWithFormat:@"RRULE:FREQ=%@;INTERVAL=%@", [task[@"recurrence_type"] uppercaseString], task[@"recurrence_interval"]];
            if (previous.count && ![previous isEqual:@[simple]]) {
                [self dbErr:SQLITE_CONSTRAINT message:@"复杂重复规则需整体修改" error:error]; return nil;
            }
            result[@"recurrence"] = @[[NSString stringWithFormat:@"RRULE:FREQ=%@;INTERVAL=%@", type.uppercaseString, result[@"recurrence_interval"]]];
        }
    }
    if (![self vldTsk:result error:error]) return nil;
    result[@"list_id"] = [result[@"list_id"] lowercaseString];
    NSArray *lists = [self qry:"SELECT list_id FROM task_lists WHERE list_id=? AND deleted=0" values:@[result[@"list_id"]] error:error];
    if (!lists || !lists.count) { if (lists) [self dbErr:SQLITE_NOTFOUND message:@"清单已删除或不存在" error:error]; return nil; }
    if (result[@"parent_id"] != NSNull.null) result[@"parent_id"] = [result[@"parent_id"] lowercaseString];
    if (result[@"parent_id"] != NSNull.null) {
        NSArray *ancestors = [self qry:"WITH RECURSIVE ancestors(task_id,parent_id) AS ("
            "SELECT task_id,parent_id FROM tasks WHERE task_id=? UNION SELECT t.task_id,t.parent_id FROM tasks t JOIN ancestors a ON t.task_id=a.parent_id)"
            "SELECT task_id,list_id,recurrence_type,deleted FROM tasks WHERE task_id IN (SELECT task_id FROM ancestors)" values:@[result[@"parent_id"]] error:error];
        if (!ancestors) return nil;
        if (!ancestors.count) {
            [self dbErr:SQLITE_CONSTRAINT message:@"父任务不存在或不在同一清单" error:error]; return nil;
        }
        for (NSDictionary *ancestor in ancestors) {
            if ([ancestor[@"deleted"] boolValue] && ![result[@"deleted"] boolValue]) { [self dbErr:SQLITE_NOTFOUND message:@"父任务已删除" error:error]; return nil; }
            if (![ancestor[@"recurrence_type"] isEqual:@"none"]) {
                [self dbErr:SQLITE_CONSTRAINT message:@"重复任务不能添加子任务" error:error]; return nil;
            }
            if (![ancestor[@"list_id"] isEqual:result[@"list_id"]]) {
                [self dbErr:SQLITE_CONSTRAINT message:@"父任务不在同一清单" error:error]; return nil;
            }
            if ([ancestor[@"task_id"] isEqual:result[@"task_id"]]) {
                [self dbErr:SQLITE_CONSTRAINT message:@"子任务关系不能成环" error:error]; return nil;
            }
        }
    }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (![task[@"starred"] isEqual:result[@"starred"]]) result[@"starred_at"] = [result[@"starred"] boolValue] ? @(now) : NSNull.null;
    result[@"updated_at"] = @(fmax(now, [task[@"updated_at"] doubleValue]));
    result[@"completed_at"] = [result[@"status"] isEqual:@"completed"]
        ? (task[@"completed_at"] != NSNull.null ? task[@"completed_at"] : @(now)) : NSNull.null;
    return result;
}

// 将API重复属性转换为单个SQLite文本字段。
- (NSDictionary *)enc:(NSDictionary *)task error:(NSError **)error {
    NSMutableDictionary *row = [task mutableCopy];
    NSData *data = [NSJSONSerialization dataWithJSONObject:row[@"recurrence"] options:0 error:error];
    if (!data) return nil;
    row[@"recurrence_json"] = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [row removeObjectForKey:@"recurrence"];
    return row;
}

// 读取存储的重复属性数组。
- (NSDictionary *)dec:(NSDictionary *)row error:(NSError **)error {
    NSMutableDictionary *task = [row mutableCopy];
    id recurrence = [NSJSONSerialization JSONObjectWithData:[row[@"recurrence_json"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:error];
    if (![recurrence isKindOfClass:NSArray.class]) return nil;
    task[@"recurrence"] = recurrence;
    [task removeObjectForKey:@"recurrence_json"];
    return task;
}

// 以参数绑定写入整条记录。
- (BOOL)wrt:(NSDictionary *)row table:(NSString *)table key:(NSString *)key insert:(BOOL)insert error:(NSError **)error {
    NSArray *columns = [[row allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *parts = [NSMutableArray array], *values = [NSMutableArray array];
    for (NSString *column in columns) {
        if (!insert && [column isEqual:key]) continue;
        [parts addObject:insert ? @"?" : [column stringByAppendingString:@"=?"]];
        [values addObject:row[column]];
    }
    NSString *sql;
    if (insert) sql = [NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (%@)", table,
        [columns componentsJoinedByString:@","], [parts componentsJoinedByString:@","]];
    else { sql = [NSString stringWithFormat:@"UPDATE %@ SET %@ WHERE %@=?", table, [parts componentsJoinedByString:@","], key]; [values addObject:row[key]]; }
    return [self qry:sql.UTF8String values:values error:error] != nil;
}

// 创建稳定UUID任务并保存默认字段。
- (NSDictionary *)crtTsk:(NSDictionary *)fields error:(NSError **)error {
    return [self crtTsk:fields uuid:NSUUID.UUID.UUIDString error:error];
}

// 创建或导入指定UUID的任务，重复标识不覆盖已有任务。
- (NSDictionary *)crtTsk:(NSDictionary *)fields uuid:(NSString *)uuid error:(NSError **)error {
    __block NSDictionary *result = nil;
    BOOL success = [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(uuid)) return [self dbErr:SQLITE_MISMATCH message:@"任务UUID无效" error:failure];
        NSNumber *now = @(NSDate.date.timeIntervalSince1970);
        NSDictionary *task = @{@"task_id": uuid.lowercaseString, @"title": @"", @"notes": @"",
            @"due_at": NSNull.null, @"timezone_id": NSTimeZone.localTimeZone.name, @"recurrence_type": @"none", @"recurrence_interval": @1,
            @"status": @"needsAction", @"snooze_until": NSNull.null, @"created_at": now, @"updated_at": now,
            @"list_id": TS_DFLT_LST, @"parent_id": NSNull.null, @"position": @0, @"starred": @0, @"starred_at": NSNull.null,
            @"schedule_kind": @"none", @"planned_duration": NSNull.null, @"deadline_at": NSNull.null, @"deadline_kind": @"none",
            @"recurrence": @[], @"completed_at": NSNull.null, @"deleted": @0, @"urgency": @0, @"difficulty": @0, @"reminder_version": @1};
        result = [self mrg:fields into:task error:failure];
        NSDictionary *row = result ? [self enc:result error:failure] : nil;
        return row && [self wrt:row table:@"tasks" key:@"task_id" insert:YES error:failure];
    } error:error];
    return success ? result : nil;
}

// 更新最新任务行，避免并发补丁覆盖其他字段。
- (BOOL)updTsk:(NSString *)taskID fields:(NSDictionary *)fields error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        NSDictionary *old = [self rdTsk:taskID error:failure];
        NSDictionary *task = old ? [self mrg:fields into:old error:failure] : nil;
        if (!task) return NO;
        BOOL reschedule = NO;
        for (NSString *key in @[@"due_at", @"timezone_id", @"recurrence", @"schedule_kind", @"deadline_at", @"deadline_kind", @"snooze_until", @"status", @"deleted"])
            if (![old[key] isEqual:task[key]]) reschedule = YES;
        if (reschedule) {
            NSMutableDictionary *changed = [task mutableCopy];
            changed[@"reminder_version"] = @([old[@"reminder_version"] longLongValue] + 1);
            task = changed;
            if (![self qry:"UPDATE reminder_occurrences SET status='handled',action='invalidated',handled_at=?,snooze_until=NULL,updated_at=? WHERE task_id=? AND status!='handled'"
                values:@[task[@"updated_at"], task[@"updated_at"], taskID.lowercaseString] error:failure]) return NO;
        }
        if (![task[@"recurrence_type"] isEqual:@"none"]) {
            NSArray *children = [self qry:"SELECT task_id FROM tasks WHERE parent_id=? LIMIT 1" values:@[taskID.lowercaseString] error:failure];
            if (!children) return NO;
            if (children.count || ![old[@"list_id"] isEqual:task[@"list_id"]])
                return [self dbErr:SQLITE_CONSTRAINT message:@"重复任务不能含子任务或更换清单" error:failure];
        }
        NSDictionary *row = task ? [self enc:task error:failure] : nil;
        if (!row || ![self wrt:row table:@"tasks" key:@"task_id" insert:NO error:failure]) return NO;
        if ([task[@"deleted"] boolValue]) {
            NSArray *children = [self qry:"WITH RECURSIVE children(task_id) AS (SELECT task_id FROM tasks WHERE parent_id=? UNION SELECT t.task_id FROM tasks t JOIN children c ON t.parent_id=c.task_id) "
                "UPDATE tasks SET deleted=1,reminder_version=reminder_version+1,updated_at=? WHERE task_id IN (SELECT task_id FROM children) AND deleted=0"
                values:@[taskID.lowercaseString, task[@"updated_at"]] error:failure];
            if (!children || ![self qry:"UPDATE reminder_occurrences SET status='handled',action='invalidated',handled_at=?,updated_at=?,snooze_until=NULL WHERE task_id IN (SELECT task_id FROM tasks WHERE deleted=1) AND status!='handled'"
                values:@[task[@"updated_at"], task[@"updated_at"]] error:failure]) return NO;
        }
        if (![old[@"list_id"] isEqual:task[@"list_id"]]) {
            return [self qry:"WITH RECURSIVE children(task_id) AS (SELECT task_id FROM tasks WHERE parent_id=? "
                "UNION SELECT t.task_id FROM tasks t JOIN children c ON t.parent_id=c.task_id) "
                "UPDATE tasks SET list_id=?,updated_at=? WHERE task_id IN (SELECT task_id FROM children)"
                values:@[taskID.lowercaseString, task[@"list_id"], task[@"updated_at"]] error:failure] != nil;
        }
        return YES;
    } error:error];
}

// 读取指定任务。
- (NSDictionary *)rdTsk:(NSString *)taskID error:(NSError **)error {
    @synchronized(self) {
        if (!ts_uuid(taskID)) { [self dbErr:SQLITE_MISMATCH message:@"任务标识无效" error:error]; return nil; }
        NSArray *rows = [self qry:"SELECT * FROM tasks WHERE task_id=?" values:@[taskID.lowercaseString] error:error];
        if (rows && rows.count == 0) [self dbErr:SQLITE_NOTFOUND message:@"任务不存在" error:error];
        return rows.count ? [self dec:rows.firstObject error:error] : nil;
    }
}

// 读取包括软删除在内的完整任务记录。
- (NSArray *)lsTsks:(NSError **)error {
    @synchronized(self) {
        NSArray *rows = [self qry:"SELECT * FROM tasks ORDER BY list_id,position,created_at,task_id" values:@[] error:error];
        if (!rows) return nil;
        NSMutableArray *tasks = [NSMutableArray array];
        for (NSDictionary *row in rows) { NSDictionary *task = [self dec:row error:error]; if (!task) return nil; [tasks addObject:task]; }
        return tasks;
    }
}

// 软删除整棵任务子树并保留历史。
- (BOOL)delTsk:(NSString *)taskID error:(NSError **)error { return [self updTsk:taskID fields:@{@"deleted": @YES} error:error]; }

// 显式完成单个任务，重复系列也停止。
- (BOOL)cmplTsk:(NSString *)taskID error:(NSError **)error { return [self updTsk:taskID fields:@{@"status": @"completed"} error:error]; }

// 恢复指定任务的待办状态。
- (BOOL)rstrTsk:(NSString *)taskID error:(NSError **)error { return [self updTsk:taskID fields:@{@"status": @"needsAction"} error:error]; }

// 读取独立的完成任务列表。
- (NSArray *)lsCmpl:(NSError **)error {
    NSArray *all = [self lsTsks:error]; if (!all) return nil;
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *task in all) if (![task[@"deleted"] boolValue] && [task[@"status"] isEqual:@"completed"]) [result addObject:task];
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"completed_at"] compare:a[@"completed_at"]]; }];
}

// 读取持久化修订号，通知合并或丢失也可发现更新。
- (long long)revision:(NSError **)error {
    @synchronized(self) {
        NSArray *rows = [self qry:"SELECT data_revision FROM store_meta WHERE singleton=1" values:@[] error:error];
        return rows.count == 1 ? [rows.firstObject[@"data_revision"] longLongValue] : -1;
    }
}

// 在同一事务读取一致的任务与提醒处理记录。
- (NSDictionary *)snapshot:(NSError **)error {
    __block NSDictionary *result = nil;
    BOOL success = [self wrTxn:^BOOL(NSError **failure) {
        NSArray *tasks = [self lsTsks:failure];
        NSArray *history = tasks ? [self qry:"SELECT * FROM reminder_occurrences ORDER BY created_at,occurrence_id" values:@[] error:failure] : nil;
        long long revision = history ? [self revision:failure] : -1;
        if (revision < 0) return NO;
        result = @{@"tasks": tasks, @"history": history, @"revision": @(revision)};
        return YES;
    } error:error];
    return success ? result : nil;
}

// 按有效提醒时间排序，未安排提醒的任务仍在末尾返回。
- (NSArray *)lsPnd:(NSError **)error {
    NSDictionary *snapshot = [self planAt:NSDate.date.timeIntervalSince1970 error:error]; if (!snapshot) return nil;
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *task in snapshot[@"tasks"]) {
        if ([task[@"deleted"] boolValue] || ![task[@"status"] isEqual:@"needsAction"]) continue;
        NSMutableDictionary *item = [task mutableCopy];
        item[@"remind_at"] = NSNull.null;
        item[@"next_cycle_at"] = NSNull.null;
        for (NSDictionary *alert in snapshot[@"alerts"]) if ([alert[@"task_id"] isEqual:task[@"task_id"]]) {
            item[@"remind_at"] = alert[@"remind_at"]; item[@"next_cycle_at"] = alert[@"cycle_at"]; break;
        }
        [result addObject:item];
    }
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        id first = a[@"remind_at"], second = b[@"remind_at"];
        if (first == NSNull.null && second != NSNull.null) return NSOrderedDescending;
        if (first != NSNull.null && second == NSNull.null) return NSOrderedAscending;
        NSComparisonResult order = first == NSNull.null ? NSOrderedSame : [first compare:second];
        return order == NSOrderedSame ? [a[@"task_id"] compare:b[@"task_id"]] : order;
    }];
}

// 使用同一数据快照与原生重复模块生成完整计划。
- (NSDictionary *)planAt:(NSTimeInterval)stamp error:(NSError **)error {
    if (!isfinite(stamp)) { [self dbErr:SQLITE_MISMATCH message:@"调度时刻无效" error:error]; return nil; }
    NSDictionary *snapshot = [self snapshot:error]; if (!snapshot) return nil;
    NSMutableArray *alerts = [NSMutableArray array];
    for (NSDictionary *task in snapshot[@"tasks"]) {
        NSArray *items = [TaskRule alerts:task history:snapshot[@"history"] at:stamp error:error];
        if (!items) return nil;
        [alerts addObjectsFromArray:items];
    }
    NSMutableDictionary *result = [snapshot mutableCopy];
    result[@"alerts"] = [alerts sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult order = [a[@"remind_at"] compare:b[@"remind_at"]];
        return order == NSOrderedSame ? [a[@"task_id"] compare:b[@"task_id"]] : order;
    }];
    return result;
}

// 核对提交后的最新版本并原子认领一条到期提醒。
- (NSDictionary *)claim:(NSDictionary *)alert revision:(long long)revision at:(NSTimeInterval)stamp error:(NSError **)error {
    __block NSDictionary *result = nil;
    BOOL success = [self wrTxn:^BOOL(NSError **failure) {
        if (![alert isKindOfClass:NSDictionary.class] || !ts_uuid(alert[@"task_id"]) || !ts_num(alert[@"remind_at"]) || !isfinite(stamp))
            return [self dbErr:SQLITE_MISMATCH message:@"提醒候选无效" error:failure];
        if ([self revision:failure] != revision) return YES;
        NSDictionary *task = [self rdTsk:alert[@"task_id"] error:failure];
        if (!task) return NO;
        if ([task[@"deleted"] boolValue] || ![task[@"status"] isEqual:@"needsAction"]
            || ![task[@"reminder_version"] isEqual:alert[@"generation"]] || [alert[@"remind_at"] doubleValue] > stamp) return YES;
        NSArray *valid = [TaskRule alerts:task history:[self lsOcc:task[@"task_id"] error:failure] at:stamp error:failure];
        if (!valid) return NO;
        BOOL matches = NO;
        for (NSDictionary *candidate in valid) if ([candidate[@"kind"] isEqual:alert[@"kind"]] && [candidate[@"cycle_at"] isEqual:alert[@"cycle_at"]]
            && [candidate[@"scheduled_at"] isEqual:alert[@"scheduled_at"]] && [candidate[@"remind_at"] isEqual:alert[@"remind_at"]]) matches = YES;
        if (!matches) return YES;
        NSNumber *now = @(stamp);
        if (![self qry:"INSERT INTO reminder_occurrences(occurrence_id,task_id,scheduled_at,cycle_at,generation,kind,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?) "
            "ON CONFLICT(task_id,generation,kind,cycle_at) DO NOTHING"
            values:@[NSUUID.UUID.UUIDString.lowercaseString, task[@"task_id"], alert[@"scheduled_at"], alert[@"cycle_at"], alert[@"generation"], alert[@"kind"], now, now] error:failure]) return NO;
        NSArray *rows = [self qry:"SELECT * FROM reminder_occurrences WHERE task_id=? AND generation=? AND kind=? AND cycle_at=?"
            values:@[task[@"task_id"], alert[@"generation"], alert[@"kind"], alert[@"cycle_at"]] error:failure];
        NSDictionary *occ = rows.firstObject;
        if (!occ) return NO;
        if (![occ[@"status"] isEqual:@"triggered"] && ![self qry:"UPDATE reminder_occurrences SET status='triggered',triggered_at=?,handled_at=NULL,action=NULL,snooze_until=NULL,updated_at=? WHERE occurrence_id=?"
            values:@[now, now, occ[@"occurrence_id"]] error:failure]) return NO;
        NSMutableDictionary *item = [alert mutableCopy]; item[@"occurrence_id"] = occ[@"occurrence_id"]; item[@"task"] = task;
        result = item;
        return YES;
    } error:error];
    return success ? result : nil;
}

// 处理一次提醒，普通完成任务或记录重复任务本轮完成。
- (BOOL)actOcc:(NSString *)occID action:(NSString *)action until:(NSNumber *)until error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(occID) || ![@[@"complete", @"dismiss", @"snooze"] containsObject:action]
            || ([action isEqual:@"snooze"] && (!ts_num(until) || until.doubleValue <= NSDate.date.timeIntervalSince1970)))
            return [self dbErr:SQLITE_MISMATCH message:@"提醒动作或延后时间无效" error:failure];
        NSDictionary *occ = [self qry:"SELECT * FROM reminder_occurrences WHERE occurrence_id=?" values:@[occID.lowercaseString] error:failure].firstObject;
        if (!occ || ![occ[@"status"] isEqual:@"triggered"]) return [self dbErr:SQLITE_NOTFOUND message:@"提醒不存在或已处理" error:failure];
        NSDictionary *task = [self rdTsk:occ[@"task_id"] error:failure];
        if (!task) return NO;
        if ([task[@"deleted"] boolValue] || ![task[@"status"] isEqual:@"needsAction"] || ![task[@"reminder_version"] isEqual:occ[@"generation"]])
            return [self dbErr:SQLITE_NOTFOUND message:@"提醒已失效" error:failure];
        NSNumber *now = @(NSDate.date.timeIntervalSince1970);
        if (![self updOcc:occID fields:@{@"status": @"handled", @"handled_at": now, @"action": action, @"snooze_until": until ?: NSNull.null} error:failure]) return NO;
        if ([action isEqual:@"complete"] && ![task[@"recurrence"] count]) return [self cmplTsk:task[@"task_id"] error:failure];
        return YES;
    } error:error];
}

// 创建任务清单。
- (NSDictionary *)crtLst:(NSString *)title error:(NSError **)error {
    __block NSDictionary *row = nil;
    BOOL success = [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_txt(title, 1024)) return [self dbErr:SQLITE_CONSTRAINT message:@"清单名称无效" error:failure];
        NSNumber *now = @(NSDate.date.timeIntervalSince1970);
        row = @{@"list_id": NSUUID.UUID.UUIDString.lowercaseString, @"title": title, @"created_at": now, @"updated_at": now, @"deleted": @0};
        return [self wrt:row table:@"task_lists" key:@"list_id" insert:YES error:failure];
    } error:error];
    return success ? row : nil;
}

// 修改清单名称并记录更新时间。
- (BOOL)updLst:(NSString *)listID title:(NSString *)title error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(listID) || !ts_txt(title, 1024)) return [self dbErr:SQLITE_CONSTRAINT message:@"清单标识或名称无效" error:failure];
        if (![self qry:"UPDATE task_lists SET title=?,updated_at=? WHERE list_id=? AND deleted=0"
            values:@[title, @(NSDate.date.timeIntervalSince1970), listID.lowercaseString] error:failure]) return NO;
        return sqlite3_changes(self->_db) == 1 || [self dbErr:SQLITE_NOTFOUND message:@"清单不存在" error:failure];
    } error:error];
}

// 读取全部清单。
- (NSArray *)lsLsts:(NSError **)error {
    @synchronized(self) { return [self qry:"SELECT * FROM task_lists WHERE deleted=0 ORDER BY created_at,list_id" values:@[] error:error]; }
}

// 原子删除清单和任务并使全部旧提醒失效。
- (BOOL)delLst:(NSString *)listID error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(listID) || [listID.lowercaseString isEqual:TS_DFLT_LST])
            return [self dbErr:SQLITE_CONSTRAINT message:@"默认清单不能删除" error:failure];
        NSArray *lists = [self qry:"SELECT list_id FROM task_lists WHERE list_id=? AND deleted=0" values:@[listID.lowercaseString] error:failure];
        if (!lists) return NO;
        if (!lists.count) return [self dbErr:SQLITE_NOTFOUND message:@"清单不存在" error:failure];
        NSArray *tasks = [self qry:"SELECT task_id FROM tasks WHERE list_id=? AND deleted=0" values:@[listID.lowercaseString] error:failure];
        if (!tasks) return NO;
        for (NSDictionary *task in tasks) {
            NSDictionary *current = [self rdTsk:task[@"task_id"] error:failure];
            if (!current || (![current[@"deleted"] boolValue] && ![self delTsk:current[@"task_id"] error:failure])) return NO;
        }
        return [self qry:"UPDATE task_lists SET deleted=1,updated_at=? WHERE list_id=?"
            values:@[@(NSDate.date.timeIntervalSince1970), listID.lowercaseString] error:failure] != nil;
    } error:error];
}

// 在一个事务中清理指定清单的完成子树。
- (BOOL)clrCmpl:(NSString *)listID error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(listID)) return [self dbErr:SQLITE_MISMATCH message:@"清单标识无效" error:failure];
        NSArray *lists = [self qry:"SELECT list_id FROM task_lists WHERE list_id=? AND deleted=0" values:@[listID.lowercaseString] error:failure];
        if (!lists) return NO;
        if (!lists.count) return [self dbErr:SQLITE_NOTFOUND message:@"清单不存在" error:failure];
        NSArray *rows = [self qry:"SELECT task_id FROM tasks WHERE list_id=? AND status='completed' AND deleted=0" values:@[listID.lowercaseString] error:failure];
        if (!rows) return NO;
        for (NSDictionary *row in rows) if (![self delTsk:row[@"task_id"] error:failure]) return NO;
        return YES;
    } error:error];
}

// 从最新提醒计划选取一轮并原子记录完成。
- (BOOL)cmplNxt:(NSString *)taskID error:(NSError **)error {
    return [self cmplNxt:taskID cycle:nil generation:nil error:error];
}

// 在事务内核对用户看到的轮次和提醒版本。
- (BOOL)cmplNxt:(NSString *)taskID cycle:(NSNumber *)cycle generation:(NSNumber *)generation error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        if ((cycle || generation) && (!ts_num(cycle) || !ts_num(generation) || generation.longLongValue < 1 || generation.doubleValue != generation.longLongValue))
            return [self dbErr:SQLITE_MISMATCH message:@"提醒轮次或版本无效" error:failure];
        NSDictionary *task = [self rdTsk:taskID error:failure]; if (!task) return NO;
        if ([task[@"deleted"] boolValue]) return [self dbErr:SQLITE_NOTFOUND message:@"任务已删除" error:failure];
        if (![task[@"status"] isEqual:@"needsAction"]) return YES;
        if (![task[@"recurrence"] count]) return [self cmplTsk:taskID error:failure];
        NSArray *history = [self lsOcc:taskID error:failure]; if (!history) return NO;
        NSArray *alerts = [TaskRule alerts:task history:history at:NSDate.date.timeIntervalSince1970 error:failure];
        if (!alerts) return NO;
        if (cycle && (![task[@"reminder_version"] isEqual:generation] || ![alerts.firstObject[@"cycle_at"] isEqual:cycle])) return YES;
        if (!alerts.count) return [self cmplTsk:taskID error:failure];
        NSDictionary *alert = alerts.firstObject; NSNumber *now = @(NSDate.date.timeIntervalSince1970);
        return [self qry:"INSERT INTO reminder_occurrences(occurrence_id,task_id,scheduled_at,cycle_at,generation,kind,status,handled_at,action,created_at,updated_at) "
            "VALUES(?,?,?,?,?,?,'handled',?,'complete',?,?) ON CONFLICT(task_id,generation,kind,cycle_at) "
            "DO UPDATE SET status='handled',handled_at=excluded.handled_at,action='complete',snooze_until=NULL,updated_at=excluded.updated_at"
            values:@[NSUUID.UUID.UUIDString.lowercaseString, taskID.lowercaseString, alert[@"scheduled_at"], alert[@"cycle_at"],
                task[@"reminder_version"], alert[@"kind"], now, now, now] error:failure] != nil;
    } error:error];
}

// 幂等创建单次提醒，重复请求返回同一UUID。
- (NSDictionary *)crtOcc:(NSString *)taskID at:(NSNumber *)stamp error:(NSError **)error {
    __block NSDictionary *result = nil;
    BOOL success = [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(taskID) || !ts_num(stamp)) return [self dbErr:SQLITE_CONSTRAINT message:@"提醒任务或时间无效" error:failure];
        NSNumber *now = @(NSDate.date.timeIntervalSince1970);
        NSDictionary *task = [self rdTsk:taskID error:failure]; if (!task) return NO;
        if (![self qry:"INSERT INTO reminder_occurrences (occurrence_id,task_id,scheduled_at,created_at,updated_at,cycle_at,generation) VALUES(?,?,?,?,?,?,?) "
            "ON CONFLICT(task_id,generation,kind,cycle_at) DO NOTHING" values:@[NSUUID.UUID.UUIDString.lowercaseString, taskID.lowercaseString, stamp, now, now, stamp, task[@"reminder_version"]] error:failure]) return NO;
        result = [self qry:"SELECT * FROM reminder_occurrences WHERE task_id=? AND cycle_at=? AND generation=? AND kind='plan'"
            values:@[taskID.lowercaseString, stamp, task[@"reminder_version"]] error:failure].firstObject;
        return result != nil;
    } error:error];
    return success ? result : nil;
}

// 更新提醒记录的内部生命周期与处理信息。
- (BOOL)updOcc:(NSString *)occID fields:(NSDictionary *)fields error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(occID) || ![fields isKindOfClass:NSDictionary.class]) return [self dbErr:SQLITE_MISMATCH message:@"提醒补丁无效" error:failure];
        for (NSString *key in fields) if (![@[@"status", @"triggered_at", @"handled_at", @"action", @"snooze_until"] containsObject:key])
            return [self dbErr:SQLITE_MISUSE message:@"提醒字段不可修改或未知" error:failure];
        NSMutableDictionary *row = [[self qry:"SELECT * FROM reminder_occurrences WHERE occurrence_id=?"
            values:@[occID.lowercaseString] error:failure].firstObject mutableCopy];
        if (!row) return [self dbErr:SQLITE_NOTFOUND message:@"提醒不存在" error:failure];
        [row addEntriesFromDictionary:fields];
        for (NSString *key in @[@"triggered_at", @"handled_at", @"snooze_until"])
            if (row[key] != NSNull.null && !ts_num(row[key])) return [self dbErr:SQLITE_CONSTRAINT message:@"提醒时间无效" error:failure];
        if (![@[@"pending", @"triggered", @"handled"] containsObject:row[@"status"]]
            || (row[@"action"] != NSNull.null && !ts_txt(row[@"action"], 64)))
            return [self dbErr:SQLITE_CONSTRAINT message:@"提醒状态或处理动作无效" error:failure];
        row[@"updated_at"] = @(fmax(NSDate.date.timeIntervalSince1970, [row[@"updated_at"] doubleValue]));
        return [self wrt:row table:@"reminder_occurrences" key:@"occurrence_id" insert:NO error:failure];
    } error:error];
}

// 读取某任务按计划时间排列的提醒记录。
- (NSArray *)lsOcc:(NSString *)taskID error:(NSError **)error {
    @synchronized(self) {
        if (!ts_uuid(taskID)) { [self dbErr:SQLITE_MISMATCH message:@"任务标识无效" error:error]; return nil; }
        return [self qry:"SELECT * FROM reminder_occurrences WHERE task_id=? ORDER BY scheduled_at" values:@[taskID.lowercaseString] error:error];
    }
}

// 关闭连接，未提交事务由SQLite回滚。
- (void)dealloc { sqlite3_close_v2(_db); }

@end
