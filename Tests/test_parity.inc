// 核对日期、时间、重复与逐层草稿接续。
static void ut_pdate(void) API_AVAILABLE(ios(16.0));
static void ut_pdate(void) {
    ut_edt(nil);ut_title(@"日期接续验收");ut_tap(@"edit.date");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskCalendar.class];},@"日期抽屉就绪");
    ut_ui(^{UIDatePicker *time=(UIDatePicker *)ut_find(ut_surface(),@"calendar.time");ut_req(time.preferredDatePickerStyle==UIDatePickerStyleWheels && time.hidden && [ut_find(ut_surface(),@"calendar.timed") isKindOfClass:UIButton.class],@"日期默认显示月历和设置时间按钮");});
    ut_tap(@"calendar.timed");
    ut_ui(^{ut_req(ut_find(ut_surface(),@"calendar.month").hidden && !ut_find(ut_surface(),@"calendar.time").hidden,@"设置时间在当前面板切换系统滚轮");});
    ut_tap(@"calendar.removeTime");
    ut_ui(^{ut_req(!ut_find(ut_surface(),@"calendar.month").hidden && ut_find(ut_surface(),@"calendar.time").hidden,@"移除时间恢复日期模式");});
    ut_tap(@"calendar.timed");ut_tap(@"calendar.day");ut_tap(@"calendar.repeat");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskRepeat.class];},@"重复预设进入独立全屏页");
    ut_ui(^{ut_req(ut_top().navigationController.modalPresentationStyle==UIModalPresentationFullScreen && ut_find(ut_surface(),@"repeat.type.ordinal") && ut_find(ut_surface(),@"repeat.type.workdays") && !ut_find(ut_surface(),@"repeat.done"),@"预设包含按星期每月和工作日，选择即返回");});
    ut_tap(@"repeat.type.custom");
    ut_wait(^BOOL{return ut_find(ut_surface(),@"repeat.picker")!=nil;},@"自定义使用独立滚轮页");
    ut_ui(^{UIPickerView *picker=(UIPickerView *)ut_find(ut_surface(),@"repeat.picker");[picker selectRow:1 inComponent:0 animated:NO];[picker.delegate pickerView:picker didSelectRow:1 inComponent:0];[picker selectRow:1 inComponent:1 animated:NO];[picker.delegate pickerView:picker didSelectRow:1 inComponent:1];});
    ut_tap(@"repeat.end");ut_tap(@"repeat.end.count");
    ut_wait(^BOOL{UIView *row=ut_find(ut_surface(),@"repeat.end.count");UITextField *field=(UITextField *)ut_find(ut_surface(),@"repeat.count");return row.hidden && !field.superview.superview.hidden && ![field.superview.superview isKindOfClass:UIButton.class] && field.isAccessibilityElement;},@"次数输入独占当前选项行且可独立访问");
    ut_ui(^{UITextField *count=(UITextField *)ut_find(ut_surface(),@"repeat.count");count.text=@"7";});ut_tap(@"repeat.end.done");
    ut_wait(^BOOL{return ut_find(ut_surface(),@"repeat.picker")!=nil;},@"结束次数只交回自定义草稿");
    ut_tap(@"repeat.done");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskCalendar.class];},@"重复完成回到同一日期面板");ut_tap(@"calendar.done");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController;},@"日期完成回到同一任务草稿");
    ut_ui(^{ut_req(!ut_find(ut_surface(),@"edit.clearDate").hidden,@"日期摘要提供独立移除入口");});ut_save();ut_home();
    NSDictionary *task=nil;
    for(NSDictionary *row in [ut_store lsPnd:nil])if([row[@"title"] isEqual:@"日期接续验收"])task=row;
    NSString *rule=[task[@"recurrence"] firstObject];
    ut_req([task[@"schedule_kind"] isEqual:@"timed"] && [task[@"recurrence_interval"] isEqual:@2] && [rule containsString:@"COUNT=7"] && [rule containsString:@"FREQ=WEEKLY"],@"逐层完成只保存最终日期和完整重复条件");
    ut_edt(task);ut_tap(@"edit.clearDate");ut_save();ut_home();
    NSDictionary *cleared=[ut_store rdTsk:task[@"task_id"] error:nil];ut_req([cleared[@"schedule_kind"] isEqual:@"none"] && [cleared[@"recurrence"] count]==0,@"日期移除同步清除重复，不残留隐藏提醒");
    ut_req([ut_store delTsk:task[@"task_id"] error:nil],@"清理日期接续夹具");
    for(NSString *key in @[@"ordinal",@"workdays"]) {
        ut_edt(nil);ut_title(@"预设规则验收");ut_tap(@"edit.more");ut_tap(@"edit.repeat");ut_tap([@"repeat.type." stringByAppendingString:key]);
        ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController;},@"预设选择后立即回到草稿");ut_save();ut_home();
        NSDictionary *saved=nil;for(NSDictionary *row in [ut_store lsPnd:nil])if([row[@"title"] isEqual:@"预设规则验收"])saved=row;
        NSString *line=[saved[@"recurrence"] firstObject];ut_req([saved[@"recurrence_type"] isEqual:@"custom"] && [line containsString:[key isEqual:@"ordinal"]?@"FREQ=MONTHLY":@"BYDAY=MO,TU,WE,TH,FR"],@"新增预设交给既有完整规则引擎");
        ut_req([ut_store delTsk:saved[@"task_id"] error:nil],@"清理重复预设夹具");
    }
}

