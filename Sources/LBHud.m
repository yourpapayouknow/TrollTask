#import "LBHead.h"

static void lb_hudrun(UIApplication *app);

@implementation LBHudApp
// 等原生运行入口装好事件源，再完成独立HUD启动。
- (void)_run {
    [self _accessibilityInit];
    dispatch_async(dispatch_get_main_queue(), ^{ lb_hudrun(self); });
    [super _run];
}
@end

@implementation LBHudWin

// 将窗口标记为安全系统窗口。
+ (BOOL)_isSystemWindow { return YES; }

// 禁止窗口服务器接管托管策略。
- (BOOL)_isWindowServerHostingManaged { return NO; }

// 让提示层接收命中并阻断下层 App。
- (BOOL)_ignoresHitTest { return NO; }

// 将窗口内容标记为安全内容。
- (BOOL)_isSecure { return YES; }

// 创建安全的渲染上下文。
- (BOOL)_shouldCreateContextAsSecure { return YES; }

@end

@interface LBHudCtl ()
@property(nonatomic, strong) TTTaskHUD *content;
@property(nonatomic, strong) FBSOrientationObserver *orientationObserver;
@property(nonatomic, assign) UIInterfaceOrientation orientation;
- (void)dspAlrt:(NSDictionary *)alert error:(NSError *)error;
- (void)stpMon;
- (void)wndmd:(NSInteger)mode;
- (void)rtt:(UIInterfaceOrientation)orientation;
@end

static __weak LBHudCtl *s_lbhudctl = nil;
static NSMutableSet<NSNumber *> *lb_touchids;
static Class s_lbaxcls = nil;
static TaskReminder *lb_reminder;
static LBHudDel *lb_delegate;
static dispatch_source_t lb_exesrc;
static int lb_exefd = -1, lb_sbtok = -1;
static void lb_hudclr(void);

// 在释放服务资源后结束独立进程。
static void lb_hudend(int code) { [lb_reminder stop]; lb_reminder = nil; exit(code); }

// 在退出前把初始化失败阶段传给主App。
static void lb_hudfail(NSString *message) { lb_svstat(message, nil); lb_hudend(EXIT_FAILURE); }

// 动态加载无障碍底层事件解析类。
static void lb_ldax(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_NOW);
        s_lbaxcls = objc_getClass("AXEventRepresentation");
    });
}

// 将同一硬件触摸路由至原生UIKit，支持滚动及系统图片选择。
static void lb_onhidevt(void *target, void *refcon, void *service, void *event) {
    (void)target; (void)refcon; (void)service;
    LBHudCtl *ctl = s_lbhudctl;
    if (!ctl || ctl.hudWindow.hidden) return;
    AXEventRepresentation *rep = [s_lbaxcls representationWithHIDEvent:event hidStreamIdentifier:@"UIApplicationEvents"];
    if (!rep) return;
    UITouchPhase phase = [rep isCancel] ? UITouchPhaseCancelled : ([rep isTouchDown] ? UITouchPhaseBegan : ([rep isMove] ? UITouchPhaseMoved : UITouchPhaseEnded));
    if (phase == UITouchPhaseEnded && ![rep isLift] && ![rep isInRangeLift]) return;
    CGPoint global = [rep location];
    NSInteger pointer = [[[[rep handInfo] paths] firstObject] pathIdentity];
    if (pointer <= 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        LBHudWin *window = ctl.hudWindow;
        if (window.hidden || !window) return;
        CGPoint local = [window convertPoint:global fromWindow:nil];
        UIView *hit = [window hitTest:local withEvent:nil];
        NSNumber *identity = @(pointer);
        if (phase == UITouchPhaseBegan) {
            if (!hit) return;
            if (!lb_touchids) lb_touchids = [NSMutableSet set];
            [lb_touchids addObject:identity];
        } else if (![lb_touchids containsObject:identity]) return;
        [TSEventFetcher receiveAXEventID:MIN(MAX(pointer,1),98) atGlobalCoordinate:local withTouchPhase:phase inWindow:window onView:hit];
        if (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled) [lb_touchids removeObject:identity];
    });
}

@implementation LBHudCtl {
    int _testToken;
}

