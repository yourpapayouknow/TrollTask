#import "LBHead.h"

// 返回命令参数错误。
static id ts_bad(NSError **error) {
    if (error) *error = [NSError errorWithDomain:@"com.iwmei.taskforiwmei.cli" code:2
        userInfo:@{NSLocalizedDescriptionKey: @"参数无效，命令见docs/phases/PHASE03.md", @"kind": @"invalid_fields"}];
    return nil;
}

// 读取JSON参数。
static id ts_json(NSString *text, NSError **error) {
    id value = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding]
        options:NSJSONReadingFragmentsAllowed error:nil];
    return value ?: ts_bad(error);
}

// 转义非ASCII字符，避免设备控制台分块截断UTF8序列。
static NSData *ts_jdata(id object, NSError **error) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:error];
    if (!data) return nil;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSMutableData *output = [NSMutableData dataWithCapacity:data.length];
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if (character < 128) {
            uint8_t byte = character;
            [output appendBytes:&byte length:1];
        } else {
            char escape[7];
            snprintf(escape, sizeof(escape), "\\u%04x", character);
            [output appendBytes:escape length:6];
        }
    }
    return output;
}

// 分派薄命令入口到存储模块。
static id ts_cmd(TaskStore *store, NSArray *args, NSError **error) {
    if (!args.count) return ts_bad(error);
    for (id arg in args) if (![arg isKindOfClass:NSString.class]) return ts_bad(error);
    NSString *command = args[0];
    if ([command isEqual:@"schema"] && args.count == 1) {
        NSInteger version = [store schver:error];
        return version >= 0 ? @{@"schema_version": @(version), @"path": store.path, @"sqlite_version": @(sqlite3_libversion())} : nil;
    }
    if ([command isEqual:@"snapshot"] && args.count == 1) return [store snapshot:error];
    if ([command isEqual:@"day-order"] && args.count==2){id at=ts_json(args[1],error);return ts_num(at) ? [TaskDayOrder context:store at:[at doubleValue] error:error] : ts_bad(error);}
    if ([command isEqual:@"apply-order"] && args.count==4){id context=ts_json(args[1],error),result=ts_json(args[2],error),at=ts_json(args[3],error);return [context isKindOfClass:NSDictionary.class] && [result isKindOfClass:NSDictionary.class] && ts_num(at) ? ([TaskDayOrder apply:store context:context result:result at:[at doubleValue] error:error] ? @{@"applied":@YES}:nil) : ts_bad(error);}
    // 核对原轮次后通知唯一调度器，不能直接完成任务。
    if ([command isEqual:@"retry"] && args.count == 3) {
        id task=ts_json(args[1],error),stamp=ts_json(args[2],error);
        if(![task isKindOfClass:NSDictionary.class] || !ts_num(stamp))return ts_bad(error);
        NSDictionary *alert=[TaskToday reminder:store task:task at:[stamp doubleValue] error:error];
        if(alert)notify_post([TaskToday note:store].UTF8String);return alert;
    }
    if ([command isEqual:@"today"] && args.count==3) {id at=ts_json(args[1],error);return ts_num(at) ? [TaskToday rows:store at:[at doubleValue] zone:args[2] error:error] : ts_bad(error);}
    if ([command isEqual:@"intake"] && args.count==4) {
        id fields=ts_json(args[1],error),parts=ts_json(args[2],error),at=ts_json(args[3],error);
        return [fields isKindOfClass:NSDictionary.class] && [parts isKindOfClass:NSArray.class] && ts_num(at) ? [TaskIntake context:store fields:fields parts:parts at:[at doubleValue] error:error] : ts_bad(error);
    }
    if ([command isEqual:@"verdict"] && args.count==5) {
        id context=ts_json(args[1],error),estimate=ts_json(args[2],error),effort=ts_json(args[3],error),ddl=ts_json(args[4],error);
        return [context isKindOfClass:NSDictionary.class] && [estimate isKindOfClass:NSDictionary.class] && ts_num(effort) && [ddl isKindOfClass:NSNumber.class] ? [TaskIntake verdict:context estimate:estimate effort:[effort doubleValue] ddl:[ddl boolValue] error:error] : ts_bad(error);
    }
    if ([command isEqual:@"admit"] && args.count==6) {
        id context=ts_json(args[1],error),estimate=ts_json(args[2],error),effort=ts_json(args[3],error),ddl=ts_json(args[4],error),at=ts_json(args[5],error);
        return [context isKindOfClass:NSDictionary.class] && [estimate isKindOfClass:NSDictionary.class] && ts_num(effort) && ts_num(at) && [ddl isKindOfClass:NSNumber.class] ? [TaskIntake commit:store context:context estimate:estimate effort:[effort doubleValue] ddl:[ddl boolValue] at:[at doubleValue] error:error] : ts_bad(error);
    }
    if ([command isEqual:@"review"] && args.count==2)return [TaskIntake review:store task:args[1] error:error];
    if ([command isEqual:@"split-draft"] && args.count == 2) return [TaskDivision draft:store task:args[1] error:error];
    if ([command isEqual:@"split"] && args.count == 4) {
        id parts=ts_json(args[2],error), expected=ts_json(args[3],error);
        if (![parts isKindOfClass:NSArray.class] || ![expected isKindOfClass:NSDictionary.class]) return ts_bad(error);
        return [TaskDivision apply:store task:args[1] parts:parts expected:expected error:error];
    }
    if ([command isEqual:@"ai"] && args.count == 3) {
        NSData *configData=[NSData dataWithContentsOfFile:args[1] options:0 error:error];
        NSData *inputData=configData ? [NSData dataWithContentsOfFile:args[2] options:0 error:error] : nil;
        id config=configData ? [NSJSONSerialization JSONObjectWithData:configData options:0 error:error] : nil;
        id input=inputData ? [NSJSONSerialization JSONObjectWithData:inputData options:0 error:error] : nil;
        if (![config isKindOfClass:NSDictionary.class] || ![input isKindOfClass:NSDictionary.class]) return ts_bad(error);
        __block NSDictionary *value=nil; __block NSError *failure=nil; dispatch_semaphore_t done=dispatch_semaphore_create(0);
        NSURLSessionDataTask *task=[TaskAI gen:input config:config completion:^(NSDictionary *result,NSError *issue) {value=result;failure=issue;dispatch_semaphore_signal(done);}];
        if (dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,135*NSEC_PER_SEC))) { [task cancel];failure=[NSError errorWithDomain:@"com.iwmei.taskforiwmei.assistant" code:2 userInfo:@{NSLocalizedDescriptionKey:@"服务暂不可达",@"kind":@"assistant_failure"}]; }
        if (!value && error) *error=failure; return value;
    }
    if ([command isEqual:@"lists"] && args.count == 1) return [store lsLsts:error];
    if (([command isEqual:@"day"] || [command isEqual:@"timeline"]) && args.count >= 2 && args.count <= 4) {
        if (args.count==4 && ![args[3] isEqual:@"drafts"]) return ts_bad(error);
        id stamp=ts_json(args[1],error);if(!ts_num(stamp))return ts_bad(error);
        NSString *zone=args.count>=3 ? args[2] : NSTimeZone.localTimeZone.name;
        NSDictionary *plan=args.count==4 && [args[3] isEqual:@"drafts"] ? [store draftDay:[stamp doubleValue] zone:zone now:NSDate.date.timeIntervalSince1970 error:error]
            : [store dayAt:[stamp doubleValue] zone:zone now:NSDate.date.timeIntervalSince1970 error:error];
        return plan && [command isEqual:@"timeline"] ? [TaskTimeMap map:plan width:320 scale:6 error:error] : plan;
    }
    // 正式周表通过同一核心事务写入，不在CLI中实现排程。
    if ([command isEqual:@"routine-apply"] && args.count==4) {
        NSData *data=[NSData dataWithContentsOfFile:args[1] options:0 error:error];
        id document=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:error] : nil;
        id stamp=ts_json(args[2],error);
        return [document isKindOfClass:NSDictionary.class] && ts_num(stamp) ? [TaskRoutineImport formal:store document:document anchor:[NSDate dateWithTimeIntervalSince1970:[stamp doubleValue]] zone:args[3] error:error] : ts_bad(error);
    }
    if ([command isEqual:@"routine-import"] && (args.count==2 || args.count==3)) {
        NSDictionary *document=[TaskRoutineImport load:args[1] source:args.count==3 ? args[2] : @"时间表.md" anchor:NSDate.date zone:NSTimeZone.localTimeZone.name error:error];
        NSDictionary *result=document ? [store importRtns:document error:error] : nil;
        if(!result)return nil;NSMutableDictionary *value=result.mutableCopy;value[@"warnings"]=document[@"warnings"] ?: @[];return value;
    }
    if ([command isEqual:@"new-list"] && args.count == 2) return [store crtLst:args[1] error:error];
    if ([command isEqual:@"rename-list"] && args.count == 3)
        return [store updLst:args[1] title:args[2] error:error] ? @{@"updated": @YES} : nil;
    if ([command isEqual:@"delete-list"] && args.count == 2) return [store delLst:args[1] error:error] ? @{@"deleted":@YES} : nil;
    if ([command isEqual:@"clear-completed"] && args.count == 2) return [store clrCmpl:args[1] error:error] ? @{@"deleted":@YES} : nil;
    if ([command isEqual:@"complete-next"] && args.count == 2) return [store cmplNxt:args[1] error:error] ? @{@"completed":@YES} : nil;
    if ([command isEqual:@"tasks"] && args.count == 1) return [store lsTsks:error];
    if ([command isEqual:@"pending"] && args.count == 1) return [store lsPnd:error];
    if ([command isEqual:@"completed"] && args.count == 1) return [store lsCmpl:error];
    if ([command isEqual:@"plan"] && args.count <= 2) {
        id stamp = args.count == 2 ? ts_json(args[1], error) : @(NSDate.date.timeIntervalSince1970);
        return ts_num(stamp) ? [store planAt:[stamp doubleValue] error:error] : ts_bad(error);
    }
    if ([command isEqual:@"delete"] && args.count == 2) return [store delTsk:args[1] error:error] ? @{@"deleted": @YES} : nil;
    if ([command isEqual:@"complete"] && args.count == 2) return [store cmplTsk:args[1] error:error] ? @{@"completed": @YES} : nil;
    if ([command isEqual:@"restore"] && args.count == 2) return [store rstrTsk:args[1] error:error] ? @{@"restored": @YES} : nil;
    if ([command isEqual:@"import"] && args.count == 3) {
        id fields = ts_json(args[2], error); return fields ? [store crtTsk:fields uuid:args[1] error:error] : nil;
    }
    if ([command isEqual:@"claim"] && args.count == 4) {
        id alert = ts_json(args[1], error), revision = ts_json(args[2], error), stamp = ts_json(args[3], error);
        if (!ts_num(revision) || [revision doubleValue] < 0 || [revision doubleValue] != (double)[revision longLongValue]
            || !ts_num(stamp)) return ts_bad(error);
        NSDictionary *result = [store claim:alert revision:[revision longLongValue] at:[stamp doubleValue] error:error];
        return result ?: (error && *error ? nil : @{@"claimed": @NO});
    }
    if ([command isEqual:@"action"] && (args.count == 3 || args.count == 4)) {
        id until = args.count == 4 ? ts_json(args[3], error) : nil;
        return [store actOcc:args[1] action:args[2] until:until error:error] ? @{@"handled": @YES} : nil;
    }
    if ([command isEqual:@"hold"] && args.count == 3) return [store hldOcc:args[1] mode:args[2] error:error];
    if ([command isEqual:@"resume"] && args.count == 2) return [store rsmOcc:args[1] error:error] ? @{@"resumed":@YES} : nil;
    // 读取1至6个文件后交给同一多附件事务。
    if ([command isEqual:@"checkin"] && args.count >= 4 && args.count <= 3+TS_ATT_MAX) {
        NSMutableArray *attachments=[NSMutableArray array];
        for (NSString *path in [args subarrayWithRange:NSMakeRange(3,args.count-3)]) {
            NSData *image=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:error];
            if (!image) return nil;
            NSMutableDictionary *item=[@{@"method":args[2],@"image":image} mutableCopy];
            if ([args[2] isEqual:@"file"]) {item[@"name"]=path.lastPathComponent;item[@"content_type"]=@"public.data";}
            [attachments addObject:item];
        }
        return [store chkOcc:args[1] attachments:attachments error:error] ? [store rdChk:args[1] image:NO error:error] : nil;
    }
    // 列出同一提醒的附件元数据。
    if ([command isEqual:@"proofs"] && args.count == 2) return [store lsChk:args[1] images:NO error:error];
    if ([command isEqual:@"proof"] && (args.count == 2 || args.count == 3)) {
        NSDictionary *record = [store rdChk:args[1] image:args.count==3 error:error];
        if (!record || (args.count == 3 && ![record[@"image"] writeToFile:args[2] options:NSDataWritingAtomic error:error])) return nil;
        return [store rdChk:args[1] image:NO error:error];
    }
    if ([command isEqual:@"get"] && args.count == 2) return [store rdTsk:args[1] error:error];
    if ([command isEqual:@"create"] && args.count == 2) {
        id fields = ts_json(args[1], error);
        return fields ? [store crtTsk:fields error:error] : nil;
    }
    if ([command isEqual:@"update"] && args.count == 3) {
        id fields = ts_json(args[2], error);
        return fields && [store updTsk:args[1] fields:fields error:error] ? @{@"updated": @YES} : nil;
    }
    if ([command isEqual:@"occurrences"] && args.count == 2) return [store lsOcc:args[1] error:error];
    if ([command isEqual:@"occur"] && args.count == 3) {
        id stamp = ts_json(args[2], error);
        return stamp ? [store crtOcc:args[1] at:stamp error:error] : nil;
    }
    if ([command isEqual:@"handle"] && args.count == 3) {
        id fields = ts_json(args[2], error);
        return fields && [store updOcc:args[1] fields:fields error:error] ? @{@"updated": @YES} : nil;
    }
    if ([command isEqual:@"batch"] && args.count == 2) {
        id operations = ts_json(args[1], error);
        if (![operations isKindOfClass:NSArray.class]) return ts_bad(error);
        NSMutableArray *results = [NSMutableArray array];
        BOOL success = [store wrTxn:^BOOL(NSError **failure) {
            for (id operation in operations) {
                if (![operation isKindOfClass:NSArray.class] || [[operation firstObject] isEqual:@"batch"]) { ts_bad(failure); return NO; }
                id result = ts_cmd(store, operation, failure);
                if (!result) return NO;
                [results addObject:result];
            }
            return YES;
        } error:error];
        return success ? results : nil;
    }
    return ts_bad(error);
}

