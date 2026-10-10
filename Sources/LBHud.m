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
@property(nonatomic, strong) UIButton *completeButton;
@property(nonatomic, strong) UIButton *snoozeButton;
@property(nonatomic, weak) UIButton *touchButton;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *kindLabel;
@property(nonatomic, strong) UILabel *timeLabel;
@property(nonatomic, strong) UIStackView *actions;
@property(nonatomic, strong) UIStackView *snoozes;
@property(nonatomic, strong) TaskSched *scheduler;
@property(nonatomic, strong) NSDictionary *alert;
@property(nonatomic, assign) BOOL acting;
- (void)onTchDn:(CGPoint)point;
- (void)onTchUp:(CGPoint)point;
- (void)onTchCn;
- (void)dspAlrt:(NSDictionary *)alert error:(NSError *)error;
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
    card.layer.cornerRadius = 16.0;
    card.layer.masksToBounds = YES;
    card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];

    UIImageView *icon = [[UIImageView alloc] initWithImage:lb_icon(@"list")];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = lb_acnt();
    [icon.heightAnchor constraintEqualToConstant:44.0].active = YES;
    UILabel *title = [[UILabel alloc] init];
    title.text = @"待办提醒";
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    title.textColor = [UIColor colorWithWhite:244.0/255 alpha:1.0];
    title.adjustsFontForContentSizeCategory = YES;
    self.titleLabel = title;
    UILabel *kind = [[UILabel alloc] init];
    kind.textAlignment = NSTextAlignmentCenter;
    kind.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    kind.textColor = title.textColor; kind.adjustsFontForContentSizeCategory = YES;
    kind.hidden = YES; self.kindLabel = kind;
    UILabel *time = [[UILabel alloc] init];
    time.textAlignment = NSTextAlignmentCenter;
    time.font = kind.font; time.textColor = title.textColor; time.adjustsFontForContentSizeCategory = YES;
    time.hidden = YES; self.timeLabel = time;
    UIButton *button = lb_mkbtn(@"收起预览", self, @selector(hdeprvw));
    self.closeButton = button;
    self.completeButton = lb_mkbtn(@"完成任务", self, @selector(cmpTask));
    self.snoozeButton = lb_mkbtn(@"延后提醒", self, @selector(snzMenu));
    self.completeButton.hidden = YES; self.snoozeButton.hidden = YES;
    self.actions = [[UIStackView alloc] initWithArrangedSubviews:@[self.completeButton, self.snoozeButton, button]];
    self.actions.axis = UILayoutConstraintAxisVertical; self.actions.spacing = 4.0;
    self.snoozes = [[UIStackView alloc] init];
    self.snoozes.axis = UILayoutConstraintAxisVertical; self.snoozes.spacing = 4.0; self.snoozes.hidden = YES;
    for (NSNumber *minutes in @[@5, @10, @30, @60]) {
        UIButton *choice = lb_mkbtn([NSString stringWithFormat:@"%@分钟", minutes], self, @selector(snzPick:));
        choice.tag = minutes.integerValue; [self.snoozes addArrangedSubview:choice];
    }
    [self.snoozes addArrangedSubview:lb_mkbtn(@"返回", self, @selector(hdesnz))];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, kind, title, time, self.actions, self.snoozes]];
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
    self.touchButton = nil;
    if (self.alert) { [self wrkAct:@"dismiss" until:nil]; return; }
    self.hudWindow.hidden = YES;
}

// 按真实按钮及其子视图判断触摸命中。
- (UIButton *)btntst:(CGPoint)point {
    UIView *hit = [self.hudWindow hitTest:point withEvent:nil];
    while (hit && ![hit isKindOfClass:UIButton.class]) hit = hit.superview;
    UIButton *button = (UIButton *)hit;
    return button.enabled && !button.hidden ? button : nil;
}

// 只记录按钮内开始的触摸。
- (void)onTchDn:(CGPoint)point {
    BOOL active = self.touchActive;
    self.touchButton = [self btntst:point];
    lb_btntap(&active, self.touchButton != nil, YES);
    self.touchActive = active;
}

// 仅在按钮内结束有效触摸时触发按钮动作。
- (void)onTchUp:(CGPoint)point {
    BOOL active = self.touchActive;
    UIButton *button = self.touchButton;
    BOOL fire = lb_btntap(&active, button && [self btntst:point] == button, NO);
    self.touchActive = active;
    self.touchButton = nil;
    if (fire) [button sendActionsForControlEvents:UIControlEventTouchUpInside];
}

