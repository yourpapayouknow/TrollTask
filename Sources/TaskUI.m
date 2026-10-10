#import "LBHead.h"

// 返回主文字或柔和次级文字。
static UIColor *tu_ink(BOOL secondary) {
    return secondary ? [UIColor colorWithRed:163.0/255 green:173.0/255 blue:178.0/255 alpha:1]
        : [UIColor colorWithWhite:244.0/255 alpha:1];
}
// 创建统一青绿文字或图标按钮。
UIButton *tu_btn(NSString *title, NSString *icon, id target, SEL action) {
    UIButton *button = lb_mkbtn(title, target, action);
    UIButtonConfiguration *config = button.configuration;
    config.baseBackgroundColor = UIColor.clearColor; config.baseForegroundColor = lb_acnt();
    config.image = icon ? lb_icon(icon) : nil; config.imagePadding = 4;
    button.configuration = config; button.tintColor = lb_acnt();
    button.contentHorizontalAlignment = title.length ? UIControlContentHorizontalAlignmentLeading : UIControlContentHorizontalAlignmentCenter;
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    return button;
}
// 设置图标按钮可读的辅助功能身份。
static UIButton *tu_ibtn(NSString *icon, NSString *label, NSString *identifier, id target, SEL action) {
    UIButton *button = tu_btn(nil, icon, target, action);
    button.accessibilityLabel = label; button.accessibilityIdentifier = identifier;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES; return button;
}
// 设置统一字体和单行显示边界。
UILabel *tu_lbl(NSString *text) {
    UILabel *label = [UILabel new]; label.text = text;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = tu_ink(NO);
    label.adjustsFontSizeToFitWidth = YES; label.minimumScaleFactor = 0.5;
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    return label;
}

// 创建统一间距的单列内容。
UIStackView *tu_stk(NSArray<UIView *> *views) {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 4;
    return stack;
}
// 将功能标签与可滚动的原生输入按同一行排列。
UIStackView *tu_row(NSString *title, UIView *control) {
    UILabel *label = tu_lbl(title); [label setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    if ([control isKindOfClass:UITextField.class]) [control.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    UIStackView *row = tu_stk(@[label,control]); row.axis = UILayoutConstraintAxisHorizontal; row.alignment = UIStackViewAlignmentCenter;
    [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [control setContentCompressionResistancePriority:[control isKindOfClass:UITextField.class] || [control isKindOfClass:UIDatePicker.class]
        ? UILayoutPriorityDefaultLow : UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal]; return row;
}

// 将内容限定在安全区和最大宽度内。
static void tu_wdth(UIView *content, UIView *parent) {
    content.translatesAutoresizingMaskIntoConstraints = NO;
    NSLayoutConstraint *width = [content.widthAnchor constraintEqualToAnchor:parent.safeAreaLayoutGuide.widthAnchor constant:-8];
    width.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[width,
        [content.widthAnchor constraintLessThanOrEqualToConstant:680],
        [content.centerXAnchor constraintEqualToAnchor:parent.safeAreaLayoutGuide.centerXAnchor],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:parent.safeAreaLayoutGuide.leadingAnchor constant:4],
        [content.trailingAnchor constraintLessThanOrEqualToAnchor:parent.safeAreaLayoutGuide.trailingAnchor constant:-4]]];
}

// 展示短错误提示并保留当前输入。
void tu_err(UIViewController *view, NSError *error) {
    NSLog(@"待办界面操作失败：%@", error);
    NSDictionary *names = @{@"invalid_fields": @"请检查输入", @"not_found": @"任务已删除",
        @"database_busy": @"数据库忙碌", @"duplicate_uuid": @"任务编号重复"};
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:names[error.userInfo[@"kind"]] ?: @"操作失败"
        message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    if (!view.presentedViewController) [view presentViewController:alert animated:YES completion:nil];
}

// 拒绝修改已删除的记录。
static BOOL tu_live(NSDictionary *task, NSError **error) {
    if (!task) return NO;
    if (![task[@"deleted"] boolValue]) return YES;
    if (error) *error = [NSError errorWithDomain:@"com.iwmei.taskforiwmei.ui" code:SQLITE_NOTFOUND
        userInfo:@{@"kind": @"not_found", NSLocalizedDescriptionKey: @"任务已删除"}];
    return NO;
}

// 用系统面板和原生列表承载可选择的菜单项。
@interface TaskMenu : UITableViewController
@property(nonatomic, copy) NSArray<UIAction *> *actions;
@end
@implementation TaskMenu
// 初始化无嵌套卡片的菜单列表。
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.blackColor; self.tableView.separatorColor = UIColor.clearColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 52;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(cls)];
}
// 关闭菜单面板。
- (void)cls { [self dismissViewControllerAnimated:YES completion:nil]; }
// 返回完整的选项数量。
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return self.actions.count; }
// 使用系统完成标记和MingCute图标显示操作状态。
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    (void)table; UIAction *action = self.actions[path.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = UIColor.clearColor;
    UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
    content.text = action.title; content.image = action.image; content.textProperties.numberOfLines = 0;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    content.textProperties.color = action.attributes & UIMenuElementAttributesDisabled ? tu_ink(YES)
        : (action.attributes & UIMenuElementAttributesDestructive ? [UIColor colorWithRed:1 green:138.0/255 blue:128.0/255 alpha:1] : tu_ink(NO));
    content.imageProperties.tintColor = lb_acnt(); content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(4,4,4,4);
    cell.contentConfiguration = content; cell.accessibilityIdentifier = (NSString *)action.identifier;
    cell.accessoryType = action.state == UIMenuElementStateOn ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = lb_acnt(); cell.userInteractionEnabled = !(action.attributes & UIMenuElementAttributesDisabled); return cell;
}
// 在面板关闭后执行选中操作。
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES]; UIAction *action = self.actions[path.row];
    if (action.attributes & UIMenuElementAttributesDisabled) return;
    [self dismissViewControllerAnimated:YES completion:^{
        UIButton *sender = [UIButton buttonWithConfiguration:UIButtonConfiguration.plainButtonConfiguration primaryAction:action];
        [sender sendActionsForControlEvents:UIControlEventTouchUpInside];
    }];
}
@end

// 配置iPhone底部面板和iPad系统自适应面板。
void tu_sheet(UIViewController *parent, UIViewController *content) {
    content.modalPresentationStyle = UIModalPresentationPageSheet;
    content.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; content.view.tintColor = lb_acnt();
    content.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    if (@available(iOS 16.0,*)) if (content.preferredContentSize.height > 0) {
        CGFloat height = content.preferredContentSize.height;
        content.sheetPresentationController.detents = @[[UISheetPresentationControllerDetent customDetentWithIdentifier:@"content"
            resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) { return MIN(height,context.maximumDetentValue); }],UISheetPresentationControllerDetent.largeDetent];
    }
    content.sheetPresentationController.prefersGrabberVisible = YES;
    [parent presentViewController:content animated:YES completion:nil];
}
// 构建原生菜单选项。
static UIAction *tu_act(NSString *title, NSString *icon, NSString *identifier, void (^work)(void)) {
    return [UIAction actionWithTitle:title image:icon ? lb_icon(icon) : nil identifier:(UIActionIdentifier)identifier
        handler:^(__unused UIAction *action) { work(); }];
}
// 打开可滚动的功能菜单。
static void tu_menu(UIViewController *parent, NSString *title, NSArray<UIAction *> *actions) {
    TaskMenu *menu = [[TaskMenu alloc] initWithStyle:UITableViewStylePlain]; menu.actions = actions; menu.title = title;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:menu];
    nav.view.tintColor = lb_acnt(); tu_sheet(parent, nav);
}
// 使用原生确认对话框执行删除操作。
static void tu_cfrm(UIViewController *parent, NSString *title, void (^work)(void)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { work(); }]];
    [parent presentViewController:alert animated:YES completion:nil];
}

// 复用安全区、最大宽度和系统键盘避让的滚动表单。
UIScrollView *tu_form(UIViewController *parent, UIStackView *fields, NSString *identifier) {
    UIScrollView *scroll = [UIScrollView new]; scroll.accessibilityIdentifier = identifier;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive; [parent.view addSubview:scroll]; tu_wdth(scroll, parent.view);
    fields.translatesAutoresizingMaskIntoConstraints = NO; [scroll addSubview:fields];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:parent.view.safeAreaLayoutGuide.topAnchor constant:4],
        [scroll.bottomAnchor constraintEqualToAnchor:parent.view.keyboardLayoutGuide.topAnchor constant:-4],
        [fields.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:4],
        [fields.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-4],
        [fields.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:4],
        [fields.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-4],
        [fields.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-8]]]; return scroll;
}