// 解析参数并输出一次原子操作的JSON结果。
int ts_cli(int argc, char *argv[], NSString *path) {
    NSError *error = nil;
    TaskStore *store = [[TaskStore alloc] initAt:path error:&error];
    NSMutableArray *args = [NSMutableArray array];
    for (int index = 0; index < argc; index++) [args addObject:@(argv[index])];
    if (store && args.count == 1 && [args[0] isEqual:@"watch"]) {
        TaskScheduler *scheduler = [[TaskScheduler alloc] initStore:store handler:^(NSDictionary *alert, NSError *failure) {
            NSData *line = ts_jdata(@{@"alert": alert ?: (id)NSNull.null, @"error": failure.localizedDescription ?: (id)NSNull.null}, nil);
            fwrite(line.bytes, 1, line.length, stdout); putchar('\n'); fflush(stdout);
        }];
        if ([scheduler start:&error]) { CFRunLoopRun(); [scheduler stop]; return EXIT_SUCCESS; }
    }
    id result = store ? ts_cmd(store, args, &error) : nil;
    NSData *data = result ? ts_jdata(result, &error) : nil;
    if (!data) {
        NSDictionary *failure = @{@"domain": error.domain ?: @"com.iwmei.taskforiwmei.store", @"code": @(error.code),
            @"kind": error.userInfo[@"kind"] ?: @"database_failure", @"message": error.localizedDescription ?: @"存储操作失败"};
        NSData *line = ts_jdata(failure, nil);
        fwrite(line.bytes, 1, line.length, stderr); fputc('\n', stderr); return EXIT_FAILURE;
    }
    fwrite(data.bytes, 1, data.length, stdout);
    putchar('\n'); fflush(stdout);
    return EXIT_SUCCESS;
}

#ifdef TT_STORE_CLI
// 为宿主测试提供显式数据库路径入口。
int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 3) { fprintf(stderr, "用法：taskstore <数据库绝对路径> <命令> [参数]\n"); return 2; }
        return ts_cli(argc - 2, argv + 2, @(argv[1]));
    }
}
#endif
