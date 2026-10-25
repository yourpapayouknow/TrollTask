#import "LBHead.h"

#if !defined(LB_HOST_TEST) || defined(LB_UI_TEST)
// 复用LaunchServices激活同一App，不派生第二个采集守护进程。
BOOL lb_opnapp(void) {
    Class workspace=NSClassFromString(@"LSApplicationWorkspace");
    if (![workspace respondsToSelector:@selector(defaultWorkspace)]) return NO;
    id instance=[workspace defaultWorkspace];
    return [instance respondsToSelector:@selector(openApplicationWithBundleID:)] && [instance openApplicationWithBundleID:@"com.iwmei.taskforiwmei"];
}
#endif

#ifdef LB_HOST_TEST
// 为未使用服务的宿主入口提供可由隔离测试覆盖的路径符号。
__attribute__((weak)) NSString *lb_tstpath;
__attribute__((weak)) const char *lb_tstlock;
#endif

#ifndef LB_HOST_TEST
#define LB_PERSONA_FLAGS 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *attr, uid_t persona, uint32_t flags);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *attr, uid_t uid);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *attr, uid_t gid);
#endif

// 仅诊断安装包启用限时HUD，正常包没有此标记。
BOOL lb_dbg(void) { return [NSBundle.mainBundle.infoDictionary[@"TTHUDDebug"] boolValue]; }

// 默认SIGALRM由系统结束进程，不依赖触摸或主RunLoop。
void lb_dbgarm(unsigned int seconds) { signal(SIGALRM, SIG_DFL); alarm(seconds); }

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
    int handle = open(LB_LOCK_PATH, O_RDWR | O_CREAT | O_CLOEXEC, 0644);
    if (handle < 0) return -1;
    if (flock(handle, LOCK_EX | LOCK_NB) != 0) {
        int failure = errno;
        close(handle); errno = failure;
        return -1;
    }
    ftruncate(handle, 0);
    dprintf(handle, "%d\n", getpid());
    return handle;
}

// 只读探测锁，避免主App重复创建后台进程。
BOOL lb_svcup(void) {
    int handle = open(LB_LOCK_PATH, O_RDONLY | O_CLOEXEC);
    if (handle < 0) return NO;
    BOOL held = flock(handle, LOCK_EX | LOCK_NB) != 0 && errno == EWOULDBLOCK;
    close(handle); return held;
}

// 写入同一服务的诊断快照，不访问正常任务数据库。
void lb_svstat(NSString *state, NSNumber *next) {
    if (!LB_PREF_PATH.length) return;
    NSString *path = [LB_PREF_PATH stringByAppendingString:@".status"];
    NSMutableDictionary *value = [@{@"state":state, @"pid":@(getpid())} mutableCopy];
    if (next) value[@"next_fire_at"] = next;
    NSMutableDictionary *old = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy];
    [old removeObjectForKey:@"at"];
    if ([old isEqual:value]) return;
    value[@"at"] = @(NSDate.date.timeIntervalSince1970);
    if (![value writeToFile:path atomically:YES]) NSLog(@"服务诊断状态保存失败");
}

// 真实锁优先于遗留正常记录，旧进程快照不能冒充新服务。
NSDictionary *lb_rdstat(void) {
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:[LB_PREF_PATH stringByAppendingString:@".status"]] ?: @{};
    NSString *state = [saved[@"state"] isKindOfClass:NSString.class] ? saved[@"state"] : @"";
    int handle = open(LB_LOCK_PATH, O_RDONLY | O_CLOEXEC); char text[64] = {0};
    if (handle >= 0) { pread(handle, text, sizeof(text)-1, 0); close(handle); }
    pid_t pid = (pid_t)atoi(text);
    BOOL alive = pid > 0 && lb_svcup();
    BOOL matches = alive && [saved[@"pid"] intValue] == pid;
    BOOL healthy = [@[@"正在运行", @"正在提醒"] containsObject:state];
    if (matches && healthy) {
        NSMutableDictionary *result = saved.mutableCopy; result[@"running"] = @YES; return result;
    }
    if (state.length && !healthy && ![@[@"启动中", @"服务已关闭"] containsObject:state] && (!alive || matches))
        return @{@"state":state, @"running":@NO};
    BOOL enabled = [lb_ldcfg()[@"enabled"] boolValue];
    BOOL starting = enabled && (alive || ([state isEqual:@"启动中"] && fabs(NSDate.date.timeIntervalSince1970-[saved[@"at"] doubleValue]) < 3));
    return @{@"state": starting ? @"启动中" : enabled ? @"服务未运行" : @"服务已关闭", @"running":@NO};
}

// 记录按钮按下状态，并在有效松开后清除状态。
BOOL lb_btntap(BOOL *active, BOOL inside, BOOL down) {
    BOOL fire = !down && *active && inside;
    *active = down && inside;
    return fire;
}

// 截取界面中允许显示的13个完整字形。
NSString *lb_shrt(NSString *text) {
    __block NSUInteger length = 0, count = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences
        usingBlock:^(__unused NSString *value, NSRange range, __unused NSRange enclosing, BOOL *stop) {
            if (++count > 13) { *stop = YES; return; } length = NSMaxRange(range);
        }];
    return [text substringToIndex:length];
}

#ifndef LB_UI_TEST
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

// 将启动失败传回前台诊断区域。
static BOOL lb_spfail(void) { lb_svstat(@"HUD启动失败", nil); return NO; }

