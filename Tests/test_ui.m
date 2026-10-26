#import "LBHead.h"

NSString *lb_tstpath;
const char *lb_tstlock;
static UIWindow *ut_window;
static UINavigationController *ut_nav;
static TaskStore *ut_store;
static NSString *ut_docs;
static NSMutableArray *ut_checks;
static NSArray<NSString *> *ut_args;
static BOOL ut_spawn = YES;
static TaskReminder *ut_sched;
static NSMutableArray *ut_events;

// 复现UIKit拒绝在当前宿主上呈现采集页。
@interface UTHost : UIViewController
@property(nonatomic) BOOL rejects;
@end
@implementation UTHost
// 按夹具意图拒绝呈现，其余调用真实UIKit。
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    if (!self.rejects) [super presentViewController:controller animated:animated completion:completion];
}
@end

// 仅在独立模拟器测试中替代设备root启动。
BOOL lb_spawn(void) { return ut_spawn; }

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
// 完整详情返回即保存，新建草稿使用保存按钮。
static void ut_save(void) {
    __block BOOL back=NO;
    ut_ui(^{back=ut_find(ut_surface(),@"edit.save").hidden;});
    ut_tap(back ? @"edit.back" : @"edit.save");
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
        // 附件滚动内容由HUD单行及末项可达断言单独检查。
        if ([child.accessibilityIdentifier isEqual:@"hud.attachments"]) {
            CGRect frame=[child convertRect:child.bounds toView:viewport];
            if (CGRectGetMinX(frame)<-1 || CGRectGetMaxX(frame)>viewport.bounds.size.width+1 || child.hasAmbiguousLayout)
                [NSException raise:@"UITestFailure" format:@"附件滚动区超出页面或布局歧义：%@",NSStringFromCGRect(frame)];
            continue;
        }
        ut_bounds(child, viewport);
    }
}
// 保存UIKit真实渲染并检查应用控件边界。
static void ut_shot(NSString *name, CGFloat width, CGFloat height, BOOL large) {
    // 按用户验收范围仅检查iPhone宽度。
    if (width > 430) return;
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
        NSMutableArray *frames=[NSMutableArray array];
        for (NSString *key in @[@"edit.form",@"edit.actions",@"edit.title",@"edit.notes",@"edit.save",@"edit.complete",@"calendar.form",@"calendar.month"]) {
            UIView *item=ut_find(root.view,key); if(item) [frames addObject:@{@"id":key,@"frame":NSStringFromCGRect([item convertRect:item.bounds toView:root.view]),@"safe":NSStringFromUIEdgeInsets(item.safeAreaInsets)}];
        }
        [[NSJSONSerialization dataWithJSONObject:frames options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[ut_docs stringByAppendingPathComponent:[@"screens/" stringByAppendingString:[name stringByAppendingString:@".json"]]] atomically:YES];
        if (![root isKindOfClass:TTTaskHUD.class]) ut_req(root.traitCollection.userInterfaceStyle==ut_nav.traitCollection.userInterfaceStyle,@"所有子页沿用首页明暗主题");
        UIView *actions=ut_find(root.view,@"edit.actions"); if(actions) ut_req(actions.bounds.size.width>=width-26,@"编辑底部操作保留整行宽度");
        UIButton *complete=(UIButton *)ut_find(root.view,@"edit.complete"); if(complete && !complete.hidden) ut_req(complete.titleLabel.bounds.size.height<=complete.titleLabel.font.lineHeight+1,@"详情完成操作保持单行文字");
        UIView *month=ut_find(root.view,@"calendar.month"); if(month) ut_req(month.bounds.size.width>=width-34,@"原生月历保留完整七列宽度");
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
    __block BOOL editing;ut_ui(^{ [ut_top() dismissViewControllerAnimated:NO completion:nil];editing=[ut_top() isKindOfClass:TaskEdit.class]; }); if(editing)ut_tap(@"edit.cancel");ut_home();
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
        UIButton *toggle = (UIButton *)ut_find(ut_window,@"calendar.timed"); [toggle sendActionsForControlEvents:UIControlEventTouchUpInside];
        UIDatePicker *time = (UIDatePicker *)ut_find(ut_window,@"calendar.time");
        NSDateFormatter *format = [NSDateFormatter new]; format.timeZone = time.timeZone; format.dateFormat = @"yyyy-MM-dd HH:mm";
        time.date = [format dateFromString:@"2026-11-01 10:30"]; });
    ut_tap(@"calendar.repeat"); ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskRepeat.class]; },@"日期面板可设置重复");
    ut_tap(@"repeat.type.custom");
    ut_wait(^BOOL{return ut_find(ut_surface(),@"repeat.picker")!=nil;},@"自定义进入独立滚轮页");
    ut_ui(^{UIPickerView *picker=(UIPickerView *)ut_find(ut_surface(),@"repeat.picker");[picker selectRow:1 inComponent:0 animated:NO];[picker.delegate pickerView:picker didSelectRow:1 inComponent:0];[picker selectRow:1 inComponent:1 animated:NO];[picker.delegate pickerView:picker didSelectRow:1 inComponent:1];});
    ut_tap(@"repeat.day.MO"); ut_tap(@"repeat.day.WE"); ut_tap(@"repeat.end"); ut_tap(@"repeat.end.count");
    ut_ui(^{UITextField *count=(UITextField *)ut_find(ut_surface(),@"repeat.count");count.text=@"7";[count sendActionsForControlEvents:UIControlEventEditingChanged];});ut_tap(@"repeat.end.done");
    ut_wait(^BOOL{return ut_find(ut_surface(),@"repeat.picker")!=nil;},@"结束条件交回自定义页");
    ut_shot(@"repeat-320.png",320,850,NO); ut_shot(@"repeat-768.png",768,1024,NO);
    ut_tap(@"repeat.done"); ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskCalendar.class] && !ut_top().presentedViewController; },@"重复返回日期面板");
    ut_ui(^{ ut_req([[(UIButton *)ut_find(ut_window,@"calendar.repeat") titleForState:UIControlStateNormal] isEqual:@"每2周"],@"日期面板同步重复状态"); });
    ut_tap(@"calendar.done"); ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController; },@"月历返回快捷草稿");
    ut_tap(@"edit.deadline"); ut_ui(^{ut_req(ut_find(ut_surface(),@"calendar.clockRow").hidden && ut_find(ut_surface(),@"calendar.repeat").hidden,@"截止日期仅显示月历，不混入计划时间及重复");}); ut_tap(@"calendar.done"); ut_save(); ut_home();
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
    NSDictionary *shortTask=[ut_store crtTsk:@{@"title":@"排序联动夹具",@"list_id":listID,@"urgency":@1,@"difficulty":@3,@"planned_duration":@60} error:nil];
    ut_wait(^BOOL{return ut_find(ut_table(),[@"task." stringByAppendingString:shortTask[@"task_id"]])!=nil;},@"字段排序夹具刷新");
    for(NSString *key in @[@"urgency",@"difficulty",@"effort"]) {
        ut_tap(@"home.more");ut_tap(@"sort.more");ut_tap([@"sort." stringByAppendingString:key]);
        NSString *expected=[key isEqual:@"urgency"]?uuid:shortTask[@"task_id"];
        ut_wait(^BOOL { return ut_find([ut_table() cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]],[@"task." stringByAppendingString:expected])!=nil; },[@"清单实际应用字段排序：" stringByAppendingString:key]);
    }
    ut_req([ut_store delTsk:shortTask[@"task_id"] error:nil],@"清理排序联动夹具");
    ut_wait(^BOOL{return ut_find(ut_table(),[@"task." stringByAppendingString:shortTask[@"task_id"]])==nil;},@"字段排序清理刷新");
    ut_tap(@"home.more"); ut_tap(@"sort.date"); ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskHome.class]; },@"恢复日期排序");
    // 旧画面的重复完成意图不能跳到下一轮。
    __block NSArray *afterFirstCycle;
    ut_ui(^{ UIButton *button = (UIButton *)ut_find(ut_table(),[@"task." stringByAppendingString:uuid]);
        ut_req([ut_store cmplNxt:uuid error:nil],@"后台先完成重复轮次"); afterFirstCycle = [ut_store lsOcc:uuid error:nil]; [button sendActionsForControlEvents:UIControlEventTouchUpInside]; });
    ut_wait(^BOOL { return [[ut_store lsOcc:uuid error:nil] isEqual:afterFirstCycle] && [(UIButton *)ut_find(ut_table(),[@"task." stringByAppendingString:uuid]) isEnabled]; },@"过时重复勾选不推进下一轮");
    NSDictionary *plain = [ut_store crtTsk:@{@"title":@"子任务父级",@"list_id":listID} error:nil];
    ut_wait(^BOOL { return [ut_table() numberOfRowsInSection:0] == 2; },@"新父任务刷新首页");
    ut_ui(^{ NSArray *rows = [ut_store lsPnd:nil]; NSUInteger index = [rows indexOfObjectPassingTest:^BOOL(NSDictionary *row,NSUInteger idx,BOOL *stop) { (void)idx;(void)stop; return [row[@"task_id"] isEqual:plain[@"task_id"]]; }];
        [ut_table().delegate tableView:ut_table() didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]]; });
    ut_tap(@"edit.subtask");
    ut_ui(^{UITextField *field=(UITextField *)ut_find(ut_surface(),@"edit.childTitle");field.text=@"真实子任务";[field.delegate textFieldShouldReturn:field];[field.delegate textFieldShouldReturn:field];});
    ut_wait(^BOOL{return [[ut_store lsTsks:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"parent_id == %@",plain[@"task_id"]]].count==1;},@"内联子任务完成后回到父级详情");
    NSArray *children = [[ut_store lsTsks:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"parent_id == %@",plain[@"task_id"]]];
    ut_req(children.count == 1 && [children.firstObject[@"list_id"] isEqual:listID],@"子任务保持父级和清单");
    ut_wait(^BOOL{return ut_find(ut_surface(),[@"child." stringByAppendingString:children.firstObject[@"task_id"]])!=nil;},@"新子任务显示在父级详情");
    ut_tap([@"child." stringByAppendingString:children.firstObject[@"task_id"]]); ut_title(@"修改子任务"); ut_tap(@"edit.date");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskCalendar.class];},@"子任务也使用系统月历");
    ut_ui(^{ut_req(![(UIButton *)ut_find(ut_surface(),@"calendar.repeat") isEnabled],@"子任务月历禁用重复");[ut_top() dismissViewControllerAnimated:NO completion:nil];});ut_save();
    ut_wait(^BOOL { UIButton *entry = (UIButton *)ut_find(ut_surface(),[@"child." stringByAppendingString:children.firstObject[@"task_id"]]);
        return [entry.titleLabel.text isEqual:@"修改子任务"] && !ut_nav.transitionCoordinator; },@"编辑子任务后父级即时显示新标题");
    ut_tap(@"edit.subtask");ut_ui(^{((UITextField *)ut_find(ut_top().view,@"edit.childTitle")).text=@"返回保存子任务";});
    ut_tap(@"edit.back"); ut_home();
    NSArray *backChildren=[[ut_store lsTsks:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"parent_id == %@ AND title == %@",plain[@"task_id"],@"返回保存子任务"]];
    ut_req(backChildren.count==1,@"返回详情接续未按键盘完成的子任务且只保存一次");ut_req([ut_store delTsk:backChildren.firstObject[@"task_id"] error:nil],@"清理返回保存子任务夹具");
    ut_wait(^BOOL{return ut_find(ut_table(),[@"task." stringByAppendingString:backChildren.firstObject[@"task_id"]])==nil;},@"返回保存夹具清理后刷新");
    ut_tap(@"home.more"); ut_tap(@"sort.more"); ut_tap(@"list.reorder"); ut_wait(^BOOL { return ut_table().editing; },@"我的顺序启用原生拖动");
    ut_ui(^{ NSIndexPath *from = [NSIndexPath indexPathForRow:0 inSection:0], *to = [NSIndexPath indexPathForRow:1 inSection:0];
        if ([[ut_table().delegate tableView:ut_table() targetIndexPathForMoveFromRowAtIndexPath:from toProposedIndexPath:to] isEqual:to])
            [ut_table().dataSource tableView:ut_table() moveRowAtIndexPath:from toIndexPath:to]; });
    ut_wait(^BOOL { return [[ut_store rdTsk:uuid error:nil][@"position"] isEqual:@1] && [[ut_store rdTsk:children.firstObject[@"task_id"] error:nil][@"position"] isEqual:@2]; },@"原生拖动原子保存顺序");
    ut_tap(@"home.more"); ut_tap(@"sort.date"); ut_wait(^BOOL { return !ut_table().editing; },@"日期排序退出拖动模式");
}
// 运行真实首页、编辑和事务刷新验收。
static void ut_run(void) {
    ut_wait(^BOOL { return ut_find(ut_window, @"home.empty") != nil && [(UIButton *)ut_find(ut_window, @"home.empty") isEnabled]; }, @"空状态可新建");
    // 验证中性背景、明暗对比及实际图标与触摸尺寸。
    ut_ui(^{
        UIView *background = ut_find(ut_top().view, @"theme.surface");
        ut_req(background != nil && !background.userInteractionEnabled && CGRectEqualToRect(background.frame,ut_top().view.bounds), @"中性背景覆盖页面且不拦触摸");
        ut_req(![background.layer isKindOfClass:CAGradientLayer.class] && background.layer.animationKeys.count==0, @"主App不再叠加渐变或装饰动画");
        ut_req(lb_fnt(UIFontTextStyleBody,nil).pointSize>=20 && lb_fnt(UIFontTextStyleTitle2,nil).pointSize>=28, @"正文和标题保留可读大字");
        UIButton *create=(UIButton *)ut_find(ut_top().view,@"home.create");
        UIButton *label=(UIButton *)ut_find(ut_top().view,@"home.newlist");
        CGFloat (^luma)(UIColor *)=^CGFloat(UIColor *color) {
            CGFloat r=0,g=0,b=0,a=0;[color getRed:&r green:&g blue:&b alpha:&a];
            CGFloat rgb[3]={r,g,b};for (int i=0;i<3;i++)rgb[i]=rgb[i]<=0.04045?rgb[i]/12.92:pow((rgb[i]+0.055)/1.055,2.4);
            return 0.2126*rgb[0]+0.7152*rgb[1]+0.0722*rgb[2];
        };
        for (NSNumber *style in @[@(UIUserInterfaceStyleLight),@(UIUserInterfaceStyleDark)]) {
            UITraitCollection *traits=[UITraitCollection traitCollectionWithUserInterfaceStyle:style.integerValue];
            CGFloat paper=luma([background.backgroundColor resolvedColorWithTraitCollection:traits]);
            CGFloat ink=luma([label.configuration.baseForegroundColor resolvedColorWithTraitCollection:traits]);
            CGFloat fill=luma([create.configuration.background.backgroundColor resolvedColorWithTraitCollection:traits]);
            CGFloat text=luma([create.configuration.baseForegroundColor resolvedColorWithTraitCollection:traits]);
            ut_req((MAX(ink,paper)+0.05)/(MIN(ink,paper)+0.05)>=4.5,@"明暗普通文字对比达4.5");
            ut_req((MAX(text,fill)+0.05)/(MIN(text,fill)+0.05)>=4.5,@"明暗主要按钮对比达4.5");
        }
        for (NSNumber *offset in @[@8,@28,@48]) {
            CGPoint point=[create convertPoint:CGPointMake(28,offset.doubleValue) toView:ut_window]; UIView *hit=[ut_window hitTest:point withEvent:nil];
            ut_req(hit==create || [hit isDescendantOfView:create],@"上浮创建按钮全区域实际可触摸");
        }
        ut_req(create.configuration.image.size.width==24 && create.bounds.size.width>=44 && create.bounds.size.height>=44,@"MingCute保持24pt图形与至少44pt触摸区");
    });
    ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;});ut_shot(@"empty-light-320.png",320,568,NO);
    ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;});
    ut_shot(@"empty-320.png", 320, 568, NO); ut_tap(@"home.empty");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class]; }, @"空态进入编辑");
    ut_tap(@"edit.cancel"); ut_home(); ut_req([ut_store lsTsks:nil].count == 0, @"取消不创建数据");
    ut_tap(@"home.create"); ut_wait(^BOOL { return ut_find(ut_window, @"edit.title") != nil; }, @"固定新建入口");
    ut_wait(^BOOL { UIViewController *page=ut_top(); UINavigationController *nav=page.navigationController; CGRect frame=[nav.view convertRect:nav.view.bounds toView:ut_window]; return page.view.window && !nav.isBeingPresented && !nav.transitionCoordinator && frame.size.height<=200 && CGRectGetMaxY(frame)<ut_window.bounds.size.height-100; },@"快捷新增贴键盘且没有整页空白");
    ut_ui(^{ UIGraphicsImageRenderer *capture=[[UIGraphicsImageRenderer alloc] initWithSize:ut_window.bounds.size]; [[capture PNGDataWithActions:^(__unused UIGraphicsImageRendererContext *context){[ut_window drawViewHierarchyInRect:ut_window.bounds afterScreenUpdates:YES];}] writeToFile:[ut_docs stringByAppendingPathComponent:@"screens/quick-keyboard.png"] atomically:YES]; });
    ut_title(@"新建真实任务");
    ut_tap(@"edit.more");
    ut_ui(^{ UISwitch *toggle = (UISwitch *)ut_find(ut_window, @"plan.enabled"); toggle.on = YES; [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        UISwitch *clock = (UISwitch *)ut_find(ut_window, @"plan.timed"); clock.on = YES; [clock sendActionsForControlEvents:UIControlEventValueChanged];
        toggle = (UISwitch *)ut_find(ut_window, @"deadline.enabled"); toggle.on = YES; [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    });
    ut_shot(@"new-320.png", 320, 568, NO); ut_shot(@"new-375.png", 375, 667, NO);
    ut_save(); ut_home();
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
    ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;});ut_shot(@"home-light-375.png",375,850,NO);
    ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;});
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
    ut_save(); ut_home();
    NSDictionary *changed = [ut_store rdTsk:late[@"task_id"] error:nil];
    ut_req([changed[@"title"] isEqual:@"修改后保留高级字段"] && [changed[@"starred"] isEqual:late[@"starred"]]
        && [changed[@"recurrence"] isEqual:late[@"recurrence"]] && [changed[@"urgency"] isEqual:late[@"urgency"]]
        && [changed[@"difficulty"] isEqual:late[@"difficulty"]] && [changed[@"planned_duration"] isEqual:late[@"planned_duration"]]
        && [changed[@"due_at"] isEqual:late[@"due_at"]] && [changed[@"timezone_id"] isEqual:late[@"timezone_id"]], @"基础修改保留UUID和完整高级字段");
    ut_tap(@"home.create"); ut_wait(^BOOL { return ut_find(ut_window, @"edit.save") != nil; }, @"再次新建");
    ut_title(@"  ");
    ut_ui(^{ ut_req(![(UIButton *)ut_find(ut_window,@"edit.save") isEnabled],@"空标题禁用快捷保存"); });
    ut_title([@"a" stringByPaddingToLength:1025 withString:@"a" startingAtIndex:0]); ut_save();
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
    ut_save();
    ut_wait(^BOOL { return [ut_nav.topViewController.presentedViewController isKindOfClass:UIAlertController.class]; }, @"已删除任务保存被拒绝");
    NSDictionary *deleted = [ut_store rdTsk:late[@"task_id"] error:nil];
    ut_req([deleted[@"deleted"] boolValue] && [deleted[@"title"] isEqual:changed[@"title"]], @"失败未复活任务或覆盖标题");
}