// 只连接Swift内容和已经验证的系统宿主。
- (void)viewDidLoad {
    [super viewDidLoad]; s_lbhudctl = self; _testToken = -1;
    self.view.backgroundColor = UIColor.clearColor;
    TTTaskHUD *content = [TTTaskHUD new]; content.reminder = lb_reminder; content.globalCapture = YES; self.content = content;
    [self addChildViewController:content]; content.view.frame = self.view.bounds;
    content.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:content.view]; [content didMoveToParentViewController:self];
    __weak typeof(self) weakSelf = self;
    content.windowMode = ^(NSInteger mode) { [weakSelf wndmd:mode]; };
    Class observer = objc_getClass("FBSOrientationObserver");
    if (observer) {
        self.orientationObserver = [[observer alloc] init];
        self.orientation = (UIInterfaceOrientation)[self.orientationObserver activeInterfaceOrientation];
        [self.orientationObserver setHandler:^(FBSOrientationUpdate *update) { dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.orientation = (UIInterfaceOrientation)[update orientation]; [weakSelf wndmd:weakSelf.content.mode];
        }); }];
    }
}

// 全屏覆盖与边栏物理窗口共用同一安全context。
- (void)wndmd:(NSInteger)mode {
    LBHudWin *window = self.hudWindow;
    if (!window) return;
    if (mode == 0) { window.hidden = YES; return; }
    CGRect screen = UIScreen.mainScreen.bounds;
    window.hidden = YES;
    window.frame = screen;
    if (mode == 2) window.frame = lb_hudfrm(screen,window.safeAreaInsets,self.orientation);
    [TSEventFetcher stop]; [lb_touchids removeAllObjects];
    [self rtt:self.orientation]; window.hidden = NO;
}

// 按上游前台方向观察更新坐标与内容安全区。
- (void)rtt:(UIInterfaceOrientation)orientation {
    self.orientation = orientation;
    CGRect bounds = self.hudWindow.bounds;
    if (CGRectIsEmpty(bounds)) return;
    CGFloat angle = lb_hudang(orientation);
    if (UIInterfaceOrientationIsLandscape(orientation)) bounds = CGRectMake(0,0,bounds.size.height,bounds.size.width);
    self.view.transform = CGAffineTransformIdentity; self.view.bounds = bounds;
    self.view.center = CGPointMake(CGRectGetMidX(self.hudWindow.bounds),CGRectGetMidY(self.hudWindow.bounds));
    self.view.transform = CGAffineTransformMakeRotation(angle); [self.view setNeedsLayout];
}

// 延续上游手动跟随方向策略，避免UIKit再次旋转。
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

// 只转交数据库核对后的展示。
- (void)dspAlrt:(NSDictionary *)alert error:(NSError *)error { [self.content display:alert error:error]; }

// 保持原服务启动及预览Darwin通知顺序。
- (void)startMon {
    __weak typeof(self) weakSelf = self; NSError *error = nil;
    if (notify_register_dispatch(LB_TEST_NOTE, &_testToken, dispatch_get_main_queue(), ^(__unused int token) { [weakSelf.content preview]; notify_post(LB_READY_NOTE); }) != NOTIFY_STATUS_OK) lb_hudfail(@"服务通信失败");
    if (![lb_reminder start:&error]) { NSLog(@"TaskReminder启动失败：%@",error); lb_hudend(EXIT_FAILURE); }
}

// 停止原生触摸、方向、计时和图片资源。
- (void)stpMon {
    if (_testToken >= 0) { notify_cancel(_testToken); _testToken = -1; }
    [self.orientationObserver invalidate]; self.orientationObserver = nil;
    [TSEventFetcher stop]; [lb_touchids removeAllObjects]; [self.content stop]; self.content = nil;
    if (s_lbhudctl == self) s_lbhudctl = nil;
}

// 解除尚未停止的方向与通知。
- (void)dealloc {
    if (_testToken >= 0) notify_cancel(_testToken);
    [self.orientationObserver invalidate];
    if (s_lbhudctl == self) s_lbhudctl = nil;
}
@end

@implementation LBHudDel {
    LBHudCtl *_controller;
    id _hostingController;
}

