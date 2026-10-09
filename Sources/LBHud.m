#import "LBHead.h"

@implementation LBHudApp
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
@property(nonatomic, assign) BOOL touchActive;
@property(nonatomic, strong) UIButton *closeButton;
- (void)onTchDn:(CGPoint)point;
- (void)onTchUp:(CGPoint)point;
- (void)onTchCn;
@end

static __weak LBHudCtl *s_lbhudctl = nil;
static Class s_lbaxcls = nil;

// 动态加载无障碍底层事件解析类。
static void lb_ldax(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dlopen("/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities", RTLD_NOW);
        s_lbaxcls = objc_getClass("AXEventRepresentation");
    });
}

// 接收底层硬件触摸事件回调。
static void lb_onhidevt(void *target, void *refcon, void *service, void *event) {
    (void)target;
    (void)refcon;
    (void)service;
    LBHudCtl *ctl = s_lbhudctl;
    if (!ctl || ctl.hudWindow.hidden) return;

    AXEventRepresentation *rep = [s_lbaxcls representationWithHIDEvent:event hidStreamIdentifier:@"UIApplicationEvents"];
    if (!rep) return;
    if ([rep isCancel]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [ctl onTchCn];
        });
        return;
    }
    if (![rep respondsToSelector:@selector(location)]) return;
    CGPoint point = [rep location];
    if ([rep isTouchDown]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [ctl onTchDn:point];
        });
    } else if ([rep isLift] || [rep isInRangeLift]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [ctl onTchUp:point];
        });
    }
}




@implementation LBHudCtl {
    int _configToken;
    int _testToken;
}

// 创建手动提醒预览界面。
- (void)viewDidLoad {
    [super viewDidLoad];
    s_lbhudctl = self;
    _configToken = -1;
    _testToken = -1;
    self.view.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.88];
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
    card.layer.cornerRadius = 4.0;
    card.layer.masksToBounds = YES;
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checklist"]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = UIColor.systemRedColor;
    [icon.heightAnchor constraintEqualToConstant:44.0].active = YES;
    UILabel *title = [[UILabel alloc] init];
    title.text = @"待办提醒";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.textColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    UIButton *button = lb_mkbtn(@"收起预览", self, @selector(hdeprvw));
    self.closeButton = button;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, button]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:stack];
    NSLayoutConstraint *width = [card.widthAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor constant:-(4.0 + 4.0)];
    width.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        [card.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:4.0],
        [card.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-4.0],
        [card.widthAnchor constraintLessThanOrEqualToConstant:380.0],
        width,
        [stack.leadingAnchor constraintEqualToAnchor:card.contentView.leadingAnchor constant:4.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.contentView.trailingAnchor constant:-4.0],
        [stack.topAnchor constraintEqualToAnchor:card.contentView.topAnchor constant:4.0],
        [stack.bottomAnchor constraintEqualToAnchor:card.contentView.bottomAnchor constant:-4.0],
    ]];
}

// 收起手动预览。
- (void)hdeprvw {
    self.touchActive = NO;
    self.hudWindow.hidden = YES;
}

// 按真实按钮及其子视图判断触摸命中。
- (BOOL)btntst:(CGPoint)point {
    UIView *hit = [self.hudWindow hitTest:point withEvent:nil];
    return hit && (hit == self.closeButton || [hit isDescendantOfView:self.closeButton]);
}

// 只记录按钮内开始的触摸。
- (void)onTchDn:(CGPoint)point {
    BOOL active = self.touchActive;
    lb_btntap(&active, [self btntst:point], YES);
    self.touchActive = active;
}

// 仅在按钮内结束有效触摸时触发按钮动作。
- (void)onTchUp:(CGPoint)point {
    BOOL active = self.touchActive;
    BOOL fire = lb_btntap(&active, [self btntst:point], NO);
    self.touchActive = active;
    if (fire) [self.closeButton sendActionsForControlEvents:UIControlEventTouchUpInside];
}

// 取消触摸并清除按钮按下状态。
- (void)onTchCn {
    BOOL active = self.touchActive;
    lb_btntap(&active, NO, NO);
    self.touchActive = active;
}

// 监听共享配置与预览事件。
- (void)startMon {
    __weak typeof(self) weakSelf = self;
    if (notify_register_dispatch(LB_CFG_NOTE, &_configToken, dispatch_get_main_queue(), ^(__unused int token) {
        [weakSelf loadCfg];
    }) != NOTIFY_STATUS_OK) exit(EXIT_FAILURE);
    if (notify_register_dispatch(LB_TEST_NOTE, &_testToken, dispatch_get_main_queue(), ^(__unused int token) {
        [weakSelf forceTest];
    }) != NOTIFY_STATUS_OK) exit(EXIT_FAILURE);
    [self loadCfg];
    notify_post(LB_READY_NOTE);
}

// 同步服务停用配置。
- (void)loadCfg {
    if (![lb_ldcfg()[@"enabled"] boolValue]) notify_post(LB_STOP_NOTE);
}

// 显示手动预览并确认就绪。
- (void)forceTest {
    if (![lb_ldcfg()[@"enabled"] boolValue]) return;
    if (self.hudWindow.hidden) self.touchActive = NO;
    self.hudWindow.hidden = NO;
    notify_post(LB_READY_NOTE);
}