// 验证Swift设置页的原生配置、失败回滚和Darwin预览通信。
static void ut_sttng(void) {
    ut_ui(^{
        UIViewController *controller = [NSClassFromString(@"LBSetCtl") new];
        ut_req(controller != nil, @"Swift后台设置运行类型存在");
        [ut_nav setNavigationBarHidden:NO animated:NO]; [ut_nav pushViewController:controller animated:NO];
        UISwitch *monitor = (UISwitch *)ut_find(controller.view, @"settings.enabled");
        UIButton *preview = (UIButton *)ut_find(controller.view, @"settings.preview");
        UIButton *recovery = (UIButton *)ut_find(controller.view, @"settings.recovery");
        ut_req([recovery.configuration.title containsString:@"需打开一次App恢复提醒服务"] && recovery.titleLabel.numberOfLines==0,@"整机重启限制明确可见并允许大字换行");
        monitor.on = NO; [monitor sendActionsForControlEvents:UIControlEventValueChanged];
        ut_req(![lb_ldcfg()[@"enabled"] boolValue] && !preview.enabled, @"关闭服务保存并禁用预览");
        ut_spawn = NO; monitor.on = YES; [monitor sendActionsForControlEvents:UIControlEventValueChanged];
        ut_req(!monitor.on && ![lb_ldcfg()[@"enabled"] boolValue], @"启动失败恢复关闭状态");
        ut_spawn = YES; monitor.on = YES; [monitor sendActionsForControlEvents:UIControlEventValueChanged];
        ut_req(monitor.on && [lb_ldcfg()[@"enabled"] boolValue] && preview.enabled, @"开启服务保存并启用预览");
        [recovery sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req([lb_ldcfg()[@"enabled"] boolValue] && recovery.enabled,@"恢复入口保持已启用意图");
        [preview sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req(!preview.enabled, @"等待HUD就绪禁用重复预览");
        notify_post(LB_READY_NOTE);
        int handle = lb_lckhud(); ut_req(handle>=0,@"设置诊断使用真实隔离服务锁");
        NSNumber *stamp = @(NSDate.date.timeIntervalSince1970+120);
        lb_svstat(@"正在运行",stamp);
        UIButton *status = (UIButton *)ut_find(controller.view,@"settings.status");
        UIButton *next = (UIButton *)ut_find(controller.view,@"settings.next");
        [status sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req([status.configuration.title isEqual:@"正在运行"] && next.configuration.subtitle.length>0,@"实际PID状态和下一提醒显示");
        close(handle); [status sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req(![status.configuration.title isEqual:@"正在运行"] && next.configuration.subtitle==nil,@"服务死亡立即撤销正常状态和旧下一时间");
        for (NSString *issue in @[@"数据库不可用",@"HUD启动失败",@"私有组件加载失败",@"窗口注册失败"]) {
            lb_svstat(issue,nil); [status sendActionsForControlEvents:UIControlEventTouchUpInside];
            ut_req([status.configuration.title isEqual:issue],[@"用户可见错误：" stringByAppendingString:issue]);
        }
        lb_svstat(@"服务已关闭",nil); [status sendActionsForControlEvents:UIControlEventTouchUpInside];
        [controller setValue:@YES forKey:@"storeFailed"]; [status sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req([status.configuration.title isEqual:@"数据库不可用"],@"App自身数据库失败不会被健康HUD状态掩盖");
        [controller setValue:@NO forKey:@"storeFailed"]; [status sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
    ut_wait(^BOOL { return [(UIButton *)ut_find(ut_top().view, @"settings.preview") isEnabled]; }, @"Darwin就绪恢复预览入口");
    ut_ui(^{
        UISwitch *monitor=(UISwitch *)ut_find(ut_top().view,@"settings.enabled"); UIButton *status=(UIButton *)ut_find(ut_top().view,@"settings.status");
        ut_req(lb_svcfg(@{@"enabled":@NO}),@"外部提交关闭配置");[status sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req(!monitor.on && ![(UIButton *)ut_find(ut_top().view,@"settings.preview") isEnabled],@"状态刷新同步关闭意图和操作可用性");
        ut_req(lb_svcfg(@{@"enabled":@YES}),@"外部提交启用配置");[status sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req(monitor.on && [(UIButton *)ut_find(ut_top().view,@"settings.preview") isEnabled],@"状态刷新同步启用意图，开关不保留旧值");
    });
    ut_shot(@"settings-large-320.png", 320, 850, YES);
    ut_ui(^{ [ut_nav popViewControllerAnimated:NO]; });
}

// 用真实HUD和同库服务验证内存测试轮次、正常数据库零变化与真提醒优先。
static void ut_diag(void) {
    __block TTTaskHUD *hud; __block TaskReminder *service; __block NSDictionary *before;
    ut_ui(^{
        hud=[TTTaskHUD new];
        service=[[TaskReminder alloc] initAt:ut_store.path handler:^(NSDictionary *alert,NSError *issue) { [hud display:alert error:issue]; } cleanup:^{} finish:^(__unused BOOL restart){}];
        ut_req([service start:nil],@"诊断测试连接真实唯一数据库服务"); hud.reminder=service;
        [ut_nav pushViewController:hud animated:NO];
    });
    ut_wait(^BOOL { return [lb_rdstat()[@"running"] boolValue]; },@"生产调度器发布真实运行状态");
    ut_ui(^{
        before=[ut_store snapshot:nil]; [hud preview];
        ut_req(hud.mode==1 && [hud.testOccurrence[@"status"] isEqual:@"presented"],@"测试创建内存Presented轮次");
        NSString *identity=hud.testOccurrence[@"occurrence_id"];
        for (int i=0;i<30;i++) [hud preview];
        ut_req([identity isEqual:hud.testOccurrence[@"occurrence_id"]],@"重复预览通知不重复创建测试轮次");
        ut_req(!ut_find(hud.view,@"hud.snooze").hidden && [(UIButton *)ut_find(hud.view,@"hud.snooze") isEnabled],@"测试提供正常延期退出按钮");
    });
    ut_shot(@"diagnostic-test-320.png",320,693,NO);
    ut_ui(^{
        [(UIButton *)ut_find(hud.view,@"hud.complete") sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req(hud.mode==0 && [hud.testOccurrence[@"status"] isEqual:@"resolved"],@"测试完成立即解除全屏");
        NSString *old=hud.testOccurrence[@"occurrence_id"];[hud preview];
        ut_req(![old isEqual:hud.testOccurrence[@"occurrence_id"]],@"下一次测试创建独立身份");
        [(UIButton *)ut_find(hud.view,@"hud.snooze") sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req(hud.mode==0 && [hud.testOccurrence[@"status"] isEqual:@"snoozed"],@"测试延期立即退出且无边栏重弹");
        ut_req([before isEqual:[ut_store snapshot:nil]],@"测试完成和延期不污染任务历史附件及数据库修订");
        [hud display:@{@"occurrence_id":@"real",@"task":@{@"title":@"真实优先"},@"occurrence":@{}} error:nil];
        [hud preview];ut_req(hud.mode==1 && [((UILabel *)ut_find(hud.view,@"hud.title")).text isEqual:@"真实优先"],@"测试不能覆盖真实待办");
        [hud stop];[service stop];[ut_nav popViewControllerAnimated:NO];
    });
}

// 用独立数据库连接运行生产调度器并记录真实回调。
static void ut_mon(void) {
    ut_ui(^{
        ut_events = [NSMutableArray array];
        ut_sched = [[TaskReminder alloc] initAt:ut_store.path handler:^(NSDictionary *alert, NSError *error) {
            [ut_events addObject:@{@"alert":alert ?: (id)NSNull.null,@"error":error.localizedDescription ?: @"",@"at":@(NSDate.date.timeIntervalSince1970)}];
            NSData *data = [NSJSONSerialization dataWithJSONObject:ut_events options:NSJSONWritingPrettyPrinted error:nil];
            [data writeToFile:[ut_docs stringByAppendingPathComponent:@"SchedulerEvents.json"] atomically:YES];
        } cleanup:^{} finish:^(__unused BOOL r){}];
        ut_req([ut_sched start:nil],@"独立连接启动真实后台调度");
    });
}
// 通过原生导航打开统一新建或已有详情。
static void ut_edt(NSDictionary *task) {
    ut_ui(^{ [ut_nav setNavigationBarHidden:NO animated:NO]; [ut_nav pushViewController:[[TaskEdit alloc] initWithStore:ut_store task:task saved:nil] animated:NO]; });
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && ut_find(ut_top().view,@"edit.title"); },@"统一编辑页面就绪");
}
// 从系统月历和时刻控件修改草稿。
static void ut_date(NSDate *date) API_AVAILABLE(ios(16.0));
static void ut_date(NSDate *date) {
    ut_tap(@"edit.date");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskCalendar.class] && !ut_top().isBeingPresented; },@"编辑使用系统日期时间页面");
    ut_ui(^{
        UICalendarView *calendar = (UICalendarView *)ut_find(ut_top().view,@"calendar.month");
        UIDatePicker *picker = (UIDatePicker *)ut_find(ut_top().view,@"calendar.time");
        ut_req(calendar && picker,@"月历与时刻均为原生UIKit控件");
        NSDateComponents *parts = [calendar.calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:date];
        UICalendarSelectionSingleDate *selection = (UICalendarSelectionSingleDate *)calendar.selectionBehavior;
        [selection setSelectedDate:parts animated:NO]; [(TaskCalendar *)ut_top() dateSelection:selection didSelectDate:parts];
        UIButton *toggle = (UIButton *)ut_find(ut_top().view,@"calendar.timed"); [toggle sendActionsForControlEvents:UIControlEventTouchUpInside];
        picker.date = date;
    });
    ut_tap(@"calendar.done");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController; },@"日期选择回到同一草稿");
}
// 验证统一编辑校验、完整回填和真实计时失效链路。
// 取消重复与月历必须保留原草稿，互斥入口按草稿实时更新。
static void ut_clsr(void) API_AVAILABLE(ios(16.0));
static void ut_clsr(void) {
    for (NSDictionary *task in [ut_store lsTsks:nil]) if (![task[@"deleted"] boolValue]) [ut_store delTsk:task[@"task_id"] error:nil];
    ut_edt(nil); ut_title(@"取消重复验证"); ut_tap(@"edit.more"); ut_tap(@"edit.repeat");
    ut_tap(@"repeat.type.custom"); ut_ui(^{[ut_top().navigationController popViewControllerAnimated:NO];}); ut_tap(@"repeat.cancel");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController; },@"取消重复回到原草稿");
    ut_ui(^{ ut_req(![(UISwitch *)ut_find(ut_top().view,@"plan.enabled") isOn],@"取消重复不能启用原本没有的日期"); });
    ut_tap(@"edit.date"); ut_tap(@"calendar.repeat"); ut_tap(@"repeat.type.weekly");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskCalendar.class] && !ut_top().presentedViewController; },@"重复修改暂存在月历内");
    ut_ui(^{ [ut_top() dismissViewControllerAnimated:YES completion:nil]; });
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController; },@"取消月历回到草稿");
    ut_ui(^{ ut_req(![(UISwitch *)ut_find(ut_top().view,@"plan.enabled") isOn] && [[(UIButton *)ut_find(ut_top().view,@"edit.repeat") titleForState:UIControlStateNormal] isEqual:@"不重复"],@"取消月历同时放弃其中日期与重复修改"); });
    ut_save(); ut_home();
    NSDictionary *plain = [ut_store lsPnd:nil].firstObject;
    ut_req([plain[@"schedule_kind"] isEqual:@"none"] && [plain[@"recurrence"] count]==0,@"取消后保存不产生隐藏提醒");
    ut_edt(plain); ut_tap(@"edit.more"); ut_tap(@"edit.repeat"); ut_tap(@"repeat.type.daily");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController; },@"确认重复回到详情");
    ut_ui(^{ ut_req([(UISwitch *)ut_find(ut_top().view,@"plan.enabled") isOn] && ![(UIButton *)ut_find(ut_top().view,@"edit.subtask") isEnabled],@"确认重复自动补日期并立即禁用子任务"); });
    ut_ui(^{ UISwitch *enabled=(UISwitch *)ut_find(ut_top().view,@"plan.enabled"); enabled.on=NO; [enabled sendActionsForControlEvents:UIControlEventValueChanged];
        ut_req([[(UIButton *)ut_find(ut_top().view,@"edit.repeat") titleForState:UIControlStateNormal] isEqual:@"不重复"] && [(UIButton *)ut_find(ut_top().view,@"edit.subtask") isEnabled],@"高级开关清除日期同步清除重复，不留下无法保存的草稿"); });
    ut_tap(@"edit.repeat"); ut_tap(@"repeat.type.daily");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController; },@"清除日期后可再次设置重复");
    ut_tap(@"edit.repeat"); ut_tap(@"repeat.type.none");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController; },@"清除重复返回详情");
    ut_ui(^{ ut_req([(UIButton *)ut_find(ut_top().view,@"edit.subtask") isEnabled],@"清除重复立即恢复子任务入口"); });
    ut_tap(@"edit.cancel"); ut_home();
    [ut_store delTsk:plain[@"task_id"] error:nil];
    // 首页重试必须同步连接状态，存储未就绪时菜单不能强制解包。
    __block BOOL fail = YES; __block TaskStore *loaded; __block NSUInteger attempts = 0;
    Method method = class_getClassMethod(TaskStore.class,@selector(shrd:)); IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^TaskStore *(__unused id receiver, NSError **error) {
        if (fail) { if (error) *error = [NSError errorWithDomain:@"closure" code:SQLITE_CANTOPEN userInfo:nil]; return nil; } return ut_store;
    });
    __block TaskHome *probe; __block NSArray *controllers;
    ut_ui(^{ method_setImplementation(method,replacement); controllers = ut_nav.viewControllers;
        probe = [[TaskHome alloc] initWithStore:nil settings:nil]; probe.onStore = ^(TaskStore *store) { loaded=store; attempts++; };
        [ut_nav setViewControllers:@[probe] animated:NO];
    });
    ut_wait(^BOOL { return attempts>0 && [[(UIButton *)ut_find(probe.view,@"home.empty") configuration].title isEqual:@"读取失败"]; },@"数据库首次失败可见且有重试入口");
    ut_tap(@"home.more"); ut_tap(@"home.lists");
    ut_ui(^{ ut_req(!probe.presentedViewController && loaded==nil,@"存储缺失时排序与清单入口不崩溃、不进入无效表单"); fail=NO; });
    ut_tap(@"home.empty");
    ut_wait(^BOOL { return loaded==ut_store && [[(UIButton *)ut_find(probe.view,@"home.empty") configuration].title isEqual:@"暂无待办"]; },@"重试恢复连接并通知采集与服务共用同一库");
    ut_ui(^{ method_setImplementation(method,original); [ut_nav setViewControllers:controllers animated:NO]; }); imp_removeBlock(replacement);
    // 设置状态实时读取故障标志，不能保留首次启动的失败快照。
    __block UIViewController *settings; __block BOOL unavailable=YES;
    ut_ui(^{ settings=[objc_getClass("LBSetCtl") new]; [settings setValue:[^BOOL{return unavailable;} copy] forKey:@"storeIssue"]; [ut_nav pushViewController:settings animated:NO]; });
    ut_tap(@"settings.status"); ut_ui(^{ ut_req([[(UIButton *)ut_find(settings.view,@"settings.status") configuration].title isEqual:@"数据库不可用"],@"设置显示当前数据库故障"); unavailable=NO; });
    ut_tap(@"settings.status"); ut_ui(^{ ut_req(![[(UIButton *)ut_find(settings.view,@"settings.status") configuration].title isEqual:@"数据库不可用"],@"数据库恢复后设置撤销旧故障"); [ut_nav popViewControllerAnimated:NO]; });
    // 冷启动必须读取先前已保存的排序，不能重新退回日期排序。
    NSDictionary *first=[ut_store crtTsk:@{@"title":@"顺序甲",@"position":@0,@"due_at":@(NSDate.date.timeIntervalSince1970+7200)} error:nil];
    NSDictionary *second=[ut_store crtTsk:@{@"title":@"顺序乙",@"position":@1,@"due_at":@(NSDate.date.timeIntervalSince1970+3600)} error:nil];
    NSString *key=[NSString stringWithFormat:@"%@.%@.sort",ut_store.changeNote,TS_DFLT_LST];
    ut_ui(^{ [NSUserDefaults.standardUserDefaults setObject:@"manual" forKey:key];
        TaskHome *fresh=[[TaskHome alloc] initWithStore:ut_store settings:nil]; [ut_nav setViewControllers:@[fresh] animated:NO];
    });
    ut_wait(^BOOL { UITableViewCell *cell=[ut_table() cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        return ut_find(cell,[@"task." stringByAppendingString:first[@"task_id"]])!=nil; },@"重新创建首页沿用已保存的手动排序");
    ut_ui(^{ [NSUserDefaults.standardUserDefaults removeObjectForKey:key]; [ut_nav setViewControllers:controllers animated:NO]; });
    ut_req([ut_store delTsk:first[@"task_id"] error:nil] && [ut_store delTsk:second[@"task_id"] error:nil],@"排序验证夹具清理");
}
static void ut_edit(void) API_AVAILABLE(ios(16.0));
static void ut_edit(void) {
    for (NSDictionary *task in [ut_store lsTsks:nil]) if (![task[@"deleted"] boolValue]) [ut_store delTsk:task[@"task_id"] error:nil];
    ut_mon(); ut_edt(nil);
    ut_ui(^{ ut_req(![(UIButton *)ut_find(ut_top().view,@"edit.save") isEnabled],@"完整新建空标题禁用保存"); });
    ut_title(@"   \n ");
    ut_ui(^{ ut_req(![(UIButton *)ut_find(ut_top().view,@"edit.save") isEnabled],@"统一编辑纯空白标题不可保存"); });
    ut_title([@"a" stringByPaddingToLength:1025 withString:@"a" startingAtIndex:0]);
    long long revision = [ut_store revision:nil]; ut_save();
    ut_wait(^BOOL { return [ut_top() isKindOfClass:UIAlertController.class]; },@"标题过长在保存前报错");
    ut_req([ut_store revision:nil] == revision && [ut_store lsPnd:nil].count == 0,@"文本校验失败不提交或产生提醒");
    ut_ui(^{ [ut_top() dismissViewControllerAnimated:NO completion:nil]; });
    ut_title(@"统一页面保存"); ut_tap(@"edit.details");
    ut_ui(^{ UITextView *notes = (UITextView *)ut_find(ut_top().view,@"edit.notes"); notes.text = [@"a" stringByPaddingToLength:8193 withString:@"a" startingAtIndex:0]; [notes.delegate textViewDidChange:notes]; });
    ut_save(); ut_wait(^BOOL { return [ut_top() isKindOfClass:UIAlertController.class]; },@"说明超限保存前校验");
    ut_req([ut_store revision:nil] == revision,@"说明校验失败没有提交修订");
    ut_ui(^{ [ut_top() dismissViewControllerAnimated:NO completion:nil]; });
    ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController; },@"错误弹窗关闭后继续原草稿");
    ut_ui(^{ UITextView *notes = (UITextView *)ut_find(ut_top().view,@"edit.notes"); notes.text = @"第一行\n第二行"; [notes.delegate textViewDidChange:notes]; });
    NSDate *now = NSDate.date; ut_date(now); ut_save(); ut_home();
    NSDictionary *task = [ut_store lsPnd:nil].firstObject; NSString *uuid = task[@"task_id"];
    ut_req([task[@"title"] isEqual:@"统一页面保存"] && [task[@"notes"] isEqual:@"第一行\n第二行"] && [task[@"schedule_kind"] isEqual:@"timed"],@"标题说明及具体时刻一次写入");
    ut_wait(^BOOL { return [ut_events.lastObject[@"alert"] isKindOfClass:NSDictionary.class] && [ut_events.lastObject[@"alert"][@"task_id"] isEqual:uuid]; },@"页面保存立即通知真实调度器触发");
    ut_edt([ut_store rdTsk:uuid error:nil]);
    ut_ui(^{ ut_req([[(UITextView *)ut_find(ut_top().view,@"edit.title") text] isEqual:task[@"title"]]
        && [[(UITextView *)ut_find(ut_top().view,@"edit.notes") text] isEqual:task[@"notes"]],@"已有任务标题说明完整回填"); });
    ut_title(@" \n "); ut_ui(^{ ut_req(![(UIButton *)ut_find(ut_top().view,@"edit.save") isEnabled],@"已有任务清空标题也禁用保存"); }); ut_title(task[@"title"]);
    ut_date([NSDate dateWithTimeIntervalSinceNow:3600]); ut_save(); ut_home();
    ut_wait(^BOOL { return ut_events.lastObject[@"alert"] == NSNull.null; },@"改为未来时刻立即撤下旧提醒");
    NSDictionary *history = [ut_store lsOcc:uuid error:nil].firstObject;
    ut_req([history[@"action"] isEqual:@"invalidated"] && [history[@"status"] isEqual:@"resolved"],@"旧提醒处理记录永久失效");
    NSDictionary *future = [ut_store planAt:NSDate.date.timeIntervalSince1970 error:nil];
    ut_req([future[@"alerts"] count] == 1 && [future[@"alerts"][0][@"remind_at"] doubleValue] > NSDate.date.timeIntervalSince1970 + 3500,@"后台计划仅保留新时刻");
    // 旧候选已经进入展示队列时，提交后也不能显示。
    __block NSDictionary *oldTask;
    ut_ui(^{
        oldTask = [ut_store crtTsk:@{@"title":@"队列旧时间",@"due_at":@(NSDate.date.timeIntervalSince1970-1)} error:nil];
        [NSThread sleepForTimeInterval:1.2];
        ut_req([ut_store updTsk:oldTask[@"task_id"] fields:@{@"due_at":@(NSDate.date.timeIntervalSince1970+3600)} error:nil],@"主线程排队期间提交新提醒时间");
    });
    NSString *oldID = oldTask[@"task_id"];
    usleep(1200000);
    ut_ui(^{ BOOL stale = NO; for (NSDictionary *event in ut_events) if ([event[@"alert"] isKindOfClass:NSDictionary.class] && [event[@"alert"][@"task_id"] isEqual:oldID]) stale = YES;
        ut_req(!stale,@"排队旧提醒被展示前数据库核对拦截"); });
    [ut_store delTsk:oldID error:nil];
    // 实际跨过旧计时时刻，独立连接不得认领旧提醒。
    NSTimeInterval oldTime = NSDate.date.timeIntervalSince1970 + 10;
    NSDictionary *pending = [ut_store crtTsk:@{@"title":@"待修改计时",@"due_at":@(oldTime),@"deadline_at":@(oldTime+7200),@"urgency":@3,@"difficulty":@2,@"starred":@1,@"planned_duration":@90000,@"timezone_id":@"UTC"} error:nil];
    NSString *pendingID = pending[@"task_id"]; ut_edt(pending); ut_tap(@"edit.more");
    ut_ui(^{
        ut_req([[(UITextField *)ut_find(ut_top().view,@"edit.duration") text] isEqual:@"1500"] && [[(UITextField *)ut_find(ut_top().view,@"edit.timezone") text] isEqual:@"UTC"],@"时区和预计投入回填");
        ut_req([[(UIButton *)ut_find(ut_top().view,@"edit.urgency") configuration].title isEqual:@"紧急程度：高"] && [[(UIButton *)ut_find(ut_top().view,@"edit.difficulty") configuration].title isEqual:@"难易程度：一般"],@"紧急难度回填");
        ut_req([(UISwitch *)ut_find(ut_top().view,@"plan.enabled") isOn] && [(UISwitch *)ut_find(ut_top().view,@"plan.timed") isOn] && [(UISwitch *)ut_find(ut_top().view,@"deadline.enabled") isOn] && [(UISwitch *)ut_find(ut_top().view,@"deadline.timed") isOn],@"计划和独立截止开关回填");
        UIDatePicker *plan = (UIDatePicker *)ut_find(ut_top().view,@"plan.time"), *ddl = (UIDatePicker *)ut_find(ut_top().view,@"deadline.time");
        ut_req(fabs(plan.date.timeIntervalSince1970-oldTime)<1 && fabs(ddl.date.timeIntervalSince1970-oldTime-7200)<1,@"计划截止保留原始绝对时刻精度");
    });
    ut_date([NSDate dateWithTimeIntervalSinceNow:3600]); ut_save(); ut_home();
    ut_req(NSDate.date.timeIntervalSince1970 < oldTime,@"修改在旧计时到期之前提交");
    while (NSDate.date.timeIntervalSince1970 < oldTime + 1) usleep(20000);
    ut_req([ut_store lsOcc:pendingID error:nil].count == 0,@"修改后跨过旧时间仍无触发记录");
    NSDictionary *changed = [ut_store rdTsk:pendingID error:nil];
    ut_req([changed[@"urgency"] isEqual:@3] && [changed[@"difficulty"] isEqual:@2] && [changed[@"planned_duration"] isEqual:@90000],@"改时间保留全部未修改扩展字段");
    ut_edt(changed); ut_title(@"取消不提交"); ut_tap(@"edit.cancel"); ut_home();
    ut_req([[ut_store rdTsk:pendingID error:nil][@"title"] isEqual:@"待修改计时"],@"放弃草稿不改变任务或调度");
    ut_edt(changed); ut_tap(@"edit.delete");
    ut_wait(^BOOL { return [ut_top() isKindOfClass:UIAlertController.class]; },@"删除使用系统原生确认");
    ut_req(![[ut_store rdTsk:pendingID error:nil][@"deleted"] boolValue],@"未确认删除前任务及计划保留");
    ut_ui(^{ [ut_top() dismissViewControllerAnimated:NO completion:nil]; }); ut_tap(@"edit.cancel"); ut_home();
    ut_req([ut_store delTsk:pendingID error:nil] && [ut_store delTsk:uuid error:nil],@"删除未来任务提交成功");
    ut_wait(^BOOL { return [[ut_store planAt:NSDate.date.timeIntervalSince1970 error:nil][@"alerts"] count] == 0; },@"删除后全部未来提醒失效");
    ut_ui(^{ for (NSDictionary *event in ut_events) ut_req([event[@"error"] length] == 0,@"后台调度没有数据库错误"); [ut_sched stop]; });
}

