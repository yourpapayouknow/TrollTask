#import "LBHead.h"

// 返回命令参数错误。
static id ts_bad(NSError **error) {
    if (error) *error = [NSError errorWithDomain:@"com.iwmei.taskforiwmei.cli" code:2
        userInfo:@{NSLocalizedDescriptionKey: @"参数无效，命令见PHASE03.md", @"kind": @"invalid_fields"}];
    return nil;
}

// 读取JSON参数。
static id ts_json(NSString *text, NSError **error) {
    id value = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding]
        options:NSJSONReadingFragmentsAllowed error:nil];
    return value ?: ts_bad(error);
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
    if ([command isEqual:@"lists"] && args.count == 1) return [store lsLsts:error];
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
        TaskSched *scheduler = [[TaskSched alloc] initStore:store handler:^(NSDictionary *alert, NSError *failure) {
            NSData *line = [NSJSONSerialization dataWithJSONObject:@{@"alert": alert ?: (id)NSNull.null, @"error": failure.localizedDescription ?: (id)NSNull.null}
                options:NSJSONWritingSortedKeys error:nil];
            fwrite(line.bytes, 1, line.length, stdout); putchar('\n'); fflush(stdout);
        }];
        if ([scheduler start:&error]) { CFRunLoopRun(); [scheduler stop]; return EXIT_SUCCESS; }
    }
    id result = store ? ts_cmd(store, args, &error) : nil;
    NSData *data = result ? [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:&error] : nil;
    if (!data) {
        NSDictionary *failure = @{@"domain": error.domain ?: @"com.iwmei.taskforiwmei.store", @"code": @(error.code),
            @"kind": error.userInfo[@"kind"] ?: @"database_failure", @"message": error.localizedDescription ?: @"存储操作失败"};
        NSData *line = [NSJSONSerialization dataWithJSONObject:failure options:NSJSONWritingSortedKeys error:nil];
        fwrite(line.bytes, 1, line.length, stderr); fputc('\n', stderr); return EXIT_FAILURE;
    }
    fwrite(data.bytes, 1, data.length, stdout);
    putchar('\n');
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