// 显示勾选、标题及本地日期时间。
@interface TaskCell : UITableViewCell
@property(nonatomic, strong) UIButton *check;
@property(nonatomic, strong) UILabel *title;
@property(nonatomic, strong) UILabel *day;
@property(nonatomic, strong) UILabel *clock;
@property(nonatomic, strong) UIButton *star;
@property(nonatomic, strong) NSLayoutConstraint *titleHeight;
@property(nonatomic, strong) NSLayoutConstraint *dayHeight;
@property(nonatomic, strong) NSLayoutConstraint *clockHeight;
- (void)bnd:(NSDictionary *)task owner:(id)owner;
- (void)sz:(CGFloat)width;
@end

@implementation TaskCell
// 创建统一待办行。
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor; self.selectionStyle = UITableViewCellSelectionStyleNone;
    _check = tu_btn(nil, nil, nil, NULL); _check.translatesAutoresizingMaskIntoConstraints = NO;
    UIButtonConfiguration *config = _check.configuration;
    config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:20];
    _check.configuration = config;
    _title = tu_lbl(nil); _day = tu_lbl(nil); _clock = tu_lbl(nil);
    _title.numberOfLines = 0; _title.adjustsFontSizeToFitWidth = NO;
    _day.textColor = tu_ink(YES); _clock.textColor = tu_ink(YES);
    _day.font = _clock.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _star = tu_btn(nil, @"star", nil, NULL); _star.translatesAutoresizingMaskIntoConstraints = NO;
    _titleHeight = [_title.heightAnchor constraintEqualToConstant:1]; _dayHeight = [_day.heightAnchor constraintEqualToConstant:1]; _clockHeight = [_clock.heightAnchor constraintEqualToConstant:1];
    UIStackView *labels = tu_stk(@[_title, _day, _clock]); labels.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_check]; [self.contentView addSubview:labels]; [self.contentView addSubview:_star];
    [NSLayoutConstraint activateConstraints:@[
        [_check.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:4],
        [_check.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor], [_check.widthAnchor constraintEqualToConstant:44],
        [_check.topAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.topAnchor constant:4],
        [_check.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-4],
        [labels.leadingAnchor constraintEqualToAnchor:_check.trailingAnchor constant:4],
        [labels.trailingAnchor constraintEqualToAnchor:_star.leadingAnchor constant:-4],
        [_star.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-4],
        [_star.centerYAnchor constraintEqualToAnchor:_check.centerYAnchor], [_star.widthAnchor constraintEqualToConstant:44],
        [labels.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        [labels.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-4],_titleHeight,_dayHeight,_clockHeight]];
    return self;
}
// 绑定稳定任务身份与显示内容。
- (void)bnd:(NSDictionary *)task owner:(id)owner {
    BOOL completed = [task[@"status"] isEqual:@"completed"];
    self.check.accessibilityIdentifier = [@"task." stringByAppendingString:task[@"task_id"]];
    self.check.accessibilityLabel = completed ? @"恢复待办" : @"完成待办";
    self.check.accessibilityValue = task[@"status"];
    objc_setAssociatedObject(self.check,@selector(tglTsk:),task,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self.check setImage:lb_icon(completed ? @"check_circle" : @"round") forState:UIControlStateNormal];
    self.star.accessibilityIdentifier = [@"star." stringByAppendingString:task[@"task_id"]];
    self.star.accessibilityLabel = [task[@"starred"] boolValue] ? @"取消星标" : @"添加星标";
    self.star.accessibilityValue = [task[@"starred"] boolValue] ? @"1" : @"0";
    [self.star setImage:lb_icon([task[@"starred"] boolValue] ? @"star_fill" : @"star") forState:UIControlStateNormal];
    [self.star removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [self.star addTarget:owner action:@selector(tglStar:) forControlEvents:UIControlEventTouchUpInside];
    [self.check removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    [self.check addTarget:owner action:@selector(tglTsk:) forControlEvents:UIControlEventTouchUpInside];
    self.title.text = task[@"title"]; self.title.accessibilityLabel = task[@"title"];
    UITraitCollection *traits = [(UIViewController *)owner traitCollection];
    self.title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:traits];
    self.day.font = self.clock.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline compatibleWithTraitCollection:traits];
    self.title.textColor = completed ? tu_ink(YES) : tu_ink(NO);
    self.indentationLevel = task[@"parent_id"] == NSNull.null ? 0 : 1; self.indentationWidth = 4;
    id stamp = task[completed ? @"completed_at" : @"remind_at"];
    if (!ts_num(stamp)) stamp = task[@"due_at"];
    if (!ts_num(stamp)) stamp = task[@"deadline_at"];
    self.clock.hidden = !ts_num(stamp);
    self.day.text = @"未设提醒"; self.clock.text = nil;
    if (ts_num(stamp)) {
        NSDateFormatter *format = [NSDateFormatter new]; format.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        format.timeZone = NSTimeZone.localTimeZone; format.dateFormat = @"yyyy-MM-dd";
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:[stamp doubleValue]];
        self.day.text = [format stringFromDate:date]; format.dateFormat = @"HH:mm";
        self.clock.text = [format stringFromDate:date];
    }
}
// 按UIKit文本测量固定行高，避免小数像素造成布局歧义。
- (void)sz:(CGFloat)width {
    _titleHeight.constant = MAX(1,ceil([_title sizeThatFits:CGSizeMake(MAX(1,width-104),CGFLOAT_MAX)].height));
    _dayHeight.constant = ceil(_day.font.lineHeight); _clockHeight.constant = _clock.hidden ? 0 : ceil(_clock.font.lineHeight);
}
@end

