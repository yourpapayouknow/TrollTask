#import "LBHead.h"

NSString *lb_tstpath;
const char *lb_tstlock;

// 消耗通知初始状态。
static int tstreg(const char *name) {
    int token = -1;
    int changed = 0;
    assert(notify_register_check(name, &token) == NOTIFY_STATUS_OK);
    assert(notify_check(token, &changed) == NOTIFY_STATUS_OK);
    return token;
}

// 等待跨进程通知状态。
static void tstnote(int token) {
    int changed = 0;
    for (int index = 0; index < 100 && !changed; index++) {
        usleep(10000);
        assert(notify_check(token, &changed) == NOTIFY_STATUS_OK);
    }
    assert(changed);
}

// 验证配置默认值、异常输入和读写通知。
static void tstcfg(void) {
    assert([lb_ldcfg() isEqual:@{@"enabled": @YES}]);
    int config = tstreg(LB_CFG_NOTE);
    int preview = tstreg(LB_TEST_NOTE);
    assert(lb_svcfg(@{@"enabled": @NO, @"unknown": @42}));
    assert([lb_ldcfg() isEqual:@{@"enabled": @NO}]);
    tstnote(config);
    int changed = 0;
    assert(notify_check(preview, &changed) == NOTIFY_STATUS_OK && !changed);

    assert(lb_svcfg(nil));
    assert([lb_ldcfg() isEqual:@{@"enabled": @YES}]);
    for (id value in @[@"false", NSNull.null, @[], @{}]) {
        assert(lb_svcfg(@{@"enabled": value}));
        assert([lb_ldcfg() isEqual:@{@"enabled": @YES}]);
    }
    assert(lb_svcfg((NSDictionary *)(id)@[]));
    assert([lb_ldcfg() isEqual:@{@"enabled": @YES}]);
    assert([@"invalid plist" writeToFile:lb_tstpath atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    assert([lb_ldcfg() isEqual:@{@"enabled": @YES}]);

    assert(notify_check(config, &changed) == NOTIFY_STATUS_OK);
    NSString *savedPath = lb_tstpath;
    lb_tstpath = [savedPath stringByAppendingPathComponent:@"missing/preferences.plist"];
    assert(!lb_svcfg(@{@"enabled": @NO}));
    lb_tstpath = savedPath;
    assert(notify_check(config, &changed) == NOTIFY_STATUS_OK && !changed);
    assert(notify_cancel(config) == NOTIFY_STATUS_OK);
    assert(notify_cancel(preview) == NOTIFY_STATUS_OK);
}

// 验证预览、就绪和退出通知互不串扰。
static void tstipc(void) {
    const char *names[] = {LB_TEST_NOTE, LB_READY_NOTE, LB_STOP_NOTE};
    int tokens[3];
    for (int index = 0; index < 3; index++) tokens[index] = tstreg(names[index]);
    for (int index = 0; index < 3; index++) {
        assert(notify_post(names[index]) == NOTIFY_STATUS_OK);
        tstnote(tokens[index]);
        for (int other = 0; other < 3; other++) {
            int changed = 0;
            if (other != index) assert(notify_check(tokens[other], &changed) == NOTIFY_STATUS_OK && !changed);
        }
    }
    for (int index = 0; index < 3; index++) assert(notify_cancel(tokens[index]) == NOTIFY_STATUS_OK);
}

// 验证单实例锁和遗留锁文件恢复。
static void tstlock(void) {
    int handle = lb_lckhud();
    assert(handle >= 0);
    assert(lb_svcup() && (fcntl(handle, F_GETFD) & FD_CLOEXEC));
    assert(lb_lckhud() == -1);
    char text[64] = {0};
    assert(pread(handle, text, sizeof(text) - 1, 0) > 0);
    assert(atoi(text) == getpid());
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        close(handle);
        _exit(lb_lckhud() == -1 ? EXIT_SUCCESS : EXIT_FAILURE);
    }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == EXIT_SUCCESS);
    close(handle);
    assert(!lb_svcup());
    handle = lb_lckhud();
    assert(handle >= 0);
    close(handle);
    const char *savedPath = lb_tstlock;
    lb_tstlock = "/nonexistent/trolltask/hud.lock";
    assert(lb_lckhud() == -1);
    lb_tstlock = savedPath;
}

