#import "LBHead.h"

// 根据启动参数选择配置 App 或全局 HUD 模式。
int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--hud") == 0) return lb_hudmain();
        if (argc > 1 && strcmp(argv[1], "--start") == 0) return lb_spawn() ? EXIT_SUCCESS : EXIT_FAILURE;
        if (argc > 1 && strcmp(argv[1], "--stop") == 0) return notify_post(LB_STOP_NOTE) == NOTIFY_STATUS_OK ? EXIT_SUCCESS : EXIT_FAILURE;
        if (argc > 1 && strcmp(argv[1], "--preview") == 0) return notify_post(LB_TEST_NOTE) == NOTIFY_STATUS_OK ? EXIT_SUCCESS : EXIT_FAILURE;
        return UIApplicationMain(argc, argv, NSStringFromClass([LBApp class]), NSStringFromClass([LBAppDel class]));
    }
}