// 验证原生重复设置、单次延后及连续提前完成。
static void ut_hdue(NSString *path, NSString *id);
static void ut_rpt(void) API_AVAILABLE(ios(16.0));
static void ut_rpt(void) {
    for (NSDictionary *task in [ut_store lsTsks:nil]) if (![task[@"deleted"] boolValue]) [ut_store delTsk:task[@"task_id"] error:nil];
    ut_mon();
    for (NSString *type in @[@"daily",@"weekly",@"monthly",@"none"]) {
        ut_edt(nil); ut_title(@"重复链路验证"); ut_date(NSDate.date);
        ut_tap(@"edit.more"); ut_tap(@"edit.repeat");
        ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskRepeat.class]; },@"原生重复规则页面就绪");
        ut_tap([@"repeat.type." stringByAppendingString:type]);
        ut_wait(^BOOL { return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController; },@"重复规则返回统一编辑");
        ut_save(); ut_home();
        NSString *uuid = [ut_store lsPnd:nil].firstObject[@"task_id"];
        NSDictionary *task = [ut_store rdTsk:uuid error:nil];
        BOOL repeated = ![type isEqual:@"none"];
        ut_req([task[@"recurrence_type"] isEqual:type] && [task[@"recurrence"] count] == (repeated ? 1 : 0),@"页面保存所选规则及稳定任务UUID");
        ut_wait(^BOOL { return [ut_events.lastObject[@"alert"] isKindOfClass:NSDictionary.class] && [ut_events.lastObject[@"alert"][@"task_id"] isEqual:uuid]; },@"保存重复任务通知真实后台调度器");
        __block NSDictionary *current;
        ut_ui(^{ current = [ut_events.lastObject[@"alert"] copy]; });
        if ([type isEqual:@"daily"]) {
            NSTimeInterval start = NSDate.date.timeIntervalSince1970;
            ut_ui(^{ [ut_sched hold:@"snooze" occID:current[@"occurrence_id"]]; });
            ut_wait(^BOOL { return ut_events.lastObject[@"alert"] == NSNull.null; },@"单次延后立即撤下当前提醒");
            ut_req([[ut_store rdTsk:uuid error:nil] isEqual:task],@"单次延期不修改任务或整个重复规则");
            NSDictionary *plan = [ut_store planAt:NSDate.date.timeIntervalSince1970 error:nil];
            NSDictionary *snoozed = [plan[@"alerts"] firstObject];
            NSNumber *until = snoozed[@"remind_at"];
            ut_req([snoozed[@"occurrence_id"] isEqual:current[@"occurrence_id"]] && [snoozed[@"cycle_at"] isEqual:current[@"cycle_at"]]
                && [snoozed[@"scheduled_at"] isEqual:current[@"scheduled_at"]] && until.doubleValue-start>=300 && until.doubleValue-start<302,@"五分钟延期仅替换当前Occurrence提醒时刻");
            // 缩短隔离库期限，生产入口仍严格校验一次五分钟。
            ut_hdue(ut_store.path,current[@"occurrence_id"]);
            until = [ut_store lsOcc:uuid error:nil].firstObject[@"hold_until"]; notify_post(ut_store.changeNote.UTF8String);
            ut_wait(^BOOL { for (NSDictionary *event in ut_events) {
                NSDictionary *alert = event[@"alert"];
                if ([alert isKindOfClass:NSDictionary.class] && [alert[@"occurrence_id"] isEqual:current[@"occurrence_id"]]
                    && [alert[@"remind_at"] isEqual:until] && [event[@"at"] doubleValue] >= until.doubleValue) return YES;
            } return NO; },@"真实计时器以同一Occurrence再次触发");
            ut_req([ut_store lsOcc:uuid error:nil].count == 1,@"延后重触发不产生重复Occurrence");
        }
        ut_edt([ut_store rdTsk:uuid error:nil]); ut_tap(@"edit.complete"); ut_home();
        ut_wait(^BOOL { return ut_events.lastObject[@"alert"] == NSNull.null; },@"完成当前轮次立即撤下后台提醒");
        NSDictionary *changed = [ut_store rdTsk:uuid error:nil];
        if (repeated) {
            NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
            calendar.timeZone = [NSTimeZone timeZoneWithName:task[@"timezone_id"]];
            NSCalendarUnit unit = [type isEqual:@"daily"] ? NSCalendarUnitDay : [type isEqual:@"weekly"] ? NSCalendarUnitWeekOfYear : NSCalendarUnitMonth;
            NSDate *anchor = [NSDate dateWithTimeIntervalSince1970:[task[@"due_at"] doubleValue]];
            NSDate *next = [calendar dateByAddingUnit:unit value:1 toDate:anchor options:0];
            NSDictionary *alert = [[ut_store planAt:NSDate.date.timeIntervalSince1970 error:nil][@"alerts"] firstObject];
            ut_req([changed[@"status"] isEqual:@"needsAction"] && [changed[@"due_at"] isEqual:task[@"due_at"]]
                && [changed[@"recurrence"] isEqual:task[@"recurrence"]] && [changed[@"reminder_version"] isEqual:task[@"reminder_version"]],@"完成单轮保留任务计划锚点及系列版本");
            ut_req(fabs([alert[@"cycle_at"] doubleValue] - next.timeIntervalSince1970) < 0.001,@"下一轮从原始计划日历计算");
            if ([type isEqual:@"daily"]) {
                for (NSInteger index = 2; index <= 9; index++) {
                    ut_edt([ut_store rdTsk:uuid error:nil]); ut_tap(@"edit.complete"); ut_home();
                    NSDate *expected = [calendar dateByAddingUnit:unit value:index toDate:anchor options:0];
                    NSDictionary *future = [[ut_store planAt:NSDate.date.timeIntervalSince1970 error:nil][@"alerts"] firstObject];
                    ut_req([future[@"task_id"] isEqual:uuid] && fabs([future[@"cycle_at"] doubleValue] - expected.timeIntervalSince1970) < 0.001
                        && [[ut_store rdTsk:uuid error:nil][@"status"] isEqual:@"needsAction"],@"连续提前完成超过预取窗口仍产生下一轮");
                }
                NSArray *history = [ut_store lsOcc:uuid error:nil]; NSMutableSet *ids = [NSMutableSet set];
                for (NSDictionary *item in history) [ids addObject:item[@"occurrence_id"]];
                NSArray *resolved = [history filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"status == 'resolved' AND action == 'complete'"]];
                NSArray *nextPending = [history filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"status == 'pending'"]];
                ut_req(resolved.count == 9 && nextPending.count == 1 && history.count == 10 && ids.count == 10,@"九次完成各一终态且只有一个下一轮待提醒");
                ut_shot(@"phase06-next-cycle-320.png",320,850,NO);
            }
        } else {
            ut_req([changed[@"status"] isEqual:@"completed"] && [[ut_store planAt:NSDate.date.timeIntervalSince1970 error:nil][@"alerts"] count] == 0,@"不重复任务完成后没有下一轮");
        }
        ut_req([ut_store delTsk:uuid error:nil],@"测试任务删除后停止整个系列");
    }
    ut_ui(^{ BOOL valid = YES; for (NSDictionary *event in ut_events) if ([event[@"error"] length]) valid = NO;
        ut_req(valid,@"真实重复调度没有数据库错误"); [ut_sched stop]; });
}

