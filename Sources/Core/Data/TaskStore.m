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

#include "TaskStoreAgenda.inc"

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
        // 空文件须绑定为零长BLOB，不能把空指针当成SQL空值。
        } else if ([value isKindOfClass:NSData.class]) code = [value length] ? sqlite3_bind_blob(statement, slot, [value bytes], (int)[value length], SQLITE_TRANSIENT) : sqlite3_bind_zeroblob(statement, slot, 0);
        else code = SQLITE_MISMATCH;
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
            else if (type == SQLITE_BLOB) value = [NSData dataWithBytes:sqlite3_column_blob(statement, column) length:sqlite3_column_bytes(statement, column)];
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
        if (version <= 4 && ![self exec:
            "ALTER TABLE reminder_occurrences ADD COLUMN defer_count INTEGER NOT NULL DEFAULT 0 CHECK(defer_count IN (0,1));"
            "ALTER TABLE reminder_occurrences ADD COLUMN hold_reason TEXT CHECK(hold_reason IN ('snooze','screenshot'));"
            "ALTER TABLE reminder_occurrences ADD COLUMN hold_until REAL;"
            "CREATE TABLE reminder_checkins(occurrence_id TEXT PRIMARY KEY NOT NULL REFERENCES reminder_occurrences(occurrence_id) ON DELETE CASCADE,"
            "method TEXT NOT NULL CHECK(method IN ('camera','screenshot','image')), image BLOB NOT NULL CHECK(length(image)>0),created_at REAL NOT NULL);"
            "UPDATE store_meta SET schema_version=5 WHERE singleton=1;" error:failure]) return NO;
        if (version <= 5 && ![self exec:
            "CREATE TABLE reminder_checkins_v6(occurrence_id TEXT NOT NULL REFERENCES reminder_occurrences(occurrence_id) ON DELETE CASCADE,"
            "position INTEGER NOT NULL CHECK(typeof(position)='integer' AND position BETWEEN 0 AND 5),"
            "method TEXT NOT NULL CHECK(method IN ('camera','screenshot','image')),image BLOB NOT NULL CHECK(length(image)>0),"
            "created_at REAL NOT NULL,PRIMARY KEY(occurrence_id,position));"
            "INSERT INTO reminder_checkins_v6 SELECT occurrence_id,0,method,image,created_at FROM reminder_checkins;"
            "DROP TABLE reminder_checkins;ALTER TABLE reminder_checkins_v6 RENAME TO reminder_checkins;"
            "UPDATE store_meta SET schema_version=6 WHERE singleton=1;" error:failure]) return NO;
        if (version <= 6 && ![self exec:
            "CREATE TABLE capture_request(token TEXT PRIMARY KEY NOT NULL,occurrence_id TEXT NOT NULL REFERENCES reminder_occurrences(occurrence_id) ON DELETE CASCADE,"
            "source TEXT NOT NULL CHECK(source IN ('camera','image','screenshot','file')),capacity INTEGER NOT NULL CHECK(capacity BETWEEN 1 AND 6),"
            "created_at REAL NOT NULL,state INTEGER NOT NULL DEFAULT 0 CHECK(state BETWEEN 0 AND 2),pid INTEGER,payload BLOB,issue TEXT);"
            "UPDATE store_meta SET schema_version=7 WHERE singleton=1;" error:failure]) return NO;
        // 复用原附件表，保留旧图片字段并增加普通文件元数据。
        if (version <= 7 && ![self exec:
            "CREATE TABLE reminder_checkins_v8(occurrence_id TEXT NOT NULL REFERENCES reminder_occurrences(occurrence_id) ON DELETE CASCADE,"
            "position INTEGER NOT NULL CHECK(typeof(position)='integer' AND position BETWEEN 0 AND 5),"
            "method TEXT NOT NULL CHECK(method IN ('camera','screenshot','image','file')),"
            "image BLOB NOT NULL CHECK(length(image)<=20971520 AND (method='file' OR length(image)>0)),"
            "created_at REAL NOT NULL,name TEXT,content_type TEXT,PRIMARY KEY(occurrence_id,position),"
            "CHECK(method!='file' OR (name IS NOT NULL AND length(name)>0 AND content_type IS NOT NULL AND length(content_type)>0)));"
            "INSERT INTO reminder_checkins_v8(occurrence_id,position,method,image,created_at) SELECT occurrence_id,position,method,image,created_at FROM reminder_checkins;"
            "DROP TABLE reminder_checkins;ALTER TABLE reminder_checkins_v8 RENAME TO reminder_checkins;"
            "UPDATE store_meta SET schema_version=8 WHERE singleton=1;" error:failure]) return NO;
        // 原子迁移五态及下一触发时刻，附件和前台采集请求保持原身份。
        if (version <= 8 && ![self exec:
            "CREATE TEMP TABLE saved_checkins AS SELECT * FROM reminder_checkins;"
            "CREATE TEMP TABLE saved_capture AS SELECT * FROM capture_request;"
            "CREATE TABLE occurrences_v9(occurrence_id TEXT PRIMARY KEY NOT NULL,task_id TEXT NOT NULL REFERENCES tasks(task_id),"
            "scheduled_at REAL NOT NULL,triggered_at REAL,handled_at REAL,status TEXT NOT NULL DEFAULT 'pending' "
            "CHECK(status IN ('pending','presented','snoozed','completed','resolved')),action TEXT,next_fire_at REAL,"
            "created_at REAL NOT NULL,updated_at REAL NOT NULL,generation INTEGER NOT NULL DEFAULT 1,"
            "kind TEXT NOT NULL DEFAULT 'plan' CHECK(kind IN ('plan','deadline','both')),cycle_at REAL NOT NULL,"
            "defer_count INTEGER NOT NULL DEFAULT 0 CHECK(defer_count IN (0,1)),hold_reason TEXT CHECK(hold_reason IN ('snooze','screenshot')),hold_until REAL,"
            "UNIQUE(task_id,generation,kind,cycle_at),"
            "CHECK((status='pending' AND triggered_at IS NULL AND handled_at IS NULL AND next_fire_at IS NOT NULL) OR "
            "(status='presented' AND triggered_at IS NOT NULL AND handled_at IS NULL AND next_fire_at IS NOT NULL) OR "
            "(status='snoozed' AND triggered_at IS NOT NULL AND handled_at IS NOT NULL AND action='snooze' AND next_fire_at IS NOT NULL) OR "
            "(status='completed' AND handled_at IS NOT NULL AND action='complete' AND next_fire_at IS NULL) OR "
            "(status='resolved' AND handled_at IS NOT NULL AND next_fire_at IS NULL)));"
            "INSERT INTO occurrences_v9 SELECT occurrence_id,task_id,scheduled_at,CASE WHEN status='handled' AND action='snooze' THEN COALESCE(triggered_at,created_at) ELSE triggered_at END,handled_at,"
            "CASE status WHEN 'triggered' THEN 'presented' WHEN 'handled' THEN CASE action WHEN 'snooze' THEN 'snoozed' ELSE 'resolved' END ELSE 'pending' END,"
            "action,CASE WHEN status='handled' AND (action IS NULL OR action!='snooze') THEN NULL ELSE COALESCE(snooze_until,scheduled_at) END,"
            "created_at,updated_at,generation,kind,cycle_at,defer_count,hold_reason,hold_until FROM reminder_occurrences;"
            "DROP TABLE reminder_occurrences;ALTER TABLE occurrences_v9 RENAME TO reminder_occurrences;"
            "CREATE INDEX occurrences_due ON reminder_occurrences(status,next_fire_at);"
            "INSERT INTO reminder_checkins SELECT * FROM saved_checkins;INSERT INTO capture_request SELECT * FROM saved_capture;"
            "DROP TABLE saved_checkins;DROP TABLE saved_capture;"
            "UPDATE store_meta SET schema_version=9 WHERE singleton=1;" error:failure]) return NO;
        // 声振确认与时限沿用唯一数据库，旧轮次默认尚未开始声振。
        if (version <= 9 && ![self exec:
            "ALTER TABLE reminder_occurrences ADD COLUMN signal_at REAL;"
            "ALTER TABLE reminder_occurrences ADD COLUMN signal_uptime REAL;"
            "ALTER TABLE reminder_occurrences ADD COLUMN signal_ack INTEGER NOT NULL DEFAULT 0 CHECK(signal_ack IN (0,1));"
            "UPDATE store_meta SET schema_version=10 WHERE singleton=1;" error:failure]) return NO;
        // 常律和日程继续保存在同一数据库，旧任务保持原有提醒语义。
        if (version <= 10 && ![self exec:
            "ALTER TABLE tasks ADD COLUMN routine_kind TEXT NOT NULL DEFAULT 'none' CHECK(routine_kind IN ('none','fixed','work','rest','background'));"
            "ALTER TABLE tasks ADD COLUMN routine_end INTEGER CHECK(routine_end BETWEEN 0 AND 1439);"
            "ALTER TABLE tasks ADD COLUMN routine_enabled INTEGER NOT NULL DEFAULT 1 CHECK(routine_enabled IN (0,1));"
            "ALTER TABLE tasks ADD COLUMN routine_source TEXT;"
            "CREATE UNIQUE INDEX routine_source_unique ON tasks(routine_source) WHERE routine_source IS NOT NULL;"
            "CREATE TABLE agenda_slots(task_id TEXT NOT NULL REFERENCES tasks(task_id),generation INTEGER NOT NULL,cycle_at REAL NOT NULL,"
            "scheduled_at REAL NOT NULL,day_at REAL NOT NULL,start_at REAL NOT NULL,end_at REAL NOT NULL CHECK(end_at>start_at),"
            "PRIMARY KEY(task_id,generation,cycle_at));"
            "CREATE INDEX agenda_day ON agenda_slots(day_at,start_at);"
            "CREATE TABLE routine_documents(name TEXT PRIMARY KEY NOT NULL,content TEXT NOT NULL,created_at REAL NOT NULL);"
            "UPDATE store_meta SET schema_version=11 WHERE singleton=1;" error:failure]) return NO;
        // 评估与提醒分别保存状态，继续复用唯一数据库。
        if (version <= 11 && ![self exec:
            "ALTER TABLE tasks ADD COLUMN planning_mode TEXT NOT NULL DEFAULT 'fixed' CHECK(planning_mode IN ('fixed','window'));"
            "CREATE TABLE task_reviews(task_id TEXT PRIMARY KEY NOT NULL REFERENCES tasks(task_id),data TEXT NOT NULL);"
            "UPDATE store_meta SET schema_version=12 WHERE singleton=1;" error:failure]) return NO;
        // 归档快照和云端附件索引与任务使用同一个数据库。
        if (version <= 12 && ![self exec:
            "CREATE TABLE IF NOT EXISTS task_archive(entry_id TEXT PRIMARY KEY NOT NULL,task_id TEXT NOT NULL REFERENCES tasks(task_id),"
            "occurrence_id TEXT UNIQUE REFERENCES reminder_occurrences(occurrence_id),"
            "title TEXT NOT NULL,notes TEXT NOT NULL,routine_kind TEXT NOT NULL,completed_at REAL NOT NULL,scheduled_at REAL,"
            "restore_at REAL,provider_id TEXT,archive_day TEXT,uploaded INTEGER NOT NULL DEFAULT 0);"
            "CREATE INDEX IF NOT EXISTS task_archive_time ON task_archive(completed_at DESC,entry_id);"
            "CREATE INDEX IF NOT EXISTS task_archive_pending ON task_archive(completed_at,entry_id) WHERE uploaded=0;"
            "CREATE TABLE IF NOT EXISTS archive_files(occurrence_id TEXT NOT NULL REFERENCES reminder_occurrences(occurrence_id),"
            "position INTEGER NOT NULL,method TEXT NOT NULL,created_at REAL NOT NULL,name TEXT,content_type TEXT,image_bytes INTEGER NOT NULL,"
            "provider_id TEXT NOT NULL,remote_key TEXT NOT NULL,sha256 TEXT NOT NULL,PRIMARY KEY(occurrence_id,position));"
            "INSERT OR IGNORE INTO task_archive(entry_id,task_id,occurrence_id,title,notes,routine_kind,completed_at,scheduled_at,restore_at) "
            "SELECT o.occurrence_id,t.task_id,o.occurrence_id,t.title,t.notes,t.routine_kind,o.handled_at,o.scheduled_at,"
            "CASE WHEN t.status='completed' AND abs(t.completed_at-o.handled_at)<1 THEN t.completed_at END "
            "FROM reminder_occurrences o JOIN tasks t ON t.task_id=o.task_id WHERE o.action='complete' AND o.handled_at IS NOT NULL "
            "AND o.occurrence_id=(SELECT r.occurrence_id FROM reminder_occurrences r WHERE r.task_id=o.task_id AND r.generation=o.generation "
            "AND r.cycle_at=o.cycle_at AND r.action='complete' AND r.handled_at IS NOT NULL "
            "ORDER BY EXISTS(SELECT 1 FROM reminder_checkins c WHERE c.occurrence_id=r.occurrence_id) DESC,"
            "r.triggered_at IS NOT NULL DESC,r.scheduled_at DESC,r.occurrence_id LIMIT 1);"
            "INSERT INTO task_archive(entry_id,task_id,title,notes,routine_kind,completed_at,restore_at) "
            "SELECT lower(hex(randomblob(16))),t.task_id,t.title,t.notes,t.routine_kind,t.completed_at,t.completed_at FROM tasks t "
            "WHERE t.status='completed' AND t.deleted=0 AND NOT EXISTS(SELECT 1 FROM task_archive a WHERE a.task_id=t.task_id AND a.restore_at=t.completed_at);"
            "UPDATE task_archive SET archive_day=substr(strftime('%Y%m%d',completed_at,'unixepoch','localtime'),3,6);"
            "CREATE TRIGGER IF NOT EXISTS archive_local_day AFTER INSERT ON task_archive WHEN NEW.archive_day IS NULL BEGIN "
            "UPDATE task_archive SET archive_day=substr(strftime('%Y%m%d',NEW.completed_at,'unixepoch','localtime'),3,6) WHERE entry_id=NEW.entry_id; END;"
            "CREATE TRIGGER IF NOT EXISTS archive_task_new AFTER INSERT ON tasks WHEN NEW.status='completed' BEGIN "
            "INSERT INTO task_archive(entry_id,task_id,title,notes,routine_kind,completed_at,restore_at) "
            "VALUES(lower(hex(randomblob(16))),NEW.task_id,NEW.title,NEW.notes,NEW.routine_kind,NEW.completed_at,NEW.completed_at); END;"
            "CREATE TRIGGER IF NOT EXISTS archive_task_done AFTER UPDATE OF status ON tasks WHEN NEW.status='completed' AND OLD.status!='completed' BEGIN "
            "INSERT INTO task_archive(entry_id,task_id,title,notes,routine_kind,completed_at,restore_at) "
            "VALUES(lower(hex(randomblob(16))),NEW.task_id,NEW.title,NEW.notes,NEW.routine_kind,NEW.completed_at,NEW.completed_at); END;"
            "CREATE TRIGGER IF NOT EXISTS archive_occ_new AFTER INSERT ON reminder_occurrences WHEN NEW.status='completed' BEGIN "
            "INSERT OR IGNORE INTO task_archive(entry_id,task_id,occurrence_id,title,notes,routine_kind,completed_at,scheduled_at) "
            "SELECT NEW.occurrence_id,task_id,NEW.occurrence_id,title,notes,routine_kind,NEW.handled_at,NEW.scheduled_at FROM tasks WHERE task_id=NEW.task_id; END;"
            "CREATE TRIGGER IF NOT EXISTS archive_occ_done AFTER UPDATE OF status ON reminder_occurrences WHEN NEW.status='completed' AND OLD.status!='completed' BEGIN "
            "INSERT OR IGNORE INTO task_archive(entry_id,task_id,occurrence_id,title,notes,routine_kind,completed_at,scheduled_at) "
            "SELECT NEW.occurrence_id,task_id,NEW.occurrence_id,title,notes,routine_kind,NEW.handled_at,NEW.scheduled_at FROM tasks WHERE task_id=NEW.task_id; END;"
            "UPDATE store_meta SET schema_version=13 WHERE singleton=1;" error:failure]) return NO;
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
    if (![@[@"fixed",@"window"] containsObject:task[@"planning_mode"] ?: @"fixed"])
        return [self dbErr:SQLITE_CONSTRAINT message:@"规划类型无效" error:error];
    if ([task[@"planning_mode"] isEqual:@"window"] && (task[@"due_at"]==NSNull.null || task[@"deadline_at"]==NSNull.null
        || [task[@"deadline_at"] doubleValue]<=[task[@"due_at"] doubleValue] || [task[@"recurrence"] count] || ![task[@"routine_kind"] isEqual:@"none"]))
        return [self dbErr:SQLITE_CONSTRAINT message:@"规划窗口无效" error:error];
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
    NSString *role = task[@"routine_kind"];
    id end = task[@"routine_end"], enabled = task[@"routine_enabled"], source = task[@"routine_source"];
    if (![@[@"none",@"fixed",@"work",@"rest",@"background"] containsObject:role]
        || ![enabled isKindOfClass:NSNumber.class] || ![@[@0,@1] containsObject:enabled]
        || (end != NSNull.null && (!ts_num(end) || [end doubleValue] != [end integerValue] || [end integerValue] < 0 || [end integerValue] > 1439))
        || (source != NSNull.null && !ts_txt(source,1024))) return [self dbErr:SQLITE_CONSTRAINT message:@"常律参数无效" error:error];
    if (![role isEqual:@"none"] && ![task[@"deleted"] boolValue] && (![task[@"list_id"] isEqual:TS_RTN_LST] || task[@"parent_id"] != NSNull.null
        || ![task[@"schedule_kind"] isEqual:@"timed"] || end == NSNull.null || !recurrence.count))
        return [self dbErr:SQLITE_CONSTRAINT message:@"常律需设置时段和重复" error:error];
    if ([role isEqual:@"none"] && ([task[@"list_id"] isEqual:TS_RTN_LST] || end != NSNull.null))
        return [self dbErr:SQLITE_CONSTRAINT message:@"请选择常律类型" error:error];
    return [TaskRule vld:task error:error];
}

