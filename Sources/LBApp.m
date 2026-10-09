#import "LBHead.h"

@implementation LBApp
@end

@interface LBSetCtl ()
@property(nonatomic, strong) UISwitch *monitorSwitch;
@property(nonatomic, strong) UIButton *previewButton;
@property(nonatomic, assign) BOOL previewPending;
@property(nonatomic, assign) NSInteger previewRequest;
@property(nonatomic, assign) int readyToken;
@end

@implementation LBSetCtl

// 更新功能按钮标题。
- (void)btnstat:(NSString *)title {
    UIButtonConfiguration *config = self.previewButton.configuration;
    config.title = title;
    self.previewButton.configuration = config;
}

// 同步服务开关与预览状态。
- (void)syncUI {
    self.previewButton.enabled = self.monitorSwitch.on && !self.previewPending;
}

// 构建最小服务设置页。
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"TrollTask";
    self.view.backgroundColor = [UIColor colorWithWhite:0.03 alpha:1.0];
    self.readyToken = -1;

    UILabel *label = [[UILabel alloc] init];
    label.text = @"后台服务";
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.textColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.monitorSwitch = [[UISwitch alloc] init];
    self.monitorSwitch.onTintColor = UIColor.systemRedColor;
    self.monitorSwitch.on = [lb_ldcfg()[@"enabled"] boolValue];
    [self.monitorSwitch setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self.monitorSwitch addTarget:self action:@selector(monChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, self.monitorSwitch]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 4.0;
    self.previewButton = lb_mkbtn(@"预览浮层", self, @selector(testTapped));
    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[row, self.previewButton]];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 4.0;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:content];
    NSLayoutConstraint *width = [content.widthAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor constant:-(4.0 + 4.0)];
    width.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:4.0],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-4.0],
        [content.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4.0],
        [content.widthAnchor constraintLessThanOrEqualToConstant:380.0],
        width,
    ]];

    __weak typeof(self) weakSelf = self;
    int token = -1;
    uint32_t result = notify_register_dispatch(LB_READY_NOTE, &token, dispatch_get_main_queue(), ^(__unused int note) {
        typeof(weakSelf) controller = weakSelf;
        if (!controller.previewPending) return;
        controller.previewPending = NO;
        [controller btnstat:@"预览浮层"];
        [controller syncUI];
        notify_post(LB_TEST_NOTE);
    });
    if (result == NOTIFY_STATUS_OK) self.readyToken = token;
    [self syncUI];
}

// 保存服务状态并启停独立HUD。
- (void)monChanged:(UISwitch *)sender {
    self.previewPending = NO;
    self.previewRequest++;
    if (!lb_svcfg(@{@"enabled": @(sender.on)})) {
        sender.on = !sender.on;
        [self btnstat:@"保存失败"];
    } else if (sender.on) {
        if (!lb_spawn()) {
            sender.on = NO;
            lb_svcfg(@{@"enabled": @NO});
            [self btnstat:@"启动失败"];
        } else {
            [self btnstat:@"预览浮层"];
        }
    } else {
        notify_post(LB_STOP_NOTE);
        [self btnstat:@"预览浮层"];
    }
    [self syncUI];
}

// 请求预览并等待HUD就绪。
- (void)testTapped {
    if (self.readyToken < 0) {
        [self btnstat:@"通信失败"];
        return;
    }
    self.previewPending = YES;
    NSInteger request = ++self.previewRequest;
    [self syncUI];
    if (!lb_spawn()) {
        self.previewPending = NO;
        [self btnstat:@"启动失败"];
        [self syncUI];
        return;
    }
    notify_post(LB_TEST_NOTE);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        typeof(weakSelf) controller = weakSelf;
        if (!controller.previewPending || request != controller.previewRequest) return;
        controller.previewPending = NO;
        [controller btnstat:@"预览未响应"];
        [controller syncUI];
    });
}

// 注销HUD就绪通知。
- (void)dealloc {
    if (self.readyToken >= 0) notify_cancel(self.readyToken);
}

@end

@implementation LBAppDel {
    TaskStore *_store;
}

// 创建设置窗口并恢复已启用的HUD服务。
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;
    (void)options;
    NSError *error = nil;
    _store = [TaskStore shrd:&error];
    if (!_store) NSLog(@"TaskStore初始化失败：%@", error);
    LBSetCtl *settings = [[LBSetCtl alloc] init];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible];
    if (_store && [lb_ldcfg()[@"enabled"] boolValue]) lb_spawn();
    return YES;
}

@end