// 验证iPhone原生调度对全部到期轮次、处理推进和修改打断。
static void ut_schd(void) {
    for (NSDictionary *task in [ut_store lsTsks:nil]) if (![task[@"deleted"] boolValue]) [ut_store delTsk:task[@"task_id"] error:nil];
    ut_mon(); NSMutableArray *tasks = [NSMutableArray array]; NSTimeInterval base = NSDate.date.timeIntervalSince1970 + 0.6;
    for (NSInteger index = 0; index < 3; index++) {
        NSDictionary *task = [ut_store crtTsk:@{@"title":@"绝对调度验收",@"due_at":@(base+index*0.3),@"timezone_id":@"UTC"} error:nil];
        ut_req(task != nil,@"独立连接写入绝对时刻"); [tasks addObject:task];
    }
    ut_wait(^BOOL { for (NSDictionary *task in tasks) if ([ut_store lsOcc:task[@"task_id"] error:nil].count != 1) return NO; return YES; },@"未处理首条时其他到期轮次仍按时持久化");
    NSMutableArray *occurrences = [NSMutableArray array];
    for (NSDictionary *task in tasks) {
        NSDictionary *occ = [ut_store lsOcc:task[@"task_id"] error:nil].firstObject; [occurrences addObject:occ];
        NSTimeInterval delay = [occ[@"triggered_at"] doubleValue] - [task[@"due_at"] doubleValue];
        ut_req(delay >= 0 && delay < 2 && [occ[@"status"] isEqual:@"presented"],@"iPhone到期误差小于两秒且不提前触发");
    }
    for (NSUInteger index = 0; index < tasks.count; index++) {
        ut_wait(^BOOL { return [ut_events.lastObject[@"alert"] isKindOfClass:NSDictionary.class] && [ut_events.lastObject[@"alert"][@"task_id"] isEqual:tasks[index][@"task_id"]]; },@"到期队列按提醒顺序展示");
        NSTimeInterval handled = NSDate.date.timeIntervalSince1970;
        ut_ui(^{ [ut_sched act:@"complete" until:nil occID:ut_events.lastObject[@"alert"][@"occurrence_id"]]; });
        ut_wait(^BOOL { id alert = ut_events.lastObject[@"alert"]; return index+1 == tasks.count ? alert == NSNull.null
            : [alert isKindOfClass:NSDictionary.class] && [alert[@"task_id"] isEqual:tasks[index+1][@"task_id"]]; },@"处理后立即展示下一条或进入空闲");
        ut_req(NSDate.date.timeIntervalSince1970 - handled < 0.8,@"处理推进无需等待周期轮询");
    }
    NSDictionary *future = [ut_store crtTsk:@{@"title":@"未来调度验收",@"due_at":@(NSDate.date.timeIntervalSince1970+60)} error:nil];
    ut_req(future != nil,@"创建未来调度任务");
    ut_wait(^BOOL { return fabs(ut_sched.nextFireAt.timeIntervalSince1970-[future[@"due_at"] doubleValue])<0.001; },@"新建立即唤醒并设置nextFireAt");
    NSTimeInterval updated = NSDate.date.timeIntervalSince1970+120;
    ut_req([ut_store updTsk:future[@"task_id"] fields:@{@"due_at":@(updated)} error:nil],@"修改未来绝对时刻");
    ut_wait(^BOOL { return fabs(ut_sched.nextFireAt.timeIntervalSince1970-updated)<0.001; },@"修改取消旧计时并重排最近任务");
    ut_req([ut_store delTsk:future[@"task_id"] error:nil],@"删除未来调度任务");
    ut_wait(^BOOL { return ut_sched.nextFireAt == nil; },@"删除立即解除最后一个计时");
    NSData *data = [NSJSONSerialization dataWithJSONObject:occurrences options:NSJSONWritingPrettyPrinted error:nil];
    ut_req([data writeToFile:[ut_docs stringByAppendingPathComponent:@"SchedulerTiming.json"] atomically:YES],@"保留原生Occurrence触发时刻证据");
    ut_ui(^{ for (NSDictionary *event in ut_events) ut_req([event[@"error"] length] == 0,@"原生绝对调度没有数据库错误"); [ut_sched stop]; });
}