// 生成可写字段名列表。
- (NSArray *)tskFlds {
    return @[@"title", @"notes", @"due_at", @"timezone_id", @"recurrence_type", @"recurrence_interval", @"status", @"snooze_until",
        @"list_id", @"parent_id", @"position", @"starred", @"schedule_kind", @"planned_duration", @"deadline_at", @"deadline_kind",
        @"recurrence", @"deleted", @"urgency", @"difficulty", @"routine_kind", @"routine_end", @"routine_enabled", @"routine_source", @"planning_mode"];
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
    if (![result[@"routine_kind"] isEqual:@"none"]) {
        if (![self rtnList:error]) return nil;
    }
    if (![result[@"routine_kind"] isEqual:@"none"] && ts_num(result[@"due_at"]) && ts_num(result[@"routine_end"])) {
        NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = [NSTimeZone timeZoneWithName:result[@"timezone_id"]];
        NSDate *start = [NSDate dateWithTimeIntervalSince1970:[result[@"due_at"] doubleValue]]; NSInteger end = [result[@"routine_end"] integerValue];
        NSDate *finish = [calendar dateBySettingHour:end/60 minute:end%60 second:0 ofDate:start options:0];
        if (finish.timeIntervalSince1970 <= start.timeIntervalSince1970) finish = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:finish options:0];
        result[@"planned_duration"] = @([finish timeIntervalSinceDate:start]);
    }
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

