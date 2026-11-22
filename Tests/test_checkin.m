#import "LBHead.h"

// 记录打卡核心断言。
static NSUInteger ck_checks;
static void ck_at(BOOL value,int line) { if (!value) NSLog(@"Checkin断言失败：%lu，第%d行",(unsigned long)(ck_checks+1),line); assert(value); ck_checks++; }
#define ck_req(...) ck_at((__VA_ARGS__),__LINE__)

// 在隔离库模拟迁移和写入故障。
static void ck_sql(NSString *path, NSString *sql) {
    sqlite3 *db = NULL; assert(sqlite3_open(path.fileSystemRepresentation, &db) == SQLITE_OK);
    assert(sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL) == SQLITE_OK); sqlite3_close(db);
}

// 读取迁移失败后的原始数据库状态，不触发自动迁移。
static int ck_int(NSString *path, const char *sql) {
    sqlite3 *db=NULL;sqlite3_stmt *stmt=NULL;assert(sqlite3_open(path.fileSystemRepresentation,&db)==SQLITE_OK);
    assert(sqlite3_prepare_v2(db,sql,-1,&stmt,NULL)==SQLITE_OK && sqlite3_step(stmt)==SQLITE_ROW);
    int result=sqlite3_column_int(stmt,0);sqlite3_finalize(stmt);sqlite3_close(db);return result;
}

// 创建并认领一个实际到期轮次。
static NSDictionary *ck_clm(TaskStore *store, BOOL repeat) {
    NSMutableDictionary *fields = [@{@"title":@"打卡测试",@"notes":@"完整说明",@"due_at":@(NSDate.date.timeIntervalSince1970-1),@"schedule_kind":@"timed",@"timezone_id":@"UTC"} mutableCopy];
    if (repeat) { fields[@"recurrence_type"]=@"daily"; fields[@"recurrence"]=@[@"RRULE:FREQ=DAILY"]; }
    NSDictionary *task=[store crtTsk:fields error:nil]; ck_req(task!=nil);
    NSDictionary *plan=[store planAt:NSDate.date.timeIntervalSince1970 error:nil];
    for (NSDictionary *alert in plan[@"alerts"]) if ([alert[@"task_id"] isEqual:task[@"task_id"]])
        return [store claim:alert revision:[plan[@"revision"] longLongValue] at:NSDate.date.timeIntervalSince1970 error:nil];
    assert(NO); return nil;
}

// 恢复真实旧版Occurrence结构，供既有迁移用例降级隔离库。
static void ck_old(NSString *path) {
    ck_sql(path,[NSString stringWithContentsOfFile:@"Tests/Fixtures/archive-v12.sql" encoding:NSUTF8StringEncoding error:nil]);
    ck_sql(path,[NSString stringWithContentsOfFile:@"Tests/Fixtures/agenda-v10.sql" encoding:NSUTF8StringEncoding error:nil]);
    NSString *fixture=[NSString stringWithContentsOfFile:@"Tests/Fixtures/occurrence-v8.sql" encoding:NSUTF8StringEncoding error:nil];
    NSString *schema=nil;
    for (NSString *line in [fixture componentsSeparatedByString:@"\n"]) if ([line hasPrefix:@"CREATE TABLE reminder_occurrences "]) schema=line;
    ck_req(schema!=nil);
    ck_sql(path,[NSString stringWithFormat:@"CREATE TEMP TABLE old_rows AS SELECT * FROM reminder_occurrences;DROP TABLE reminder_occurrences;%@ INSERT INTO reminder_occurrences SELECT occurrence_id,task_id,scheduled_at,triggered_at,handled_at,CASE status WHEN 'presented' THEN 'triggered' WHEN 'snoozed' THEN 'handled' WHEN 'resolved' THEN 'handled' WHEN 'completed' THEN 'handled' ELSE 'pending' END,action,CASE WHEN status='snoozed' THEN next_fire_at END,created_at,updated_at,generation,kind,cycle_at,defer_count,hold_reason,hold_until FROM old_rows;DROP TABLE old_rows;",schema]);
}

