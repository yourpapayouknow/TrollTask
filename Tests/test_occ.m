#import "LBHead.h"

static NSUInteger oc_checks;
// 记录状态机断言。
static void oc_req(BOOL valid) { if (!valid) { NSLog(@"Occurrence断言失败：%lu",(unsigned long)oc_checks+1); abort(); } oc_checks++; }
// 在隔离库准备旧版本及事务失败探针。
static void oc_sql(NSString *path, NSString *sql) {
    sqlite3 *db=NULL;oc_req(sqlite3_open(path.fileSystemRepresentation,&db)==SQLITE_OK);
    char *issue=NULL;int rc=sqlite3_exec(db,sql.UTF8String,NULL,NULL,&issue);if (issue) NSLog(@"%s",issue);
    sqlite3_free(issue);oc_req(rc==SQLITE_OK);sqlite3_close(db);
}
// 读取迁移后的独立SQL计数。
static int oc_int(NSString *path,const char *sql) {
    sqlite3 *db=NULL;sqlite3_stmt *stmt=NULL;oc_req(sqlite3_open(path.fileSystemRepresentation,&db)==SQLITE_OK);
    oc_req(sqlite3_prepare_v2(db,sql,-1,&stmt,NULL)==SQLITE_OK && sqlite3_step(stmt)==SQLITE_ROW);
    int value=sqlite3_column_int(stmt,0);sqlite3_finalize(stmt);sqlite3_close(db);return value;
}
// 检查真实schema8的身份、附件、短期请求及失败回滚。
static void oc_mgr(NSString *root) {
    NSString *fixture=[NSString stringWithContentsOfFile:@"Tests/Fixtures/occurrence-v8.sql" encoding:NSUTF8StringEncoding error:nil];oc_req(fixture!=nil);
    for (NSNumber *fail in @[@NO,@YES]) {
        NSString *path=[root stringByAppendingPathComponent:fail.boolValue?@"migration-fail.sqlite3":@"migration.sqlite3"];
        oc_sql(path,fixture);
        if (fail.boolValue) oc_sql(path,@"CREATE TRIGGER migration_failure BEFORE UPDATE ON store_meta WHEN NEW.schema_version=9 BEGIN SELECT RAISE(ABORT,'test');END;");
        TaskStore *store=[[TaskStore alloc] initAt:path error:nil];oc_req((store==nil)==fail.boolValue);
        if (fail.boolValue) {
            oc_req(oc_int(path,"SELECT schema_version FROM store_meta")==8);
            oc_req(oc_int(path,"SELECT count(*) FROM reminder_checkins")==1 && oc_int(path,"SELECT count(*) FROM capture_request")==1);
            oc_req(oc_int(path,"SELECT count(*) FROM sqlite_master WHERE name='occurrences_v9'")==0);
            oc_sql(path,@"DROP TRIGGER migration_failure;");store=[[TaskStore alloc] initAt:path error:nil];
        }
        oc_req([store schver:nil]==9);
        NSArray *rows=[store snapshot:nil][@"history"];oc_req(rows.count==7);
        for (NSString *state in @[@"pending",@"presented",@"snoozed",@"resolved"]) {
            NSArray *items=[rows filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"status == %@",state]];
            oc_req(items.count==([state isEqual:@"resolved"]?3:([state isEqual:@"snoozed"]?2:1)));
            for (NSDictionary *row in items) {
                oc_req([fixture containsString:row[@"occurrence_id"]]);
                if ([state isEqual:@"resolved"]) oc_req(row[@"next_fire_at"]==NSNull.null);
                if ([row[@"action"] isEqual:@"complete"]) oc_req([[[store lsChk:row[@"occurrence_id"] images:YES error:nil] firstObject][@"image"] isEqual:[@"original" dataUsingEncoding:NSUTF8StringEncoding]]);
            }
        }
        oc_req(oc_int(path,"SELECT count(*) FROM capture_request")==1 && oc_int(path,"SELECT count(*) FROM pragma_foreign_key_check")==0);
    }
}
// 创建并认领独立的到期提醒。
static NSDictionary *oc_clm(TaskStore *store, BOOL repeats) {
    NSMutableDictionary *fields=[@{@"title":@"状态验收",@"due_at":@(NSDate.date.timeIntervalSince1970-1),@"timezone_id":@"UTC"} mutableCopy];
    if (repeats) { fields[@"recurrence_type"]=@"daily"; fields[@"recurrence"]=@[@"RRULE:FREQ=DAILY"]; }
    NSDictionary *task=[store crtTsk:fields error:nil];oc_req(task!=nil);
    NSDictionary *plan=[store planAt:NSDate.date.timeIntervalSince1970 error:nil];
    for (NSDictionary *alert in plan[@"alerts"]) if ([alert[@"task_id"] isEqual:task[@"task_id"]])
        return [store claim:alert revision:[plan[@"revision"] longLongValue] at:NSDate.date.timeIntervalSince1970 error:nil];
    abort();
}
// 验证五态、一次延期、终态不可复活及下一轮持久化。
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        NSDictionary *file=@{@"method":@"file",@"image":[@"original" dataUsingEncoding:NSUTF8StringEncoding],@"name":@"proof.txt",@"content_type":@"public.plain-text"};
        // 独立进程复用生产事务竞争同一次提交。
        if (argc==4 && strcmp(argv[1],"--complete")==0) {
            TaskStore *store=[[TaskStore alloc] initAt:@(argv[2]) error:nil];return [store chkOcc:@(argv[3]) attachments:@[file] error:nil]?0:1;
        }
        char folder[]="/tmp/trolltask-occ.XXXXXX";assert(mkdtemp(folder));
        oc_mgr(@(folder));
        TaskStore *store=[[TaskStore alloc] initAt:[@(folder) stringByAppendingPathComponent:@"tasks.sqlite3"] error:nil];oc_req(store!=nil);
        NSDictionary *alert=oc_clm(store,YES);NSString *id=alert[@"occurrence_id"],*task=alert[@"task_id"];
        NSDictionary *row=[store lsOcc:task error:nil].firstObject;
        oc_req([row[@"status"] isEqual:@"presented"] && [row[@"next_fire_at"] isEqual:alert[@"remind_at"]]);
        oc_req(![store actOcc:id action:@"snooze" until:@(NSDate.date.timeIntervalSince1970+900) error:nil]);
        NSDictionary *hold=[store hldOcc:id mode:@"snooze" error:nil];oc_req(hold!=nil);
        row=[store lsOcc:task error:nil].firstObject;
        oc_req([row[@"status"] isEqual:@"snoozed"] && [row[@"next_fire_at"] isEqual:hold[@"hold_until"]] && [row[@"defer_count"] intValue]==1);
        long long revision=[store revision:nil];
        for (NSUInteger i=0;i<20;i++) oc_req(![store hldOcc:id mode:@"snooze" error:nil]);
        oc_req([store revision:nil]==revision);
        oc_req([store rsmOcc:id error:nil] && ![store hldOcc:id mode:@"snooze" error:nil]);
        oc_req(![store actOcc:id action:@"snooze" until:@(NSDate.date.timeIntervalSince1970+300) error:nil]);
        oc_sql(store.path,@"CREATE TABLE audit(state TEXT);CREATE TRIGGER state_audit AFTER UPDATE OF status ON reminder_occurrences BEGIN INSERT INTO audit VALUES(NEW.status);END;");
        oc_req([store chkOcc:id attachments:@[file] error:nil]);
        oc_req(oc_int(store.path,"SELECT count(*) FROM audit WHERE state='completed'")==1 && oc_int(store.path,"SELECT count(*) FROM audit WHERE state='resolved'")==1);
        NSArray *history=[store lsOcc:task error:nil];oc_req(history.count==2);
        row=history.firstObject;NSDictionary *next=history.lastObject;
        oc_req([row[@"status"] isEqual:@"resolved"] && [row[@"action"] isEqual:@"complete"] && row[@"next_fire_at"]==NSNull.null);
        oc_req([next[@"status"] isEqual:@"pending"] && ![next[@"occurrence_id"] isEqual:id] && [next[@"cycle_at"] doubleValue]>[row[@"cycle_at"] doubleValue]);
        oc_req([next[@"next_fire_at"] isEqual:next[@"scheduled_at"]] && [[store rdTsk:task error:nil][@"status"] isEqual:@"needsAction"]);
        revision=[store revision:nil];
        for (NSUInteger i=0;i<20;i++) {oc_req(![store chkOcc:id attachments:@[file] error:nil]);oc_req(![store actOcc:id action:@"complete" until:nil error:nil]);}
        oc_req([store revision:nil]==revision && [store lsOcc:task error:nil].count==2 && [store lsChk:id images:YES error:nil].count==1);
        oc_req(![store updOcc:id fields:@{@"status":@"presented",@"handled_at":NSNull.null,@"triggered_at":@1} error:nil]);
        NSDictionary *single=oc_clm(store,NO);oc_req([store chkOcc:single[@"occurrence_id"] attachments:@[file] error:nil]);
        oc_req([[store rdTsk:single[@"task_id"] error:nil][@"status"] isEqual:@"completed"] && [[store lsOcc:single[@"task_id"] error:nil].firstObject[@"status"] isEqual:@"resolved"]);
        NSDictionary *race=oc_clm(store,NO);NSMutableArray *jobs=[NSMutableArray array];
        for (NSUInteger i=0;i<2;i++) {NSTask *job=[NSTask new];job.executableURL=[NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];job.arguments=@[@"--complete",store.path,race[@"occurrence_id"]];oc_req([job launchAndReturnError:nil]);[jobs addObject:job];}
        NSUInteger won=0;for (NSTask *job in jobs) {[job waitUntilExit];if (job.terminationStatus==0) won++;}
        oc_req(won==1 && [store lsChk:race[@"occurrence_id"] images:YES error:nil].count==1);
        // 同一轮计划与截止均到期，只完成一轮；有限系列最后一轮停止。
        for (NSNumber *count in @[@1,@2]) {
            NSTimeInterval now=NSDate.date.timeIntervalSince1970;
            NSDictionary *series=[store crtTsk:@{@"title":@"双提醒系列",@"due_at":@(now-2),@"deadline_at":@(now-1),@"timezone_id":@"UTC",@"recurrence_type":@"custom",@"recurrence":@[[NSString stringWithFormat:@"RRULE:FREQ=DAILY;COUNT=%@",count]]} error:nil];
            oc_req(series!=nil);NSMutableArray *ids=[NSMutableArray array];
            for (NSUInteger i=0;i<2;i++) {
                NSDictionary *plan=[store planAt:now error:nil];
                for (NSDictionary *candidate in plan[@"alerts"]) if ([candidate[@"task_id"] isEqual:series[@"task_id"]] && [candidate[@"remind_at"] doubleValue]<=now) {
                    NSDictionary *claimed=[store claim:candidate revision:[plan[@"revision"] longLongValue] at:now error:nil];
                    if (claimed && ![ids containsObject:claimed[@"occurrence_id"]]) {[ids addObject:claimed[@"occurrence_id"]];break;}
                }
            }
            oc_req(ids.count==2 && [store chkOcc:ids[0] attachments:@[file] error:nil]);
            NSArray *rows=[store lsOcc:series[@"task_id"] error:nil];
            oc_req([[rows filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"status == 'resolved'"]] count]==2);
            oc_req([[rows filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"status == 'pending'"]] count]==(count.intValue==1?0:2));
            oc_req([[store rdTsk:series[@"task_id"] error:nil][@"status"] isEqual:count.intValue==1?@"completed":@"needsAction"]);
            oc_req(![store chkOcc:ids[1] attachments:@[file] error:nil] && [store lsChk:ids[1] images:YES error:nil].count==0);
        }
        printf("Occurrence: %lu checks passed; five states, once-only defer/completion, persisted next cycle\n",(unsigned long)oc_checks);
        oc_req([NSFileManager.defaultManager removeItemAtPath:@(folder) error:nil]);return 0;
    }
}