// 共用新任务字段，批量预检和实际创建保持相同语义。
- (NSDictionary *)newTsk:(NSString *)uuid {
    NSNumber *now = @(NSDate.date.timeIntervalSince1970);
    return @{@"task_id": uuid.lowercaseString, @"title": @"", @"notes": @"",
        @"due_at": NSNull.null, @"timezone_id": NSTimeZone.localTimeZone.name, @"recurrence_type": @"none", @"recurrence_interval": @1,
        @"status": @"needsAction", @"snooze_until": NSNull.null, @"created_at": now, @"updated_at": now,
        @"list_id": TS_DFLT_LST, @"parent_id": NSNull.null, @"position": @0, @"starred": @0, @"starred_at": NSNull.null,
        @"schedule_kind": @"none", @"planned_duration": NSNull.null, @"deadline_at": NSNull.null, @"deadline_kind": @"none",
        @"recurrence": @[], @"completed_at": NSNull.null, @"deleted": @0, @"urgency": @0, @"difficulty": @0, @"reminder_version": @1,
        @"routine_kind": @"none", @"routine_end": NSNull.null, @"routine_enabled": @1, @"routine_source": NSNull.null, @"planning_mode": @"fixed"};
}

// 在写入事务中核对所有常律，冲突携带完整事项与时段。
- (BOOL)chkRtn:(NSArray *)tasks error:(NSError **)error {
    NSPredicate *filter = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *task, NSDictionary *bindings) {
        (void)bindings;
        return ![task[@"routine_kind"] isEqual:@"none"] && ![task[@"deleted"] boolValue] && ![task[@"status"] isEqual:@"completed"];
    }];
    NSArray *candidates = [tasks filteredArrayUsingPredicate:filter];
    if (!candidates.count) return YES;
    NSArray *rows = [self qry:"SELECT * FROM tasks WHERE deleted=0 AND status='needsAction' AND routine_kind!='none'" values:@[] error:error];
    if (!rows) return NO;
    NSMutableArray *peers = [NSMutableArray array];
    for (NSDictionary *row in rows) { NSDictionary *task = [self dec:row error:error]; if (!task) return NO; [peers addObject:task]; }
    NSArray *conflicts = [TaskRoutineCheck check:candidates against:peers at:NSDate.date.timeIntervalSince1970 error:error];
    if (!conflicts) return NO;
    if (conflicts.count) {
        if (error) *error = [NSError errorWithDomain:@"routine" code:2 userInfo:@{NSLocalizedDescriptionKey:@"常律时段冲突",@"routine_conflicts":conflicts}];
        return NO;
    }
    return YES;
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
        NSDictionary *task = [self newTsk:uuid];
        result = [self mrg:fields into:task error:failure];
        if (!result || ![self chkRtn:@[result] error:failure]) return NO;
        NSDictionary *row = [self enc:result error:failure];
        return row && [self wrt:row table:@"tasks" key:@"task_id" insert:YES error:failure];
    } error:error];
    return success ? result : nil;
}

// 更新最新任务行，避免并发补丁覆盖其他字段。
- (BOOL)updTsk:(NSString *)taskID fields:(NSDictionary *)fields error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        NSDictionary *old = [self rdTsk:taskID error:failure];
        NSDictionary *task = old ? [self mrg:fields into:old error:failure] : nil;
        if (!task || ![self chkRtn:@[task] error:failure]) return NO;
        BOOL reschedule = NO;
        for (NSString *key in @[@"due_at", @"timezone_id", @"recurrence", @"schedule_kind", @"deadline_at", @"deadline_kind", @"snooze_until", @"status", @"deleted", @"routine_kind", @"routine_end", @"routine_enabled", @"planning_mode"])
            if (![old[key] isEqual:task[key]]) reschedule = YES;
        if (reschedule) {
            NSMutableDictionary *changed = [task mutableCopy];
            changed[@"reminder_version"] = @([old[@"reminder_version"] longLongValue] + 1);
            task = changed;
            if (![self qry:"UPDATE reminder_occurrences SET status='resolved',action='invalidated',handled_at=?,next_fire_at=NULL,updated_at=? WHERE task_id=? AND status NOT IN ('completed','resolved')"
                values:@[task[@"updated_at"], task[@"updated_at"], taskID.lowercaseString] error:failure]) return NO;
        }
        if (![task[@"recurrence_type"] isEqual:@"none"]) {
            NSArray *children = [self qry:"SELECT task_id FROM tasks WHERE parent_id=? AND deleted=0 LIMIT 1" values:@[taskID.lowercaseString] error:failure];
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
            if (!children || ![self qry:"UPDATE reminder_occurrences SET status='resolved',action='invalidated',handled_at=?,updated_at=?,next_fire_at=NULL WHERE task_id IN (SELECT task_id FROM tasks WHERE deleted=1) AND status NOT IN ('completed','resolved')"
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

// 读取独立的完成任务。
- (NSArray *)lsCmpl:(NSError **)error {
    NSArray *all = [self lsTsks:error]; if (!all) return nil;
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *task in all) if (![task[@"deleted"] boolValue] && [task[@"status"] isEqual:@"completed"]) [result addObject:task];
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"completed_at"] compare:a[@"completed_at"]]; }];
}

// 归档显示完成当时的字段，恢复只对应当前普通待办状态。
- (NSArray *)arcRows:(NSError **)error {
    @synchronized(self) {
        return [self qry:"SELECT a.*, (a.routine_kind='none' AND t.deleted=0 AND t.status='completed' "
            "AND COALESCE(a.restore_at=t.completed_at,0)) AS can_restore FROM task_archive a JOIN tasks t ON a.task_id=t.task_id "
            "ORDER BY a.completed_at DESC,a.entry_id" values:@[] error:error];
    }
}

// 同步只读取未确认记录，按完成先后处理。
- (NSArray *)arcPend:(NSError **)error {
    @synchronized(self) {
        return [self qry:"SELECT * FROM task_archive WHERE uploaded=0 ORDER BY completed_at,entry_id" values:@[] error:error];
    }
}

// 在事务内重新核对待恢复的是同一次完成。
- (BOOL)rstrArc:(NSString *)entryID error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        NSDictionary *row = [self qry:"SELECT t.task_id FROM task_archive a JOIN tasks t ON a.task_id=t.task_id "
            "WHERE a.entry_id=? AND a.routine_kind='none' AND t.deleted=0 AND t.status='completed' AND a.restore_at=t.completed_at"
            values:@[entryID] error:failure].firstObject;
        if (!row) return [self dbErr:SQLITE_NOTFOUND message:@"当前任务不可恢复" error:failure];
        return [self rstrTsk:row[@"task_id"] error:failure];
    } error:error];
}

// 校验每一份远端回执，再在同一事务保留索引和删除原件。
- (BOOL)arcDone:(NSString *)entryID provider:(NSString *)provider day:(NSString *)day files:(NSArray *)files error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(provider) || day.length != 6 || [day rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound)
            return [self dbErr:SQLITE_MISMATCH message:@"归档目标无效" error:failure];
        NSDictionary *entry = [self qry:"SELECT occurrence_id FROM task_archive WHERE entry_id=? AND uploaded=0 "
            "AND (archive_day IS NULL OR archive_day=?)" values:@[entryID,day] error:failure].firstObject;
        if (!entry) return [self dbErr:SQLITE_NOTFOUND message:@"找不到待上传归档" error:failure];
        id occurrence = entry[@"occurrence_id"];
        NSArray *positions = [self qry:"SELECT position FROM reminder_checkins WHERE occurrence_id=? ORDER BY position"
            values:@[occurrence] error:failure];
        if (!positions || positions.count != files.count)
            return [self dbErr:SQLITE_CONSTRAINT message:@"附件回执数量不符" error:failure];
        for (NSUInteger index=0; index<positions.count; index++) {
            NSDictionary *receipt = files[index];
            NSNumber *position = positions[index][@"position"];
            if (![receipt isKindOfClass:NSDictionary.class] || ![receipt[@"position"] isEqual:position]
                || !ts_txt(receipt[@"remote_key"],4096) || !ts_txt(receipt[@"sha256"],64) || [receipt[@"sha256"] length] != 64)
                return [self dbErr:SQLITE_MISMATCH message:@"附件回执无效" error:failure];
            if (![self qry:"INSERT INTO archive_files SELECT occurrence_id,position,method,created_at,name,content_type,length(image),?,?,? "
                "FROM reminder_checkins WHERE occurrence_id=? AND position=?"
                values:@[provider,receipt[@"remote_key"],receipt[@"sha256"],occurrence,position] error:failure]) return NO;
        }
        if (positions.count && ![self qry:"DELETE FROM reminder_checkins WHERE occurrence_id=?" values:@[occurrence] error:failure]) return NO;
        return [self qry:"UPDATE task_archive SET uploaded=1,provider_id=?,archive_day=? WHERE entry_id=?"
            values:@[provider,day,entryID] error:failure] != nil;
    } error:error];
}

// 批量上传后释放足够大的空闲页，日常小文件复用空闲空间。
- (BOOL)arcTrim:(NSError **)error {
    @synchronized(self) {
        NSArray *rows = [self qry:"SELECT freelist_count*page_size AS bytes FROM pragma_freelist_count,pragma_page_size" values:@[] error:error];
        if (!rows) return NO;
        return [rows.firstObject[@"bytes"] longLongValue] < 1024*1024 || [self exec:"VACUUM" error:error];
    }
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
        NSArray *slots = history ? [self qry:"SELECT * FROM agenda_slots ORDER BY start_at,task_id" values:@[] error:failure] : nil;
        long long revision = slots ? [self revision:failure] : -1;
        if (revision < 0) return NO;
        result = @{@"tasks": tasks, @"history": history, @"slots":slots, @"revision": @(revision)};
        return YES;
    } error:error];
    return success ? result : nil;
}

// 按有效提醒时间排序，未安排提醒的任务仍在末尾返回。
- (NSArray *)lsPnd:(NSError **)error {
    NSDictionary *snapshot = [self planAt:NSDate.date.timeIntervalSince1970 error:error];
    return snapshot ? [TaskStore pndRows:snapshot] : nil;
}