// 启动独立系统HUD进程。
BOOL lb_spawn(void) {
    if (![lb_ldcfg()[@"enabled"] boolValue]) return NO;
    if (lb_svcup()) return YES;
    lb_svstat(@"启动中", nil);
    const char *path = lb_exepath();
    if (!path[0]) return lb_spfail();

    posix_spawnattr_t attr;
    if (posix_spawnattr_init(&attr) != 0) return lb_spfail();
    int result = 0;
#ifndef LB_HOST_TEST
    result = posix_spawnattr_set_persona_np(&attr, 99, LB_PERSONA_FLAGS);
    if (!result) result = posix_spawnattr_set_persona_uid_np(&attr, 0);
    if (!result) result = posix_spawnattr_set_persona_gid_np(&attr, 0);
#endif
    if (!result) result = posix_spawnattr_setpgroup(&attr, 0);
    if (!result) result = posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT);

    // 仅保留标准流，避免新连接复用已关闭的日志描述符。
    posix_spawn_file_actions_t actions;
    int actionResult = posix_spawn_file_actions_init(&actions);
    if (actionResult) { posix_spawnattr_destroy(&attr); return lb_spfail(); }
    for (int descriptor = 0; descriptor < 3 && !result; descriptor++) {
        if (fcntl(descriptor, F_GETFD) >= 0) result = posix_spawn_file_actions_addinherit_np(&actions, descriptor);
        else result = posix_spawn_file_actions_addopen(&actions, descriptor, "/dev/null", descriptor == 0 ? O_RDONLY : O_WRONLY, 0);
    }

    pid_t pid = 0;
    char *const args[] = {(char *)path, "--hud", NULL};
    if (!result) result = posix_spawn(&pid, path, &actions, &attr, args, environ);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);
    if (result == 0) {
        int status = 0;
        waitpid(pid, &status, WNOHANG);
    }
    return result == 0 ? YES : lb_spfail();
}
#endif

#if !defined(LB_HOST_TEST) || defined(LB_UI_TEST)
// 返回统一青绿强调色。
UIColor *lb_acnt(void) { return [UIColor colorWithRed:28.0/255 green:209.0/255 blue:194.0/255 alpha:1]; }
// 使用UIKit加载同库的多倍率模板图标。
UIImage *lb_icon(NSString *name) {
    return [[UIImage imageNamed:[@"MingCute/" stringByAppendingString:name]] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
// 将同一前台方向用于内容和边栏投影。
CGFloat lb_hudang(UIInterfaceOrientation orientation) {
    if (orientation == UIInterfaceOrientationLandscapeLeft) return -M_PI_2;
    if (orientation == UIInterfaceOrientationLandscapeRight) return M_PI_2;
    return orientation == UIInterfaceOrientationPortraitUpsideDown ? M_PI : 0;
}

// 在真实安全区右缘放置单一边栏窗口。
CGRect lb_hudfrm(CGRect screen, UIEdgeInsets insets, UIInterfaceOrientation orientation) {
    CGFloat angle = lb_hudang(orientation);
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation);
    CGSize logical = landscape ? CGSizeMake(screen.size.height,screen.size.width) : screen.size;
    CGRect safe = CGRectOffset(UIEdgeInsetsInsetRect(screen,insets),-CGRectGetMidX(screen),-CGRectGetMidY(screen));
    safe = CGRectApplyAffineTransform(safe,CGAffineTransformMakeRotation(-angle));
    safe = CGRectOffset(safe,logical.width/2,logical.height/2);
    CGPoint center = CGPointMake(CGRectGetMaxX(safe)-40-logical.width/2,CGRectGetMidY(safe)-logical.height/2);
    center = CGPointApplyAffineTransform(center,CGAffineTransformMakeRotation(angle));
    center.x += CGRectGetMidX(screen); center.y += CGRectGetMidY(screen);
    CGSize size = landscape ? CGSizeMake(96,72) : CGSizeMake(72,96);
    return CGRectMake(center.x-size.width/2,center.y-size.height/2,size.width,size.height);
}

// 读取统一大字与动态字体。
UIFont *lb_fnt(UIFontTextStyle style, UITraitCollection *traits) {
    CGFloat size = 20; UIFontWeight weight = UIFontWeightMedium;
    if ([style isEqual:UIFontTextStyleTitle1] || [style isEqual:UIFontTextStyleTitle2] || [style isEqual:UIFontTextStyleLargeTitle]) {
        size = 28; weight = UIFontWeightSemibold;
    } else if ([style isEqual:UIFontTextStyleHeadline]) {
        weight = UIFontWeightSemibold;
    } else if ([style isEqual:UIFontTextStyleSubheadline] || [style isEqual:UIFontTextStyleFootnote] || [style isEqual:UIFontTextStyleCaption1] || [style isEqual:UIFontTextStyleCaption2]) {
        size = 18;
    }
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight] compatibleWithTraitCollection:traits];
}

// 创建统一外观的功能按钮。
UIButton *lb_mkbtn(NSString *title, id target, SEL action) {
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.title = title;
    config.baseBackgroundColor = [UIColor colorWithRed:37/255.0 green:51/255.0 blue:53/255.0 alpha:0.72];
    config.baseForegroundColor = lb_acnt();
    config.cornerStyle = UIButtonConfigurationCornerStyleFixed;
    config.background.cornerRadius = 20.0;
    config.background.strokeColor = [UIColor colorWithWhite:1 alpha:0.12];
    config.background.strokeWidth = 1.0 / UIScreen.mainScreen.scale;
    config.contentInsets = NSDirectionalEdgeInsetsMake(8.0, 8.0, 8.0, 8.0);
    config.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey,id> *(NSDictionary<NSAttributedStringKey,id> *attributes) {
        NSMutableDictionary *result = attributes.mutableCopy; result[NSFontAttributeName] = lb_fnt(UIFontTextStyleHeadline, nil); return result;
    };
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
#endif
