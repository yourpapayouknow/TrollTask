#import "LBHead.h"

// 根据启动参数选择主App或独立TaskReminder服务。
int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--store") == 0) return ts_cli(argc - 2, argv + 2, TS_DB_PATH);
        if (argc > 1 && strcmp(argv[1], "--hud") == 0) return lb_hudmain(argc, argv);
        if (argc > 1 && strcmp(argv[1], "--start") == 0) return lb_spawn() ? EXIT_SUCCESS : EXIT_FAILURE;
        if (argc > 1 && strcmp(argv[1], "--stop") == 0) return notify_post(LB_STOP_NOTE) == NOTIFY_STATUS_OK ? EXIT_SUCCESS : EXIT_FAILURE;
        if (argc > 1 && strcmp(argv[1], "--preview") == 0) return notify_post(LB_TEST_NOTE) == NOTIFY_STATUS_OK ? EXIT_SUCCESS : EXIT_FAILURE;
        // 诊断包每次打开先停服务，用户手动启用才进行30秒有界测试。
        if (lb_dbg()) {
            if (!lb_svcfg(@{@"enabled": @NO})) return EXIT_FAILURE;
            notify_post(LB_STOP_NOTE);
        }
        return UIApplicationMain(argc, argv, NSStringFromClass([LBApp class]), NSStringFromClass([LBAppDel class]));
    }
}