// 共享计划快照中的任务排序与有效提醒。
+ (NSArray *)pndRows:(NSDictionary *)snapshot {
    NSMutableDictionary *first = [NSMutableDictionary dictionary];
    for (NSDictionary *alert in snapshot[@"alerts"]) if (!first[alert[@"task_id"]]) first[alert[@"task_id"]] = alert;
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *task in snapshot[@"tasks"]) {
        if ([task[@"deleted"] boolValue] || ![task[@"status"] isEqual:@"needsAction"]) continue;
        NSMutableDictionary *item = [task mutableCopy];
        NSDictionary *alert = first[task[@"task_id"]];
        item[@"remind_at"] = alert[@"remind_at"] ?: NSNull.null;
        item[@"next_cycle_at"] = alert[@"cycle_at"] ?: NSNull.null;
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

// 用当地日历定位最近的02:00边界，兼容夏令时。
static NSDate *ts_expiry(NSCalendar *calendar, NSDate *day) {
    return [calendar nextDateAfterDate:[day dateByAddingTimeInterval:-1]
        matchingHour:2 minute:0 second:0 options:NSCalendarMatchNextTime | NSCalendarMatchFirst];
}

// 最近一次02:00对应的日界之前属于过期轮次。
static double ts_cutoff(double stamp, NSCalendar *calendar) {
    NSDate *day = [calendar startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:stamp]];
    if (stamp < ts_expiry(calendar,day).timeIntervalSince1970)
        day = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:day options:0];
    return day.timeIntervalSince1970;
}

// 下次过期检查与午夜换日由同一墙钟调度。
+ (NSTimeInterval)nextExpiry:(NSTimeInterval)stamp zone:(NSString *)zone {
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:zone] ?: NSTimeZone.localTimeZone;
    NSDate *day = [calendar startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:stamp]];
    NSDate *expiry = ts_expiry(calendar,day);
    if (expiry.timeIntervalSince1970 <= stamp)
        expiry = ts_expiry(calendar,[calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:day options:0]);
    return expiry.timeIntervalSince1970;
}

// 以实际安排开始时间判断轮次归属，延期不改变原日期。
static BOOL ts_stale(NSDictionary *alert, NSArray *slots, double cutoff) {
    NSDictionary *task = alert[@"task"];
    for (NSDictionary *slot in slots)
        if ([slot[@"task_id"] isEqual:alert[@"task_id"]] && [slot[@"generation"] isEqual:alert[@"generation"]]
            && [slot[@"cycle_at"] isEqual:alert[@"cycle_at"]]) return [slot[@"start_at"] doubleValue] < cutoff;
    id anchor = task[@"due_at"] != NSNull.null && ![task[@"planning_mode"] isEqual:@"window"] ? alert[@"cycle_at"] : alert[@"scheduled_at"];
    return [anchor doubleValue] < cutoff;
}

// 原子丢弃过期执行轮次，保留任务、常律规则与已完成记录。
- (BOOL)expAt:(double)stamp cutoff:(double)cutoff error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        NSDictionary *snapshot = [self snapshot:failure]; if (!snapshot) return NO;
        NSArray *history = snapshot[@"history"], *slots = snapshot[@"slots"];
        for (NSDictionary *task in snapshot[@"tasks"]) {
            NSArray *alerts = ta_alerts(task,history,slots,cutoff,failure);
            if (!alerts) return NO;
            for (NSDictionary *alert in alerts) {
                if (!ts_stale(alert,slots,cutoff)) continue;
                NSNumber *now = @(stamp);
                if (![self qry:"INSERT INTO reminder_occurrences(occurrence_id,task_id,scheduled_at,cycle_at,generation,kind,handled_at,status,action,created_at,updated_at) "
                    "VALUES(?,?,?,?,?,?,?,'resolved','expire',?,?) ON CONFLICT(task_id,generation,kind,cycle_at) DO UPDATE SET "
                    "status='resolved',action='expire',next_fire_at=NULL,hold_reason=NULL,hold_until=NULL,handled_at=excluded.handled_at,updated_at=excluded.updated_at "
                    "WHERE reminder_occurrences.status IN ('pending','presented','snoozed')"
                    values:@[NSUUID.UUID.UUIDString.lowercaseString,alert[@"task_id"],alert[@"scheduled_at"],alert[@"cycle_at"],alert[@"generation"],alert[@"kind"],now,now,now] error:failure]) return NO;
            }
        }
        return YES;
    } error:error];
}

// 使用同一数据快照与原生重复模块生成完整计划。
- (NSDictionary *)planAt:(NSTimeInterval)stamp error:(NSError **)error {
    if (!isfinite(stamp)) { [self dbErr:SQLITE_MISMATCH message:@"调度时刻无效" error:error]; return nil; }
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = NSTimeZone.localTimeZone;
    double cutoff = ts_cutoff(stamp,calendar);
    if (![self expAt:stamp cutoff:cutoff error:error] || ![self arrangeAt:stamp zone:calendar.timeZone.name error:error]) return nil;
    NSDictionary *snapshot = [self snapshot:error]; if (!snapshot) return nil;
    NSMutableArray *alerts = [NSMutableArray array];
    NSMutableSet *parents=[NSMutableSet set],*active=[NSMutableSet set],*ready=[NSMutableSet set],*slotted=[NSMutableSet set];
    NSMutableDictionary *children=[NSMutableDictionary dictionary],*byID=[NSMutableDictionary dictionary];
    for(NSDictionary *task in snapshot[@"tasks"])byID[task[@"task_id"]]=task;
    for(NSDictionary *slot in snapshot[@"slots"])if([slot[@"generation"] isEqual:byID[slot[@"task_id"]][@"reminder_version"]])[slotted addObject:slot[@"task_id"]];
    for(NSDictionary *task in snapshot[@"tasks"]) {
        NSString *id=task[@"task_id"];if([task[@"deleted"] boolValue])continue;
        if(task[@"parent_id"]!=NSNull.null){NSString *parent=task[@"parent_id"];if(!children[parent])children[parent]=[NSMutableArray array];[children[parent] addObject:task];}
        if(task[@"due_at"]!=NSNull.null || task[@"deadline_at"]!=NSNull.null || [slotted containsObject:id])[ready addObject:id];
    }
    for(NSDictionary *row in snapshot[@"history"])if([@[@"presented",@"snoozed"] containsObject:row[@"status"]]){[active addObject:row[@"task_id"]];[ready addObject:row[@"task_id"]];}
    // 全部未完成子级都有独立提醒时才停用汇总提醒；旧子任务未估时仍保留父级。
    BOOL changed=YES;while(changed){changed=NO;for(NSString *id in children){
        if([parents containsObject:id])continue;BOOL pending=NO,all=YES;
        for(NSDictionary *child in children[id])if([child[@"status"] isEqual:@"needsAction"]){pending=YES;if(![ready containsObject:child[@"task_id"]])all=NO;}
        if(pending && all){[parents addObject:id];if(![ready containsObject:id]){[ready addObject:id];changed=YES;}}
    }}
    for (NSDictionary *task in snapshot[@"tasks"]) {
        if([parents containsObject:task[@"task_id"]] && ![active containsObject:task[@"task_id"]])continue;
        NSArray *items = ta_alerts(task,snapshot[@"history"],snapshot[@"slots"],stamp,error);
        if (!items) return nil;
        for (NSDictionary *alert in items) if (!ts_stale(alert,snapshot[@"slots"],cutoff)) [alerts addObject:alert];
    }
    NSMutableDictionary *result = [snapshot mutableCopy];
    NSDate *day = [calendar startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:stamp]];
    double midnight = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:day options:0].timeIntervalSince1970;
    result[@"agenda_wake_at"] = @(fmin(midnight,[TaskStore nextExpiry:stamp zone:calendar.timeZone.name]));
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
        NSArray *slots = [self qry:"SELECT * FROM agenda_slots WHERE task_id=?" values:@[task[@"task_id"]] error:failure];
        NSArray *history = slots ? [self lsOcc:task[@"task_id"] error:failure] : nil;
        NSArray *valid = history ? ta_alerts(task,history,slots,stamp,failure) : nil;
        if (!valid) return NO;
        BOOL matches = NO;
        for (NSDictionary *candidate in valid) if ([candidate[@"kind"] isEqual:alert[@"kind"]] && [candidate[@"cycle_at"] isEqual:alert[@"cycle_at"]]
            && [candidate[@"scheduled_at"] isEqual:alert[@"scheduled_at"]] && [candidate[@"remind_at"] isEqual:alert[@"remind_at"]]) {
            NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
            calendar.timeZone = NSTimeZone.localTimeZone;
            matches = !ts_stale(candidate,slots,ts_cutoff(stamp,calendar));
        }
        if (!matches) return YES;
        NSNumber *now = @(stamp);
        if (![self qry:"INSERT INTO reminder_occurrences(occurrence_id,task_id,scheduled_at,cycle_at,generation,kind,next_fire_at,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?) "
            "ON CONFLICT(task_id,generation,kind,cycle_at) DO NOTHING"
            values:@[NSUUID.UUID.UUIDString.lowercaseString, task[@"task_id"], alert[@"scheduled_at"], alert[@"cycle_at"], alert[@"generation"], alert[@"kind"], alert[@"remind_at"], now, now] error:failure]) return NO;
        NSArray *rows = [self qry:"SELECT * FROM reminder_occurrences WHERE task_id=? AND generation=? AND kind=? AND cycle_at=?"
            values:@[task[@"task_id"], alert[@"generation"], alert[@"kind"], alert[@"cycle_at"]] error:failure];
        NSDictionary *occ = rows.firstObject;
        if (!occ) return NO;
        if (![@[@"pending",@"presented",@"snoozed"] containsObject:occ[@"status"]]) return YES;
        if (![occ[@"status"] isEqual:@"presented"] && ![self qry:"UPDATE reminder_occurrences SET status='presented',triggered_at=?,handled_at=NULL,action=NULL,next_fire_at=?,updated_at=?,signal_at=NULL,signal_uptime=NULL,signal_ack=0 WHERE occurrence_id=?"
            values:@[now, alert[@"remind_at"], now, occ[@"occurrence_id"]] error:failure]) return NO;
        NSMutableDictionary *item = [alert mutableCopy]; item[@"occurrence_id"] = occ[@"occurrence_id"]; item[@"task"] = task;
        result = item;
        return YES;
    } error:error];
    return success ? result : nil;
}