// 检查本次收起次数、图片原子提交与恢复。
static void ck_cap(NSString *root) {
    NSUInteger before=ck_checks;
    NSString *path=[root stringByAppendingPathComponent:@"capture.sqlite3"];
    TaskStore *store=[[TaskStore alloc] initAt:path error:nil],*reader=[[TaskStore alloc] initAt:path error:nil];
    NSDictionary *alert=ck_clm(store,NO);NSString *occ=alert[@"occurrence_id"];
    NSData *image=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=" options:0];
    NSDictionary *proof=@{@"image":image,@"method":@"image"};
    ck_req(![store reqCap:occ source:@"invalid" limit:1 error:nil] && ![store reqCap:occ source:@"image" limit:7 error:nil]);
    NSDictionary *request=[store reqCap:occ source:@"image" limit:6 error:nil];NSString *token=request[@"token"];
    ck_req(token && [[reader rdCap:nil error:nil][@"token"] isEqual:token]);
    ck_req(![store finCap:token attachments:@[proof] issue:nil error:nil]);
    ck_req([reader ackCap:token error:nil] && ![store ackCap:token error:nil]);
    ck_req(![reader finCap:token attachments:@[proof,proof,proof,proof,proof,proof,proof] issue:nil error:nil]);
    ck_req(![reader finCap:token attachments:@[@{@"method":@"image",@"image":[NSData data]}] issue:nil error:nil]);
    ck_req([[store rdCap:token error:nil][@"state"] intValue]==1);
    ck_req([reader finCap:token attachments:@[proof,proof,proof,proof,proof,proof] issue:nil error:nil]);
    NSDictionary *result=[store rdCap:token error:nil];
    ck_req([result[@"attachments"] count]==6 && [result[@"attachments"][5][@"image"] isEqual:image]);
    ck_req([[store rdTsk:alert[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"] && [store lsChk:occ images:NO error:nil].count==0);
    ck_req(![reader finCap:token attachments:@[proof] issue:nil error:nil]);
    ck_req([store delCap:token error:nil] && [reader rdCap:token error:nil].count==0);
    request=[store reqCap:occ source:@"file" limit:1 error:nil];token=request[@"token"];
    ck_req([reader ackCap:token error:nil] && [reader finCap:token attachments:@[] issue:nil error:nil]);
    ck_req([[[store rdCap:token error:nil] objectForKey:@"attachments"] count]==0 && [[store rdTsk:alert[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"]);
    NSString *old=token;request=[store reqCap:occ source:@"camera" limit:1 error:nil];token=request[@"token"];
    ck_req(![old isEqual:token] && ![reader finCap:old attachments:@[proof] issue:nil error:nil]);
    ck_sql(path,@"UPDATE capture_request SET created_at=0;");ck_req(![reader ackCap:token error:nil]);
    request=[store reqCap:occ source:@"screenshot" limit:1 error:nil];token=request[@"token"];
    // 独立进程完成采集后，父进程仍须显式确认最终打卡。
    NSTask *job=[NSTask new];job.executableURL=[NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];job.arguments=@[@"--capture",path,token];
    ck_req([job launchAndReturnError:nil]);[job waitUntilExit];ck_req(job.terminationStatus==0);
    NSArray *items=[store rdCap:token error:nil][@"attachments"];ck_req(items.count==1);
    ck_req([store chkOcc:occ attachments:items error:nil] && [reader lsChk:occ images:YES error:nil].count==1);
    ck_req([store delCap:nil error:nil] && [reader rdCap:nil error:nil].count==0);
    printf("Capture: %lu checks passed; one database, bounded batches, cancellation, stale tokens and real process handoff\n",(unsigned long)(ck_checks-before));
}

// 核对普通文件的原始内容、混合批次和旧图片迁移。
static void ck_files(NSString *root) {
    NSUInteger before=ck_checks;NSString *path=[root stringByAppendingPathComponent:@"files.sqlite3"];
    TaskStore *store=[[TaskStore alloc] initAt:path error:nil],*reader=[[TaskStore alloc] initAt:path error:nil];
    NSData *bytes=[NSData dataWithBytes:(unsigned char[]){0,255,1,0,42} length:5];
    NSData *png=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=" options:0];
    NSDictionary *file=@{@"method":@"file",@"image":bytes,@"name":@"原始文件.bin",@"content_type":@"public.data"};
    NSDictionary *empty=@{@"method":@"file",@"image":[NSData data],@"name":@"空文件.txt",@"content_type":@"public.plain-text"};
    NSDictionary *image=@{@"method":@"image",@"image":png};
    ck_req([TaskStore vldPrfs:@[file,empty,image] error:nil]);
    for (NSDictionary *bad in @[@{@"method":@"file",@"image":bytes},@{@"method":@"file",@"image":bytes,@"name":@"",@"content_type":@"public.data"},@{@"method":@"file",@"image":bytes,@"name":@"a",@"content_type":NSNull.null},@{@"method":@"file",@"image":[NSMutableData dataWithLength:20*1024*1024+1],@"name":@"large",@"content_type":@"public.data"}]) ck_req(![TaskStore vldPrfs:@[bad] error:nil]);
    NSDictionary *alert=ck_clm(store,NO);NSString *occ=alert[@"occurrence_id"];
    NSString *token=[store reqCap:occ source:@"file" limit:6 error:nil][@"token"];
    NSArray *batch=@[file,image,empty,file,image,file];
    ck_req([reader ackCap:token error:nil] && [reader finCap:token attachments:batch issue:nil error:nil]);
    NSArray *result=[store rdCap:token error:nil][@"attachments"];
    ck_req([result isEqual:batch] && [[store rdTsk:alert[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"]);
    ck_req(![store chkOcc:occ attachments:[batch arrayByAddingObject:file] error:nil]);
    ck_sql(path,@"CREATE TRIGGER file_failure BEFORE INSERT ON reminder_checkins WHEN NEW.position=2 BEGIN SELECT RAISE(ABORT,'test');END;");
    ck_req(![store chkOcc:occ attachments:batch error:nil] && [reader lsChk:occ images:YES error:nil].count==0 && [[reader rdTsk:alert[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"]);
    ck_sql(path,@"DROP TRIGGER file_failure;");ck_req([store chkOcc:occ attachments:result error:nil]);
    NSArray *saved=[reader lsChk:occ images:YES error:nil],*meta=[reader lsChk:occ images:NO error:nil];
    ck_req(saved.count==6 && [saved[0][@"image"] isEqual:bytes] && [saved[0][@"name"] isEqual:file[@"name"]] && [saved[2][@"image"] length]==0 && [saved[1][@"image"] isEqual:png]);
    ck_req([meta[0][@"method"] isEqual:@"file"] && [meta[0][@"content_type"] isEqual:@"public.data"] && [meta[0][@"image_bytes"] intValue]==5 && !meta[0][@"image"]);
    ck_req([[reader rdPrf:occ position:2 error:nil][@"image"] length]==0 && [[reader rdPrf:occ position:1 error:nil][@"image"] isEqual:png]);
    ck_req([reader rdPrf:occ position:6 error:nil]==nil && [reader rdPrf:@"invalid" position:0 error:nil]==nil);
    for (NSNumber *fail in @[@NO,@YES]) {
        NSString *legacy=[root stringByAppendingPathComponent:fail.boolValue?@"v8-fail.sqlite3":@"v7-files.sqlite3"];__block NSString *oldID;
        @autoreleasepool {TaskStore *old=[[TaskStore alloc] initAt:legacy error:nil];NSDictionary *a=ck_clm(old,NO);oldID=a[@"occurrence_id"];ck_req([old chkOcc:oldID attachments:@[image,image] error:nil]);}
        ck_old(legacy);ck_sql(legacy,@"CREATE TABLE checkins_v7(occurrence_id TEXT NOT NULL REFERENCES reminder_occurrences(occurrence_id) ON DELETE CASCADE,position INTEGER NOT NULL CHECK(position BETWEEN 0 AND 5),method TEXT NOT NULL CHECK(method IN ('camera','screenshot','image')),image BLOB NOT NULL CHECK(length(image)>0),created_at REAL NOT NULL,PRIMARY KEY(occurrence_id,position));INSERT INTO checkins_v7 SELECT occurrence_id,position,method,image,created_at FROM reminder_checkins;DROP TABLE reminder_checkins;ALTER TABLE checkins_v7 RENAME TO reminder_checkins;UPDATE store_meta SET schema_version=7;");
        if (fail.boolValue) ck_sql(legacy,@"CREATE TRIGGER v8_failure BEFORE UPDATE ON store_meta WHEN NEW.schema_version=8 BEGIN SELECT RAISE(ABORT,'test');END;");
        TaskStore *migrated=[[TaskStore alloc] initAt:legacy error:nil];ck_req((migrated!=nil)!=fail.boolValue);
        if (fail.boolValue) {
            ck_req(ck_int(legacy,"SELECT schema_version FROM store_meta")==7 && ck_int(legacy,"SELECT count(*) FROM pragma_table_info('reminder_checkins') WHERE name='content_type'")==0 && ck_int(legacy,"SELECT count(*) FROM reminder_checkins")==2 && ck_int(legacy,"SELECT count(*) FROM sqlite_master WHERE name='reminder_checkins_v8'")==0);
            ck_sql(legacy,@"DROP TRIGGER v8_failure;");migrated=[[TaskStore alloc] initAt:legacy error:nil];
        }
        NSArray *old=[migrated lsChk:oldID images:YES error:nil];ck_req([migrated schver:nil]==TS_SCH_VER && old.count==2 && [old[1][@"image"] isEqual:png] && ck_int(legacy,"SELECT count(*) FROM pragma_foreign_key_check")==0);
    }
    printf("Files: %lu checks passed; raw bytes, empty files, mixed batches, metadata, same DB handoff and migration rollback\n",(unsigned long)(ck_checks-before));
}

// 检查本次收起次数、图片原子提交与恢复。
static void ck_run(NSString *root) {
    NSString *path=[root stringByAppendingPathComponent:@"checkin.sqlite3"];
    TaskStore *store=[[TaskStore alloc] initAt:path error:nil]; ck_req(store!=nil);
    NSData *image=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=" options:0];
    NSDictionary *alert=ck_clm(store,NO); NSString *id=alert[@"occurrence_id"];
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    NSDictionary *hold=[store hldOcc:id mode:@"snooze" error:nil];
    ck_req(hold && [hold[@"defer_count"] intValue]==1);
    ck_req(fabs([hold[@"hold_until"] doubleValue]-now-300)<2);
    NSError *error=nil; long long revision=[store revision:nil];
    ck_req(![store hldOcc:id mode:@"snooze" error:&error] && error.code==SQLITE_CONSTRAINT);
    ck_req([store revision:nil]==revision);
    TaskStore *reopened=[[TaskStore alloc] initAt:path error:nil];
    NSDictionary *row=[reopened lsOcc:alert[@"task_id"] error:nil].firstObject;
    ck_req([row[@"defer_count"] intValue]==1 && [row[@"hold_until"] isEqual:hold[@"hold_until"]]);
    NSDictionary *future=[store planAt:[hold[@"hold_until"] doubleValue]+0.01 error:nil];
    NSDictionary *candidate=nil;
    for (NSDictionary *item in future[@"alerts"]) if ([item[@"occurrence_id"] isEqual:id]) candidate=item;
    ck_req(candidate && [candidate[@"scheduled_at"] isEqual:alert[@"scheduled_at"]] && [candidate[@"cycle_at"] isEqual:alert[@"cycle_at"]]);
    ck_req([store claim:candidate revision:[future[@"revision"] longLongValue] at:[hold[@"hold_until"] doubleValue]+0.01 error:nil]!=nil);
    ck_req(![store hldOcc:id mode:@"snooze" error:nil]);
    ck_req([store chkOcc:id attachments:@[@{@"method":@"image",@"image":image}] error:nil]);
    ck_req([[store rdChk:id image:YES error:nil][@"image"] isEqual:image]);
    ck_req([[reopened rdChk:id image:NO error:nil][@"method"] isEqual:@"image"]);
    ck_req([[store rdTsk:alert[@"task_id"] error:nil][@"status"] isEqual:@"completed"]);
    ck_req(![store chkOcc:id attachments:@[@{@"method":@"image",@"image":image}] error:nil]);

    NSDictionary *screen=ck_clm(store,YES); NSString *sid=screen[@"occurrence_id"];
    NSDictionary *shot=[store hldOcc:sid mode:@"screenshot" error:nil];
    ck_req(shot && [shot[@"defer_count"] intValue]==0 && fabs([shot[@"hold_until"] doubleValue]-NSDate.date.timeIntervalSince1970-120)<2);
    NSDictionary *again=[store planAt:[shot[@"hold_until"] doubleValue]+0.01 error:nil];
    for (NSDictionary *item in again[@"alerts"]) if ([item[@"occurrence_id"] isEqual:sid]) candidate=item;
    ck_req([store claim:candidate revision:[again[@"revision"] longLongValue] at:[shot[@"hold_until"] doubleValue]+0.01 error:nil]!=nil);
    ck_req([store hldOcc:sid mode:@"screenshot" error:nil]!=nil);
    ck_req([store rsmOcc:sid error:nil]);
    ck_req([store hldOcc:sid mode:@"screenshot" error:nil]!=nil);
    ck_req([store rsmOcc:sid error:nil] && [store chkOcc:sid attachments:@[@{@"method":@"screenshot",@"image":image}] error:nil]);
    ck_req([[store rdTsk:screen[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"]);
    ck_req([[store rdTsk:screen[@"task_id"] error:nil][@"due_at"] isEqual:screen[@"cycle_at"]]);

    NSDictionary *bad=ck_clm(store,NO); NSString *bid=bad[@"occurrence_id"];
    revision=[store revision:nil];
    for (NSData *bytes in @[[NSData data], [@"not an image" dataUsingEncoding:NSUTF8StringEncoding]])
        ck_req(![store chkOcc:bid attachments:@[@{@"method":@"camera",@"image":bytes}] error:nil]);
    ck_req(![store chkOcc:bid attachments:@[@{@"method":@"unknown",@"image":image}] error:nil]);
    ck_req([store revision:nil]==revision && [[store lsOcc:bad[@"task_id"] error:nil].firstObject[@"status"] isEqual:@"presented"]);
    ck_sql(path,@"CREATE TRIGGER proof_failure BEFORE INSERT ON reminder_checkins BEGIN SELECT RAISE(ABORT,'test'); END;");
    ck_req(![store chkOcc:bid attachments:@[@{@"method":@"camera",@"image":image}] error:nil]);
    ck_req([[store rdTsk:bad[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"] && [store revision:nil]==revision);
    ck_req([[store lsOcc:bad[@"task_id"] error:nil].firstObject[@"status"] isEqual:@"presented"] && ![store rdChk:bid image:NO error:nil]);
    ck_sql(path,@"DROP TRIGGER proof_failure;");
    ck_req([store chkOcc:bid attachments:@[@{@"method":@"camera",@"image":image}] error:nil]);
    NSDictionary *stale=ck_clm(store,NO);
    ck_req([store updTsk:stale[@"task_id"] fields:@{@"due_at":@(NSDate.date.timeIntervalSince1970+600)} error:nil]);
    ck_req(![store chkOcc:stale[@"occurrence_id"] attachments:@[@{@"method":@"image",@"image":image}] error:nil]);
    ck_req(![store hldOcc:stale[@"occurrence_id"] mode:@"screenshot" error:nil]);
    ck_req(![store hldOcc:@"invalid" mode:@"snooze" error:nil]);

    // 真实并发进程只允许一次五分钟延期。
    NSDictionary *race=ck_clm(store,NO); NSMutableArray *jobs=[NSMutableArray array];
    for (NSUInteger i=0;i<2;i++) { NSTask *job=[NSTask new]; job.executableURL=[NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];
        job.arguments=@[@"--hold",path,race[@"occurrence_id"]]; ck_req([job launchAndReturnError:nil]); [jobs addObject:job]; }
    NSUInteger won=0; for (NSTask *job in jobs) { [job waitUntilExit]; if (job.terminationStatus==0) won++; }
    ck_req(won==1 && [[[store lsOcc:race[@"task_id"] error:nil].firstObject objectForKey:@"defer_count"] intValue]==1);

    // 从第四版完整迁移，失败时不留下字段或证据表。
    for (NSNumber *fail in @[@NO,@YES]) {
        NSString *legacy=[root stringByAppendingPathComponent:fail.boolValue?@"failed.sqlite3":@"legacy.sqlite3"];
        @autoreleasepool { ck_req([[TaskStore alloc] initAt:legacy error:nil]!=nil); }
        ck_old(legacy);ck_sql(legacy,@"DROP TABLE capture_request; DROP TABLE reminder_checkins; ALTER TABLE reminder_occurrences DROP COLUMN defer_count; ALTER TABLE reminder_occurrences DROP COLUMN hold_reason; ALTER TABLE reminder_occurrences DROP COLUMN hold_until; UPDATE store_meta SET schema_version=4;");
        if (fail.boolValue) ck_sql(legacy,@"CREATE TRIGGER migration_failure BEFORE UPDATE ON store_meta WHEN NEW.schema_version=5 BEGIN SELECT RAISE(ABORT,'test'); END;");
        TaskStore *migrated=[[TaskStore alloc] initAt:legacy error:&error]; ck_req((migrated!=nil)!=fail.boolValue);
        if (fail.boolValue) { ck_sql(legacy,@"DROP TRIGGER migration_failure;"); migrated=[[TaskStore alloc] initAt:legacy error:nil]; }
        ck_req([migrated schver:nil]==TS_SCH_VER);
    }
    // 六附件上限、非法中间项和中途插入失败必须整组回滚。
    NSDictionary *multi=ck_clm(store,NO);NSString *mid=multi[@"occurrence_id"];
    NSMutableArray *batch=[NSMutableArray array];NSArray *methods=@[@"image",@"screenshot",@"camera"];
    for (NSUInteger index=0;index<TS_ATT_MAX;index++) [batch addObject:@{@"method":methods[index%3],@"image":image}];
    revision=[store revision:nil];
    ck_req(![store chkOcc:mid attachments:@[] error:nil]);
    ck_req(![store chkOcc:mid attachments:(NSArray *)NSNull.null error:nil]);
    ck_req(![store chkOcc:mid attachments:(NSArray *)@[NSNull.null] error:nil]);
    ck_req(![store chkOcc:mid attachments:@[@{}] error:nil]);
    ck_req(![store chkOcc:mid attachments:[batch arrayByAddingObject:batch[0]] error:nil]);
    NSMutableArray *invalid=batch.mutableCopy;invalid[3]=@{@"method":@"image",@"image":[NSData data]};
    ck_req(![store chkOcc:mid attachments:invalid error:nil]);
    ck_req([store revision:nil]==revision && [store lsChk:mid images:YES error:nil].count==0 && [[store rdTsk:multi[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"]);
    ck_sql(path,@"CREATE TRIGGER batch_failure BEFORE INSERT ON reminder_checkins WHEN NEW.position=3 BEGIN SELECT RAISE(ABORT,'test'); END;");
    ck_req(![store chkOcc:mid attachments:batch error:nil]);
    ck_req([store revision:nil]==revision && [store lsChk:mid images:YES error:nil].count==0 && [[store lsOcc:multi[@"task_id"] error:nil].firstObject[@"status"] isEqual:@"presented"] && [[store rdTsk:multi[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"]);
    ck_sql(path,@"DROP TRIGGER batch_failure;");ck_req([store chkOcc:mid attachments:batch error:nil]);
    NSArray *saved=[reopened lsChk:mid images:YES error:nil],*metadata=[store lsChk:mid images:NO error:nil];
    ck_req(saved.count==TS_ATT_MAX && metadata.count==TS_ATT_MAX && [[store rdTsk:multi[@"task_id"] error:nil][@"status"] isEqual:@"completed"]);
    for (NSUInteger index=0;index<TS_ATT_MAX;index++) ck_req([saved[index][@"position"] unsignedIntegerValue]==index && [saved[index][@"image"] isEqual:image] && [saved[index][@"method"] isEqual:methods[index%3]] && metadata[index][@"image"]==nil);
    ck_req([[store rdChk:mid image:YES error:nil][@"image"] isEqual:image] && ![store chkOcc:mid attachments:batch error:nil]);

    // 保留第五版单图及其完成状态，迁移失败时完整回滚再重试。
    for (NSNumber *fail in @[@NO,@YES]) {
        NSString *legacy=[root stringByAppendingPathComponent:fail.boolValue?@"v5-failed.sqlite3":@"v5.sqlite3"];
        __block NSDictionary *oldAlert;
        @autoreleasepool { TaskStore *old=[[TaskStore alloc] initAt:legacy error:nil];oldAlert=ck_clm(old,NO);ck_req([old chkOcc:oldAlert[@"occurrence_id"] attachments:@[@{@"method":@"camera",@"image":image}] error:nil]); }
        ck_old(legacy);ck_sql(legacy,@"CREATE TABLE checkins_v5(occurrence_id TEXT PRIMARY KEY NOT NULL REFERENCES reminder_occurrences(occurrence_id) ON DELETE CASCADE,method TEXT NOT NULL CHECK(method IN ('camera','screenshot','image')),image BLOB NOT NULL CHECK(length(image)>0),created_at REAL NOT NULL);INSERT INTO checkins_v5 SELECT occurrence_id,method,image,created_at FROM reminder_checkins WHERE position=0;DROP TABLE capture_request; DROP TABLE reminder_checkins;ALTER TABLE checkins_v5 RENAME TO reminder_checkins;UPDATE store_meta SET schema_version=5;");
        if (fail.boolValue) ck_sql(legacy,@"CREATE TRIGGER v6_failure BEFORE UPDATE ON store_meta WHEN NEW.schema_version=6 BEGIN SELECT RAISE(ABORT,'test'); END;");
        TaskStore *migrated=[[TaskStore alloc] initAt:legacy error:&error];ck_req((migrated!=nil)!=fail.boolValue);
        if (fail.boolValue) {
            ck_req(ck_int(legacy,"SELECT schema_version FROM store_meta")==5 && ck_int(legacy,"SELECT count(*) FROM pragma_table_info('reminder_checkins') WHERE name='position'")==0 && ck_int(legacy,"SELECT count(*) FROM reminder_checkins")==1);
            ck_sql(legacy,@"DROP TRIGGER v6_failure;");migrated=[[TaskStore alloc] initAt:legacy error:nil];
        }
        NSArray *records=[migrated lsChk:oldAlert[@"occurrence_id"] images:YES error:nil];
        ck_req([migrated schver:nil]==TS_SCH_VER && records.count==1 && [records[0][@"position"] intValue]==0 && [records[0][@"image"] isEqual:image] && [records[0][@"method"] isEqual:@"camera"] && [[migrated rdTsk:oldAlert[@"task_id"] error:nil][@"status"] isEqual:@"completed"]);
        ck_req(ck_int(legacy,"SELECT count(*) FROM pragma_foreign_key_check")==0);
    }
    // 第六版迁移失败时原打卡图片保留，临时表不残留。
    for (NSNumber *fail in @[@NO,@YES]) {
        NSString *legacy=[root stringByAppendingPathComponent:fail.boolValue?@"v7failed.sqlite3":@"v6.sqlite3"];
        @autoreleasepool { TaskStore *old=[[TaskStore alloc] initAt:legacy error:nil];NSDictionary *a=ck_clm(old,NO);ck_req([old chkOcc:a[@"occurrence_id"] attachments:@[@{@"method":@"image",@"image":image}] error:nil]); }
        ck_old(legacy);ck_sql(legacy,@"DROP TABLE capture_request;UPDATE store_meta SET schema_version=6;");
        if (fail.boolValue) ck_sql(legacy,@"CREATE TRIGGER v7_failure BEFORE UPDATE ON store_meta WHEN NEW.schema_version=7 BEGIN SELECT RAISE(ABORT,'test');END;");
        TaskStore *migrated=[[TaskStore alloc] initAt:legacy error:nil];ck_req((migrated!=nil)!=fail.boolValue);
        if (fail.boolValue) {
            ck_req(ck_int(legacy,"SELECT schema_version FROM store_meta")==6 && ck_int(legacy,"SELECT count(*) FROM sqlite_master WHERE name='capture_request'")==0);
            ck_sql(legacy,@"DROP TRIGGER v7_failure;");migrated=[[TaskStore alloc] initAt:legacy error:nil];
        }
        ck_req([migrated schver:nil]==TS_SCH_VER && ck_int(legacy,"SELECT count(*) FROM reminder_checkins")==1);
    }
    printf("Checkin: %lu checks passed; valid images, atomic rollback, stale intents, occurrence holds, persisted limits, migration and process race\n",(unsigned long)ck_checks);
}

// 验证旧库归档、单轮恢复、远端确认和数据库实际缩减。
static void ck_archive(NSString *root) {
    NSUInteger before = ck_checks;
    NSString *path = [root stringByAppendingPathComponent:@"archive.sqlite3"];
    TaskStore *store = [[TaskStore alloc] initAt:path error:nil];
    NSDictionary *ordinary = ck_clm(store, NO);
    NSString *occurrence = ordinary[@"occurrence_id"];
    NSData *bytes = [NSMutableData dataWithLength:2*1024*1024];
    NSDictionary *file = @{@"method":@"file", @"name":@"证据.bin", @"content_type":@"public.data", @"image":bytes};
    ck_req([store chkOcc:occurrence attachments:@[file] error:nil]);
    ck_req([store arcRows:nil].count == 1 && [[store arcRows:nil].firstObject[@"occurrence_id"] isEqual:occurrence]);
    ck_req([[store arcRows:nil].firstObject[@"can_restore"] boolValue]);
    NSDictionary *repeat = ck_clm(store, YES);
    ck_req([store chkOcc:repeat[@"occurrence_id"] attachments:@[file] error:nil]);
    ck_req([store arcRows:nil].count == 2 && [[store rdTsk:repeat[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"]);
    ck_req(![store rstrArc:repeat[@"occurrence_id"] error:nil]);
    NSString *fixture = [NSString stringWithContentsOfFile:@"Tests/Fixtures/archive-v12.sql" encoding:NSUTF8StringEncoding error:nil];
    store = nil;
    ck_sql(path, fixture);
    ck_sql(path, @"CREATE TRIGGER reject_archive BEFORE UPDATE ON store_meta WHEN NEW.schema_version=13 BEGIN SELECT RAISE(ABORT,'test');END;");
    ck_req(![[TaskStore alloc] initAt:path error:nil] && ck_int(path, "SELECT schema_version FROM store_meta")==12);
    ck_req(ck_int(path, "SELECT count(*) FROM reminder_checkins")==2 && ck_int(path, "SELECT count(*) FROM sqlite_master WHERE name='task_archive'")==0);
    ck_sql(path, @"DROP TRIGGER reject_archive;");
    store = [[TaskStore alloc] initAt:path error:nil];
    ck_req([store schver:nil]==TS_SCH_VER && [store arcRows:nil].count==2 && [store arcPend:nil].count==2);
    ck_req([[store rdPrf:occurrence position:0 error:nil][@"image"] isEqual:bytes]);
    NSString *provider = NSUUID.UUID.UUIDString.lowercaseString;
    NSDateFormatter *calendar = [NSDateFormatter new];
    calendar.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    calendar.dateFormat = @"yyMMdd";
    NSString *day = [calendar stringFromDate:NSDate.date];
    ck_req(![store arcDone:occurrence provider:provider day:@"bad" files:@[] error:nil]);
    ck_req(![store arcDone:occurrence provider:provider day:day files:@[] error:nil]);
    ck_req([[store rdPrf:occurrence position:0 error:nil][@"image"] isEqual:bytes]);
    NSDictionary *receipt = @{@"position":@0,@"remote_key":@"archive/261111/proof", @"sha256":[@"" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0]};
    unsigned long long full = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileSize;
    ck_req([store arcDone:occurrence provider:provider day:day files:@[receipt] error:nil]);
    ck_req([store arcPend:nil].count==1 && ![store lsChk:occurrence images:YES error:nil]);
    NSDictionary *remote = [store rdPrf:occurrence position:0 error:nil];
    ck_req([remote[@"remote_key"] isEqual:receipt[@"remote_key"]] && [remote[@"image_bytes"] unsignedIntegerValue]==bytes.length && !remote[@"image"]);
    ck_req([store arcTrim:nil] && [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileSize + 1024*1024 < full);
    ck_req([store rstrArc:occurrence error:nil] && ![store rstrArc:occurrence error:nil]);
    ck_req([[store rdTsk:ordinary[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"] && [store arcRows:nil].count==2);
    printf("Archive store: %lu checks passed; migration, repeat, retry, receipts and physical reclaim\n",(unsigned long)(ck_checks-before));
}

// 运行隔离核心检查或并发子进程。
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc==4) {
            TaskStore *store=[[TaskStore alloc] initAt:@(argv[2]) error:nil];
            if (strcmp(argv[1],"--capture")==0) {
                NSData *image=[[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=" options:0];
                return [store ackCap:@(argv[3]) error:nil] && [store finCap:@(argv[3]) attachments:@[@{@"method":@"screenshot",@"image":image}] issue:nil error:nil] ? 0 : 1;
            }
            return [store hldOcc:@(argv[3]) mode:@"snooze" error:nil] ? 0 : 1;
        }
        NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]; ck_run(root); ck_cap(root); ck_files(root); ck_archive(root);
        [NSFileManager.defaultManager removeItemAtPath:root error:nil];
    } return 0;
}