@implementation TaskHome {
    TaskStore *_store;
    void (^_settings)(UINavigationController *);
    UITableView *_table;
    UIButton *_empty;
    NSArray *_pending, *_completed;
    NSArray *_allPnd, *_allCmpl, *_lists;
    UIStackView *_tabs;
    NSLayoutConstraint *_tabHeight;
    NSString *_listID, *_sort;
    dispatch_queue_t _queue;
    NSMutableSet *_busy;
    NSUInteger _load;
    int _token;
    BOOL _expanded, _loaded, _failed;
}
// 注入共享存储和设置入口。
- (instancetype)initWithStore:(TaskStore *)store settings:(void (^)(UINavigationController *))settings {
    self = [super init]; if (!self) return nil;
    _store = store; _settings = [settings copy]; _pending = @[]; _completed = @[];
    _busy = [NSMutableSet set]; _queue = dispatch_queue_create("com.iwmei.taskforiwmei.home", DISPATCH_QUEUE_SERIAL);
    _token = -1; _listID = TS_DFLT_LST; _sort = @"date"; _lists = @[]; return self;
}
// 创建安全区内的列表和新建入口。
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"待办"; self.view.backgroundColor = UIColor.blackColor; self.view.tintColor = lb_acnt();
    UINavigationBarAppearance *bar = [UINavigationBarAppearance new]; [bar configureWithOpaqueBackground];
    bar.backgroundColor = UIColor.blackColor; bar.titleTextAttributes = @{NSForegroundColorAttributeName:tu_ink(NO)};
    self.navigationController.navigationBar.standardAppearance = bar; self.navigationController.navigationBar.scrollEdgeAppearance = bar;
    self.navigationController.navigationBar.tintColor = lb_acnt();
    UIButton *settings = tu_ibtn(@"settings", @"后台设置", @"home.settings", self, @selector(sttng));
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:settings];
    UIButton *create = tu_ibtn(@"add", @"新建待办", @"home.create", self, @selector(crt));
    UIButtonConfiguration *add = create.configuration; add.baseBackgroundColor = lb_acnt(); add.baseForegroundColor = UIColor.blackColor; create.configuration = add;
    UIButton *lists = tu_ibtn(@"menu", @"选择清单", @"home.lists", self, @selector(lstMenu));
    UIButton *more = tu_ibtn(@"more", @"清单选项", @"home.more", self, @selector(more));
    NSMutableArray *slots = [NSMutableArray array];
    for (UIButton *button in @[lists,create,more]) {
        UIView *slot = [UIView new]; button.translatesAutoresizingMaskIntoConstraints = NO; [slot addSubview:button];
        CGFloat size = button == create ? 60 : 44;
        [NSLayoutConstraint activateConstraints:@[[button.widthAnchor constraintEqualToConstant:size],[button.heightAnchor constraintEqualToConstant:size],
            [button.centerXAnchor constraintEqualToAnchor:slot.centerXAnchor],[button.centerYAnchor constraintEqualToAnchor:slot.centerYAnchor],
            [slot.heightAnchor constraintEqualToConstant:60]]]; [slots addObject:slot];
    }
    UIStackView *barView = tu_stk(slots); barView.axis = UILayoutConstraintAxisHorizontal; barView.distribution = UIStackViewDistributionFillEqually;
    [self.view addSubview:barView]; tu_wdth(barView, self.view);
    UIScrollView *tabs = [UIScrollView new]; tabs.showsHorizontalScrollIndicator = NO; tabs.accessibilityIdentifier = @"home.tabs";
    [self.view addSubview:tabs]; tu_wdth(tabs, self.view);
    _tabs = tu_stk(@[]); _tabs.axis = UILayoutConstraintAxisHorizontal; _tabs.translatesAutoresizingMaskIntoConstraints = NO; [tabs addSubview:_tabs];
    [NSLayoutConstraint activateConstraints:@[[_tabs.leadingAnchor constraintEqualToAnchor:tabs.contentLayoutGuide.leadingAnchor],
        [_tabs.trailingAnchor constraintEqualToAnchor:tabs.contentLayoutGuide.trailingAnchor], [_tabs.topAnchor constraintEqualToAnchor:tabs.contentLayoutGuide.topAnchor],
        [_tabs.bottomAnchor constraintEqualToAnchor:tabs.contentLayoutGuide.bottomAnchor], [_tabs.heightAnchor constraintEqualToAnchor:tabs.frameLayoutGuide.heightAnchor]]];
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.accessibilityIdentifier = @"home.list"; _table.backgroundColor = UIColor.clearColor;
    _table.dataSource = self; _table.delegate = self; _table.rowHeight = UITableViewAutomaticDimension;
    _table.estimatedRowHeight = 84; _table.sectionHeaderTopPadding = 0;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone; _table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [_table registerClass:TaskCell.class forCellReuseIdentifier:@"task"];
    [self.view addSubview:_table]; tu_wdth(_table, self.view);
    _tabHeight = [tabs.heightAnchor constraintEqualToConstant:52];
    [NSLayoutConstraint activateConstraints:@[
        [barView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-4],
        [tabs.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4], _tabHeight,
        [_table.topAnchor constraintEqualToAnchor:tabs.bottomAnchor constant:4],
        [_table.bottomAnchor constraintEqualToAnchor:barView.topAnchor constant:-4]]];
    __weak TaskHome *weak = self;
    if (_store) notify_register_dispatch(_store.changeNote.UTF8String, &_token, dispatch_get_main_queue(), ^(__unused int token) { [weak rfrsh]; });
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(rfrsh) name:UIApplicationDidBecomeActiveNotification object:nil];
}
// 返回首页时重新读取共享数据。
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self rfrsh]; }
// 让页签高度随系统动态字体更新。
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    _tabHeight.constant = MAX(52,ceil([UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:self.traitCollection].lineHeight)+8);
}
// 取消通知监听。
- (void)dealloc { if (_token >= 0) notify_cancel(_token); [NSNotificationCenter.defaultCenter removeObserver:self]; }
// 从同一事务快照读取两类任务并防止旧读覆盖。
- (void)rfrsh {
    NSUInteger load = ++_load;
    TaskStore *store = _store;
    dispatch_async(_queue, ^{
        NSError *error = nil;
        TaskStore *active = store ?: [TaskStore shrd:&error];
        __block NSArray *pending = nil, *completed = nil, *lists = nil;
        BOOL ok = [active wrTxn:^BOOL(NSError **failure) {
            pending = [active lsPnd:failure]; if (!pending) return NO;
            completed = [active lsCmpl:failure]; if (!completed) return NO;
            lists = [active lsLsts:failure]; return lists != nil;
        } error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (load != self->_load) return;
            self->_store = active;
            self->_loaded = YES; self->_failed = !ok;
            if (ok) { self->_allPnd = pending; self->_allCmpl = completed; self->_lists = lists; [self fltr]; [self tabs]; }
            else { self->_pending = @[]; self->_completed = @[]; NSLog(@"读取待办失败：%@", error); }
            [self->_table reloadData];
            if (ok && self->_token < 0) {
                __weak TaskHome *weak = self;
                notify_register_dispatch(self->_store.changeNote.UTF8String, &self->_token, dispatch_get_main_queue(), ^(__unused int token) { [weak rfrsh]; });
            }
        });
    });
}
// 打开后台设置。
- (void)sttng { if (_settings) _settings(self.navigationController); }
// 打开快捷草稿面板。
- (void)crt {
    if (!_store || self.presentedViewController) return;
    __weak TaskHome *weak = self;
    NSDictionary *draft = @{@"list_id": [_listID isEqual:@"starred"] ? TS_DFLT_LST : _listID, @"starred": @([_listID isEqual:@"starred"])};
    TaskEdit *editor = [[TaskEdit alloc] initWithStore:_store task:nil draft:draft quick:YES saved:^{ [weak rfrsh]; }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor]; nav.preferredContentSize = editor.preferredContentSize;
    tu_sheet(self, nav);
}
// 在同一读取快照上筛选清单并应用用户排序。
- (void)fltr {
    BOOL starred = [_listID isEqual:@"starred"];
    if (!starred && ![_lists filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"list_id == %@", _listID]].count) _listID = TS_DFLT_LST;
    NSMutableArray *sets[2] = {[NSMutableArray array], [NSMutableArray array]};
    NSArray *all[2] = {_allPnd ?: @[], _allCmpl ?: @[]};
    for (int index = 0; index < 2; index++) for (NSDictionary *task in all[index])
        if ((starred && [task[@"starred"] boolValue]) || (!starred && [task[@"list_id"] isEqual:_listID])) [sets[index] addObject:task];
    if (![_sort isEqual:@"date"]) [sets[0] sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        id av = a[[self->_sort isEqual:@"star"] ? @"starred_at" : @"position"], bv = b[[self->_sort isEqual:@"star"] ? @"starred_at" : @"position"];
        NSComparisonResult order = av == NSNull.null ? (bv == NSNull.null ? NSOrderedSame : NSOrderedDescending)
            : (bv == NSNull.null ? NSOrderedAscending : [av compare:bv]);
        if ([self->_sort isEqual:@"star"] && av != NSNull.null && bv != NSNull.null) order = -order;
        return order == NSOrderedSame ? [a[@"created_at"] compare:b[@"created_at"]] : order;
    }];
    _pending = sets[0]; _completed = sets[1];
}
// 更新横向清单页签及唯一选中状态。
- (void)tabs {
    for (UIView *view in _tabs.arrangedSubviews) { [_tabs removeArrangedSubview:view]; [view removeFromSuperview]; }
    NSUInteger count = [_allPnd filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"starred == 1"]].count;
    NSMutableArray *items = [NSMutableArray arrayWithObject:@{@"list_id":@"starred", @"title":[NSString stringWithFormat:@"%lu",(unsigned long)count]}];
    [items addObjectsFromArray:_lists];
    for (NSDictionary *list in items) {
        BOOL star = [list[@"list_id"] isEqual:@"starred"], selected = [list[@"list_id"] isEqual:_listID];
        UIButton *button = tu_btn(lb_shrt(list[@"title"]), star ? @"star_fill" : nil, self, @selector(selLst:));
        button.accessibilityIdentifier = [@"list." stringByAppendingString:list[@"list_id"]];
        button.accessibilityLabel = star ? @"星标待办" : list[@"title"]; button.accessibilityValue = selected ? @"已选中" : @"未选中";
        UIButtonConfiguration *config = button.configuration; config.baseForegroundColor = selected ? lb_acnt() : tu_ink(YES); button.configuration = config;
        if (selected) button.accessibilityTraits |= UIAccessibilityTraitSelected;
        [_tabs addArrangedSubview:button];
    }
    UIButton *add = tu_btn(@"新建清单", @"add", self, @selector(crtLst)); add.accessibilityIdentifier = @"home.newlist"; [_tabs addArrangedSubview:add];
}
// 切换所选清单而不修改任务数据。
- (void)selLst:(UIButton *)button {
    _listID = [button.accessibilityIdentifier substringFromIndex:5]; _expanded = NO;
    _sort = [NSUserDefaults.standardUserDefaults stringForKey:[NSString stringWithFormat:@"%@.%@.sort", _store.changeNote, _listID]] ?: @"date";
    [_table setEditing:NO animated:NO]; [self fltr]; [self tabs]; [_table reloadData];
}
// 在提交后刷新界面并显示明确错误。
- (void)wrt:(BOOL (^)(NSError **))work {
    dispatch_async(_queue, ^{ NSError *error = nil; BOOL ok = [self->_store wrTxn:work error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ [self rfrsh]; if (!ok) tu_err(self, error); }); });
}
// 保存清单名称并报告结构化错误。
- (void)lstName:(BOOL)create {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:create ? @"新建清单" : @"重命名清单" message:nil preferredStyle:UIAlertControllerStyleAlert];
    NSString *listID = _listID;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"清单名称"; field.accessibilityIdentifier = @"list.name";
        if (!create) for (NSDictionary *list in self->_lists) if ([list[@"list_id"] isEqual:listID]) field.text = list[@"title"]; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text ?: @"";
        [self wrt:^BOOL(NSError **error) { return create ? [self->_store crtLst:name error:error] != nil : [self->_store updLst:listID title:name error:error]; }];
    }]]; [self presentViewController:alert animated:YES completion:nil];
}
// 新建原生任务清单。
- (void)crtLst { [self lstName:YES]; }
// 打开底部清单切换菜单。
- (void)lstMenu {
    NSMutableArray *actions = [NSMutableArray array];
    for (NSDictionary *list in _lists) {
        UIAction *action = tu_act(lb_shrt(list[@"title"]), @"list", list[@"list_id"], ^{
            UIButton *button = [UIButton new]; button.accessibilityIdentifier = [@"list." stringByAppendingString:list[@"list_id"]]; [self selLst:button]; });
        action.state = [list[@"list_id"] isEqual:_listID] ? UIMenuElementStateOn : UIMenuElementStateOff; [actions addObject:action];
    }
    [actions addObject:tu_act(@"新建清单", @"add", @"list.create", ^{ [self crtLst]; })]; tu_menu(self, @"任务清单", actions);
}
// 显示排序、手动顺序、清单维护和清理入口。
- (void)more {
    NSMutableArray *actions = [NSMutableArray array]; NSArray *keys = @[@"manual", @"date", @"star"], *names = @[@"我的顺序", @"日期", @"最近加星时间"];
    for (NSUInteger index = 0; index < keys.count; index++) {
        NSString *key = keys[index]; UIAction *action = tu_act(names[index], @"sort", [@"sort." stringByAppendingString:key], ^{
            self->_sort = key; [NSUserDefaults.standardUserDefaults setObject:key forKey:[NSString stringWithFormat:@"%@.%@.sort", self->_store.changeNote, self->_listID]];
            [self->_table setEditing:NO animated:NO]; [self fltr]; [self->_table reloadData]; });
        action.state = [_sort isEqual:key] ? UIMenuElementStateOn : UIMenuElementStateOff; [actions addObject:action];
    }
    UIAction *reorder = tu_act(@"调整顺序", @"list", @"list.reorder", ^{
        self->_sort = @"manual"; [NSUserDefaults.standardUserDefaults setObject:@"manual" forKey:[NSString stringWithFormat:@"%@.%@.sort", self->_store.changeNote, self->_listID]];
        [self fltr]; [self->_table reloadData]; [self->_table setEditing:!self->_table.editing animated:YES]; });
    if ([_listID isEqual:@"starred"] || !_pending.count) reorder.attributes = UIMenuElementAttributesDisabled; [actions addObject:reorder];
    UIAction *rename = tu_act(@"重命名清单", @"notes", @"list.rename", ^{ [self lstName:NO]; });
    NSString *listID = _listID;
    UIAction *remove = tu_act(@"删除清单", @"delete", @"list.delete", ^{ tu_cfrm(self, @"删除清单及全部任务", ^{ [self wrt:^BOOL(NSError **error) { return [self->_store delLst:listID error:error]; }]; }); });
    remove.attributes = UIMenuElementAttributesDestructive;
    UIAction *clear = tu_act(@"删除所有已完成任务", @"delete", @"list.clear", ^{ tu_cfrm(self, @"删除完成项及子任务", ^{ [self wrt:^BOOL(NSError **error) { return [self->_store clrCmpl:listID error:error]; }]; }); });
    clear.attributes = UIMenuElementAttributesDestructive;
    if ([_listID isEqual:@"starred"]) rename.attributes = remove.attributes = clear.attributes = UIMenuElementAttributesDisabled;
    if ([_listID isEqual:TS_DFLT_LST]) remove.attributes = UIMenuElementAttributesDisabled;
    if (!_completed.count) clear.attributes |= UIMenuElementAttributesDisabled;
    [actions addObjectsFromArray:@[rename, remove, clear]]; tu_menu(self, @"清单选项", actions);
}
// 在事务中保存明确的加星或取消意图。
- (void)tglStar:(UIButton *)button {
    NSString *taskID = [button.accessibilityIdentifier substringFromIndex:5]; NSNumber *starred = @(![button.accessibilityValue isEqual:@"1"]);
    [self wrt:^BOOL(NSError **error) { return tu_live([self->_store rdTsk:taskID error:error], error) && [self->_store updTsk:taskID fields:@{@"starred":starred} error:error]; }];
}
// 在存储可用时进入编辑。
- (void)edt:(NSDictionary *)task {
    if (!_store) { [self rfrsh]; return; }
    __weak TaskHome *weak = self;
    TaskEdit *editor = [[TaskEdit alloc] initWithStore:_store task:task saved:^{ [weak rfrsh]; }];
    [self.navigationController pushViewController:editor animated:YES];
}
// 仅允许未完成任务在同一父任务下调整顺序。
- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path { (void)table; return path.section == 0 && _pending.count && [_sort isEqual:@"manual"]; }
// 隐藏与完成操作重复的原生删除入口。
- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path { (void)table; (void)path; return UITableViewCellEditingStyleNone; }
// 保持子任务的父级身份和清单不变。
- (NSIndexPath *)tableView:(UITableView *)table targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    (void)table;
    if (to.section != 0 || to.row >= (NSInteger)_pending.count || ![_pending[from.row][@"parent_id"] isEqual:_pending[to.row][@"parent_id"]]) return from;
    return to;
}
// 在事务中保存排序，提交失败恢复数据库中的原顺序。
- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSMutableArray *order = [_pending mutableCopy]; NSDictionary *task = order[from.row]; [order removeObjectAtIndex:from.row]; [order insertObject:task atIndex:to.row];
    [table reloadData];
    [self wrt:^BOOL(NSError **error) {
        for (NSUInteger index = 0; index < order.count; index++) {
            NSString *uuid = order[index][@"task_id"];
            if (!tu_live([self->_store rdTsk:uuid error:error],error) || ![self->_store updTsk:uuid fields:@{@"position":@(index)} error:error]) return NO;
        } return YES;
    }];
}
// 展开或折叠已完成区。
- (void)fld { _expanded = !_expanded; [_table reloadData]; }
// 重试读取或通过空态新建。
- (void)empt { if (!_loaded) return; if (_failed) [self rfrsh]; else [self crt]; }
// 在提交成功后更新完成状态。
- (void)tglTsk:(UIButton *)button {
    NSString *taskID = [button.accessibilityIdentifier substringFromIndex:5];
    BOOL restore = [button.accessibilityValue isEqual:@"completed"];
    NSDictionary *display = objc_getAssociatedObject(button,@selector(tglTsk:));
    if ([_busy containsObject:taskID]) return;
    [_busy addObject:taskID]; button.enabled = NO;
    dispatch_async(_queue, ^{
        NSError *error = nil;
        BOOL ok = [self->_store wrTxn:^BOOL(NSError **failure) {
            NSDictionary *task = [self->_store rdTsk:taskID error:failure];
            if (!tu_live(task, failure)) return NO;
            NSNumber *cycle = ts_num(display[@"next_cycle_at"]) ? display[@"next_cycle_at"] : nil;
            return restore ? [self->_store rstrTsk:taskID error:failure]
                : [self->_store cmplNxt:taskID cycle:cycle generation:cycle ? display[@"reminder_version"] : nil error:failure];
        } error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_busy removeObject:taskID]; [self rfrsh];
            if (!ok) tu_err(self, error);
        });
    });
}
// 将两类任务分区。
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { (void)table; return 2; }
// 折叠完成区并在无待办时提供空态。
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; return section == 0 ? MAX((NSInteger)_pending.count, 1) : (_expanded ? _completed.count : 0);
}
// 绑定任务行或功能性空态。
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0 && !_pending.count) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.backgroundColor = UIColor.clearColor; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        _empty = tu_btn(_failed ? @"读取失败" : (_loaded ? @"暂无待办" : @"正在读取"), nil, self, @selector(empt));
        _empty.enabled = _loaded; _empty.accessibilityIdentifier = @"home.empty";
        _empty.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:_empty];
        [NSLayoutConstraint activateConstraints:@[
            [_empty.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:4],
            [_empty.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-4],
            [_empty.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
            [_empty.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4]]];
        return cell;
    }
    TaskCell *cell = [table dequeueReusableCellWithIdentifier:@"task" forIndexPath:path];
    NSDictionary *task = (path.section == 0 ? _pending : _completed)[path.row];
    [cell bnd:task owner:self]; [cell sz:table.bounds.size.width]; cell.check.enabled = ![_busy containsObject:task[@"task_id"]]; return cell;
}
// 显示唯一的完成区展开入口。
- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    (void)table; if (!section || !_completed.count) return nil;
    UIButton *fold = tu_btn(@"已完成", nil, self, @selector(fld));
    UIButtonConfiguration *config = fold.configuration;
    config.image = lb_icon(@"down");
    config.imagePadding = 4;
    config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:20];
    fold.configuration = config;
    fold.accessibilityIdentifier = @"home.completed"; fold.accessibilityValue = _expanded ? @"已展开" : @"已折叠"; return fold;
}
// 限定完成区头部触摸高度。
- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    (void)table;
    CGFloat height = [UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:self.traitCollection].lineHeight + 8;
    return section && _completed.count ? MAX(44, ceil(height)) : 0.01;
}
// 点击文字区域进入编辑。
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0 && !_pending.count) { [self empt]; return; }
    [self edt:(path.section == 0 ? _pending : _completed)[path.row]];
}
@end