// 结束同轮双提醒并持久化重复任务的下一轮。
- (BOOL)finCyc:(NSDictionary *)occ task:(NSDictionary *)task at:(NSNumber *)now error:(NSError **)error {
    if (![self qry:"UPDATE reminder_occurrences SET status='resolved',action='complete',handled_at=?,next_fire_at=NULL,updated_at=? "
        "WHERE task_id=? AND generation=? AND cycle_at=? AND status!='resolved'"
        values:@[now,now,task[@"task_id"],occ[@"generation"],occ[@"cycle_at"]] error:error]) return NO;
    NSArray *alerts = @[];
    if ([task[@"recurrence"] count]) {
        NSArray *history=[self lsOcc:task[@"task_id"] error:error];
        alerts=history ? [TaskRule alerts:task history:history at:now.doubleValue error:error] : nil;
    }
    if (!alerts) return NO;
    if (!alerts.count) {
        if (![self cmplTsk:task[@"task_id"] error:error]) return NO;
        NSArray *rows = [self qry:"UPDATE task_archive SET restore_at=(SELECT completed_at FROM tasks WHERE task_id=?) "
            "WHERE task_id=? AND occurrence_id IN (SELECT occurrence_id FROM reminder_occurrences WHERE task_id=? AND generation=? AND cycle_at=?)"
            values:@[task[@"task_id"],task[@"task_id"],task[@"task_id"],occ[@"generation"],occ[@"cycle_at"]] error:error];
        return rows && [self qry:"DELETE FROM task_archive WHERE occurrence_id IS NULL AND task_id=? "
            "AND completed_at=(SELECT completed_at FROM tasks WHERE task_id=?)"
            values:@[task[@"task_id"],task[@"task_id"]] error:error] != nil;
    }
    NSNumber *cycle=alerts.firstObject[@"cycle_at"];
    for (NSDictionary *next in alerts) if ([next[@"cycle_at"] isEqual:cycle]) {
        if (![self qry:"INSERT INTO reminder_occurrences(occurrence_id,task_id,scheduled_at,cycle_at,generation,kind,next_fire_at,created_at,updated_at) "
            "VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(task_id,generation,kind,cycle_at) DO NOTHING"
            values:@[NSUUID.UUID.UUIDString.lowercaseString,task[@"task_id"],next[@"scheduled_at"],cycle,task[@"reminder_version"],next[@"kind"],next[@"remind_at"],now,now] error:error]) return NO;
    }
    return YES;
}

// 处理一次提醒，普通完成任务或记录重复任务本轮完成。
- (BOOL)actOcc:(NSString *)occID action:(NSString *)action until:(NSNumber *)until error:(NSError **)error {
    return [self actOcc:occID action:action until:until hold:@"snooze" error:error];
}

// 同一事务核对一次延期，截图收起不消耗延期名额。
- (BOOL)actOcc:(NSString *)occID action:(NSString *)action until:(NSNumber *)until hold:(NSString *)mode error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(occID) || ![@[@"complete", @"dismiss", @"snooze"] containsObject:action]
            || ([action isEqual:@"snooze"] && (!ts_num(until) || until.doubleValue <= NSDate.date.timeIntervalSince1970)))
            return [self dbErr:SQLITE_MISMATCH message:@"提醒动作或延后时间无效" error:failure];
        NSDictionary *occ = [self qry:"SELECT * FROM reminder_occurrences WHERE occurrence_id=?" values:@[occID.lowercaseString] error:failure].firstObject;
        if (!occ) return [self dbErr:SQLITE_NOTFOUND message:@"提醒不存在" error:failure];
        if (![occ[@"status"] isEqual:@"presented"]) return [self dbErr:SQLITE_NOTFOUND message:@"提醒已处理" error:failure];
        NSDictionary *task = [self rdTsk:occ[@"task_id"] error:failure];
        if (!task) return NO;
        if ([task[@"deleted"] boolValue] || ![task[@"status"] isEqual:@"needsAction"] || ![task[@"reminder_version"] isEqual:occ[@"generation"]])
            return [self dbErr:SQLITE_NOTFOUND message:@"提醒已失效" error:failure];
        BOOL snooze=[action isEqual:@"snooze"], counted=snooze && [mode isEqual:@"snooze"];
        if (counted && [occ[@"defer_count"] integerValue]!=0) return [self dbErr:SQLITE_CONSTRAINT message:@"本次已延后" error:failure];
        NSNumber *now = @(NSDate.date.timeIntervalSince1970);
        if (snooze && fabs(until.doubleValue-now.doubleValue-(counted?300:120))>2)
            return [self dbErr:SQLITE_CONSTRAINT message:@"收起时长无效" error:failure];
        NSString *state = [action isEqual:@"snooze"] ? @"snoozed" : ([action isEqual:@"complete"] ? @"completed" : @"resolved");
        if (![self updOcc:occID fields:@{@"status":state,@"handled_at":now,@"action":action,@"next_fire_at":until ?: NSNull.null} error:failure]) return NO;
        if (snooze && ![self qry:"UPDATE reminder_occurrences SET defer_count=defer_count+?,hold_reason=?,hold_until=? WHERE occurrence_id=?"
            values:@[@(counted?1:0),mode,until,occID.lowercaseString] error:failure]) return NO;
        return ![action isEqual:@"complete"] || [self finCyc:occ task:task at:now error:failure];
    } error:error];
}

// 在当前轮次的同一事务中处理收起和次数限制。
- (NSDictionary *)hldOcc:(NSString *)occID mode:(NSString *)mode error:(NSError **)error {
    __block NSDictionary *result = nil;
    BOOL success = [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(occID) || ![@[@"snooze",@"screenshot"] containsObject:mode])
            return [self dbErr:SQLITE_MISMATCH message:@"收起方式无效" error:failure];
        NSDictionary *row = [self qry:"SELECT * FROM reminder_occurrences WHERE occurrence_id=?" values:@[occID.lowercaseString] error:failure].firstObject;
        if (!row) return [self dbErr:SQLITE_NOTFOUND message:@"提醒不存在" error:failure];
        BOOL snooze = [mode isEqual:@"snooze"];
        if (snooze && [row[@"defer_count"] integerValue] != 0)
            return [self dbErr:SQLITE_CONSTRAINT message:@"本次已延后" error:failure];
        NSNumber *until = @(NSDate.date.timeIntervalSince1970 + (snooze ? 300 : 120));
        if (![self actOcc:occID action:@"snooze" until:until hold:mode error:failure]) return NO;
        result = [self qry:"SELECT occurrence_id,defer_count,hold_reason,hold_until FROM reminder_occurrences WHERE occurrence_id=?"
            values:@[occID.lowercaseString] error:failure].firstObject;
        return result != nil;
    } error:error];
    return success ? result : nil;
}

// 主动展开边栏，保留该轮次的唯一延期次数。
- (BOOL)rsmOcc:(NSString *)occID error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(occID)) return [self dbErr:SQLITE_MISMATCH message:@"提醒标识无效" error:failure];
        NSDictionary *row = [self qry:"SELECT * FROM reminder_occurrences WHERE occurrence_id=?" values:@[occID.lowercaseString] error:failure].firstObject;
        NSDictionary *task = row ? [self rdTsk:row[@"task_id"] error:failure] : nil;
        if (!task || ![row[@"status"] isEqual:@"snoozed"] || ![row[@"action"] isEqual:@"snooze"] || row[@"hold_reason"]==NSNull.null
            || [task[@"deleted"] boolValue] || ![task[@"status"] isEqual:@"needsAction"] || ![task[@"reminder_version"] isEqual:row[@"generation"]])
            return [self dbErr:SQLITE_NOTFOUND message:@"边栏提醒已失效" error:failure];
        if (![self updOcc:occID fields:@{@"status":@"presented",@"triggered_at":@(NSDate.date.timeIntervalSince1970),@"handled_at":NSNull.null,@"action":NSNull.null,@"next_fire_at":@(NSDate.date.timeIntervalSince1970)} error:failure]) return NO;
        // 用户主动展开已表示注意到提醒，不再启动新一轮声振。
        return [self qry:"UPDATE reminder_occurrences SET signal_ack=1 WHERE occurrence_id=?" values:@[occID.lowercaseString] error:failure] != nil;
    } error:error];
}

// 只为真实显示的当前呈现建立时限，队列中的等待项不提前消耗。
- (NSDictionary *)sigOcc:(NSString *)occID trigger:(NSNumber *)trigger ack:(BOOL)ack error:(NSError **)error {
    __block NSDictionary *result = nil;
    BOOL success = [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(occID) || !ts_num(trigger)) return [self dbErr:SQLITE_MISMATCH message:@"声振标识无效" error:failure];
        NSDictionary *row = [self qry:"SELECT * FROM reminder_occurrences WHERE occurrence_id=?" values:@[occID.lowercaseString] error:failure].firstObject;
        if (!row) { if (failure && *failure) return NO; return YES; }
        NSDictionary *task = [self rdTsk:row[@"task_id"] error:failure];
        if (!task) return NO;
        if (![row[@"status"] isEqual:@"presented"] || ![row[@"triggered_at"] isEqual:trigger]
            || [task[@"deleted"] boolValue] || ![task[@"status"] isEqual:@"needsAction"] || ![task[@"reminder_version"] isEqual:row[@"generation"]]) return YES;
        BOOL fresh = row[@"signal_at"] == NSNull.null;
        if (fresh) {
            if (![self qry:"UPDATE reminder_occurrences SET signal_at=?,signal_uptime=?,signal_ack=MAX(signal_ack,?) WHERE occurrence_id=?"
                values:@[@(NSDate.date.timeIntervalSince1970),@(NSProcessInfo.processInfo.systemUptime),@(ack),occID.lowercaseString] error:failure]) return NO;
        } else if (ack && ![row[@"signal_ack"] boolValue]) {
            if (![self qry:"UPDATE reminder_occurrences SET signal_ack=1 WHERE occurrence_id=?" values:@[occID.lowercaseString] error:failure]) return NO;
        }
        result = [self qry:"SELECT signal_at,signal_uptime,signal_ack FROM reminder_occurrences WHERE occurrence_id=?" values:@[occID.lowercaseString] error:failure].firstObject;
        if (result) { NSMutableDictionary *state = [result mutableCopy]; state[@"signal_new"] = @(fresh); result = state; }
        return result != nil;
    } error:error];
    return success ? result : nil;
}