// 验证服务在原生iPhone进程中持锁、同步和显式窗口释放。
static void ut_svc(void) {
    NSString *path=[ut_docs stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".sqlite3"]];
    TaskStore *writer=[[TaskStore alloc] initAt:path error:nil];
    __block UIWindow *fixture; __block __weak UIWindow *released; __block __weak UIViewController *controller;
    __block NSUInteger cleaned=0,finished=0; __block BOOL held=NO; __block TaskReminder *service;
    ut_ui(^{ fixture=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; fixture.rootViewController=[UIViewController new]; released=fixture; controller=fixture.rootViewController; });
    ut_ui(^{
        service=[[TaskReminder alloc] initAt:path handler:^(__unused NSDictionary *a,__unused NSError *e){} cleanup:^{
            held=lb_svcup(); cleaned++; fixture.hidden=YES; fixture.rootViewController=nil; fixture=nil;
        } finish:^(__unused BOOL r){ finished++; }];
        ut_req([service open:nil] && !service.running && lb_svcup(),@"原生服务先持锁并加载数据库");
        ut_req([service start:nil] && [service start:nil] && service.running,@"原生重复启动同一服务幂等");
        NSError *error=nil;
        TaskReminder *duplicate=[[TaskReminder alloc] initAt:path handler:^(__unused NSDictionary *a,__unused NSError *e){} cleanup:^{} finish:^(__unused BOOL r){}];
        ut_req(![duplicate start:&error] && error.code==EWOULDBLOCK && service.running,@"原生第二服务受flock拒绝");
    });
    NSTimeInterval due=NSDate.date.timeIntervalSince1970+60;
    ut_req([writer crtTsk:@{@"title":@"原生服务资源",@"due_at":@(due)} error:nil]!=nil,@"原生服务独立连接写入任务");
    ut_wait(^BOOL { return fabs(service.nextFireAt.timeIntervalSince1970-due)<0.001; },@"原生Darwin通知立即同步服务计划");
    notify_post(LB_STOP_NOTE);
    ut_wait(^BOOL { return !service.running && finished==1 && released==nil && controller==nil; },@"服务停止释放原生窗口及控制器");
    ut_ui(^{
        ut_req(held && !lb_svcup() && cleaned==1 && service.nextFireAt==nil,@"窗口清理先于锁释放且计时解除");
        [service stop]; ut_req(cleaned==1 && finished==1,@"重复停止没有重复清理或退出");
    });
}