// 验证按钮内外、拖动、取消和重复抬起的触摸边界。
static void tsttap(void) {
    for (int start = 0; start < 2; start++) {
        for (int end = 0; end < 2; end++) {
            BOOL active = NO;
            assert(!lb_btntap(&active, start, YES));
            assert(lb_btntap(&active, end, NO) == (start && end));
            assert(!active);
            assert(!lb_btntap(&active, YES, NO));
        }
    }
    BOOL active = NO;
    assert(!lb_btntap(&active, YES, NO));
    assert(!lb_btntap(&active, YES, YES));
    assert(!lb_btntap(&active, NO, NO));
    assert(!lb_btntap(&active, YES, NO));
    assert(!lb_btntap(&active, YES, YES));
    assert(lb_btntap(&active, YES, NO));
}

// 主线程永久等待时由系统期限退出，并自动释放单实例锁。
static void tstescape(void) {
    pid_t child = fork(); assert(child >= 0);
    if (child == 0) {
        if (lb_lckhud() < 0) _exit(EXIT_FAILURE);
        lb_dbgarm(1); for (;;) pause();
    }
    int status = 0; assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGALRM);
    assert(!lb_svcup());
}

// 验证真实锁、下一时刻、启动阶段错误与异常死亡后的陈旧快照。
static void tststat(void) {
    assert(lb_svcfg(@{@"enabled":@YES}));
    NSNumber *next = @(NSDate.date.timeIntervalSince1970+120);
    lb_svstat(@"正在运行", next);
    assert(![lb_rdstat()[@"running"] boolValue] && !lb_rdstat()[@"next_fire_at"]);
    int handle = lb_lckhud(); assert(handle >= 0);
    lb_svstat(@"正在运行", next);
    assert([lb_rdstat()[@"running"] boolValue] && [lb_rdstat()[@"next_fire_at"] isEqual:next]);
    NSString *path = [LB_PREF_PATH stringByAppendingString:@".status"];
    NSMutableDictionary *wrong = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy];
    wrong[@"pid"] = @(getpid()+1); assert([wrong writeToFile:path atomically:YES]);
    assert(![lb_rdstat()[@"running"] boolValue] && !lb_rdstat()[@"next_fire_at"]);
    for (NSString *issue in @[@"数据库不可用",@"HUD启动失败",@"私有组件加载失败",@"窗口注册失败",@"调度读取失败"]) {
        lb_svstat(issue, nil); assert([lb_rdstat()[@"state"] isEqual:issue] && ![lb_rdstat()[@"running"] boolValue]);
    }
    close(handle);
    assert([lb_rdstat()[@"state"] isEqual:@"调度读取失败"]);
    lb_svstat(@"正在运行", next); assert([lb_rdstat()[@"state"] isEqual:@"服务未运行"]);
    pid_t child = fork(); assert(child >= 0);
    if (!child) { int fd = lb_lckhud(); if (fd < 0) _exit(1); lb_svstat(@"正在运行", next); for (;;) pause(); }
    // 等待指定子进程完成发布，旧父进程快照不能提前结束等待。
    BOOL ready = NO;
    for (int i=0;i<200;i++) {
        NSDictionary *current = lb_rdstat();
        ready = [current[@"running"] boolValue] && [current[@"pid"] intValue] == child;
        if (ready) break; usleep(10000);
    }
    assert(kill(child,SIGKILL)==0); int status=0; assert(waitpid(child,&status,0)==child);
    assert(ready);
    assert(![lb_rdstat()[@"running"] boolValue] && !lb_rdstat()[@"next_fire_at"]);
    assert([lb_rdstat()[@"state"] isEqual:@"服务未运行"]);
    assert(lb_svcfg(@{@"enabled":@NO})); lb_svstat(@"服务已关闭", nil);
    assert([lb_rdstat()[@"state"] isEqual:@"服务已关闭"]);
    puts("Service diagnostics: live PID/lock, next time, five failure states and SIGKILL stale-status rejection passed");
}

// 运行共享配置、进程通信和按钮触摸测试。
int main(void) {
    @autoreleasepool {
        char directory[] = "/tmp/trolltask-tests.XXXXXX";
        assert(mkdtemp(directory));
        NSString *root = [NSString stringWithUTF8String:directory];
        lb_tstpath = [root stringByAppendingPathComponent:@"preferences.plist"];
        NSString *lockPath = [root stringByAppendingPathComponent:@"hud.lock"];
        lb_tstlock = lockPath.fileSystemRepresentation;
        tstcfg();
        tstipc();
        tstlock();
        tsttap();
        tststat();
        tstescape();
        assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
        puts("Shared configuration, Darwin IPC, single-instance lock and button tap tests passed");
    }
    return EXIT_SUCCESS;
}
