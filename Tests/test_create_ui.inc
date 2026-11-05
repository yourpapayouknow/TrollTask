// 在隔离数据库和真实UIKit中验证创建卡片的退出与保存事务。
static void ut_crtfix(void) API_AVAILABLE(ios(16.0));
static void ut_crtfix(void) {
    ut_home();ut_tap([@"list." stringByAppendingString:TS_RTN_LST]);ut_tap(@"home.create");
    ut_title(@"创建交互回归长标题用于验证卡片高度超过两百点后仍然可以退出");
    __block id<UIViewControllerTransitioningDelegate> transition;
    ut_ui(^{
        UIViewController *page=ut_top();transition=page.navigationController.transitioningDelegate;
        ut_req(!ut_find(page.view,@"edit.dateChip") && [ut_find(page.view,@"edit.schedule") isKindOfClass:UILabel.class],@"常律时间摘要只读且没有重复气泡入口");
        UITextView *title=(UITextView *)ut_find(page.view,@"edit.title");
        ut_req(title.returnKeyType==UIReturnKeyDone,@"标题键盘提供完成键");
        ut_req(![title.delegate textView:title shouldChangeTextInRange:NSMakeRange(title.text.length,0) replacementText:@"\n"] && !title.isFirstResponder,@"完成键收起键盘且不插入换行");
    });
    ut_tap(@"edit.more");
    ut_ui(^{
        UIViewController *page=ut_top();UILabel *summary=(UILabel *)ut_find(page.view,@"edit.schedule");
        ut_req(![summary.text containsString:@"–"] && ut_find(page.view,@"routine.end"),@"展开时结束时刻只显示在编辑控件");
        ut_req(page.preferredContentSize.height>200,@"退出测试覆盖超过两百点的展开卡片");
    });
    ut_tap(@"edit.date");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskCalendar.class] && !ut_top().isBeingPresented;},@"打开常律开始时间面板");
    ut_ui(^{ut_req(ut_find(ut_top().view,@"calendar.repeat").hidden,@"常律时间面板不重复提供重复设置");[ut_top() dismissViewControllerAnimated:NO completion:nil];});
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().isBeingDismissed;},@"取消时间面板返回同一草稿");
    ut_ui(^{
        UIPresentationController *dock=ut_top().navigationController.presentationController;SEL selector=NSSelectorFromString(@"swp");
        ((void (*)(id,SEL))[dock methodForSelector:selector])(dock,selector);
    });ut_home();ut_req([ut_store lsTsks:nil].count==0,@"展开卡片下拉取消不创建任务");
    ut_tap(@"home.create");ut_title(@"保存唯一验收");
    ut_ui(^{
        UIViewController *page=ut_top();UINavigationController *nav=page.navigationController;UIButton *save=(UIButton *)ut_find(page.view,@"edit.save");
        [save sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req(nav.isModalInPresentation,@"保存开始即锁定弹层关闭");
        UIPresentationController *dock=nav.presentationController;SEL selector=NSSelectorFromString(@"cls");
        ((void (*)(id,SEL))[dock methodForSelector:selector])(dock,selector);
        ut_req(nav.presentingViewController!=nil && !nav.isBeingDismissed,@"保存期间遮罩不能提前关闭");
        [save sendActionsForControlEvents:UIControlEventTouchUpInside];
    });ut_home();
    NSArray *rows=[ut_store lsTsks:nil];ut_req(rows.count==1,@"重复保存事件只产生一条任务");
    NSDictionary *created=rows.firstObject;
    // 写入只读身份字段让真实事务失败，验证关闭保护和输入恢复。
    ut_ui(^{
        NSDictionary *draft=@{@"task_id":created[@"task_id"],@"title":@"失败保留输入",@"list_id":TS_RTN_LST,@"routine_kind":@"fixed",@"routine_end":@510,@"routine_enabled":@1,@"due_at":@([NSDate dateWithTimeIntervalSinceNow:3600].timeIntervalSince1970),@"schedule_kind":@"timed",@"recurrence_type":@"daily",@"recurrence_interval":@1,@"recurrence":@[@"RRULE:FREQ=DAILY;INTERVAL=1"],@"timezone_id":NSTimeZone.localTimeZone.name};
        TaskEdit *page=[[TaskEdit alloc] initWithStore:ut_store task:nil draft:draft quick:YES saved:nil];
        UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:page];nav.modalPresentationStyle=UIModalPresentationCustom;nav.transitioningDelegate=transition;
        [ut_nav.viewControllers.firstObject presentViewController:nav animated:NO completion:nil];
    });
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskEdit.class] && ut_find(ut_top().view,@"edit.save");},@"失败事务草稿就绪");ut_tap(@"edit.save");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:UIAlertController.class];},@"真实非法字段事务返回错误");
    ut_ui(^{[ut_top() dismissViewControllerAnimated:NO completion:nil];});
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController;},@"错误提示退出后恢复原草稿");
    ut_ui(^{
        UIViewController *page=ut_top();
        ut_req(!page.navigationController.isModalInPresentation && ((UIButton *)ut_find(page.view,@"edit.save")).enabled,@"事务失败后恢复编辑和关闭入口");
        ut_req([((UITextView *)ut_find(page.view,@"edit.title")).text isEqual:@"失败保留输入"],@"事务失败保留标题草稿");
    });ut_tap(@"edit.cancel");ut_home();ut_req([ut_store lsTsks:nil].count==1,@"失败和取消均不额外落库");
    ut_tap([@"list." stringByAppendingString:TS_DFLT_LST]);ut_tap(@"home.create");ut_tap(@"edit.date");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskCalendar.class] && !ut_top().isBeingPresented;},@"普通待办日期面板就绪");
    ut_ui(^{ut_req(!ut_find(ut_top().view,@"calendar.repeat").hidden,@"普通待办保留原日期重复设置");[ut_top() dismissViewControllerAnimated:NO completion:nil];});
    ut_tap(@"edit.cancel");ut_home();
    // 两个具体时段与跨段新建冲突，提示必须列出全部事项。
    ut_req([ut_store delTsk:created[@"task_id"] error:nil],@"移除本轮保存夹具");
    NSDateComponents *parts=[NSDateComponents new];parts.year=2030;parts.month=1;parts.day=7;parts.hour=9;
    NSCalendar *calendar=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=[NSTimeZone timeZoneWithName:@"UTC"];
    double stamp=[calendar dateFromComponents:parts].timeIntervalSince1970;
    NSMutableDictionary *base=[@{@"title":@"冲突甲",@"list_id":TS_RTN_LST,@"routine_kind":@"fixed",@"routine_end":@600,@"due_at":@(stamp),@"schedule_kind":@"timed",@"recurrence_type":@"daily",@"recurrence_interval":@1,@"recurrence":@[@"RRULE:FREQ=DAILY;INTERVAL=1"],@"timezone_id":@"UTC"} mutableCopy];
    ut_req([ut_store crtTsk:base error:nil]!=nil,@"第一条冲突参考保存成功");
    base[@"title"]=@"冲突乙";base[@"due_at"]=@(stamp+3600);base[@"routine_end"]=@660;
    ut_req([ut_store crtTsk:base error:nil]!=nil,@"第二条相接参考保存成功");
    base[@"title"]=@"冲突保留输入";base[@"due_at"]=@(stamp+1800);base[@"routine_end"]=@630;
    ut_ui(^{
        TaskEdit *page=[[TaskEdit alloc]initWithStore:ut_store task:nil draft:base quick:YES saved:nil];
        UINavigationController *nav=[[UINavigationController alloc]initWithRootViewController:page];nav.modalPresentationStyle=UIModalPresentationCustom;nav.transitioningDelegate=transition;
        [ut_nav.viewControllers.firstObject presentViewController:nav animated:NO completion:nil];
    });
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskEdit.class] && ut_find(ut_top().view,@"edit.repeat");},@"冲突新建卡片就绪");
    ut_tap(@"edit.repeat");ut_wait(^BOOL{return ut_find(ut_top().view,@"repeat.type.workdays")!=nil;},@"打开常律重复规则");ut_tap(@"repeat.type.workdays");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController;},@"工作日规则返回创建卡片");
    ut_ui(^{UILabel *summary=(UILabel *)ut_find(ut_top().view,@"edit.schedule");ut_req([summary.text containsString:@"工作日"],@"修改重复规则立即同步时间摘要");ut_req(!ut_find(ut_top().view,@"routine.enabled"),@"新建没有禁用草稿开关");});
    ut_shot(@"create-repeat-summary-320.png",320,693,NO);
    long long revision=[ut_store revision:nil];ut_tap(@"edit.save");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:UIAlertController.class];},@"保存冲突返回提示");
    ut_ui(^{UIAlertController *alert=(UIAlertController *)ut_top();ut_req([alert.title isEqual:@"常律时段冲突"] && [alert.message containsString:@"冲突甲"] && [alert.message containsString:@"冲突乙"] && [alert.message containsString:@"09:00"] && [alert.message containsString:@"11:00"],@"提示包含全部冲突项和安排时间");});
    ut_shot(@"create-all-conflicts-320.png",320,693,NO);
    ut_req([ut_store revision:nil]==revision,@"冲突保存没有数据库副作用");
    ut_ui(^{[ut_top() dismissViewControllerAnimated:NO completion:nil];});
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController;},@"冲突后返回原创建卡片");
    ut_ui(^{ut_req([((UITextView *)ut_find(ut_top().view,@"edit.title")).text isEqual:@"冲突保留输入"] && !ut_top().navigationController.isModalInPresentation,@"冲突后保留输入并恢复编辑");});
    ut_tap(@"edit.cancel");ut_home();

}
