#import "LBHead.h"

// 在隔离数据库模拟九版迁移失败并核验事务回滚。
static void sig_mgr(NSString *path) {
    sqlite3 *db=NULL;assert(sqlite3_open(path.fileSystemRepresentation,&db)==SQLITE_OK);
    NSString *downgrade=[NSString stringWithContentsOfFile:@"Tests/Fixtures/agenda-v10.sql" encoding:NSUTF8StringEncoding error:nil];
    assert(sqlite3_exec(db,downgrade.UTF8String,NULL,NULL,NULL)==SQLITE_OK);
    const char *fixture="ALTER TABLE reminder_occurrences DROP COLUMN signal_at;ALTER TABLE reminder_occurrences DROP COLUMN signal_uptime;"
        "ALTER TABLE reminder_occurrences DROP COLUMN signal_ack;UPDATE store_meta SET schema_version=9;"
        "CREATE TRIGGER signal_migration_failure BEFORE UPDATE ON store_meta WHEN NEW.schema_version=10 BEGIN SELECT RAISE(ABORT,'test');END;";
    assert(sqlite3_exec(db,fixture,NULL,NULL,NULL)==SQLITE_OK);sqlite3_close(db);
    assert(![[TaskStore alloc] initAt:path error:nil]);
    assert(sqlite3_open(path.fileSystemRepresentation,&db)==SQLITE_OK);sqlite3_stmt *query=NULL;
    assert(sqlite3_prepare_v2(db,"SELECT schema_version,(SELECT count(*) FROM pragma_table_info('reminder_occurrences') WHERE name LIKE 'signal_%') FROM store_meta",-1,&query,NULL)==SQLITE_OK);
    assert(sqlite3_step(query)==SQLITE_ROW && sqlite3_column_int(query,0)==9 && sqlite3_column_int(query,1)==0);sqlite3_finalize(query);
    assert(sqlite3_exec(db,"DROP TRIGGER signal_migration_failure",NULL,NULL,NULL)==SQLITE_OK);sqlite3_close(db);
    TaskStore *store=[[TaskStore alloc] initAt:path error:nil];assert(store && [store schver:nil]==TS_SCH_VER);
    assert([store snapshot:nil][@"history"] && [[store snapshot:nil][@"history"] count]==1);
}

// 直接验证声振记录与提醒状态机的同库边界。
int main(void) { @autoreleasepool {
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    TaskStore *store=[[TaskStore alloc] initAt:path error:nil]; assert(store);
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSDictionary *task=[store crtTsk:@{@"title":@"声振验收",@"due_at":@(now-10),@"urgency":@3} error:nil];
    NSDictionary *plan=[store planAt:now error:nil];
    NSDictionary *claimed=[store claim:[plan[@"alerts"] firstObject] revision:[plan[@"revision"] longLongValue] at:now error:nil];
    assert(claimed); NSString *oid=claimed[@"occurrence_id"];
    NSDictionary *occ=[store lsOcc:task[@"task_id"] error:nil].firstObject; NSNumber *trigger=occ[@"triggered_at"];
    assert(occ[@"signal_at"]==NSNull.null && ![occ[@"signal_ack"] boolValue]);
    NSDictionary *start=[store sigOcc:oid trigger:trigger ack:NO error:nil]; assert(start && ![start[@"signal_ack"] boolValue]);
    assert([start[@"signal_new"] boolValue]);
    NSMutableDictionary *repeated=[start mutableCopy];repeated[@"signal_new"]=@NO;
    long long revision=[store revision:nil];
    for (int n=0;n<100;n++) assert([[store sigOcc:oid trigger:trigger ack:NO error:nil] isEqual:repeated]);
    assert([store revision:nil]==revision);
    NSDictionary *quiet=[store sigOcc:oid trigger:trigger ack:YES error:nil]; assert([quiet[@"signal_ack"] boolValue]);
    assert([[quiet objectForKey:@"signal_at"] isEqual:start[@"signal_at"]]);
    assert([[[store lsOcc:task[@"task_id"] error:nil].firstObject objectForKey:@"status"] isEqual:@"presented"]);
    assert([[[store rdTsk:task[@"task_id"] error:nil] objectForKey:@"status"] isEqual:@"needsAction"]);
    store=nil; store=[[TaskStore alloc] initAt:path error:nil];
    assert([[store sigOcc:oid trigger:trigger ack:NO error:nil][@"signal_ack"] boolValue]);
    assert([store hldOcc:oid mode:@"snooze" error:nil]);
    assert(![store sigOcc:oid trigger:trigger ack:NO error:nil]);
    now=NSDate.date.timeIntervalSince1970+301; plan=[store planAt:now error:nil];
    assert([store claim:[plan[@"alerts"] firstObject] revision:[plan[@"revision"] longLongValue] at:now error:nil]);
    occ=[store lsOcc:task[@"task_id"] error:nil].firstObject;
    assert(occ[@"signal_at"]==NSNull.null && ![occ[@"signal_ack"] boolValue]);
    assert(![store sigOcc:oid trigger:trigger ack:YES error:nil]);
    NSDictionary *rearmed=[store sigOcc:oid trigger:occ[@"triggered_at"] ack:NO error:nil];
    assert(rearmed && ![rearmed[@"signal_ack"] boolValue]);
    assert(![store hldOcc:oid mode:@"snooze" error:nil]);
    assert([store hldOcc:oid mode:@"screenshot" error:nil]); assert([store rsmOcc:oid error:nil]);
    occ=[store lsOcc:task[@"task_id"] error:nil].firstObject;
    assert([[store sigOcc:oid trigger:occ[@"triggered_at"] ack:NO error:nil][@"signal_ack"] boolValue]);
    assert([store cmplTsk:task[@"task_id"] error:nil]);
    assert(![store sigOcc:oid trigger:occ[@"triggered_at"] ack:NO error:nil]);
    assert([[[store lsOcc:task[@"task_id"] error:nil].firstObject objectForKey:@"status"] isEqual:@"resolved"]);
    assert(![store sigOcc:@"invalid" trigger:@1 ack:NO error:nil]);
    store=nil;sig_mgr(path);[NSFileManager.defaultManager removeItemAtPath:path error:nil];
    puts("SignalStore: duplicate/restart/snooze/resume/resolved checks passed"); return 0;
} }