// 管理独立计划日期和截止日期的原生控件。
@interface TaskDate : NSObject
@property(nonatomic, strong) UIStackView *view;
@property(nonatomic, strong) UISwitch *enabled;
@property(nonatomic, strong) UISwitch *timed;
@property(nonatomic, strong) UIDatePicker *date;
@property(nonatomic, strong) UIDatePicker *time;
@property(nonatomic, strong) UIStackView *fields;
@property(nonatomic) BOOL deadline;
- (instancetype)initWithTask:(NSDictionary *)task deadline:(BOOL)deadline zone:(NSTimeZone *)zone target:(id)target;
- (void)rfrsh;
- (NSDictionary *)fieldsIn:(NSTimeZone *)zone;
@end

@implementation TaskDate
// 创建日期与时间分离的窄屏控件。
- (instancetype)initWithTask:(NSDictionary *)task deadline:(BOOL)deadline zone:(NSTimeZone *)zone target:(id)target {
    self = [super init]; if (!self) return nil;
    _deadline = deadline; NSString *prefix = deadline ? @"deadline" : @"plan";
    NSString *kind = task[deadline ? @"deadline_kind" : @"schedule_kind"];
    _enabled = [UISwitch new]; _enabled.on = kind && ![kind isEqual:@"none"];
    _timed = [UISwitch new]; _timed.on = [kind isEqual:@"timed"];
    _enabled.accessibilityIdentifier = [prefix stringByAppendingString:@".enabled"];
    _timed.accessibilityIdentifier = [prefix stringByAppendingString:@".timed"];
    _enabled.accessibilityLabel = deadline ? @"截止日期" : @"计划日期";
    _timed.accessibilityLabel = deadline ? @"截止时刻" : @"计划时刻";
    UIStackView *enableRow = tu_stk(@[tu_lbl(_enabled.accessibilityLabel), _enabled]); enableRow.axis = UILayoutConstraintAxisHorizontal;
    UIStackView *timeRow = tu_stk(@[tu_lbl(deadline ? @"截止时刻" : @"计划时刻"), _timed]); timeRow.axis = UILayoutConstraintAxisHorizontal;
    for (UIStackView *row in @[enableRow, timeRow]) row.alignment = UIStackViewAlignmentCenter;
    for (UISwitch *toggle in @[_enabled, _timed]) {
        toggle.onTintColor = lb_acnt();
        [toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [toggle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    }
    _date = [UIDatePicker new]; _time = [UIDatePicker new];
    for (UIDatePicker *picker in @[_date, _time]) {
        picker.preferredDatePickerStyle = UIDatePickerStyleCompact; picker.timeZone = zone;
        picker.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        [picker setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [picker addTarget:target action:@selector(dtChg:) forControlEvents:UIControlEventValueChanged];
    }
    _date.datePickerMode = UIDatePickerModeDate; _time.datePickerMode = UIDatePickerModeTime;
    _date.accessibilityIdentifier = [prefix stringByAppendingString:@".date"]; _time.accessibilityIdentifier = [prefix stringByAppendingString:@".time"];
    id stamp = task[deadline ? @"deadline_at" : @"due_at"];
    NSDate *date = ts_num(stamp) ? [NSDate dateWithTimeIntervalSince1970:[stamp doubleValue]] : NSDate.date;
    if (deadline && [kind isEqual:@"date"]) {
        NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = zone;
        date = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:date options:0];
    }
    _date.date = date; _time.date = date;
    _fields = tu_stk(@[_date, timeRow, _time]); _view = tu_stk(@[enableRow, _fields]);
    for (UISwitch *toggle in @[_enabled, _timed]) [toggle addTarget:target action:@selector(dtChg:) forControlEvents:UIControlEventValueChanged];
    [self rfrsh]; return self;
}
// 根据启用状态显示日期及时间。
- (void)rfrsh { _fields.hidden = !_enabled.on; _time.hidden = !_timed.on; }
// 将用户选择转换为原时区中的绝对时间。
- (NSDictionary *)fieldsIn:(NSTimeZone *)zone {
    NSString *key = _deadline ? @"deadline_at" : @"due_at";
    NSString *kind = _deadline ? @"deadline_kind" : @"schedule_kind";
    if (!_enabled.on) return @{key: NSNull.null, kind: @"none"};
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = zone;
    NSDate *date = [calendar startOfDayForDate:_date.date];
    if (_timed.on) {
        NSDateComponents *clock = [calendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:_time.date];
        date = [calendar dateBySettingHour:clock.hour minute:clock.minute second:0 ofDate:date options:0];
    } else if (_deadline) date = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:date options:0];
    return @{key: @(date.timeIntervalSince1970), kind: _timed.on ? @"timed" : @"date"};
}
@end

@implementation TaskEdit {
    TaskStore *_store;
    NSDictionary *_task, *_draft;
    NSMutableDictionary *_extras;
    void (^_saved)(void);
    UITextView *_titleField, *_notes;
    UILabel *_hint;
    TaskDate *_plan, *_deadline;
    NSTimeZone *_zone;
    NSMutableSet *_dirty;
    UIButton *_save, *_notesBtn, *_dateBtn, *_ddlBtn, *_starBtn, *_listBtn, *_repeatBtn, *_subBtn;
    UIStackView *_advanced, *_detail;
    UITextField *_duration, *_timezone;
    BOOL _saving, _quick, _complete, _series;
}
// 注入完整编辑上下文。
- (instancetype)initWithStore:(TaskStore *)store task:(NSDictionary *)task saved:(void (^)(void))saved {
    return [self initWithStore:store task:task draft:nil quick:NO saved:saved];
}
// 复用同一草稿与提交逻辑创建快捷面板。
- (instancetype)initWithStore:(TaskStore *)store task:(NSDictionary *)task draft:(NSDictionary *)draft quick:(BOOL)quick saved:(void (^)(void))saved {
    self = [super init]; if (!self) return nil;
    _store = store; _task = [task copy]; _draft = [draft copy] ?: @{}; _quick = quick; _saved = [saved copy]; _dirty = [NSMutableSet set];
    _extras = [task mutableCopy] ?: [@{@"list_id":TS_DFLT_LST, @"parent_id":NSNull.null, @"starred":@0, @"urgency":@0, @"difficulty":@0,
        @"recurrence_type":@"none", @"recurrence_interval":@1, @"recurrence":@[], @"timezone_id":NSTimeZone.localTimeZone.name} mutableCopy];
    [_extras addEntriesFromDictionary:_draft]; _zone = [NSTimeZone timeZoneWithName:_extras[@"timezone_id"]] ?: NSTimeZone.localTimeZone;
    if (quick) self.preferredContentSize = CGSizeMake(540, 240); return self;
}
// 构建原生轻量详情和可展开的完整选项。
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = _task ? @"任务详情" : @"添加待办";
    self.view.backgroundColor = UIColor.blackColor; self.view.tintColor = lb_acnt();
    _save = tu_btn(@"保存", nil, self, @selector(sv)); _save.accessibilityIdentifier = @"edit.save";
    if (_quick) [self.navigationController setNavigationBarHidden:YES animated:NO];
    if (!_quick) {
        __weak TaskEdit *weak = self;
        UIButton *back = tu_ibtn(@"back",@"返回",@"edit.back",self,@selector(bk));
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:back];
        UIButton *more = tu_ibtn(@"more", @"任务选项", @"edit.menu", nil, NULL);
        NSMutableArray *actions = [NSMutableArray arrayWithObject:tu_act(@"放弃更改", @"close", @"edit.cancel", ^{ [weak cncl]; })];
        if (_task) {
            UIAction *remove = tu_act(@"删除任务", @"delete", @"edit.delete", ^{ TaskEdit *owner = weak; if (owner) tu_cfrm(owner,@"删除任务及子任务", ^{ [weak dl]; }); });
            remove.attributes = UIMenuElementAttributesDestructive; [actions addObject:remove];
            if ([_task[@"recurrence"] count]) [actions addObject:tu_act(@"完成整个系列", @"check_circle", @"edit.series", ^{ TaskEdit *owner = weak; if (!owner) return; owner->_complete = YES; owner->_series = YES; [owner sv]; })];
            [actions addObject:tu_act(@"完成记录", @"list", @"edit.history", ^{ [weak hist]; })];
            if (_task[@"parent_id"] != NSNull.null) [actions addObject:tu_act(@"转为独立任务", @"subtask", @"edit.detach", ^{
                TaskEdit *owner = weak; if (!owner) return; owner->_extras[@"parent_id"] = NSNull.null; [owner->_dirty addObject:@"parent_id"]; })];
        }
        more.menu = [UIMenu menuWithChildren:actions]; more.showsMenuAsPrimaryAction = YES;
        self.navigationItem.rightBarButtonItems = @[[[UIBarButtonItem alloc] initWithCustomView:more]];
    }
    _titleField = [UITextView new]; _titleField.text = _task[@"title"] ?: _draft[@"title"] ?: @""; _titleField.delegate = self;
    _titleField.accessibilityIdentifier = @"edit.title"; _titleField.accessibilityLabel = @"任务标题";
    _titleField.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2]; _titleField.adjustsFontForContentSizeCategory = YES;
    _titleField.textColor = tu_ink(NO); _titleField.backgroundColor = UIColor.clearColor;
    _titleField.textContainerInset = UIEdgeInsetsMake(4,4,4,4); _titleField.textContainer.lineFragmentPadding = 0;
    [_titleField.heightAnchor constraintEqualToConstant:120].active = YES;
    _hint = tu_lbl(@"新建任务"); _hint.textColor = tu_ink(YES); _hint.hidden = _titleField.text.length > 0;
    _hint.translatesAutoresizingMaskIntoConstraints = NO; [_titleField addSubview:_hint];
    [NSLayoutConstraint activateConstraints:@[[_hint.leadingAnchor constraintEqualToAnchor:_titleField.leadingAnchor constant:4],[_hint.topAnchor constraintEqualToAnchor:_titleField.topAnchor constant:4]]];
    _notes = [UITextView new]; _notes.text = _task[@"notes"] ?: _draft[@"notes"] ?: @""; _notes.delegate = self;
    _notes.accessibilityIdentifier = @"edit.notes"; _notes.accessibilityLabel = @"详细信息";
    _notes.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; _notes.adjustsFontForContentSizeCategory = YES;
    _notes.textColor = tu_ink(NO); _notes.backgroundColor = UIColor.clearColor;
    _notes.textContainerInset = UIEdgeInsetsMake(4,4,4,4); _notes.textContainer.lineFragmentPadding = 0;
    [_notes.heightAnchor constraintEqualToConstant:120].active = YES; _notes.hidden = !_notes.text.length;
    _plan = [[TaskDate alloc] initWithTask:_task ?: _draft deadline:NO zone:_zone target:self];
    _deadline = [[TaskDate alloc] initWithTask:_task ?: _draft deadline:YES zone:_zone target:self];
    _notesBtn = tu_btn(_quick ? nil : @"添加详细信息", @"notes", self, @selector(nts)); _notesBtn.accessibilityLabel = @"添加详细信息";
    _notesBtn.accessibilityIdentifier = @"edit.details";
    _dateBtn = tu_btn(nil,@"time",self,@selector(clndr:)); _dateBtn.accessibilityIdentifier = @"edit.date";
    _ddlBtn = tu_btn(nil,@"target",self,@selector(clndr:)); _ddlBtn.accessibilityIdentifier = @"edit.deadline";
    _starBtn = tu_ibtn(@"star",@"添加星标",@"edit.star",self,@selector(star));
    _listBtn = tu_btn(nil,@"down",self,@selector(lists)); _listBtn.accessibilityIdentifier = @"edit.list";
    _repeatBtn = tu_btn(nil,@"repeat",self,@selector(rpt)); _repeatBtn.accessibilityIdentifier = @"edit.repeat";
    UIButton *sub = tu_btn(@"添加子任务",@"subtask",self,@selector(sub)); sub.accessibilityIdentifier = @"edit.subtask"; sub.hidden = !_task;
    _subBtn = sub;
    _detail = tu_stk(@[_listBtn,_ddlBtn,sub]); _detail.hidden = _quick;
    _duration = [UITextField new]; _duration.keyboardType = UIKeyboardTypeDecimalPad;
    _duration.accessibilityIdentifier = @"edit.duration"; _duration.accessibilityLabel = @"预计分钟";
    if (ts_num(_extras[@"planned_duration"])) _duration.text = [NSString stringWithFormat:@"%.10g",[_extras[@"planned_duration"] doubleValue]/60];
    _timezone = [UITextField new]; _timezone.text = _zone.name;
    _timezone.accessibilityIdentifier = @"edit.timezone"; _timezone.accessibilityLabel = @"时区";
    _timezone.autocorrectionType = UITextAutocorrectionTypeNo; _timezone.autocapitalizationType = UITextAutocapitalizationTypeNone;
    for (UITextField *field in @[_duration,_timezone]) {
        field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; field.adjustsFontForContentSizeCategory = YES;
        field.textColor = tu_ink(NO); [field.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        [field addTarget:self action:@selector(extraChg:) forControlEvents:UIControlEventEditingChanged];
    }
    _advanced = tu_stk(@[_plan.view,_deadline.view,_repeatBtn,[self grade:@"urgency"],[self grade:@"difficulty"],tu_row(@"预计分钟",_duration),tu_row(@"时区",_timezone)]); _advanced.hidden = YES;
    UIButton *extra = tu_btn(@"更多选项",@"down",self,@selector(more)); extra.accessibilityIdentifier = @"edit.more";
    NSMutableArray *fields = [NSMutableArray arrayWithObjects:_titleField,_notes,nil];
    if (!_quick) [fields insertObject:_listBtn atIndex:0];
    if (!_quick) { [_detail removeArrangedSubview:_listBtn]; [_listBtn removeFromSuperview]; [fields addObjectsFromArray:@[_notesBtn,_dateBtn,_detail]]; }
    else { [fields addObjectsFromArray:@[_detail,extra,_advanced]]; }
    if (!_quick) [fields addObjectsFromArray:@[extra,_advanced]];
    UIScrollView *scroll = tu_form(self,tu_stk(fields),@"edit.form");
    UIView *footer;
    if (_quick) {
        UIButton *cancel = tu_ibtn(@"close",@"取消",@"edit.cancel",self,@selector(cncl));
        footer = tu_stk(@[cancel,_notesBtn,_dateBtn,_starBtn,_save]); [(UIStackView *)footer setAxis:UILayoutConstraintAxisHorizontal];
        [(UIStackView *)footer setDistribution:UIStackViewDistributionFillEqually];
    } else {
        UIButton *complete = tu_btn([_task[@"status"] isEqual:@"completed"] ? @"恢复待办" : @"标记为已完成",@"check_circle",self,@selector(cmpl));
        complete.accessibilityIdentifier = @"edit.complete"; complete.hidden = !_task;
        UIStackView *row = tu_stk(@[complete,_save]); row.axis = UILayoutConstraintAxisHorizontal; footer = row;
        self.navigationItem.rightBarButtonItems = [self.navigationItem.rightBarButtonItems arrayByAddingObject:[[UIBarButtonItem alloc] initWithCustomView:_starBtn]];
    }
    [self.view addSubview:footer]; tu_wdth(footer,self.view);
    for (NSLayoutConstraint *constraint in self.view.constraints) if (constraint.firstItem == scroll && constraint.firstAttribute == NSLayoutAttributeBottom) constraint.active = NO;
    [NSLayoutConstraint activateConstraints:@[[footer.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor constant:-4],
        [scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-4]]];
    [self rfrshDtl]; if (_quick) _save.enabled = _titleField.text.length > 0;
    if (_task) [self children:sub];
    _repeatBtn.enabled = _extras[@"parent_id"] == NSNull.null && _detail.arrangedSubviews.lastObject == sub;
    sub.enabled = ![_extras[@"recurrence"] count];
    if (!_quick && _notes.text.length) _notesBtn.hidden = YES;
}
// 在快捷面板显示后使用系统键盘输入标题。
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; if (_quick && !_titleField.text.length) [_titleField becomeFirstResponder]; }
// 返回详情时重读子任务入口并保留当前编辑草稿。
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if (_task && _subBtn) [self children:_subBtn]; }
// 创建紧急程度或难度的原生选择菜单。
- (UIButton *)grade:(NSString *)key {
    NSString *label = [key isEqual:@"urgency"] ? @"紧急程度" : @"难易程度";
    NSArray *titles = [key isEqual:@"urgency"] ? @[@"未设置",@"低",@"中",@"高"] : @[@"未评估",@"简单",@"一般",@"困难"];
    UIButton *button = tu_btn([NSString stringWithFormat:@"%@：%@",label,titles[[_extras[key] unsignedIntegerValue]]],@"down",nil,NULL);
    button.accessibilityIdentifier = [@"edit." stringByAppendingString:key]; NSMutableArray *actions = [NSMutableArray array];
    __weak UIButton *weak = button; __weak TaskEdit *editor = self;
    for (NSUInteger index = 0; index < titles.count; index++) {
        UIAction *action = [UIAction actionWithTitle:titles[index] image:nil identifier:[NSString stringWithFormat:@"edit.%@.%lu",key,(unsigned long)index] handler:^(__unused UIAction *item) {
            TaskEdit *owner = editor; if (!owner) return;
            owner->_extras[key] = @(index); [owner->_dirty addObject:key]; [weak setTitle:[NSString stringWithFormat:@"%@：%@",label,titles[index]] forState:UIControlStateNormal];
            for (UIAction *entry in weak.menu.children) entry.state = [entry.title isEqual:titles[index]] ? UIMenuElementStateOn : UIMenuElementStateOff;
        }]; action.state = [_extras[key] unsignedIntegerValue] == index ? UIMenuElementStateOn : UIMenuElementStateOff; [actions addObject:action];
    }
    button.menu = [UIMenu menuWithChildren:actions]; button.showsMenuAsPrimaryAction = YES; return button;
}
// 显示简短日期状态及独立星标状态。
- (void)rfrshDtl {
    [self->_starBtn setImage:lb_icon([_extras[@"starred"] boolValue] ? @"star_fill" : @"star") forState:UIControlStateNormal];
    _starBtn.accessibilityLabel = [_extras[@"starred"] boolValue] ? @"取消星标" : @"添加星标";
    NSArray *dates = @[_plan,_deadline], *buttons = @[_dateBtn,_ddlBtn];
    for (NSUInteger index = 0; index < dates.count; index++) {
        TaskDate *value = dates[index]; UIButton *button = buttons[index]; NSString *text = index ? @"添加截止期限" : @"添加日期/时间";
        if (value.enabled.on) {
            NSDateFormatter *format = [NSDateFormatter new]; format.timeZone = NSTimeZone.localTimeZone;
            format.dateFormat = value.timed.on ? @"MM-dd HH:mm" : @"yyyy-MM-dd";
            NSDictionary *fields = [value fieldsIn:_zone]; NSNumber *stamp = fields[index ? @"deadline_at" : @"due_at"];
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:stamp.doubleValue];
            if (index && !value.timed.on) { NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = _zone; date = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:date options:0]; format.timeZone = _zone; }
            text = [format stringFromDate:date];
        }
        if (_quick && !index) { [button setTitle:nil forState:UIControlStateNormal]; button.accessibilityLabel = text; }
        else [button setTitle:text forState:UIControlStateNormal];
    }
    [_repeatBtn setTitle:[self rptTitle] forState:UIControlStateNormal];
    for (NSDictionary *list in [_store lsLsts:nil]) if ([list[@"list_id"] isEqual:_extras[@"list_id"]]) [_listBtn setTitle:lb_shrt(list[@"title"]) forState:UIControlStateNormal];
}
// 返回重复类型的中文功能标签。
- (NSString *)rptTitle {
    NSString *type = _extras[@"recurrence_type"], *unit = @{@"daily":@"天",@"weekly":@"周",@"monthly":@"月",@"yearly":@"年"}[type];
    if (unit && [_extras[@"recurrence_interval"] longLongValue] > 1) return [NSString stringWithFormat:@"每%@%@",_extras[@"recurrence_interval"],unit];
    return @{@"none":@"不重复",@"daily":@"每天",@"weekly":@"每周",@"monthly":@"每月",@"yearly":@"每年",@"custom":@"完整重复规则"}[type] ?: @"不重复";
}
// 展开完整字段并让系统面板扩展到最大高度。
- (void)more { _advanced.hidden = !_advanced.hidden; _detail.hidden = NO;
    if (_quick) { UISheetPresentationController *sheet = self.navigationController.sheetPresentationController ?: self.sheetPresentationController;
        [sheet animateChanges:^{ sheet.selectedDetentIdentifier = UISheetPresentationControllerDetentIdentifierLarge; }]; } }