// 保留单图入口并复用同一批次提交事务。
- (BOOL)chkOcc:(NSString *)occID method:(NSString *)method image:(NSData *)image error:(NSError **)error {
    if (!method || !image) return [self dbErr:SQLITE_MISMATCH message:@"打卡图片或方式无效" error:error];
    return [self chkOcc:occID attachments:@[@{@"method":method,@"image":image}] error:error];
}

// 核对全部图片后在同一事务保存附件并完成提醒。
- (BOOL)chkOcc:(NSString *)occID attachments:(NSArray<NSDictionary *> *)attachments error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(occID)) return [self dbErr:SQLITE_MISMATCH message:@"打卡标识无效" error:failure];
        if (![TaskStore vldPrfs:attachments error:failure]) return NO;
        if (![self actOcc:occID action:@"complete" until:nil error:failure]) return NO;
        NSTimeInterval stamp=NSDate.date.timeIntervalSince1970;
        for (NSUInteger index=0;index<attachments.count;index++) {
            NSDictionary *item=attachments[index];
            if (![self qry:"INSERT INTO reminder_checkins(occurrence_id,position,method,image,created_at,name,content_type) VALUES(?,?,?,?,?,?,?)"
                values:@[occID.lowercaseString,@(index),item[@"method"],item[@"image"],@(stamp),item[@"name"] ?: NSNull.null,item[@"content_type"] ?: NSNull.null] error:failure]) return NO;
        }
        return YES;
    } error:error];
}

// 所有采集和最终提交复用同一组图片边界。
+ (BOOL)vldPrfs:(NSArray *)attachments error:(NSError **)error {
    if (![attachments isKindOfClass:NSArray.class] || attachments.count<1 || attachments.count>TS_ATT_MAX)
        return ts_err(error,SQLITE_MISMATCH,@"附件数量须为1至6个");
    for (id item in attachments) {
        if (![item isKindOfClass:NSDictionary.class]) return ts_err(error,SQLITE_MISMATCH,@"附件无效");
        NSString *method=item[@"method"]; NSData *image=item[@"image"];
        if (![method isKindOfClass:NSString.class] || ![@[@"camera",@"screenshot",@"image",@"file"] containsObject:method] || ![image isKindOfClass:NSData.class]
            || image.length>20*1024*1024) return ts_err(error,SQLITE_MISMATCH,@"附件或方式无效");
        // 普通文件保留原始内容，不能按图片解码或转换。
        if ([method isEqual:@"file"]) {
            if (!ts_txt(item[@"name"],1024) || !ts_txt(item[@"content_type"],255)) return ts_err(error,SQLITE_MISMATCH,@"文件信息无效");
            continue;
        }
        if (!image.length) return ts_err(error,SQLITE_MISMATCH,@"打卡图片或方式无效");
        CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)image,NULL);
        NSDictionary *properties=source ? CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL)) : nil;
        long long width=[properties[(__bridge NSString *)kCGImagePropertyPixelWidth] longLongValue],height=[properties[(__bridge NSString *)kCGImagePropertyPixelHeight] longLongValue];
        BOOL valid=width>0 && height>0 && width<=20000 && height<=20000 && width*height<=100000000;
        CGImageRef decoded=valid ? CGImageSourceCreateImageAtIndex(source,0,NULL) : NULL;
        if (source) CFRelease(source);
        if (decoded) CGImageRelease(decoded); else return ts_err(error,SQLITE_MISMATCH,@"图片无法读取");
    }
    return YES;
}

// 请求只携带轮次、来源和剩余名额，不修改完成状态。
- (NSDictionary *)reqCap:(NSString *)occID source:(NSString *)source limit:(NSInteger)limit error:(NSError **)error {
    __block NSDictionary *request=nil;
    BOOL success=[self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(occID) || ![@[@"camera",@"image",@"screenshot",@"file"] containsObject:source] || limit<1 || limit>TS_ATT_MAX)
            return [self dbErr:SQLITE_MISMATCH message:@"采集参数无效" error:failure];
        NSArray *valid=[self qry:"SELECT o.occurrence_id FROM reminder_occurrences o JOIN tasks t ON t.task_id=o.task_id WHERE o.occurrence_id=? AND o.status='presented' AND t.deleted=0 AND t.status='needsAction' AND o.generation=t.reminder_version" values:@[occID] error:failure];
        if (!valid) return NO;
        if (!valid.count) return [self dbErr:SQLITE_NOTFOUND message:@"采集轮次已失效" error:failure];
        NSString *token=NSUUID.UUID.UUIDString.lowercaseString;
        if (![self qry:"DELETE FROM capture_request" values:@[] error:failure] || ![self qry:"INSERT INTO capture_request(token,occurrence_id,source,capacity,created_at) VALUES(?,?,?,?,?)" values:@[token,occID,source,@(limit),@(NSDate.date.timeIntervalSince1970)] error:failure]) return NO;
        request=[self rdCap:token error:failure];return request!=nil;
    } error:error];
    return success ? request : nil;
}

// 二进制属性列表只在短期交接表内传递，不增加数据库文件。
- (NSDictionary *)rdCap:(NSString *)token error:(NSError **)error {
    @synchronized(self) {
        NSArray *rows=[self qry:token ? "SELECT * FROM capture_request WHERE token=?" : "SELECT * FROM capture_request LIMIT 1" values:token ? @[token] : @[] error:error];
        if (!rows) return nil;
        if (!rows.count) return @{};
        NSMutableDictionary *row=[rows.firstObject mutableCopy];
        if ([row[@"payload"] isKindOfClass:NSData.class]) {
            id items=[NSPropertyListSerialization propertyListWithData:row[@"payload"] options:NSPropertyListImmutable format:nil error:error];
            if (![items isKindOfClass:NSArray.class]) return nil;
            row[@"attachments"]=items;
        }
        [row removeObjectForKey:@"payload"];return row;
    }
}

// 前台进程确认接管后，HUD监视该进程退出。
- (BOOL)ackCap:(NSString *)token error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        NSDictionary *row=[self rdCap:token error:failure];
        if (!row[@"token"] || [row[@"state"] intValue]!=0 || NSDate.date.timeIntervalSince1970-[row[@"created_at"] doubleValue]>30)
            return [self dbErr:SQLITE_NOTFOUND message:@"采集请求已失效" error:failure];
        return [self qry:"UPDATE capture_request SET state=1,pid=? WHERE token=?" values:@[@(getpid()),token] error:failure]!=nil;
    } error:error];
}

// 取消、读取失败与有效结果均只交回HUD，不直接打卡。
- (BOOL)finCap:(NSString *)token attachments:(NSArray *)attachments issue:(NSString *)issue error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        NSDictionary *row=[self rdCap:token error:failure];
        if (!row || [row[@"state"] intValue]!=1 || [row[@"pid"] intValue]!=getpid()) return [self dbErr:SQLITE_NOTFOUND message:@"采集请求已失效" error:failure];
        if (![attachments isKindOfClass:NSArray.class] || attachments.count>[row[@"capacity"] unsignedIntegerValue]) return [self dbErr:SQLITE_MISMATCH message:@"附件超出剩余名额" error:failure];
        if (attachments.count && ![TaskStore vldPrfs:attachments error:failure]) return NO;
        NSData *payload=[NSPropertyListSerialization dataWithPropertyList:attachments format:NSPropertyListBinaryFormat_v1_0 options:0 error:failure];
        if (!payload) return NO;
        return [self qry:"UPDATE capture_request SET state=2,payload=?,issue=? WHERE token=?" values:@[payload,issue ?: NSNull.null,token] error:failure]!=nil;
    } error:error];
}

// 交接结束或服务重新启动时清理临时结果。
- (BOOL)delCap:(NSString *)token error:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {return [self qry:token ? "DELETE FROM capture_request WHERE token=?" : "DELETE FROM capture_request" values:token ? @[token] : @[] error:failure]!=nil;} error:error];
}

// 按序读取同一提醒的全部附件，普通读取仅返回元数据。
- (NSArray<NSDictionary *> *)lsChk:(NSString *)occID images:(BOOL)images error:(NSError **)error {
    @synchronized(self) {
        if (!ts_uuid(occID)) { [self dbErr:SQLITE_MISMATCH message:@"打卡标识无效" error:error]; return nil; }
        NSArray *local = [self qry:images ? "SELECT * FROM reminder_checkins WHERE occurrence_id=? ORDER BY position"
            : "SELECT occurrence_id,position,method,created_at,name,content_type,length(image) AS image_bytes FROM reminder_checkins WHERE occurrence_id=? ORDER BY position"
            values:@[occID.lowercaseString] error:error];
        if (!local || local.count) return local;
        NSArray *remote = [self qry:"SELECT * FROM archive_files WHERE occurrence_id=? ORDER BY position" values:@[occID.lowercaseString] error:error];
        if (images && remote.count) {
            [self dbErr:SQLITE_NOTFOUND message:@"附件已转存云端，请在归档中打开" error:error];
            return nil;
        }
        return remote;
    }
}