// 注销共享通知。
- (void)dealloc {
    if (_configToken >= 0) notify_cancel(_configToken);
    if (_testToken >= 0) notify_cancel(_testToken);
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
    window.windowLevel = 10000010.0;
    window.alpha = 0.0;
    window.hidden = NO;
    [window makeKeyAndVisible];
    [[window _boundContext] setSecure:YES];

    Class hostClass = objc_getClass("SBSAccessibilityWindowHostingController");
    if (!hostClass) return NO;
    _hostingController = [[hostClass alloc] init];
    SEL registerSelector = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
    if (![_hostingController respondsToSelector:registerSelector]) return NO;
    unsigned int contextId = [window _contextId];
    double level = window.windowLevel;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:"v@:Id"];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:_hostingController];
    [invocation setSelector:registerSelector];
    [invocation setArgument:&contextId atIndex:2];
    [invocation setArgument:&level atIndex:3];
    [invocation invoke];

    window.alpha = 1.0;
    window.hidden = YES;
    self.window = window;
    _controller.hudWindow = window;
    [_controller startMon];
    return YES;
}

@end

// 打开运行 HUD 所需的私有框架。
static BOOL lb_ldfw(void) {
    const char *frameworks[] = {
        "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices",
        "/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
    };
    for (size_t index = 0; index < sizeof(frameworks) / sizeof(frameworks[0]); index++) {
        if (!dlopen(frameworks[index], RTLD_NOW | RTLD_GLOBAL)) return NO;
    }
    return YES;
}

// 获取无参数私有函数。
static void (*lb_fn0(const char *name))(void) {
    return (void (*)(void))dlsym(RTLD_DEFAULT, name);
}

static int lb_lockfd = -1;
static dispatch_source_t lb_exesrc;

// 在 App 可执行文件被删除时退出 HUD。
static void lb_monexe(void) {
    char path[PATH_MAX];
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) return;
    int handle = open(path, O_EVTONLY);
    if (handle < 0) return;

    lb_exesrc = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, handle, DISPATCH_VNODE_DELETE, dispatch_get_main_queue());
    dispatch_source_set_event_handler(lb_exesrc, ^{
        close(handle);
        exit(EXIT_SUCCESS);
    });
    dispatch_resume(lb_exesrc);
}

// 运行全局 HUD 进程。
int lb_hudmain(void) {
    lb_lockfd = lb_lckhud();
    if (lb_lockfd < 0) return EXIT_FAILURE;
    lb_monexe();

    int stopToken = 0;
    notify_register_dispatch(LB_STOP_NOTE, &stopToken, dispatch_get_main_queue(), ^(__unused int token) {
        exit(EXIT_SUCCESS);
    });
    int springBoardToken = 0;
    notify_register_dispatch("SBSpringBoardDidLaunchNotification", &springBoardToken, dispatch_get_main_queue(), ^(__unused int token) {
        flock(lb_lockfd, LOCK_UN);
        close(lb_lockfd);
        lb_lockfd = -1;
        lb_spawn();
        exit(EXIT_SUCCESS);
    });

    if (!lb_ldfw()) return EXIT_FAILURE;
    void (*gsInit)(void) = lb_fn0("GSInitialize");
    void (*bksStart)(void) = lb_fn0("BKSDisplayServicesStart");
    void (*uiInit)(void) = lb_fn0("UIApplicationInitialize");
    void (*uiSingle)(Class) = (void (*)(Class))dlsym(RTLD_DEFAULT, "UIApplicationInstantiateSingleton");
    if (!gsInit || !bksStart || !uiInit || !uiSingle) return EXIT_FAILURE;

    [UIScreen initialize];
    CFRunLoopGetCurrent();
    gsInit();
    bksStart();
    uiInit();
    uiSingle([LBHudApp class]);

    LBHudDel *delegate = [[LBHudDel alloc] init];
    UIApplication *app = UIApplication.sharedApplication;
    app.delegate = delegate;
    [app _accessibilityInit];

    // 预加载无障碍事件解析类（必须在回调注册前就绪）。
    lb_ldax();

    // 注册全局 HID 触摸回调——必须在 __completeAndRunAsPlugin 之前，
    // 与 TrollSpeed/HUDApp.mm 保持完全一致的初始化顺序。
    void (*pBKSHID)(void (*)(void *, void *, void *, void *)) =
        (void (*)(void (*)(void *, void *, void *, void *)))dlsym(RTLD_DEFAULT, "BKSHIDEventRegisterEventCallback");
    if (pBKSHID) pBKSHID(lb_onhidevt);

    // iOS 15+ 需要额外初始化 GSEvent RunLoop 模式才能正常路由 BKS 事件。
    void (*gsEvtInit)(int) = (void (*)(int))dlsym(RTLD_DEFAULT, "GSEventInitialize");
    void (*gsEvtPush)(CFStringRef) = (void (*)(CFStringRef))dlsym(RTLD_DEFAULT, "GSEventPushRunLoopMode");
    if (gsEvtInit && gsEvtPush) {
        gsEvtInit(0);
        gsEvtPush(kCFRunLoopDefaultMode);
    }

    [app __completeAndRunAsPlugin];
    CFRunLoopRun();
    return EXIT_SUCCESS;
}