// 显示详细信息输入。
- (void)nts { _notes.hidden = NO; if (!_quick) _notesBtn.hidden = YES; [_notes becomeFirstResponder]; }
// 记录标题或备注，快捷保存仅对非空标题启用。
- (void)textViewDidChange:(UITextView *)view {
    [_dirty addObject:view == _titleField ? @"title" : @"notes"]; _hint.hidden = _titleField.text.length > 0;
    if (_quick) _save.enabled = [[_titleField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length] > 0;
}
// 记录独立计划或截止日期变化。
- (void)dtChg:(UIControl *)control {
    BOOL plan = control == _plan.enabled || control == _plan.timed || control == _plan.date || control == _plan.time;
    [_dirty addObject:plan ? @"plan" : @"deadline"]; [_plan rfrsh]; [_deadline rfrsh]; [self rfrshDtl];
}
// 记录用户改变的时区和预计投入。
- (void)extraChg:(UITextField *)field {
    NSString *key = field == _timezone ? @"timezone_id" : @"planned_duration"; [_dirty addObject:key];
    if (field == _timezone) {
        _extras[key] = field.text ?: @""; NSTimeZone *zone = [NSTimeZone timeZoneWithName:field.text];
        if (zone && ![zone.name isEqual:_zone.name]) {
            NSCalendar *previous = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; previous.timeZone = _zone;
            NSCalendar *current = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; current.timeZone = zone;
            for (TaskDate *value in @[_plan,_deadline]) {
                NSDate *date = value.date.date;
                if (value.enabled.on && !value.timed.on) {
                    date = [current dateFromComponents:[previous components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:date]];
                    [_dirty addObject:value == _plan ? @"plan" : @"deadline"];
                } else if (value.enabled.on) date = [NSDate dateWithTimeIntervalSince1970:[[value fieldsIn:_zone][value == _plan ? @"due_at" : @"deadline_at"] doubleValue]];
                value.date.timeZone = value.time.timeZone = zone; value.date.date = value.time.date = date;
            }
            _zone = zone; [self rfrshDtl];
        }
    }
    else {
        double minutes = 0; NSScanner *scanner = [NSScanner scannerWithString:field.text];
        _extras[key] = !field.text.length ? NSNull.null : @([scanner scanDouble:&minutes] && scanner.isAtEnd ? minutes*60 : NAN);
    }
}
// 在草稿中切换星标。
- (void)star { _extras[@"starred"] = @(![_extras[@"starred"] boolValue]); [_dirty addObject:@"starred"]; [self rfrshDtl]; }
// 以原生月历编辑日期，旧系统继续使用已有日期控件。
- (void)clndr:(UIButton *)sender {
    TaskDate *value = sender == _ddlBtn ? _deadline : _plan; BOOL deadline = value == _deadline;
    if (@available(iOS 16.0,*)) {
        NSCalendar *local = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; local.timeZone = _zone;
        NSDateComponents *clock = [local components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:value.time.date];
        NSDate *date = [local dateBySettingHour:clock.hour minute:clock.minute second:0 ofDate:value.date.date options:0];
        void (^action)(UIViewController *) = _repeatBtn.enabled ? ^(UIViewController *parent) { [self rptIn:parent]; } : nil;
        TaskCalendar *calendar = [[TaskCalendar alloc] initWithDate:date timed:value.timed.on zone:_zone deadline:deadline
            repeat:[self rptTitle] action:action
            reply:^(NSDate *date, BOOL timed, BOOL clear) {
                value.enabled.on = !clear; value.timed.on = timed;
                if (date) { value.date.date = date; value.time.date = date; }
                if (!deadline && clear) {
                    self->_extras[@"recurrence_type"] = @"none"; self->_extras[@"recurrence_interval"] = @1; self->_extras[@"recurrence"] = @[];
                    [self->_dirty addObjectsFromArray:@[@"recurrence_type",@"recurrence_interval",@"recurrence"]];
                }
                [self dtChg:value.enabled];
            }]; calendar.preferredContentSize = CGSizeMake(540,600); tu_sheet(self,calendar);
    } else { _advanced.hidden = NO; value.enabled.on = YES; [self dtChg:value.enabled]; }
}
// 使用当前草稿日期打开重复设置。
- (void)rptIn:(UIViewController *)parent {
    if (!_plan.enabled.on) { _plan.enabled.on = YES; [self dtChg:_plan.enabled]; }
    NSMutableDictionary *fields = [_extras mutableCopy]; [fields addEntriesFromDictionary:[_plan fieldsIn:_zone]];
    TaskRepeat *repeat = [[TaskRepeat alloc] initWithFields:fields reply:^(NSDictionary *patch) {
        [self->_extras addEntriesFromDictionary:patch]; [self->_dirty addObjectsFromArray:patch.allKeys]; [self rfrshDtl];
        if (@available(iOS 16.0,*)) if ([parent isKindOfClass:TaskCalendar.class]) [(TaskCalendar *)parent rptName:[self rptTitle]];
    }]; tu_sheet(parent,repeat);
}
// 打开详情内的重复设置。
- (void)rpt { [self rptIn:self]; }
// 显示任务清单并保留既有清单移动限制。
- (void)lists {
    NSMutableArray *actions = [NSMutableArray array];
    for (NSDictionary *list in [_store lsLsts:nil]) {
        UIAction *action = tu_act(lb_shrt(list[@"title"]),@"list",list[@"list_id"],^{ self->_extras[@"list_id"] = list[@"list_id"]; [self->_dirty addObject:@"list_id"]; [self rfrshDtl]; });
        action.state = [list[@"list_id"] isEqual:_extras[@"list_id"]] ? UIMenuElementStateOn : UIMenuElementStateOff;
        if (action.state != UIMenuElementStateOn && ([_extras[@"recurrence"] count] || _extras[@"parent_id"] != NSNull.null)) action.attributes = UIMenuElementAttributesDisabled;
        [actions addObject:action];
    } tu_menu(self,@"任务清单",actions);
}
// 显示已有子任务的编辑入口。
- (void)children:(UIButton *)entry {
    __weak TaskEdit *weak = self;
    NSArray *all = [_store lsTsks:nil]; UIStackView *parent = (UIStackView *)entry.superview;
    for (UIView *view in parent.arrangedSubviews.copy) if ([view.accessibilityIdentifier hasPrefix:@"child."]) {
        [parent removeArrangedSubview:view]; [view removeFromSuperview];
    }
    for (NSDictionary *task in all) if (![task[@"deleted"] boolValue] && [task[@"parent_id"] isEqual:_task[@"task_id"]]) {
        UIButton *button = tu_btn(lb_shrt(task[@"title"]),@"subtask",nil,NULL); button.accessibilityLabel = task[@"title"];
        button.accessibilityIdentifier = [@"child." stringByAppendingString:task[@"task_id"]];
        [button addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
            TaskEdit *owner = weak; if (!owner) return;
            NSError *error = nil; NSDictionary *latest = [owner->_store rdTsk:task[@"task_id"] error:&error];
            if (!tu_live(latest,&error)) { [owner children:owner->_subBtn]; tu_err(owner,error); return; }
            TaskEdit *edit = [[TaskEdit alloc] initWithStore:owner->_store task:latest saved:owner->_saved]; [owner.navigationController pushViewController:edit animated:YES];
        }] forControlEvents:UIControlEventTouchUpInside]; [parent addArrangedSubview:button];
    }
    _repeatBtn.enabled = _extras[@"parent_id"] == NSNull.null && parent.arrangedSubviews.lastObject == entry;
}
// 添加同一清单中的子任务草稿。
- (void)sub {
    if (!_task) return;
    TaskEdit *editor = [[TaskEdit alloc] initWithStore:_store task:nil draft:@{@"list_id":_extras[@"list_id"],@"parent_id":_task[@"task_id"]} quick:YES saved:^{
        if (self->_saved) self->_saved(); [self children:self->_subBtn];
    }]; UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor]; nav.preferredContentSize = editor.preferredContentSize; tu_sheet(self,nav);
}
// 读取本任务的已处理记录。
- (void)hist {
    NSMutableArray *actions = [NSMutableArray array]; NSDateFormatter *format = [NSDateFormatter new]; format.dateFormat = @"MM-dd HH:mm"; format.timeZone = NSTimeZone.localTimeZone;
    for (NSDictionary *occ in [_store lsOcc:_task[@"task_id"] error:nil]) if ([occ[@"action"] isEqual:@"complete"]) {
        NSString *date = [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[occ[@"handled_at"] doubleValue]]];
        UIAction *item = tu_act(date,@"check_circle",occ[@"occurrence_id"],^{}); item.attributes = UIMenuElementAttributesDisabled; [actions addObject:item];
    }
    if (!actions.count) { UIAction *empty = tu_act(@"暂无完成记录",nil,@"history.empty",^{}); empty.attributes = UIMenuElementAttributesDisabled; [actions addObject:empty]; }
    tu_menu(self,@"完成记录",actions);
}
// 返回时保存用户修改的字段。
- (void)bk { if (!_dirty.count) [self cncl]; else [self sv]; }
// 取消编辑或关闭快捷面板。
- (void)cncl { if (_saving) return; if (_quick) [self dismissViewControllerAnimated:YES completion:nil]; else [self.navigationController popViewControllerAnimated:YES]; }
// 完成或恢复当前任务，重复任务只完成本次。
- (void)cmpl { _complete = YES; _series = NO; [self sv]; }
// 删除最新任务及其子树，提交后离开详情。
- (void)dl {
    if (_saving) return; _saving = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError *error = nil; BOOL ok = [self->_store delTsk:self->_task[@"task_id"] error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ self->_saving = NO; if (!ok) { tu_err(self,error); return; } if (self->_saved) self->_saved(); [self cncl]; });
    });
}
// 提交明确补丁及完成意图，失败保留全部输入。
- (void)sv {
    if (_saving) return; NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    if (!_task) [fields addEntriesFromDictionary:_draft];
    if (!_task || [_dirty containsObject:@"title"]) fields[@"title"] = _titleField.text ?: @"";
    if (!_task || [_dirty containsObject:@"notes"]) fields[@"notes"] = _notes.text ?: @"";
    if (!_task) fields[@"timezone_id"] = _zone.name;
    if (!_task || [_dirty containsObject:@"plan"]) [fields addEntriesFromDictionary:[_plan fieldsIn:_zone]];
    if (!_task || [_dirty containsObject:@"deadline"]) [fields addEntriesFromDictionary:[_deadline fieldsIn:_zone]];
    for (NSString *key in @[@"list_id",@"parent_id",@"starred",@"urgency",@"difficulty",@"planned_duration",@"timezone_id",@"recurrence_type",@"recurrence_interval",@"recurrence"])
        if ([_dirty containsObject:key]) fields[key] = _extras[key];
    if (!fields.count && !_complete) { [self cncl]; return; }
    BOOL complete = _complete, series = _series; _complete = NO; _series = NO;
    _saving = YES; _save.enabled = NO; self.view.userInteractionEnabled = NO; self.navigationItem.leftBarButtonItem.enabled = NO;
    for (UIBarButtonItem *item in self.navigationItem.rightBarButtonItems) item.enabled = NO;
    [self.view endEditing:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError *error = nil; BOOL ok = [self->_store wrTxn:^BOOL(NSError **failure) {
            if (!self->_task) return [self->_store crtTsk:fields error:failure] != nil;
            NSString *taskID = self->_task[@"task_id"]; NSDictionary *latest = [self->_store rdTsk:taskID error:failure];
            if (!tu_live(latest,failure)) return NO;
            if (fields.count && ![self->_store updTsk:taskID fields:fields error:failure]) return NO;
            if (!complete) return YES;
            if ([self->_task[@"status"] isEqual:@"completed"]) return [self->_store rstrTsk:taskID error:failure];
            BOOL changedPlan = fields[@"due_at"] || fields[@"recurrence"] || fields[@"timezone_id"] || fields[@"deadline_at"];
            NSNumber *cycle = !changedPlan && ts_num(self->_task[@"next_cycle_at"]) ? self->_task[@"next_cycle_at"] : nil;
            return series ? [self->_store cmplTsk:taskID error:failure]
                : [self->_store cmplNxt:taskID cycle:cycle generation:cycle ? self->_task[@"reminder_version"] : nil error:failure];
        } error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_saving = NO; self->_save.enabled = YES; self.view.userInteractionEnabled = YES; self.navigationItem.leftBarButtonItem.enabled = YES;
            for (UIBarButtonItem *item in self.navigationItem.rightBarButtonItems) item.enabled = YES;
            if (!ok) { tu_err(self,error); return; } if (self->_saved) self->_saved(); [self cncl];
        });
    });
}
@end