// 按指定序号只读取一份归档附件。
- (NSDictionary *)rdPrf:(NSString *)occID position:(NSInteger)position error:(NSError **)error {
    @synchronized(self) {
        if (!ts_uuid(occID) || position<0 || position>=TS_ATT_MAX) { [self dbErr:SQLITE_CONSTRAINT message:@"附件序号无效" error:error]; return nil; }
        NSArray *rows = [self qry:"SELECT * FROM reminder_checkins WHERE occurrence_id=? AND position=?" values:@[occID.lowercaseString,@(position)] error:error];
        if (rows && !rows.count) rows = [self qry:"SELECT * FROM archive_files WHERE occurrence_id=? AND position=?" values:@[occID.lowercaseString,@(position)] error:error];
        if (rows && !rows.count) [self dbErr:SQLITE_NOTFOUND message:@"附件不存在" error:error]; return rows.firstObject;
    }
}

// 保留旧单图读取约定，返回按序排列的首个附件。
- (NSDictionary *)rdChk:(NSString *)occID image:(BOOL)image error:(NSError **)error {
    NSArray *rows=[self lsChk:occID images:image error:error];
    if (rows && rows.count==0) [self dbErr:SQLITE_NOTFOUND message:@"尚未打卡" error:error];
    return rows.firstObject;
}

// 按固定身份创建常驻清单。
- (BOOL)rtnList:(NSError **)error {
    return [self wrTxn:^BOOL(NSError **failure) {
        return [self qry:"INSERT INTO task_lists(list_id,title,created_at,updated_at,deleted) VALUES(?,'常律',?,?,0) ON CONFLICT(list_id) DO NOTHING"
            values:@[TS_RTN_LST,@(NSDate.date.timeIntervalSince1970),@(NSDate.date.timeIntervalSince1970)] error:failure] != nil;
    } error:error];
}

// 返回现有评估，未评估任务返回空对象。
- (NSDictionary *)rdReview:(NSString *)taskID error:(NSError **)error {
    @synchronized(self) {
        NSArray *rows=[self qry:"SELECT data FROM task_reviews WHERE task_id=?" values:@[taskID] error:error];if(!rows)return nil;
        return rows.count ? [NSJSONSerialization JSONObjectWithData:[rows[0][@"data"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:error] : @{};
    }
}
// 在调用方事务中保存评估与任务，失败时整体回滚。
- (BOOL)svReview:(NSString *)taskID data:(NSDictionary *)data error:(NSError **)error {
    NSData *bytes=[NSJSONSerialization dataWithJSONObject:data options:NSJSONWritingSortedKeys error:error];if(!bytes)return NO;
    return [self wrTxn:^BOOL(NSError **failure){return [self qry:"INSERT INTO task_reviews(task_id,data) VALUES(?,?) ON CONFLICT(task_id) DO UPDATE SET data=excluded.data"
        values:@[taskID,[[NSString alloc]initWithData:bytes encoding:NSUTF8StringEncoding]] error:failure]!=nil;} error:error];
}
// 逐日模拟既有任务，已分配的一次性任务不在次日重复占用。
- (NSDictionary *)roomAt:(NSTimeInterval)start until:(NSTimeInterval)end zone:(NSString *)zone excluding:(NSArray *)ids now:(NSTimeInterval)now error:(NSError **)error {
    if(!isfinite(start)||!isfinite(end)||end<=start||!isfinite(now)||![NSTimeZone timeZoneWithName:zone]) {ts_err(error,SQLITE_CONSTRAINT,@"请选择有效时间窗口");return nil;}
    NSMutableDictionary *snapshot=[[self snapshot:error] mutableCopy];if(!snapshot)return nil;
    NSMutableSet *excluded=[NSMutableSet setWithArray:ids];BOOL changed=YES;
    while(changed){NSUInteger count=excluded.count;for(NSDictionary *task in snapshot[@"tasks"])if([excluded containsObject:task[@"parent_id"]])[excluded addObject:task[@"task_id"]];changed=count!=excluded.count;}
    NSMutableArray *tasks=[NSMutableArray array];for(NSDictionary *task in snapshot[@"tasks"])if(![excluded containsObject:task[@"task_id"]])[tasks addObject:[task mutableCopy]];
    snapshot[@"tasks"]=tasks;
    NSMutableArray *history=[NSMutableArray array];for(NSDictionary *row in snapshot[@"history"]){NSMutableDictionary *copy=row.mutableCopy;if([@[@"presented",@"snoozed"] containsObject:copy[@"status"]])copy[@"status"]=@"pending";[history addObject:copy];}snapshot[@"history"]=history;
    NSMutableArray *gaps=[NSMutableArray array];NSMutableSet *reserved=[NSMutableSet set];
    NSCalendar *calendar=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=[NSTimeZone timeZoneWithName:zone];
    NSDate *day=[calendar startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:start]];NSUInteger count=0;double capacity=0,maxSpan=0;BOOL conflicts=NO;
    while(day.timeIntervalSince1970<end){
        if(++count>400)break;
        NSDictionary *plan=ta_plan(snapshot,day.timeIntervalSince1970,zone,now,error);if(!plan)return nil;
        NSMutableArray *windows=[NSMutableArray array],*busy=[NSMutableArray array];
        for(NSDictionary *entry in plan[@"entries"]) {
            if([entry[@"kind"] isEqual:@"work"])[windows addObject:entry];
            else if(![entry[@"kind"] isEqual:@"background"])[busy addObject:entry];
            NSDictionary *task=entry[@"task"];if([entry[@"kind"] isEqual:@"task"] && ![task[@"recurrence"] count])[reserved addObject:task[@"task_id"]];
        }
        conflicts=conflicts||[plan[@"conflicts"] count]>0;
        for(NSDictionary *gap in ta_free(windows,busy)) {
            double lo=fmax([gap[@"start_at"] doubleValue],fmax(start,ceil(now/60)*60)),hi=fmin([gap[@"end_at"] doubleValue],end);
            if(hi>lo){[gaps addObject:@{@"start_at":@(lo),@"end_at":@(hi)}];capacity+=hi-lo;maxSpan=fmax(maxSpan,hi-lo);}
        }
        for(NSMutableDictionary *task in tasks)if([reserved containsObject:task[@"task_id"]])task[@"deleted"]=@1;
        day=[calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:day options:0];
    }
    return @{@"gaps":gaps,@"capacity":@(capacity),@"max_span":@(maxSpan),@"revision":snapshot[@"revision"],@"conflicts":@(conflicts),@"truncated":@(count>400)};
}

// 从同一快照读取指定日期的安排。
- (NSDictionary *)dayAt:(NSTimeInterval)stamp zone:(NSString *)zone now:(NSTimeInterval)now error:(NSError **)error {
    NSDictionary *snapshot = [self snapshot:error];
    return snapshot ? ta_plan(snapshot,stamp,zone,now,error) : nil;
}

// 按需读取一批常律日程，执行状态不参与模板展开。
- (NSArray *)rtnDays:(NSTimeInterval)stamp count:(NSUInteger)count zone:(NSString *)zone error:(NSError **)error {
    NSTimeZone *tz = [NSTimeZone timeZoneWithName:zone];
    if (!tz || !isfinite(stamp) || !count || count > 28) {
        [self dbErr:SQLITE_CONSTRAINT message:@"常律日期范围无效" error:error]; return nil;
    }
    NSArray *rows;
    @synchronized(self) {
        rows = [self qry:"SELECT * FROM tasks WHERE list_id=? AND deleted=0 ORDER BY position,created_at,task_id" values:@[TS_RTN_LST] error:error];
    }
    if (!rows) return nil;
    NSMutableArray *tasks = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSDictionary *task = [self dec:row error:error]; if (!task) return nil;
        [tasks addObject:task];
    }
    NSDictionary *snapshot = @{@"tasks":tasks,@"history":@[],@"templates":@YES,@"revision":@0};
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = tz;
    NSDate *day = [calendar startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:stamp]];
    NSMutableArray *days = [NSMutableArray array];
    for (NSUInteger index=0; index<count; index++) {
        NSDictionary *plan = ta_plan(snapshot,day.timeIntervalSince1970,zone,day.timeIntervalSince1970,error);
        if (!plan) return nil;
        [days addObject:plan];
        day = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:day options:0];
    }
    return days;
}

// 草稿预览只改快照副本，不能改变共享服务和数据库。
- (NSDictionary *)draftDay:(NSTimeInterval)stamp zone:(NSString *)zone now:(NSTimeInterval)now error:(NSError **)error {
    NSMutableDictionary *snapshot = [[self snapshot:error] mutableCopy]; if (!snapshot) return nil;
    NSMutableArray *tasks = [NSMutableArray array];
    for (NSDictionary *task in snapshot[@"tasks"]) {
        NSMutableDictionary *copy = [task mutableCopy];
        if (![copy[@"routine_kind"] isEqual:@"none"]) copy[@"routine_enabled"] = @1;
        [tasks addObject:copy];
    }
    snapshot[@"tasks"] = tasks; return ta_plan(snapshot,stamp,zone,now,error);
}

