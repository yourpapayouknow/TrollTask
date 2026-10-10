#import "LBHead.h"

NSString *lb_tstpath;
const char *lb_tstlock;
static UIWindow *ut_window;
static UINavigationController *ut_nav;
static TaskStore *ut_store;
static NSString *ut_docs;
static NSMutableArray *ut_checks;

// 在主线程执行全部UIKit访问。
static void ut_ui(void (^work)(void)) {
    __block NSException *failure = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{ @try { work(); } @catch (NSException *exception) { failure = exception; } });
    if (failure) @throw failure;
}
// 记录断言并保留可读失败原因。
static void ut_req(BOOL valid, NSString *name) {
    if (!valid) [NSException raise:@"UITestFailure" format:@"%@", name];
    [ut_checks addObject:name];
}
// 遍历实际原生控件树。
static UIView *ut_find(UIView *view, NSString *name) {
    if ([view.accessibilityIdentifier isEqual:name]) return view;
    for (UIView *child in view.subviews) { UIView *found = ut_find(child, name); if (found) return found; }
    return nil;
}
// 取得当前系统面板或导航栈中的实际页面。
static UIViewController *ut_top(void) {
    UIViewController *view = ut_nav;
    for (NSUInteger index = 0; index < 12; index++) {
        if (view.presentedViewController) view = view.presentedViewController;
        else if ([view isKindOfClass:UINavigationController.class]) view = [(UINavigationController *)view topViewController];
        else break;
    } return view;
}
// 查找原生菜单中的可操作选项。
static UIAction *ut_action(UIView *view, NSString *name) {
    if ([view isKindOfClass:UIButton.class]) for (UIMenuElement *item in [(UIButton *)view menu].children)
        if ([item isKindOfClass:UIAction.class] && [[(UIAction *)item identifier] isEqual:name]) return (UIAction *)item;
    for (UIView *child in view.subviews) { UIAction *action = ut_action(child,name); if (action) return action; } return nil;
}
// 将点击限定在当前面板及其导航栏。
static UIView *ut_surface(void) { UIViewController *root = ut_top(); return root.navigationController.view ?: root.view; }
// 等待异步数据库和主线程刷新。
static void ut_wait(BOOL (^check)(void), NSString *name) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:8]; __block BOOL found = NO;
    while (!found && end.timeIntervalSinceNow > 0) { ut_ui(^{ found = check(); }); if (!found) usleep(20000); }
    ut_req(found, name);
}
// 点击实际功能按钮。
static void ut_tap(NSString *name) {
    ut_wait(^BOOL {
        UIView *view = ut_find(ut_surface(), name); UIAction *action = ut_action(ut_surface(),name);
        return (([view isKindOfClass:UIButton.class] && [(UIButton *)view isEnabled]) || [view isKindOfClass:UITableViewCell.class] || action)
            && !ut_nav.transitionCoordinator && !ut_top().isBeingPresented && !ut_top().isBeingDismissed;
    }, [@"按钮可点击：" stringByAppendingString:name]);
    ut_ui(^{ UIView *view = ut_find(ut_surface(), name);
        if ([view isKindOfClass:UIButton.class]) [(UIButton *)view sendActionsForControlEvents:UIControlEventTouchUpInside];
        else if ([view isKindOfClass:UITableViewCell.class]) {
            UIView *parent = view.superview; while (parent && ![parent isKindOfClass:UITableView.class]) parent = parent.superview;
            UITableView *table = (UITableView *)parent; [table.delegate tableView:table didSelectRowAtIndexPath:[table indexPathForCell:(UITableViewCell *)view]];
        } else {
            UIAction *action = ut_action(ut_surface(),name); if (!action) [NSException raise:@"UITestFailure" format:@"按钮不可用：%@",name];
            [[UIButton buttonWithConfiguration:UIButtonConfiguration.plainButtonConfiguration primaryAction:action] sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
    });
}
// 取得当前首页的原生列表。
static UITableView *ut_table(void) { return (UITableView *)ut_find(ut_nav.viewControllers.firstObject.view, @"home.list"); }
// 检查可见应用控件在父容器内的水平边界。
static void ut_bounds(UIView *view, UIView *viewport) {
    if (view.hidden) return;
    if ([view.accessibilityIdentifier isEqual:@"home.tabs"]) return;
    for (UIView *child in view.subviews) {
        if (child.hidden) continue;
        if ([child isKindOfClass:UIStackView.class] || [child isKindOfClass:UILabel.class]
            || [child isKindOfClass:UIButton.class] || [child isKindOfClass:UITextField.class]
            || [child isKindOfClass:UITextView.class] || [child isKindOfClass:UISwitch.class]
            || [child isKindOfClass:UIDatePicker.class]) {
            CGRect aligned = [child alignmentRectForFrame:child.frame];
            CGRect visible = [child convertRect:child.bounds toView:viewport];
            BOOL calendar = NO;
            for (UIView *parent = view; parent; parent = parent.superview) if ([parent.accessibilityIdentifier isEqual:@"calendar.month"]) { calendar = YES; break; }
            if ((!calendar && (CGRectGetMinX(aligned) < -1 || CGRectGetMaxX(aligned) > view.bounds.size.width + 1))
                || CGRectGetMinX(visible) < -1 || CGRectGetMaxX(visible) > viewport.bounds.size.width + 1)
                [NSException raise:@"UITestFailure" format:@"控件溢出：%@ %@ 父%@ 宽%.0f 页面%@ 对齐%@ 固有%@", child.class, NSStringFromCGRect(child.frame), view.class, view.bounds.size.width, NSStringFromCGRect(visible), NSStringFromUIEdgeInsets(child.alignmentRectInsets), NSStringFromCGSize(child.intrinsicContentSize)];
            if (!calendar && child.hasAmbiguousLayout) [NSException raise:@"UITestFailure" format:@"布局歧义：%@ %@ 父%@ 内容%@", child.class, NSStringFromCGRect(child.frame), view.class,
                [child isKindOfClass:UILabel.class] ? [(UILabel *)child text] : child.accessibilityIdentifier];
        }
        // 原生文本内部滚动及日期控件内部内容由UIKit负责。
        if ([child isKindOfClass:UIButton.class] && [child.accessibilityIdentifier hasPrefix:@"task."]) {
            UIButton *button = (UIButton *)child;
            CGRect image = [button.imageView convertRect:button.imageView.bounds toView:button];
            if (!CGRectContainsRect(CGRectInset(button.bounds, -0.5, -0.5), image))
                [NSException raise:@"UITestFailure" format:@"勾选图标超出按钮%@", NSStringFromCGRect(image)];
        }
        if ([child isKindOfClass:UITextView.class] || [child isKindOfClass:UITextField.class]
            || [child isKindOfClass:UIDatePicker.class] || [child isKindOfClass:UIButton.class]) continue;
        ut_bounds(child, viewport);
    }
}
// 保存UIKit真实渲染并检查应用控件边界。
static void ut_shot(NSString *name, CGFloat width, CGFloat height, BOOL large) {
    __block CGRect originalFrame;
    __block UIView *container;
    ut_wait(^BOOL { return !ut_nav.transitionCoordinator; }, @"布局检查等待页面转场结束");
    ut_ui(^{
        UIViewController *root = ut_top(); UINavigationController *nav = root.navigationController ?: ut_nav;
        container = root.navigationController ? nav.view : root.view; originalFrame = container.frame;
        if (root.parentViewController == nav) [nav setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:
            large ? UIContentSizeCategoryAccessibilityExtraExtraExtraLarge : UIContentSizeCategoryLarge] forChildViewController:root];
        container.frame = CGRectMake(0, 0, width, height);
        [container setNeedsLayout]; [container layoutIfNeeded]; [root.view layoutIfNeeded];
        UITableView *table = ut_table(); [table reloadData]; [table layoutIfNeeded];
    });
    usleep(50000);
    ut_ui(^{
        UIViewController *root = ut_top(); UINavigationController *nav = root.navigationController ?: ut_nav;
        container.frame = CGRectMake(0,0,width,height); [container layoutIfNeeded]; [root.view layoutIfNeeded];
        ut_req(fabs(root.view.bounds.size.width - width) < 1, @"原生页面达到目标宽度");
        [ut_table() layoutIfNeeded];
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:container.bounds.size];
        NSData *png = [renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *context) {
            [container.layer renderInContext:context.CGContext];
        }];
        [png writeToFile:[ut_docs stringByAppendingPathComponent:[@"screens/" stringByAppendingString:name]] atomically:YES];
        ut_bounds(root.view, root.view);
        if (root.parentViewController == nav) [nav setOverrideTraitCollection:nil forChildViewController:root]; container.frame = originalFrame;
        [container setNeedsLayout]; [container layoutIfNeeded]; [ut_table() reloadData]; [ut_table() layoutIfNeeded];
    });
    ut_req(YES, [@"布局及截图：" stringByAppendingString:name]);
}
// 通过实际输入控件修改标题。
static void ut_title(NSString *title) {
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().isBeingPresented && ut_find(ut_top().view,@"edit.title") != nil; },@"标题输入等待原生面板就绪");
    ut_ui(^{ UITextView *field = (UITextView *)ut_find(ut_top().view, @"edit.title"); field.text = title;
        [field.delegate textViewDidChange:field]; });
}
// 等待返回首页并读取新数据。
static void ut_home(void) { ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskHome.class] && !ut_nav.transitionCoordinator; }, @"保存或取消返回首页"); }
// 验证原生月历、完整字段、排序、星标和子任务入口。
static void ut_refs(void) API_AVAILABLE(ios(16.0));
static void ut_refs(void) {
    ut_ui(^{ [ut_top() dismissViewControllerAnimated:NO completion:nil]; }); ut_tap(@"edit.cancel"); ut_home();
    ut_ui(^{ for (NSString *name in @[@"round",@"star",@"star_fill",@"time",@"calendar",@"add",@"settings"])
        ut_req(lb_icon(name) && lb_icon(name).size.width == 24,@"MingCute原生资源加载"); });
    NSDictionary *list = [ut_store crtLst:@"学习清单" error:nil]; NSString *listID = list[@"list_id"];
    ut_wait(^BOOL { return ut_find(ut_window,[@"list." stringByAppendingString:listID]) != nil; },@"新清单通知刷新页签");
    ut_tap([@"list." stringByAppendingString:listID]); ut_tap(@"home.create"); ut_title(@"完整字段任务");
    ut_tap(@"edit.details"); ut_ui(^{ UITextView *notes = (UITextView *)ut_find(ut_window,@"edit.notes"); notes.text = @"跨天完成记录"; [notes.delegate textViewDidChange:notes]; });
    ut_tap(@"edit.star"); ut_tap(@"edit.more"); ut_tap(@"edit.urgency.3"); ut_tap(@"edit.difficulty.2");
    ut_ui(^{ UITextField *field = (UITextField *)ut_find(ut_window,@"edit.duration"); field.text = @"1500"; [field sendActionsForControlEvents:UIControlEventEditingChanged];
        field = (UITextField *)ut_find(ut_window,@"edit.timezone"); field.text = @"America/New_York"; [field sendActionsForControlEvents:UIControlEventEditingChanged]; });
    ut_tap(@"edit.date"); ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskCalendar.class]; },@"日期入口使用系统月历");
    ut_shot(@"calendar-320.png",320,850,NO); ut_shot(@"calendar-768.png",768,1024,NO);
    ut_ui(^{ UICalendarView *calendar = (UICalendarView *)ut_find(ut_window,@"calendar.month");
        NSDateComponents *parts = [NSDateComponents new]; parts.year = 2026; parts.month = 11; parts.day = 1;
        UICalendarSelectionSingleDate *selection = (UICalendarSelectionSingleDate *)calendar.selectionBehavior;
        [selection setSelectedDate:parts animated:NO]; [(TaskCalendar *)ut_top() dateSelection:selection didSelectDate:parts];
        UISwitch *toggle = (UISwitch *)ut_find(ut_window,@"calendar.timed"); toggle.on = YES; [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        UIDatePicker *time = (UIDatePicker *)ut_find(ut_window,@"calendar.time");
        NSDateFormatter *format = [NSDateFormatter new]; format.timeZone = time.timeZone; format.dateFormat = @"yyyy-MM-dd HH:mm";
        time.date = [format dateFromString:@"2026-11-01 10:30"]; });
    ut_tap(@"calendar.repeat"); ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskRepeat.class]; },@"日期面板可设置重复");
    ut_tap(@"repeat.type.weekly"); ut_tap(@"repeat.day.MO"); ut_tap(@"repeat.day.WE"); ut_tap(@"repeat.end.count");
    ut_ui(^{ UITextField *interval = (UITextField *)ut_find(ut_window,@"repeat.interval"); interval.text = @"2"; [interval sendActionsForControlEvents:UIControlEventEditingChanged];
        UITextField *count = (UITextField *)ut_find(ut_window,@"repeat.count"); count.text = @"7"; [count sendActionsForControlEvents:UIControlEventEditingChanged]; });
    ut_shot(@"repeat-320.png",320,850,NO); ut_shot(@"repeat-768.png",768,1024,NO);
    ut_tap(@"repeat.done"); ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskCalendar.class] && !ut_top().presentedViewController; },@"重复返回日期面板");
    ut_ui(^{ ut_req([[(UIButton *)ut_find(ut_window,@"calendar.repeat") titleForState:UIControlStateNormal] isEqual:@"每2周"],@"日期面板同步重复状态"); });
    ut_tap(@"calendar.done"); ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController; },@"月历返回快捷草稿");
    ut_tap(@"edit.deadline"); ut_tap(@"calendar.done"); ut_tap(@"edit.save"); ut_home();
    NSArray *pending = [ut_store lsPnd:nil]; NSDictionary *task = pending.firstObject; NSString *uuid = task[@"task_id"];
    ut_req([task[@"list_id"] isEqual:listID] && [task[@"timezone_id"] isEqual:@"America/New_York"]
        && [task[@"notes"] isEqual:@"跨天完成记录"] && [task[@"starred"] boolValue]
        && [task[@"urgency"] isEqual:@3] && [task[@"difficulty"] isEqual:@2] && [task[@"planned_duration"] isEqual:@90000],@"完整草稿字段原子保存");
    ut_req([[task[@"recurrence"] firstObject] containsString:@"BYDAY=MO,WE"] && [[task[@"recurrence"] firstObject] containsString:@"COUNT=7"]
        && [task[@"recurrence_interval"] isEqual:@2] && [task[@"deadline_kind"] isEqual:@"date"],@"自定义星期及结束条件保留独立截止");
    ut_tap(@"list.starred"); ut_wait(^BOOL { return ut_find(ut_table(),[@"task." stringByAppendingString:uuid]) != nil; },@"星标清单跨清单显示");
    ut_tap([@"star." stringByAppendingString:uuid]); ut_wait(^BOOL { return ![[ut_store rdTsk:uuid error:nil][@"starred"] boolValue] && ut_find(ut_window,@"home.empty"); },@"取消星标立即移出星标清单");
    ut_tap([@"list." stringByAppendingString:listID]); ut_tap(@"home.more");
    ut_shot(@"sort-320.png",320,850,NO); ut_tap(@"sort.star");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskHome.class]; },@"选择最近加星排序");
    ut_tap(@"home.more"); ut_tap(@"sort.date"); ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskHome.class]; },@"恢复日期排序");
    // 旧画面的重复完成意图不能跳到下一轮。
    ut_ui(^{ UIButton *button = (UIButton *)ut_find(ut_table(),[@"task." stringByAppendingString:uuid]);
        ut_req([ut_store cmplNxt:uuid error:nil],@"后台先完成重复轮次"); [button sendActionsForControlEvents:UIControlEventTouchUpInside]; });
    ut_wait(^BOOL { return [ut_store lsOcc:uuid error:nil].count == 1 && [(UIButton *)ut_find(ut_table(),[@"task." stringByAppendingString:uuid]) isEnabled]; },@"过时重复勾选不推进下一轮");
    NSDictionary *plain = [ut_store crtTsk:@{@"title":@"子任务父级",@"list_id":listID} error:nil];
    ut_wait(^BOOL { return [ut_table() numberOfRowsInSection:0] == 2; },@"新父任务刷新首页");
    ut_ui(^{ NSArray *rows = [ut_store lsPnd:nil]; NSUInteger index = [rows indexOfObjectPassingTest:^BOOL(NSDictionary *row,NSUInteger idx,BOOL *stop) { (void)idx;(void)stop; return [row[@"task_id"] isEqual:plain[@"task_id"]]; }];
        [ut_table().delegate tableView:ut_table() didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]]; });
    ut_tap(@"edit.subtask"); ut_title(@"真实子任务"); ut_tap(@"edit.date");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskCalendar.class]; },@"子任务也使用系统月历");
    ut_ui(^{ ut_req(![(UIButton *)ut_find(ut_surface(),@"calendar.repeat") isEnabled],@"子任务原生月历禁用重复"); });
    ut_tap(@"calendar.clear"); ut_tap(@"edit.save");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && [((UITextView *)ut_find(ut_top().view,@"edit.title")).text isEqual:@"子任务父级"]
        && !ut_top().presentedViewController; },@"子任务保存后回到父级详情");
    NSArray *children = [[ut_store lsTsks:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"parent_id == %@",plain[@"task_id"]]];
    ut_req(children.count == 1 && [children.firstObject[@"list_id"] isEqual:listID],@"子任务保持父级和清单");
    ut_tap([@"child." stringByAppendingString:children.firstObject[@"task_id"]]); ut_title(@"修改子任务"); ut_tap(@"edit.save");
    ut_wait(^BOOL { UIButton *entry = (UIButton *)ut_find(ut_surface(),[@"child." stringByAppendingString:children.firstObject[@"task_id"]]);
        return [entry.titleLabel.text isEqual:@"修改子任务"] && !ut_nav.transitionCoordinator; },@"编辑子任务后父级即时显示新标题");
    ut_tap(@"edit.back"); ut_home();
    ut_tap(@"home.more"); ut_tap(@"list.reorder"); ut_wait(^BOOL { return ut_table().editing; },@"我的顺序启用原生拖动");
    ut_ui(^{ NSIndexPath *from = [NSIndexPath indexPathForRow:0 inSection:0], *to = [NSIndexPath indexPathForRow:1 inSection:0];
        if ([[ut_table().delegate tableView:ut_table() targetIndexPathForMoveFromRowAtIndexPath:from toProposedIndexPath:to] isEqual:to])
            [ut_table().dataSource tableView:ut_table() moveRowAtIndexPath:from toIndexPath:to]; });
    ut_wait(^BOOL { return [[ut_store rdTsk:uuid error:nil][@"position"] isEqual:@1] && [[ut_store rdTsk:children.firstObject[@"task_id"] error:nil][@"position"] isEqual:@2]; },@"原生拖动原子保存顺序");
    ut_tap(@"home.more"); ut_tap(@"sort.date"); ut_wait(^BOOL { return !ut_table().editing; },@"日期排序退出拖动模式");
}
// 运行真实首页、编辑和事务刷新验收。
static void ut_run(void) {
    ut_wait(^BOOL { return ut_find(ut_window, @"home.empty") != nil && [(UIButton *)ut_find(ut_window, @"home.empty") isEnabled]; }, @"空状态可新建");
    ut_shot(@"empty-320.png", 320, 568, NO); ut_tap(@"home.empty");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class]; }, @"空态进入编辑");
    ut_tap(@"edit.cancel"); ut_home(); ut_req([ut_store lsTsks:nil].count == 0, @"取消不创建数据");
    ut_tap(@"home.create"); ut_wait(^BOOL { return ut_find(ut_window, @"edit.title") != nil; }, @"固定新建入口");
    ut_title(@"新建真实任务");
    ut_tap(@"edit.more");
    ut_ui(^{ UISwitch *toggle = (UISwitch *)ut_find(ut_window, @"plan.enabled"); toggle.on = YES; [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        UISwitch *clock = (UISwitch *)ut_find(ut_window, @"plan.timed"); clock.on = YES; [clock sendActionsForControlEvents:UIControlEventValueChanged];
        toggle = (UISwitch *)ut_find(ut_window, @"deadline.enabled"); toggle.on = YES; [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    });
    ut_shot(@"new-320.png", 320, 568, NO); ut_shot(@"new-375.png", 375, 667, NO);
    ut_tap(@"edit.save"); ut_home();
    NSDictionary *created = [ut_store lsPnd:nil].firstObject;
    ut_req([created[@"title"] isEqual:@"新建真实任务"] && [created[@"schedule_kind"] isEqual:@"timed"] && [created[@"deadline_kind"] isEqual:@"date"], @"界面创建日期和独立截止");
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSDictionary *early = [ut_store crtTsk:@{@"title": @"最早提醒", @"due_at": @(now - 172800), @"timezone_id": @"UTC"} error:nil];
    NSDictionary *late = [ut_store crtTsk:@{@"title": @"长标题用于检查窄屏显示和保留全部任务内容", @"due_at": @(now + 86400), @"timezone_id": @"UTC",
        @"notes": @"原始备注", @"starred": @1, @"urgency": @3, @"difficulty": @2, @"planned_duration": @90000,
        @"recurrence_type": @"daily"} error:nil];
    ut_req(early && late, @"测试长标题及高级字段数据有效");
    ut_wait(^BOOL { return [ut_table() numberOfRowsInSection:0] == 3
        && ut_find(ut_table(), [@"task." stringByAppendingString:early[@"task_id"]]) != nil; }, @"Darwin通知自动刷新列表");
    ut_ui(^{ UITableViewCell *cell = [ut_table() cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        UIButton *button = (UIButton *)ut_find(cell, [@"task." stringByAppendingString:early[@"task_id"]]);
        ut_req(button != nil, @"未完成按实际提醒升序显示");
    });
    for (NSNumber *width in @[@320, @375, @390, @768, @1024, @1366]) ut_shot([NSString stringWithFormat:@"home-%@.png", width], width.doubleValue, 850, NO);
    ut_shot(@"home-large-320.png", 320, 850, YES);
    ut_tap([@"task." stringByAppendingString:early[@"task_id"]]);
    ut_wait(^BOOL { return [ut_store lsCmpl:nil].count == 1 && [ut_table() numberOfRowsInSection:1] == 0 && ut_find(ut_table(), @"home.completed") != nil; }, @"勾选提交后移动到折叠完成区");
    ut_tap(@"home.completed");
    ut_wait(^BOOL { return [ut_table() numberOfRowsInSection:1] == 1; }, @"展开已完成");
    ut_shot(@"completed-375.png", 375, 667, NO);
    ut_shot(@"completed-large-320.png", 320, 850, YES);
    ut_ui(^{ [ut_table() scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1] atScrollPosition:UITableViewScrollPositionBottom animated:NO]; });
    ut_tap([@"task." stringByAppendingString:early[@"task_id"]]);
    ut_wait(^BOOL { return [ut_store lsCmpl:nil].count == 0 && [ut_table() numberOfRowsInSection:0] == 3; }, @"勾选已完成恢复待办");
    ut_ui(^{ NSArray *pending = [ut_store lsPnd:nil]; NSUInteger index = [pending indexOfObjectPassingTest:^BOOL(NSDictionary *task, NSUInteger idx, BOOL *stop) {
        (void)idx; (void)stop; return [task[@"task_id"] isEqual:late[@"task_id"]]; }];
        [ut_table().delegate tableView:ut_table() didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];
    });
    ut_wait(^BOOL { return ut_find(ut_window, @"edit.title") != nil; }, @"点击任务进入编辑");
    ut_title(@"修改后保留高级字段");
    for (NSNumber *width in @[@320, @390, @768, @1024]) ut_shot([NSString stringWithFormat:@"edit-%@.png", width], width.doubleValue, 850, NO);
    ut_shot(@"edit-large-320.png", 320, 850, YES);
    ut_tap(@"edit.more"); ut_shot(@"advanced-320.png",320,850,NO); ut_shot(@"advanced-768.png",768,1024,NO);
    ut_shot(@"advanced-large-320.png",320,850,YES);
    ut_ui(^{ [(UITextView *)ut_find(ut_window, @"edit.title") becomeFirstResponder]; });
    ut_wait(^BOOL { UIViewController *root = ut_top();
        return root.view.keyboardLayoutGuide.layoutFrame.size.height > 100; }, @"实际键盘已显示");
    ut_ui(^{ UIViewController *root = ut_top(); UIScrollView *form = (UIScrollView *)ut_find(ut_window, @"edit.form");
        ut_req(CGRectGetMaxY(form.frame) <= CGRectGetMinY(root.view.keyboardLayoutGuide.layoutFrame) + 1, @"编辑滚动区避让键盘"); });
    ut_tap(@"edit.save"); ut_home();
    NSDictionary *changed = [ut_store rdTsk:late[@"task_id"] error:nil];
    ut_req([changed[@"title"] isEqual:@"修改后保留高级字段"] && [changed[@"starred"] isEqual:late[@"starred"]]
        && [changed[@"recurrence"] isEqual:late[@"recurrence"]] && [changed[@"urgency"] isEqual:late[@"urgency"]]
        && [changed[@"difficulty"] isEqual:late[@"difficulty"]] && [changed[@"planned_duration"] isEqual:late[@"planned_duration"]]
        && [changed[@"due_at"] isEqual:late[@"due_at"]] && [changed[@"timezone_id"] isEqual:late[@"timezone_id"]], @"基础修改保留UUID和完整高级字段");
    ut_tap(@"home.create"); ut_wait(^BOOL { return ut_find(ut_window, @"edit.save") != nil; }, @"再次新建");
    ut_title(@"  ");
    ut_ui(^{ ut_req(![(UIButton *)ut_find(ut_window,@"edit.save") isEnabled],@"空标题禁用快捷保存"); });
    ut_title([@"a" stringByPaddingToLength:1025 withString:@"a" startingAtIndex:0]); ut_tap(@"edit.save");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:UIAlertController.class]; }, @"非法标题明确报错");
    ut_req([ut_store lsTsks:nil].count == 3, @"字段非法未写入数据库");
    ut_ui(^{ ut_req([[(UITextView *)ut_find(ut_window, @"edit.title") text] length] == 1025, @"失败保留编辑输入");
        [ut_top() dismissViewControllerAnimated:NO completion:nil]; });
    ut_tap(@"edit.cancel"); ut_home();
    ut_req([ut_store updTsk:early[@"task_id"] fields:@{@"title": @"外部更新可见"} error:nil], @"外部更新提交");
    ut_wait(^BOOL { UITableViewCell *cell = [ut_table() cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        for (UIView *child in cell.contentView.subviews) for (UIView *label in child.subviews)
            if ([label isKindOfClass:UILabel.class] && [[(UILabel *)label text] isEqual:@"外部更新可见"]) return YES;
        return NO; }, @"外部写入通知即时更新文字");
    ut_req([ut_store delTsk:early[@"task_id"] error:nil], @"外部删除提交");
    ut_wait(^BOOL { return [ut_table() numberOfRowsInSection:0] == 2; }, @"删除通知即时移除列表");
    // 在同一主线程事件中模拟后台先完成，用户仍按旧画面勾选。
    ut_ui(^{ UIButton *button = (UIButton *)ut_find(ut_table(), [@"task." stringByAppendingString:created[@"task_id"]]);
        ut_req(button != nil && [button.accessibilityValue isEqual:@"needsAction"], @"取得尚未完成的勾选意图");
        ut_req([ut_store cmplTsk:created[@"task_id"] error:nil], @"后台先完成任务");
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
    ut_wait(^BOOL { return [ut_table() numberOfRowsInSection:0] == 1; }, @"过时勾选没有反向恢复任务");
    ut_ui(^{ [ut_table().delegate tableView:ut_table() didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]]; });
    ut_wait(^BOOL { return ut_find(ut_window, @"edit.title") != nil && !ut_nav.transitionCoordinator; }, @"打开将被后台删除的任务");
    ut_title(@"不应写入已删除任务");
    ut_req([ut_store delTsk:late[@"task_id"] error:nil], @"编辑期间后台删除");
    ut_tap(@"edit.save");
    ut_wait(^BOOL { return [ut_nav.topViewController.presentedViewController isKindOfClass:UIAlertController.class]; }, @"已删除任务保存被拒绝");
    NSDictionary *deleted = [ut_store rdTsk:late[@"task_id"] error:nil];
    ut_req([deleted[@"deleted"] boolValue] && [deleted[@"title"] isEqual:changed[@"title"]], @"失败未复活任务或覆盖标题");
}

// 为真实UIKit测试创建独立数据库和应用窗口。
@interface UITestDel : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation UITestDel
// 创建独立测试应用并在后台驱动主线程交互。
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)app; (void)options;
    ut_docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    [NSFileManager.defaultManager createDirectoryAtPath:[ut_docs stringByAppendingPathComponent:@"screens"] withIntermediateDirectories:YES attributes:nil error:nil];
    lb_tstpath = [ut_docs stringByAppendingPathComponent:@"test.plist"]; lb_tstlock = "/tmp/trolltask-ui.lock";
    NSString *path = [ut_docs stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".sqlite3"]];
    ut_store = [[TaskStore alloc] initAt:path error:nil]; ut_checks = [NSMutableArray array];
    TaskHome *home = [[TaskHome alloc] initWithStore:ut_store settings:nil];
    ut_nav = [[UINavigationController alloc] initWithRootViewController:home]; ut_nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; ut_window = self.window;
    UIViewController *host = [UIViewController new]; self.window.rootViewController = host;
    [host addChildViewController:ut_nav]; ut_nav.view.frame = host.view.bounds;
    [host.view addSubview:ut_nav.view]; [ut_nav didMoveToParentViewController:host];
    [self.window makeKeyAndVisible]; ut_nav.view.frame = self.window.bounds;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            BOOL passed = YES; NSString *failure = @"";
            @try { ut_run(); if (@available(iOS 16.0,*)) ut_refs(); } @catch (NSException *exception) { passed = NO; failure = exception.reason; }
            __block NSString *device, *runtime;
            ut_ui(^{ device = UIDevice.currentDevice.model; runtime = UIDevice.currentDevice.systemVersion; });
            NSDictionary *report = @{@"passed": @(passed), @"failure": failure, @"checks": ut_checks,
                @"device": device, @"runtime": runtime};
            NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
            [data writeToFile:[ut_docs stringByAppendingPathComponent:@"UITestReport.json"] atomically:YES];
            NSLog(@"UITest passed=%d %@", passed, failure);
        }
    }); return YES;
}
@end
// 启动原生UIKit测试，不运行生产HUD或访问共享生产路径。
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(UITestDel.class)); } }
