// 真实键盘由正式App验收，隔离宿主比较表单可见内容与底部空白。
static BOOL ut_draft_compact(UIViewController *draft) {
    UIScrollView *form=(UIScrollView *)ut_find(draft.view,@"edit.form");
    UIView *title=ut_find(draft.view,@"edit.title");
    return title.bounds.size.height>0 && form.bounds.size.height>0 && fabs(form.contentSize.height-title.bounds.size.height)<2
        && form.bounds.size.height-form.contentSize.height<24;
}

// 用普通清单的真实入口检查整日窗口、私人备注与两种星标。
static void ut_todo_create(void) {
    // 系统软键盘的可见性用正式App的真机点按另行验证。
    ut_home();ut_tap([@"list." stringByAppendingString:TS_DFLT_LST]);ut_tap(@"home.create");
    ut_wait(^BOOL{return [ut_find(ut_top().view,@"edit.title") isFirstResponder];},@"点加号自动聚焦总标题");
    ut_ui(^{UIView *page=ut_top().view;UIStackView *tools=(UIStackView *)ut_find(page,@"edit.actions");
        NSArray *ids=[tools.arrangedSubviews valueForKey:@"accessibilityIdentifier"];
        ut_req([ids[0] isEqual:@"edit.details"] && [ids[1] isEqual:@"edit.date"] && [ids[2] isEqual:@"edit.star"],@"第一页按顺序呈现备注时间星标");
        for (NSString *name in @[@"edit.details", @"edit.date"]) {
            UIButton *button=(UIButton *)ut_find(page,name);
            ut_req(button.configuration.image && !button.configuration.title.length && button.bounds.size.width==44,@"保留原尺寸的备注与时钟图标按钮");
        }
        for(NSString *name in @[@"edit.more",@"edit.repeat",@"edit.deadline",@"edit.urgency",@"edit.difficulty",@"edit.duration"])ut_req(!ut_find(page,name),name);
        ut_req(![(UIButton *)ut_find(page,@"edit.save") isEnabled],@"空白总标题不能进入下一步");});
    __block UIViewController *draft;__block UIColor *idleDate,*idleNote;
    ut_ui(^{draft=ut_top();
        idleDate=((UIButton *)ut_find(draft.view,@"edit.date")).configuration.baseForegroundColor;
        idleNote=((UIButton *)ut_find(draft.view,@"edit.details")).configuration.baseForegroundColor;});
    ut_tap(@"edit.date");
    ut_wait(^BOOL{
        UIView *page=draft.view,*form=ut_find(page,@"edit.form"),*end=ut_find(page,@"window.choose");
        CGRect viewport=[form convertRect:form.bounds toView:page],date=[end convertRect:end.bounds toView:page];
        return CGRectGetHeight(date)>=44 && CGRectContainsRect(CGRectInset(viewport,-1,-1),date);
    },@"没有键盘布局事件也能完整展开日期区");
    ut_ui(^{UIView *page=draft.view;UIStackView *dates=(UIStackView *)ut_find(page,@"window.form");
        [page layoutIfNeeded];ut_req(ut_top()==draft && !draft.presentedViewController && !dates.hidden,@"时间在当前草稿内联展开");
        UIButton *start=(UIButton *)ut_find(page,@"window.start"),*end=(UIButton *)ut_find(page,@"window.choose");
        UIButton *clock=(UIButton *)ut_find(page,@"edit.date");
        ut_req((clock.accessibilityTraits & UIAccessibilityTraitSelected) && ![clock.configuration.baseForegroundColor isEqual:idleDate],@"展开时钟后图标显示选中态");
        CGRect a=[start convertRect:start.bounds toView:page],b=[end convertRect:end.bounds toView:page];
        ut_req(fabs(CGRectGetMaxX(a)-CGRectGetMaxX(b))<1 && CGRectGetMinY(b)>=CGRectGetMaxY(a),@"起始日期与截止日期对齐且不重叠");
        UIScrollView *form=(UIScrollView *)ut_find(page,@"edit.form");
        ut_req(form.bounds.size.height-form.contentSize.height<36,@"内联时间表单没有大段空白");
        ut_req([ut_find(page,@"edit.title") isFirstResponder] && ut_find(page,@"window.picker").hidden,@"只展开日期行不收起键盘");
    });
    ut_tap(@"window.start");
    ut_ui(^{UIDatePicker *picker=(UIDatePicker *)ut_find(ut_surface(),@"window.picker");
        NSCalendar *cal=picker.calendar;NSDate *now=NSDate.date;NSDate *today=[cal startOfDayForDate:now];
        NSDate *expected=[cal component:NSCalendarUnitHour fromDate:now]<8 ? today : [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:today options:0];
        ut_req(picker.datePickerMode==UIDatePickerModeDate && picker.preferredDatePickerStyle==UIDatePickerStyleInline && [cal isDate:picker.date inSameDayAsDate:expected],@"08:00切换默认起始日，使用原地日历");
    });
    ut_wait(^BOOL{
        UIView *page=draft.view,*form=ut_find(page,@"edit.form"),*done=ut_find(page,@"window.done");
        return done && CGRectContainsRect([form convertRect:form.bounds toView:page],[done convertRect:done.bounds toView:page]);
    },@"展开日历后选定日期无需上滑即可点按");
    ut_tap(@"edit.date");
    ut_wait(^BOOL{return [ut_find(draft.view,@"edit.title") isFirstResponder];},@"收起日历后恢复标题焦点");
    ut_wait(^BOOL{return ut_draft_compact(draft);},@"收起日期与日历后恢复紧凑面板");
    ut_ui(^{UIButton *clock=(UIButton *)ut_find(draft.view,@"edit.date");
        ut_req(!(clock.accessibilityTraits & UIAccessibilityTraitSelected) && [clock.configuration.baseForegroundColor isEqual:idleDate],@"收起时钟后恢复原色和未选中状态");});
    ut_title(@"可交付的总目标");ut_tap(@"edit.details");
    ut_ui(^{UITextView *note=(UITextView *)ut_find(draft.view,@"edit.notes");ut_req(note.isFirstResponder,@"备注有独立可选输入");note.text=@"仅自己可见的备注";[note.delegate textViewDidChange:note];});
    ut_ui(^{UIButton *note=(UIButton *)ut_find(draft.view,@"edit.details");
        ut_req((note.accessibilityTraits & UIAccessibilityTraitSelected) && ![note.configuration.baseForegroundColor isEqual:idleNote],@"备注展开后图标显示选中态");});
    ut_tap(@"edit.details");
    ut_wait(^BOOL{return [ut_find(draft.view,@"edit.title") isFirstResponder] && ut_draft_compact(draft);},@"备注收起后回到标题且不留空白");
    ut_ui(^{UIButton *note=(UIButton *)ut_find(draft.view,@"edit.details");
        ut_req(!(note.accessibilityTraits & UIAccessibilityTraitSelected) && [note.configuration.baseForegroundColor isEqual:idleNote],@"备注收起后恢复未选中颜色");});
    ut_tap(@"edit.details");
    ut_ui(^{ut_req([((UITextView *)ut_find(draft.view,@"edit.notes")).text isEqual:@"仅自己可见的备注"],@"再次展开保留备注草稿");});
    ut_tap(@"edit.star");
    ut_ui(^{ut_req([ut_find(draft.view,@"edit.star").accessibilityValue isEqual:@"紧急程度高"],@"手动星标表示高紧急度");});
    ut_tap(@"edit.save");
    ut_wait(^BOOL{return ut_top()==draft && !ut_find(draft.view,@"window.picker").hidden;},@"按下一步前须在原地选择截止日期");
    ut_ui(^{UIDatePicker *picker=(UIDatePicker *)ut_find(draft.view,@"window.picker");
        NSDate *start=picker.date;UIButton *done=(UIButton *)ut_find(draft.view,@"window.done");
        ut_req(picker.datePickerMode==UIDatePickerModeDate && done.isEnabled,@"同日截止有效，截止仅选日期");
        picker.date=[picker.calendar dateByAddingUnit:NSCalendarUnitDay value:30 toDate:start options:0];[picker sendActionsForControlEvents:UIControlEventValueChanged];
        ut_req(!done.isEnabled && [((UILabel *)ut_find(draft.view,@"window.error")).text isEqual:@"任务最多30天"],@"第31天不可确认");
        picker.date=[picker.calendar dateByAddingUnit:NSCalendarUnitDay value:29 toDate:start options:0];[picker sendActionsForControlEvents:UIControlEventValueChanged];ut_req(done.isEnabled,@"第30天可确认");});
    ut_tap(@"window.done");ut_tap(@"edit.save");
    ut_wait(^BOOL{return ut_find(ut_surface(),@"intake.urgency")!=nil;},@"打开评估并显示移入的字段");
    ut_wait(^BOOL{UIView *page=ut_top().view,*footer=ut_find(page,@"intake.save");
        return footer && CGRectGetMaxY([footer convertRect:footer.bounds toView:page])>page.bounds.size.height-140;},@"第二页键盘收起后页脚落到底部");
    ut_ui(^{UIView *page=ut_top().view;UIView *urgency=ut_find(page,@"intake.urgency");
        ut_req([urgency.accessibilityValue isEqual:@"高"],@"手动星标在第二页清楚显示高紧急度");
        ut_req(ut_find(page,@"intake.difficulty") && ut_find(page,@"intake.minutes") && !ut_find(page,@"intake.notes"),@"难易程度和预计分钟进入下一页，备注留在第一步");
        ut_req(!ut_find(page,@"intake.start.time") && !ut_find(page,@"intake.end.time"),@"第二页同样只显示日期");
        UISwitch *split=(UISwitch *)ut_find(page,@"intake.split");UIButton *saveButton=(UIButton *)ut_find(page,@"intake.save");
        ut_req(split && split.on && [saveButton.configuration.title isEqual:@"下一步"],@"未评估难度默认打开拆分并显示下一步");
        [split setOn:NO animated:NO];[split sendActionsForControlEvents:UIControlEventValueChanged];
        ut_req([saveButton.configuration.title isEqual:@"评估并创建"],@"关闭拆分后主按钮改为评估并创建");
        [split setOn:YES animated:NO];[split sendActionsForControlEvents:UIControlEventValueChanged];
        ut_req([saveButton.configuration.title isEqual:@"下一步"],@"重新打开拆分恢复下一步");
        [page layoutIfNeeded];
        UIView *last=ut_find(page,@"intake.difficulty"),*footerSave=ut_find(page,@"intake.save");
        UIScrollView *form=(UIScrollView *)ut_find(page,@"intake.content");
        CGRect row=[last convertRect:last.bounds toView:page],saveRect=[footerSave convertRect:footerSave.bounds toView:page],visible=[form convertRect:form.bounds toView:page];
        ut_req(CGRectGetMaxY(row)<=CGRectGetMinY(saveRect) && CGRectGetMaxY(row)<=CGRectGetMaxY(visible),[NSString stringWithFormat:@"第二页最后一行完整位于页脚上方 row=%@ visible=%@",NSStringFromCGRect(row),NSStringFromCGRect(visible)]);});
    ut_droot();ut_req([ut_store lsTsks:nil].count==0,@"退出草稿和评估没有创建任务");
    NSCalendar *cal=NSCalendar.currentCalendar;NSDate *today=[cal startOfDayForDate:NSDate.date];
    NSDate *yesterday=[cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:today options:0],*tomorrow=[cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:today options:0],*dayAfter=[cal dateByAddingUnit:NSCalendarUnitDay value:2 toDate:today options:0];
    NSMutableDictionary *fields=[@{@"title":@"过半指示夹具",@"timezone_id":cal.timeZone.name,@"due_at":@(yesterday.timeIntervalSince1970),@"deadline_at":@(tomorrow.timeIntervalSince1970),@"planning_mode":@"window",@"schedule_kind":@"date",@"deadline_kind":@"date"} mutableCopy];
    NSDictionary *past=[ut_store crtTsk:fields error:nil];fields[@"title"]=@"未过半指示夹具";fields[@"due_at"]=@(today.timeIntervalSince1970);fields[@"deadline_at"]=@(dayAfter.timeIntervalSince1970);NSDictionary *future=[ut_store crtTsk:fields error:nil];
    ut_req(past!=nil && future!=nil,@"整日窗口已保存到隔离库");
    NSString *pastID=[@"star." stringByAppendingString:past[@"task_id"]],*futureID=[@"star." stringByAppendingString:future[@"task_id"]];
    ut_wait(^BOOL{return [ut_find(ut_surface(),pastID).accessibilityValue isEqual:@"时间已过半"] && [ut_find(ut_surface(),futureID).accessibilityValue isEqual:@"0"];},@"普通清单在窗口过半后自动点亮星标");
    ut_tap(@"list.starred");
    ut_wait(^BOOL{return ut_find(ut_surface(),pastID)!=nil && !ut_find(ut_surface(),pastID).hidden;},@"时间过半任务进入星标列表");
    ut_req(ut_find(ut_surface(),futureID)==nil || ut_find(ut_surface(),futureID).hidden,@"未过半任务不提前进入星标列表");
    ut_tap([@"list." stringByAppendingString:TS_DFLT_LST]);
    NSDictionary *saved=[ut_store rdTsk:past[@"task_id"] error:nil];ut_req([saved[@"starred"] intValue]==0 && [saved[@"urgency"] intValue]==0,@"自动亮星不改数据库星标或紧急度");
}

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
    ut_wait(^BOOL{return ut_find(ut_top().view,@"window.start")!=nil && !ut_top().isBeingPresented;},@"普通待办日期面板就绪");
    ut_ui(^{ut_req(!ut_find(ut_top().view,@"calendar.repeat"),@"普通待办移除重复设置");});
    ut_tap(@"edit.date");ut_droot();
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