// 取消触摸并清除按钮按下状态。
- (void)onTchCn {
    BOOL active = self.touchActive;
    lb_btntap(&active, NO, NO);
    self.touchActive = active;
    self.touchButton = nil;
}

// 显示数据库核对后的真实提醒并限制标题长度。
- (void)dspAlrt:(NSDictionary *)alert error:(NSError *)error {
    self.acting = NO;
    for (UIButton *button in self.actions.arrangedSubviews) { [button cancelTrackingWithEvent:nil]; button.enabled = YES; }
    for (UIButton *button in self.snoozes.arrangedSubviews) { [button cancelTrackingWithEvent:nil]; button.enabled = YES; }
    self.touchActive = NO; self.touchButton = nil; self.alert = alert;
    self.actions.hidden = NO; self.snoozes.hidden = YES;
    self.completeButton.hidden = !alert; self.snoozeButton.hidden = !alert;
    self.kindLabel.hidden = !alert; self.timeLabel.hidden = !alert;
    [self.closeButton setTitle:alert ? @"关闭提醒" : @"收起预览" forState:UIControlStateNormal];
    if (error) NSLog(@"提醒调度失败：%@", error);
    if (!alert) { self.titleLabel.text = @"待办提醒"; self.hudWindow.hidden = YES; return; }
    NSString *text = alert[@"task"][@"title"];
    self.titleLabel.text = lb_shrt(text);
    self.kindLabel.text = [alert[@"kind"] isEqual:@"plan"] ? @"计划提醒" : ([alert[@"kind"] isEqual:@"deadline"] ? @"截止提醒" : @"合并提醒");
    NSDateFormatter *formatter = [NSDateFormatter new]; formatter.dateFormat = @"MM-dd HH:mm"; formatter.timeZone = NSTimeZone.localTimeZone;
    self.timeLabel.text = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[alert[@"remind_at"] doubleValue]]];
    [self.completeButton setTitle:[alert[@"task"][@"recurrence"] count] ? @"完成本次" : @"完成任务" forState:UIControlStateNormal];
    if (error) [self.closeButton setTitle:@"操作失败" forState:UIControlStateNormal];
    self.hudWindow.hidden = NO;
}

// 完成当前普通任务或重复轮次。
- (void)cmpTask { [self wrkAct:@"complete" until:nil]; }

// 在原卡片内选择延后时长。
- (void)snzMenu { if (self.alert) { self.actions.hidden = YES; self.snoozes.hidden = NO; } }

// 返回当前提醒操作。
- (void)hdesnz { self.actions.hidden = NO; self.snoozes.hidden = YES; }

// 延后当前一次提醒并保留原截止日期。
- (void)snzPick:(UIButton *)button {
    [self wrkAct:@"snooze" until:@(NSDate.date.timeIntervalSince1970 + button.tag * 60)];
}

// 固定操作目标并阻止重复触摸误处理下一条提醒。
- (void)wrkAct:(NSString *)action until:(NSNumber *)until {
    if (!self.alert || self.acting) return;
    self.acting = YES;
    for (UIButton *button in self.actions.arrangedSubviews) button.enabled = NO;
    for (UIButton *button in self.snoozes.arrangedSubviews) button.enabled = NO;
    [self.scheduler act:action until:until occID:self.alert[@"occurrence_id"]];
}

// 监听共享配置与预览事件。
- (void)startMon {
    __weak typeof(self) weakSelf = self;
    NSError *error = nil;
    self.scheduler = [[TaskSched alloc] initStore:[TaskStore shrd:&error] handler:^(NSDictionary *alert, NSError *failure) {
        [weakSelf dspAlrt:alert error:failure];
    }];
    if (error || ![self.scheduler start:&error]) { NSLog(@"调度器启动失败：%@", error); self.scheduler = nil; }
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
    if (self.alert) { notify_post(LB_READY_NOTE); return; }
    [self dspAlrt:nil error:nil];
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
static TaskStore *lb_store;

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
    NSError *error = nil;
    lb_store = [TaskStore shrd:&error];
    if (!lb_store) {
        NSLog(@"TaskStore初始化失败：%@", error);
        close(lb_lockfd);
        lb_lockfd = -1;
        return EXIT_FAILURE;
    }
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