// 共用原文导入事务，正式常律仅首次写入，后续保留用户编辑。
- (NSDictionary *)rtnDoc:(NSDictionary *)document active:(BOOL)active error:(NSError **)error {
    __block NSUInteger added = 0, skipped = 0, archived = 0;
    BOOL success = [self wrTxn:^BOOL(NSError **failure) {
        if (![document isKindOfClass:NSDictionary.class] || !ts_txt(document[@"source"],255)
            || !ts_txt(document[@"text"],1024*1024) || ![document[@"tasks"] isKindOfClass:NSArray.class]
            || [document[@"tasks"] count]>1000) return [self dbErr:SQLITE_CONSTRAINT message:@"时间表格式无效" error:failure];
        NSArray *existing = [self qry:"SELECT content FROM routine_documents WHERE name=?" values:@[document[@"source"]] error:failure]; if (!existing) return NO;
        if (existing.count && ![existing.firstObject[@"content"] isEqual:document[@"text"]]) return [self dbErr:SQLITE_CONSTRAINT message:@"同名时间表已导入" error:failure];
        if (active && existing.count) { skipped = [document[@"tasks"] count]; return YES; }
        if (active) {
            NSString *prefix = document[@"replaces"];
            if (!ts_txt(prefix,1024)) return [self dbErr:SQLITE_CONSTRAINT message:@"原时间表来源无效" error:failure];
            NSArray *drafts = [self qry:"SELECT task_id FROM tasks WHERE deleted=0 AND routine_enabled=0 AND substr(routine_source,1,?)=?"
                values:@[@(prefix.length),prefix] error:failure]; if (!drafts) return NO;
            for (NSDictionary *draft in drafts) { if (![self delTsk:draft[@"task_id"] error:failure]) return NO; archived++; }
        }
        NSMutableArray *normalized = [NSMutableArray array];
        NSMutableSet *sources = [NSMutableSet set];
        for (id task in document[@"tasks"]) {
            if (![task isKindOfClass:NSDictionary.class] || ![task[@"list_id"] isEqual:TS_RTN_LST] || ![task[@"routine_enabled"] isEqual:@1]
                || !ts_txt(task[@"routine_source"],1024)) return [self dbErr:SQLITE_CONSTRAINT message:@"常律启用状态无效" error:failure];
            if ([sources containsObject:task[@"routine_source"]]) return [self dbErr:SQLITE_CONSTRAINT message:@"时间表含重复事项" error:failure];
            [sources addObject:task[@"routine_source"]];
            NSArray *rows = [self qry:"SELECT task_id FROM tasks WHERE routine_source=?" values:@[task[@"routine_source"]] error:failure]; if (!rows) return NO;
            if (rows.count) { skipped++; continue; }
            NSDictionary *checked = [self mrg:task into:[self newTsk:NSUUID.UUID.UUIDString] error:failure];
            if (!checked) return NO;
            [normalized addObject:checked];
        }
        if (![self chkRtn:normalized error:failure]) return NO;
        for (NSDictionary *task in normalized) {
            NSDictionary *row = [self enc:task error:failure];
            if (!row || ![self wrt:row table:@"tasks" key:@"task_id" insert:YES error:failure]) return NO;
            added++;
        }
        return [self qry:"INSERT INTO routine_documents(name,content,created_at) VALUES(?,?,?) ON CONFLICT(name) DO NOTHING"
            values:@[document[@"source"],document[@"text"],@(NSDate.date.timeIntervalSince1970)] error:failure]!=nil;
    } error:error];
    return success ? (active ? @{@"added":@(added),@"skipped":@(skipped),@"archived":@(archived)} : @{@"added":@(added),@"skipped":@(skipped)}) : nil;
}

// 通用Markdown整批验证并创建正式常律。
- (NSDictionary *)importRtns:(NSDictionary *)document error:(NSError **)error { return [self rtnDoc:document active:YES error:error]; }
// 已核验的常律使用同一导入实现与唯一数据库。
- (NSDictionary *)applyRtns:(NSDictionary *)document error:(NSError **)error { return [self rtnDoc:document active:YES error:error]; }

// 只在存在启用的一般任务时段时自动安排，重复读取不写入相同结果。
- (BOOL)arrangeAt:(NSTimeInterval)stamp zone:(NSString *)zone error:(NSError **)error {
    if (!isfinite(stamp) || ![NSTimeZone timeZoneWithName:zone]) return [self dbErr:SQLITE_CONSTRAINT message:@"日程日期或时区无效" error:error];
    return [self wrTxn:^BOOL(NSError **failure) {
        NSArray *windows = [self qry:"SELECT task_id FROM tasks WHERE deleted=0 AND status='needsAction' AND routine_kind='work' AND routine_enabled=1 LIMIT 1" values:@[] error:failure];
        if (!windows) return NO; if (!windows.count) return YES;
        NSDictionary *plan = [self dayAt:stamp zone:zone now:stamp error:failure]; if (!plan) return NO;
        if ([plan[@"conflicts"] count]) return YES;
        NSMutableSet *retained = [NSMutableSet set];
        for (NSDictionary *entry in plan[@"entries"]) [retained addObject:entry[@"id"]];
        NSArray *old = [self qry:"SELECT * FROM agenda_slots WHERE day_at=? AND start_at>?" values:@[plan[@"day_at"],@(stamp)] error:failure]; if (!old) return NO;
        for (NSDictionary *slot in old) {
            NSDictionary *identity = @{@"task_id":slot[@"task_id"],@"reminder_version":slot[@"generation"]};
            if (![retained containsObject:ta_key(identity,slot[@"cycle_at"])])
                if (![self qry:"DELETE FROM agenda_slots WHERE task_id=? AND generation=? AND cycle_at=?" values:@[slot[@"task_id"],slot[@"generation"],slot[@"cycle_at"]] error:failure]) return NO;
        }
        for (NSDictionary *slot in plan[@"allocations"]) {
            if (![self qry:"DELETE FROM agenda_slots WHERE task_id=? AND generation=? AND cycle_at!=? AND end_at<=?"
                values:@[slot[@"task_id"],slot[@"generation"],slot[@"cycle_at"],@(stamp)] error:failure]) return NO;
            if (![self qry:"INSERT INTO agenda_slots(task_id,generation,cycle_at,scheduled_at,day_at,start_at,end_at) VALUES(?,?,?,?,?,?,?) "
                "ON CONFLICT(task_id,generation,cycle_at) DO UPDATE SET start_at=excluded.start_at,end_at=excluded.end_at "
                "WHERE agenda_slots.start_at!=excluded.start_at OR agenda_slots.end_at!=excluded.end_at"
                values:@[slot[@"task_id"],slot[@"generation"],slot[@"cycle_at"],slot[@"scheduled_at"],slot[@"day_at"],slot[@"start_at"],slot[@"end_at"]] error:failure]) return NO;
        }
        return YES;
    } error:error];
}

// 创建普通清单。
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
        if ([listID.lowercaseString isEqual:TS_RTN_LST]) return [self dbErr:SQLITE_CONSTRAINT message:@"常律清单不可重命名" error:failure];
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
        if (!ts_uuid(listID) || [@[(NSString *)TS_DFLT_LST,(NSString *)TS_RTN_LST] containsObject:listID.lowercaseString])
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
        if (![self qry:"INSERT INTO reminder_occurrences(occurrence_id,task_id,scheduled_at,cycle_at,generation,kind,status,handled_at,action,created_at,updated_at) "
            "VALUES(?,?,?,?,?,?,'completed',?,'complete',?,?) ON CONFLICT(task_id,generation,kind,cycle_at) "
            "DO UPDATE SET status='completed',handled_at=excluded.handled_at,action='complete',next_fire_at=NULL,updated_at=excluded.updated_at"
            values:@[NSUUID.UUID.UUIDString.lowercaseString, taskID.lowercaseString, alert[@"scheduled_at"], alert[@"cycle_at"],
                task[@"reminder_version"], alert[@"kind"], now, now, now] error:failure]) return NO;
        return [self finCyc:alert task:task at:now error:failure];
    } error:error];
}

// 幂等创建单次提醒，重复请求返回同一UUID。
- (NSDictionary *)crtOcc:(NSString *)taskID at:(NSNumber *)stamp error:(NSError **)error {
    __block NSDictionary *result = nil;
    BOOL success = [self wrTxn:^BOOL(NSError **failure) {
        if (!ts_uuid(taskID) || !ts_num(stamp)) return [self dbErr:SQLITE_CONSTRAINT message:@"提醒任务或时间无效" error:failure];
        NSNumber *now = @(NSDate.date.timeIntervalSince1970);
        NSDictionary *task = [self rdTsk:taskID error:failure]; if (!task) return NO;
        if (![self qry:"INSERT INTO reminder_occurrences (occurrence_id,task_id,scheduled_at,created_at,updated_at,cycle_at,generation,next_fire_at) VALUES(?,?,?,?,?,?,?,?) "
            "ON CONFLICT(task_id,generation,kind,cycle_at) DO NOTHING" values:@[NSUUID.UUID.UUIDString.lowercaseString, taskID.lowercaseString, stamp, now, now, stamp, task[@"reminder_version"], stamp] error:failure]) return NO;
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
        for (NSString *key in fields) if (![@[@"status", @"triggered_at", @"handled_at", @"action", @"next_fire_at"] containsObject:key])
            return [self dbErr:SQLITE_MISUSE message:@"提醒字段不可修改或未知" error:failure];
        NSMutableDictionary *row = [[self qry:"SELECT * FROM reminder_occurrences WHERE occurrence_id=?"
            values:@[occID.lowercaseString] error:failure].firstObject mutableCopy];
        if (!row) return [self dbErr:SQLITE_NOTFOUND message:@"提醒不存在" error:failure];
        NSString *from=row[@"status"], *to=fields[@"status"] ?: from;
        NSDictionary *edges=@{@"pending":@[@"presented",@"completed",@"resolved"],@"presented":@[@"snoozed",@"completed",@"resolved"],
            @"snoozed":@[@"presented",@"resolved"],@"completed":@[@"resolved"],@"resolved":@[]};
        if (![from isEqual:to] && ![edges[from] containsObject:to]) return [self dbErr:SQLITE_CONSTRAINT message:@"提醒状态不可回退" error:failure];
        [row addEntriesFromDictionary:fields];
        if ([@[@"completed",@"resolved"] containsObject:to]) row[@"next_fire_at"]=NSNull.null;
        for (NSString *key in @[@"triggered_at", @"handled_at", @"next_fire_at"])
            if (row[key] != NSNull.null && !ts_num(row[key])) return [self dbErr:SQLITE_CONSTRAINT message:@"提醒时间无效" error:failure];
        if (![@[@"pending", @"presented", @"snoozed", @"completed", @"resolved"] containsObject:row[@"status"]]
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