// 创建并注册系统级全屏窗口。
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;
    (void)options;
    _controller = [[LBHudCtl alloc] init];
    (void)_controller.view;

    LBHudWin *window = [[LBHudWin alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.rootViewController = _controller;
    window.backgroundColor = UIColor.clearColor; window.opaque = NO;
    window.windowLevel = 10000010.0;
    window.alpha = 0.0;
    window.hidden = NO;
    [window makeKeyAndVisible];
    [[window _boundContext] setSecure:YES];

    Class hostClass = objc_getClass("SBSAccessibilityWindowHostingController");
    if (!hostClass) { lb_hudfail(@"窗口注册失败"); return NO; }
    _hostingController = [[hostClass alloc] init];
    SEL registerSelector = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
    if (![_hostingController respondsToSelector:registerSelector]) { lb_hudfail(@"窗口注册失败"); return NO; }
    unsigned int contextId = [window _contextId];
    if (!contextId) { lb_hudfail(@"窗口注册失败"); return NO; }
    double level = window.windowLevel;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:_hostingController];
    [invocation setSelector:registerSelector];
    [invocation setArgument:&contextId atIndex:2];
    [invocation setArgument:&level atIndex:3];
    @try { [invocation invoke]; } @catch (__unused NSException *exception) { lb_hudfail(@"窗口注册失败"); return NO; }

    window.alpha = 1.0;
    window.hidden = YES;
    self.window = window;
    _controller.hudWindow = window;
    [_controller startMon];
    return YES;
}

// 先隐藏系统窗口，再解除视图和托管控制器持有。
- (void)stp {
    [_controller stpMon]; self.window.hidden = YES; self.window.rootViewController = nil;
    self.window = nil; _hostingController = nil; _controller = nil;
}

@end

// 打开运行 HUD 所需的私有框架。
static BOOL lb_ldfw(void) {
    const char *frameworks[] = {
        "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices",
        "/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",
        "/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
    };
    for (size_t index = 0; index < sizeof(frameworks) / sizeof(frameworks[0]); index++) {
        if (!dlopen(frameworks[index], RTLD_NOW | RTLD_GLOBAL)) return NO;
    }
    return YES;
}

// 清除进程观察者和已有私有HUD窗口。
static void lb_hudclr(void) {
    if (lb_sbtok >= 0) { notify_cancel(lb_sbtok); lb_sbtok = -1; }
    if (lb_exesrc) { dispatch_source_cancel(lb_exesrc); lb_exesrc = nil; }
    if (lb_exefd >= 0) { close(lb_exefd); lb_exefd = -1; }
    [lb_delegate stp];
    if (lb_delegate) UIApplication.sharedApplication.delegate = nil;
    lb_delegate = nil; s_lbhudctl = nil;
}

// 在 App 可执行文件被删除时退出 HUD。
static void lb_monexe(void) {
    char path[PATH_MAX];
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) return;
    lb_exefd = open(path, O_EVTONLY | O_CLOEXEC);
    if (lb_exefd < 0) return;

    lb_exesrc = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, lb_exefd, DISPATCH_VNODE_DELETE, dispatch_get_main_queue());
    dispatch_source_set_event_handler(lb_exesrc, ^{
        lb_hudend(EXIT_SUCCESS);
    });
    dispatch_resume(lb_exesrc);
}

// 在UIKit事件源就绪后注册全局输入并完成插件启动。
static void lb_hudrun(UIApplication *app) {
    lb_delegate = (LBHudDel *)app.delegate;
    lb_ldax();
    void (*pBKSHID)(void (*)(void *, void *, void *, void *)) =
        (void (*)(void (*)(void *, void *, void *, void *)))dlsym(RTLD_DEFAULT, "BKSHIDEventRegisterEventCallback");
    if (!pBKSHID || !s_lbaxcls) lb_hudfail(@"触摸组件加载失败");
    pBKSHID(lb_onhidevt);
#ifdef LB_HUD_PROBE
    lb_prblog(@"input.native.ready");
#endif
    [app __completeAndRunAsPlugin];
}

// 运行长期TaskReminder服务，主App只负责启动和提交数据。
int lb_hudmain(int argc, char **argv) {
    NSError *error = nil;
    lb_reminder = [[TaskReminder alloc] initAt:TS_DB_PATH handler:^(NSDictionary *alert, NSError *failure) {
        [s_lbhudctl dspAlrt:alert error:failure];
    } cleanup:^{ lb_hudclr(); } finish:^(BOOL restart) { if (restart) lb_spawn(); lb_hudend(EXIT_SUCCESS); }];
    if (![lb_reminder open:&error]) {
        lb_reminder = nil;
        if ([error.domain isEqual:NSPOSIXErrorDomain] && (error.code == EWOULDBLOCK || error.code == ECANCELED)) return EXIT_SUCCESS;
        NSLog(@"TaskReminder初始化失败：%@", error); return EXIT_FAILURE;
    }
    lb_monexe();



    if (!lb_ldfw()) lb_hudfail(@"私有组件加载失败");
    return UIApplicationMain(argc, argv, NSStringFromClass(LBHudApp.class), NSStringFromClass(LBHudDel.class));
}