#include "test_hud.inc"
#include "test_signal.inc"
#include "test_parity.inc"

// 前台呈现失败保持待接管状态，超时取消后可再次打开采集。
static void ut_bridge(void) {
    __block id<UIApplicationDelegate> delegate; __block UIWindow *window; __block UTHost *host;
    Method method=class_getClassMethod(TaskStore.class,@selector(shrd:)); IMP original=method_getImplementation(method);
    IMP replacement=imp_implementationWithBlock(^TaskStore *(__unused id receiver,__unused NSError **error){return ut_store;});
    __block int lock=-1;
    ut_ui(^{
        method_setImplementation(method,replacement); ut_req(lb_svcfg(@{@"enabled":@YES}),@"采集夹具启用独立配置");
        lock=lb_lckhud();ut_req(lock>=0,@"采集夹具持有真实服务锁");
        delegate=[objc_getClass("LBAppDel") new]; [delegate application:UIApplication.sharedApplication didFinishLaunchingWithOptions:nil];
        window=[(id)delegate valueForKey:@"window"]; host=[UTHost new];host.rejects=YES;window.rootViewController=host;[window makeKeyAndVisible];
    });
    @try {
        NSDictionary *task=[ut_store crtTsk:@{@"title":@"采集闭环",@"due_at":@(NSDate.date.timeIntervalSince1970-1)} error:nil];
        NSDictionary *plan=[ut_store planAt:NSDate.date.timeIntervalSince1970 error:nil];
        NSDictionary *candidate=[plan[@"alerts"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"task_id == %@",task[@"task_id"]]].firstObject;
        NSDictionary *alert=[ut_store claim:candidate revision:[plan[@"revision"] longLongValue] at:NSDate.date.timeIntervalSince1970 error:nil];
        NSDictionary *request=[ut_store reqCap:alert[@"occurrence_id"] source:@"file" limit:1 error:nil];NSString *token=request[@"token"];
        ut_ui(^{ [delegate applicationDidBecomeActive:UIApplication.sharedApplication]; });
        ut_ui(^{ ut_req([[ut_store rdCap:token error:nil][@"state"] intValue]==0 && !host.presentedViewController,@"宿主拒绝呈现时不得提前确认接管并永久隐藏HUD"); });
        ut_req([ut_store delCap:token error:nil],@"模拟HUD已有超时撤销请求");
        ut_ui(^{ [delegate applicationDidBecomeActive:UIApplication.sharedApplication];host.rejects=NO; });
        request=[ut_store reqCap:alert[@"occurrence_id"] source:@"file" limit:1 error:nil];token=request[@"token"];
        ut_ui(^{ [delegate applicationDidBecomeActive:UIApplication.sharedApplication]; });
        ut_wait(^BOOL{return [[ut_store rdCap:token error:nil][@"state"] intValue]==1 && [host.presentedViewController.presentedViewController isKindOfClass:UIDocumentPickerViewController.class];},@"超时后清除旧采集并可再次呈现原生文件面板");
        ut_ui(^{ UIViewController *picker=host.presentedViewController; [(id<UIDocumentPickerDelegate>)picker documentPickerWasCancelled:(UIDocumentPickerViewController *)picker.presentedViewController]; });
        ut_wait(^BOOL{return [[ut_store rdCap:token error:nil][@"state"] intValue]==2 && !host.presentedViewController;},@"取消文件面板完成交回并解除前台采集页");
        ut_req([ut_store delCap:token error:nil],@"取消交回清理临时结果");
        // 连续交回失败也必须撤销请求，不能让活着的App永久占住采集。
        Method finish=class_getInstanceMethod(TaskStore.class,@selector(finCap:attachments:issue:error:)); IMP normal=method_getImplementation(finish);
        IMP failure=imp_implementationWithBlock(^BOOL(__unused id receiver,__unused NSString *key,__unused NSArray *items,__unused NSString *issue,NSError **error){
            if(error)*error=[NSError errorWithDomain:@"capture-fault" code:SQLITE_IOERR userInfo:nil];return NO;
        });
        ut_ui(^{ method_setImplementation(finish,failure); });
        @try {
            request=[ut_store reqCap:alert[@"occurrence_id"] source:@"file" limit:1 error:nil];token=request[@"token"];
            ut_ui(^{ [delegate applicationDidBecomeActive:UIApplication.sharedApplication]; });
            ut_wait(^BOOL{return [[ut_store rdCap:token error:nil][@"state"] intValue]==1 && [host.presentedViewController.presentedViewController isKindOfClass:UIDocumentPickerViewController.class];},@"再次采集使用同一有效轮次");
            ut_ui(^{ UIViewController *picker=host.presentedViewController; [(id<UIDocumentPickerDelegate>)picker documentPickerWasCancelled:(UIDocumentPickerViewController *)picker.presentedViewController]; });
            ut_wait(^BOOL{return [ut_store rdCap:token error:nil].count==0 && !host.presentedViewController;},@"连续交回失败仍撤销采集并释放原生面板");
        } @finally { ut_ui(^{method_setImplementation(finish,normal);});imp_removeBlock(failure); }
        ut_req([[ut_store rdTsk:task[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"] && [ut_store delTsk:task[@"task_id"] error:nil],@"采集测试不完成任务且可清理");
    } @finally {
        ut_ui(^{ method_setImplementation(method,original);window.hidden=YES;window.rootViewController=nil;[(id)delegate setValue:nil forKey:@"window"];delegate=nil;[ut_window makeKeyAndVisible];if(lock>=0)close(lock); });imp_removeBlock(replacement);
    }
}

// 在普通模拟器窗口内持续操作生产HUD及真实提醒服务。
static void ut_hdbg(BOOL seed) {
    TTTaskHUD *hud = [TTTaskHUD new]; UIViewController *host = ut_window.rootViewController;
    [host addChildViewController:hud]; hud.view.frame = host.view.bounds; hud.view.hidden = YES;
    [host.view addSubview:hud.view]; [hud didMoveToParentViewController:host];
    __weak TTTaskHUD *weakHUD = hud; __weak UIViewController *weakHost = host;
    hud.windowMode = ^(NSInteger mode) {
        UIView *view = weakHUD.view; UIView *parent = weakHost.view;
        view.hidden = mode == 0;
        view.frame = mode == 2 ? lb_hudfrm(parent.bounds, parent.safeAreaInsets, UIInterfaceOrientationPortrait) : parent.bounds;
        view.autoresizingMask = mode == 2 ? UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin
            : UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        NSLog(@"HUDInspect mode=%ld", (long)mode);
    };
    ut_req(lb_svcfg(@{@"enabled":@YES}), @"保存独立调试配置");
    ut_sched = [[TaskReminder alloc] initAt:ut_store.path handler:^(NSDictionary *alert, NSError *error) {
        NSLog(@"HUDInspect occurrence=%@ error=%@", alert[@"occurrence_id"] ?: @"idle", error.localizedDescription ?: @"");
        [weakHUD display:alert error:error];
    } cleanup:^{ [weakHUD stop]; } finish:^(__unused BOOL restart) {}];
    hud.reminder = ut_sched;
    ut_req([ut_sched start:nil], @"启动同一生产提醒服务");
    if (seed) {
        NSString *notes = [@"调试正文\n" stringByPaddingToLength:600 withString:@"检查长正文滚动与按钮位置。\n" startingAtIndex:0];
        NSMutableDictionary *fields=[@{@"title":@"调试待办", @"notes":notes, @"due_at":@(NSDate.date.timeIntervalSince1970 + 1), @"schedule_kind":@"timed"} mutableCopy];
        if ([ut_args containsObject:@"--signal-inspect"]) [fields addEntriesFromDictionary:@{@"title":@"声振联动验收",@"notes":@"检查字段、提交和附件操作。",@"urgency":@3,@"difficulty":@3,@"planned_duration":@1500}];
        ut_req([ut_store crtTsk:fields error:nil] != nil, @"创建独立调试待办");
    }
    [ut_store.path writeToFile:[ut_docs stringByAppendingPathComponent:@"HUDInspectStore.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
    BOOL signalInspect = [ut_args containsObject:@"--signal-inspect"];
    BOOL hudInspect = signalInspect || [ut_args containsObject:@"--hud-inspect"];
    if (hudInspect) { lb_tstpath = [ut_docs stringByAppendingPathComponent:@"hud-inspect.plist"]; lb_tstlock = "/tmp/trolltask-hud-inspect.lock"; }
    NSString *path = [ut_docs stringByAppendingPathComponent:hudInspect ? (signalInspect ? @"SignalInspect.sqlite3" : @"HUDInspect.sqlite3") : [NSUUID.UUID.UUIDString stringByAppendingString:@".sqlite3"]];
    BOOL seed = hudInspect && ![NSFileManager.defaultManager fileExistsAtPath:path];
    ut_store = [[TaskStore alloc] initAt:path error:nil]; ut_checks = [NSMutableArray array];
    TaskHome *home = [[TaskHome alloc] initWithStore:ut_store settings:nil];
    ut_nav = [[UINavigationController alloc] initWithRootViewController:home]; ut_nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; ut_window = self.window;
    UIViewController *host = [UIViewController new]; self.window.rootViewController = host;
    [host addChildViewController:ut_nav]; ut_nav.view.frame = host.view.bounds;
    [host.view addSubview:ut_nav.view]; [ut_nav didMoveToParentViewController:host];
    [self.window makeKeyAndVisible]; ut_nav.view.frame = self.window.bounds;
    if (hudInspect) { ut_hdbg(seed); return YES; }
    if ([ut_args containsObject:@"--inspect"]) {
        [ut_store.path writeToFile:[ut_docs stringByAppendingPathComponent:@"InspectStore.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{ ut_mon(); }); return YES;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            BOOL passed = YES; NSString *failure = @"";
            @try {
                BOOL phase5 = [ut_args containsObject:@"--phase05"];
                BOOL phase6 = [ut_args containsObject:@"--phase06"];
                BOOL phase7 = [ut_args containsObject:@"--phase07"];
                BOOL phase8 = [ut_args containsObject:@"--phase08"];
                BOOL phase9 = [ut_args containsObject:@"--phase09"];
                BOOL phase12 = [ut_args containsObject:@"--phase12"];
                BOOL phase13 = [ut_args containsObject:@"--phase13"];
                BOOL visual = [ut_args containsObject:@"--ui-refresh"];
                BOOL pages = [ut_args containsObject:@"--ui-pages"];
                BOOL closure = [ut_args containsObject:@"--closure"];
                BOOL bridge = [ut_args containsObject:@"--capture-bridge"];
                BOOL settingsOnly = [ut_args containsObject:@"--settings-only"];
                BOOL signalOnly = [ut_args containsObject:@"--signal"];
                BOOL parityOnly = [ut_args containsObject:@"--parity"];
                if (parityOnly) { ut_prty(); if (@available(iOS 16.0,*)) { ut_refs(); ut_clsr(); ut_edit(); } }
                else if (signalOnly) { ut_signal(); }
                else if (settingsOnly) { ut_sttng(); }
                else if (bridge) { ut_bridge(); }
                else if (closure) { if (@available(iOS 16.0,*)) ut_clsr(); }
                else if (visual || pages) { ut_run(); if (@available(iOS 16.0,*)) ut_refs(); ut_sttng(); if(!pages) { ut_diag(); ut_hud(); } }
                else if (phase12 || phase13) { ut_sttng(); if (phase13) ut_diag(); ut_hud(); }
                else {
                if (!phase5 && !phase6 && !phase7 && !phase8 && !phase9) { ut_run(); if (@available(iOS 16.0,*)) ut_refs(); ut_sttng(); }
                if (@available(iOS 16.0,*)) { if (!phase6 && !phase7 && !phase8 && !phase9) { ut_clsr(); ut_edit(); } if (!phase5 && !phase7 && !phase8 && !phase9) ut_rpt(); }
                if (!phase5 && !phase6 && !phase8 && !phase9) ut_schd();
                if (!phase5 && !phase6 && !phase7 && !phase9) ut_svc();
                if (!phase5 && !phase6 && !phase7 && !phase8) ut_hud();
                if (!phase5 && !phase6 && !phase7 && !phase8 && !phase9) ut_bridge();
                if (!phase5 && !phase6 && !phase7 && !phase8 && !phase9) ut_signal();
                if (!phase5 && !phase6 && !phase7 && !phase8 && !phase9) ut_prty();
                }
            } @catch (NSException *exception) { passed = NO; failure = exception.reason; }
            __block NSString *device, *runtime;
            ut_ui(^{ device = UIDevice.currentDevice.model; runtime = UIDevice.currentDevice.systemVersion; });
            NSDictionary *report = @{@"passed": @(passed), @"failure": failure, @"checks": ut_checks,
                @"device": device, @"runtime": runtime, @"arguments": ut_args, @"finished_at": @([NSDate date].timeIntervalSince1970)};
            NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
            [data writeToFile:[ut_docs stringByAppendingPathComponent:@"UITestReport.json"] atomically:YES];
            // 在独立验收界面提供当前报告，避免取报告时重启测试。
            ut_ui(^{ UILabel *result = [UILabel new]; result.text = passed ? @"验收通过" : @"验收失败"; result.textColor = UIColor.whiteColor; result.backgroundColor = UIColor.blackColor; result.frame = CGRectMake(0,60,ut_window.bounds.size.width,44); result.accessibilityIdentifier = @"ui.report"; result.accessibilityValue = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]; [ut_window addSubview:result]; });
            NSLog(@"UITest passed=%d %@", passed, failure);
        }
    }); return YES;
}
@end
// 启动原生UIKit测试，不运行生产HUD或访问共享生产路径。
int main(int argc, char **argv) { @autoreleasepool { NSMutableArray *args = [NSMutableArray array]; for (int index = 0; index < argc; index++) [args addObject:@(argv[index])]; ut_args = args.copy; return UIApplicationMain(argc, argv, nil, NSStringFromClass(UITestDel.class)); } }