// 核对实际抽屉、输入页与返回路径，所有数据只写入模拟器夹具。
static void ut_prty(void) {
    ut_home();
    NSDictionary *listing=[ut_store crtLst:@"页面对齐" error:nil]; NSString *listID=listing[@"list_id"];
    ut_wait(^BOOL{return ut_find(ut_window,[@"list." stringByAppendingString:listID])!=nil;},@"清单夹具出现在真实页签");
    ut_tap([@"list." stringByAppendingString:listID]);ut_tap(@"home.lists");
    ut_wait(^BOOL{return ut_find(ut_surface(),listID)!=nil && ut_find(ut_surface(),@"list.starred")!=nil && !ut_top().isBeingPresented;},@"清单抽屉完成首轮布局");
    ut_ui(^{
        UIViewController *menu=ut_top();
        ut_req([menu isKindOfClass:UITableViewController.class] && !menu.navigationController,@"清单使用无导航栏底部抽屉");
        ut_req(ut_find(menu.view,@"list.starred")!=nil && ut_find(menu.view,listID)!=nil,@"抽屉同时提供星标和现有清单");
        UITableViewCell *selected=(UITableViewCell *)ut_find(menu.view,listID);
        ut_req(selected.accessoryView==nil && selected.backgroundConfiguration.backgroundColor!=nil,@"清单选中态使用整行胶囊");
    });
    ut_htch(ut_window,CGPointMake(8,80),UITouchPhaseBegan);ut_htch(ut_window,CGPointMake(8,80),UITouchPhaseEnded);
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskHome.class];},@"点击遮罩可直接退出清单抽屉");
    ut_tap(@"home.lists");ut_tap(@"list.starred");
    ut_wait(^BOOL{return [ut_find(ut_window,@"list.starred").accessibilityValue isEqual:@"已选中"];},@"抽屉星标入口切到正确页签");
    ut_tap([@"list." stringByAppendingString:listID]);ut_tap(@"home.more");
    ut_wait(^BOOL{return ut_find(ut_surface(),@"sort.more")!=nil && !ut_top().isBeingPresented;},@"选项抽屉完成布局");
    ut_ui(^{
        UITableViewController *menu=(UITableViewController *)ut_top();
        ut_req([menu.tableView numberOfRowsInSection:0]==6 && ut_find(menu.view,@"sort.more")!=nil,@"基础抽屉保留三项排序和三项维护");
        ut_req(ut_find(menu.view,@"sort.urgency")==nil,@"扩展排序不混入默认抽屉");
    });
    ut_tap(@"sort.more");ut_tap(@"sort.urgency");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskHome.class];},@"第二层排序可以执行并返回首页");
    ut_tap(@"home.lists");
    ut_wait(^BOOL{return ut_find(ut_surface(),@"list.create")!=nil && !ut_top().isBeingPresented;},@"新建清单菜单就绪");
    ut_ui(^{UITableViewController *menu=(UITableViewController *)ut_top();UITableViewCell *cell=(UITableViewCell *)ut_find(menu.view,@"list.create");NSIndexPath *path=[menu.tableView indexPathForCell:cell];[menu.tableView.delegate tableView:menu.tableView didSelectRowAtIndexPath:path];[menu.tableView.delegate tableView:menu.tableView didSelectRowAtIndexPath:path];});
    ut_wait(^BOOL{return ut_find(ut_top().view,@"list.name")!=nil;},@"新建列表进入独立输入页");
    NSUInteger count=[ut_store lsLsts:nil].count;
    ut_ui(^{
        ut_req(![ut_top() isKindOfClass:UIAlertController.class] && [ut_top().title isEqual:@"新建清单"],@"输入页有独立导航标题");ut_req(ut_nav.viewControllers.count==2,@"菜单连点只打开一个名称页");
        ut_req(![(UIButton *)ut_top().navigationItem.rightBarButtonItem.customView isEnabled],@"空名称禁用完成");
        UITextField *field=(UITextField *)ut_find(ut_top().view,@"list.name");field.text=@"   ";[field sendActionsForControlEvents:UIControlEventEditingChanged];
        ut_req(![(UIButton *)ut_top().navigationItem.rightBarButtonItem.customView isEnabled],@"纯空格不能创建列表");
        [ut_nav popViewControllerAnimated:NO];
    });
    ut_req([ut_store lsLsts:nil].count==count,@"返回输入页不会写入草稿");
    ut_tap(@"home.newlist");
    ut_wait(^BOOL{return [ut_top().title isEqual:@"新建清单"] && ut_find(ut_top().view,@"list.name")!=nil && !ut_nav.transitionCoordinator;},@"页签新建输入页就绪");
    ut_ui(^{UITextField *field=(UITextField *)ut_find(ut_top().view,@"list.name");field.text=@"新列表验收";[field sendActionsForControlEvents:UIControlEventEditingChanged];});
    ut_ui(^{UIButton *done=(UIButton *)ut_top().navigationItem.rightBarButtonItem.customView;[done sendActionsForControlEvents:UIControlEventTouchUpInside];[done sendActionsForControlEvents:UIControlEventTouchUpInside];});
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskHome.class] && [ut_store lsLsts:nil].count==count+1;},@"连续两次完成只创建一次并返回首页");
    __block NSString *created;
    for(NSDictionary *row in [ut_store lsLsts:nil]) if([row[@"title"] isEqual:@"新列表验收"])created=row[@"list_id"];
    ut_req(created!=nil,@"新列表已持久化");
    ut_wait(^BOOL{return [ut_find(ut_window,[@"list." stringByAppendingString:created]).accessibilityValue isEqual:@"已选中"];},@"创建后自动选择新列表");
    ut_tap(@"home.more");ut_tap(@"list.rename");
    ut_wait(^BOOL{return ut_find(ut_top().view,@"list.name")!=nil;},@"重命名输入页就绪");
    ut_ui(^{UITextField *field=(UITextField *)ut_find(ut_top().view,@"list.name");ut_req([field.text isEqual:@"新列表验收"] && [ut_top().title isEqual:@"重命名清单"],@"重命名进入预填名称的同一输入页");field.text=@"重命名验收";[field sendActionsForControlEvents:UIControlEventEditingChanged];});
    ut_req([ut_store delLst:created error:nil],@"外部删除本轮重命名夹具");ut_tap(@"list.done");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:UIAlertController.class];},@"保存失败显示真实数据库错误");
    ut_ui(^{[ut_top() dismissViewControllerAnimated:NO completion:nil];});
    ut_wait(^BOOL{return ut_find(ut_top().view,@"list.name")!=nil;},@"失败后仍保留输入页");
    ut_ui(^{ut_req([[(UITextField *)ut_find(ut_top().view,@"list.name") text] isEqual:@"重命名验收"],@"失败保留用户输入");[ut_nav popViewControllerAnimated:NO];});
    ut_req([ut_store delLst:listID error:nil],@"清理页面对齐夹具");ut_home();
    if(@available(iOS 16.0,*))ut_pdate();
}
