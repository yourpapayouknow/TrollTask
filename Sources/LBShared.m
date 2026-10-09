#import "LBHead.h"

#ifndef LB_HOST_TEST
#define LB_PERSONA_FLAGS 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *attr, uid_t persona, uint32_t flags);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *attr, uid_t uid);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *attr, uid_t gid);
#endif

// 生成经过边界校验的配置。
static NSDictionary *lb_normcfg(NSDictionary *input) {
    id enabled = [input isKindOfClass:NSDictionary.class] ? input[@"enabled"] : nil;
    BOOL active = [enabled isKindOfClass:NSNumber.class] ? [enabled boolValue] : YES;
    return @{@"enabled": @(active)};
}

// 读取共享配置文件。
NSDictionary *lb_ldcfg(void) {
    NSDictionary *stored = [NSDictionary dictionaryWithContentsOfFile:LB_PREF_PATH];
    return lb_normcfg(stored ?: @{});
}

// 保存共享配置文件。
BOOL lb_svcfg(NSDictionary *config) {
    NSDictionary *normalized = lb_normcfg(config ?: @{});
    BOOL saved = [normalized writeToFile:LB_PREF_PATH atomically:YES];
    if (saved) notify_post(LB_CFG_NOTE);
    return saved;
}

// 获取HUD单实例锁并写入进程号。
int lb_lckhud(void) {
    int handle = open(LB_LOCK_PATH, O_RDWR | O_CREAT, 0644);
    if (handle < 0) return -1;
    if (flock(handle, LOCK_EX | LOCK_NB) != 0) {
        close(handle);
        return -1;
    }
    ftruncate(handle, 0);
    dprintf(handle, "%d\n", getpid());
    return handle;
}

// 记录按钮按下状态，并在有效松开后清除状态。
BOOL lb_btntap(BOOL *active, BOOL inside, BOOL down) {
    BOOL fire = !down && *active && inside;
    *active = down && inside;
    return fire;
}

#ifndef LB_HOST_TEST
// 返回当前可执行文件路径。
static const char *lb_exepath(void) {
    static char path[PATH_MAX];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        uint32_t size = sizeof(path);
        if (_NSGetExecutablePath(path, &size) != 0) path[0] = '\0';
    });
    return path;
}

// 启动独立系统HUD进程。
BOOL lb_spawn(void) {
    const char *path = lb_exepath();
    if (!path[0]) return NO;

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, 99, LB_PERSONA_FLAGS);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
    posix_spawnattr_setpgroup(&attr, 0);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);

    pid_t pid = 0;
    char *const args[] = {(char *)path, "--hud", NULL};
    int result = posix_spawn(&pid, path, NULL, &attr, args, environ);
    posix_spawnattr_destroy(&attr);
    if (result == 0) {
        int status = 0;
        waitpid(pid, &status, WNOHANG);
    }
    return result == 0;
}

// 创建统一外观的功能按钮。
UIButton *lb_mkbtn(NSString *title, id target, SEL action) {
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.title = title;
    config.baseBackgroundColor = UIColor.systemRedColor;
    config.baseForegroundColor = [UIColor colorWithWhite:0.03 alpha:1.0];
    config.cornerStyle = UIButtonConfigurationCornerStyleFixed;
    config.background.cornerRadius = 4.0;
    config.contentInsets = NSDirectionalEdgeInsetsMake(4.0, 4.0, 4.0, 4.0);
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
#endif
