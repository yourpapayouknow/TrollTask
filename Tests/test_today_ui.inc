// 检查页签内容、触摸范围及紧凑顶栏的真实布局。
static void ut_tabgeo(void) {
    ut_ui(^{
        [ut_surface()layoutIfNeeded];UIScrollView *strip=(UIScrollView *)ut_find(ut_surface(),@"home.tabs");UIStackView *tabs=nil;for(UIView *view in strip.subviews)if([view isKindOfClass:UIStackView.class])tabs=(UIStackView *)view;
        ut_req(strip.bounds.size.height==48 && strip.frame.origin.y-ut_top().view.safeAreaInsets.top==64,@"标准顶栏56点页签48点间距8点");
        NSArray *ids=[tabs.arrangedSubviews valueForKey:@"accessibilityIdentifier"];ut_req(ids.count>=5 && [ids[0]isEqual:@"list.today"] && [ids[1]isEqual:[@"list." stringByAppendingString:TS_RTN_LST]] && [ids[2]isEqual:@"list.starred"] && [ids[3]isEqual:[@"list." stringByAppendingString:TS_DFLT_LST]],@"页签按今日常律星标及原清单顺序排列");
        NSMutableArray *report=[NSMutableArray new];
        for(UIButton *button in tabs.arrangedSubviews){
            ut_req(button.bounds.size.width>=44 && button.bounds.size.height>=44,@"每个页签触摸区至少44点");CGRect content=CGRectNull;
            if(button.titleLabel.text.length)content=[button.titleLabel convertRect:button.titleLabel.bounds toView:button];
            if(button.imageView.image)content=CGRectUnion(content,[button.imageView convertRect:button.imageView.bounds toView:button]);
            ut_req(!CGRectIsNull(content) && fabs(CGRectGetMidX(content)-CGRectGetMidX(button.bounds))<1 && fabs(CGRectGetMidY(content)-CGRectGetMidY(button.bounds))<1,@"文字和图标整体位于页签中央");
            [report addObject:@{@"id":button.accessibilityIdentifier,@"width":@(button.bounds.size.width),@"height":@(button.bounds.size.height),@"content":NSStringFromCGRect(content),@"font":@(button.titleLabel.font.pointSize)}];
        }
        NSString *count=((UIButton *)ut_find(ut_surface(),@"list.starred")).configuration.title ?: @"0";
        [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]writeToFile:[ut_docs stringByAppendingPathComponent:[NSString stringWithFormat:@"TabGeometry-%@.json",count]] atomically:YES];
    });
}
// 通过真实原生控件验证今日律与统一创建门禁。
static void ut_tdy(void) {
    ut_home();ut_ui(^{ut_req([((UILabel *)ut_find(ut_surface(),@"home.title")).text isEqual:@"TrollTask"],@"主页只保留应用名且不重复清单标签");});
    ut_wait(^BOOL{return ut_find(ut_surface(),[@"list." stringByAppendingString:TS_DFLT_LST])!=nil;},@"首页清单读取完成");ut_tabgeo();
    __block CGPoint headingCenter;__block CGRect settingsFrame;
    ut_ui(^{[ut_surface() layoutIfNeeded];headingCenter=ut_find(ut_surface(),@"home.title").center;settingsFrame=ut_find(ut_surface(),@"home.settings").frame;ut_req(!ut_find(ut_surface(),@"home.agenda") && !ut_find(ut_surface(),@"agenda.timeline"),@"今日律只呈现执行列表");});
    ut_ui(^{UIButton *add=(UIButton *)ut_find(ut_surface(),@"home.create");ut_req(ut_find(ut_surface(),@"home.toolbar").hidden && !add.enabled,@"今日律隐藏整条底栏并禁用新增");[add sendActionsForControlEvents:UIControlEventTouchUpInside];[(UIButton *)ut_find(ut_surface(),@"home.lists") sendActionsForControlEvents:UIControlEventTouchUpInside];[(UIButton *)ut_find(ut_surface(),@"home.more") sendActionsForControlEvents:UIControlEventTouchUpInside];ut_req([ut_top()isKindOfClass:TaskHome.class] && !ut_top().presentedViewController,@"隐藏底栏按钮不能绕过页面保护");[ut_surface()layoutIfNeeded];ut_req(fabs(CGRectGetMaxY(ut_table().frame)-CGRectGetMaxY(ut_top().view.safeAreaLayoutGuide.layoutFrame))<1,@"今日正文延伸至安全区底部");});
    NSUInteger index=[ut_args indexOfObject:@"--fixture"];ut_req(index!=NSNotFound && index+1<ut_args.count,@"确定性AI夹具地址已提供");
    ut_ui(^{[NSUserDefaults.standardUserDefaults setObject:ut_args[index+1] forKey:@"assistant.endpoint"];[NSUserDefaults.standardUserDefaults setObject:@"deepseek-v4.1-flash" forKey:@"assistant.model"];});
    NSCalendar *cal=NSCalendar.currentCalendar;double day=[cal startOfDayForDate:NSDate.date].timeIntervalSince1970,now=ceil(NSDate.date.timeIntervalSince1970/60)*60;
    NSDictionary *work=[ut_store crtTsk:@{@"title":@"工作时段",@"list_id":TS_RTN_LST,@"routine_kind":@"work",@"routine_end":@1439,@"due_at":@(day),@"timezone_id":NSTimeZone.localTimeZone.name,@"recurrence_type":@"daily"} error:nil];
    NSDictionary *list=[ut_store crtLst:@"其他清单" error:nil];
    NSDictionary *longList=[ut_store crtLst:@"一个需要完整滚动显示的长清单" error:nil];
    NSDictionary *a=[ut_store crtTsk:@{@"title":@"今日任务甲",@"due_at":@(now+120),@"planned_duration":@600} error:nil];
    NSDictionary *b=[ut_store crtTsk:@{@"title":@"今日任务乙",@"list_id":list[@"list_id"],@"due_at":@(now+900),@"planned_duration":@600} error:nil];
    NSDictionary *future=[ut_store crtTsk:@{@"title":@"明日任务",@"due_at":@(day+86400+12*3600),@"planned_duration":@600} error:nil];
    ut_req(work && a && b && future,@"独立数据库创建今日及未来夹具");
    ut_ui(^{[(TaskHome *)ut_nav.viewControllers.firstObject rfrsh];});ut_wait(^BOOL{return ut_find(ut_surface(),[@"task." stringByAppendingString:a[@"task_id"]])!=nil;},@"今日律显示我的任务中的今日内容");
    NSMutableArray *stars=[NSMutableArray new];for(NSUInteger n=0;n<12;n++){NSDictionary *row=[ut_store crtTsk:@{@"title":[NSString stringWithFormat:@"星标排版%lu",(unsigned long)n],@"starred":@YES} error:nil];ut_req(row!=nil,@"创建隔离星标计数夹具");[stars addObject:row];}
    ut_ui(^{[(TaskHome *)ut_nav.viewControllers.firstObject rfrsh];});ut_wait(^BOOL{return [((UIButton *)ut_find(ut_surface(),@"list.starred")).configuration.title isEqual:@"12"];},@"两位星标计数更新");ut_tabgeo();
    for(NSDictionary *row in stars)ut_req([ut_store delTsk:row[@"task_id"] error:nil],@"清理星标计数夹具");ut_ui(^{[(TaskHome *)ut_nav.viewControllers.firstObject rfrsh];});ut_wait(^BOOL{return !((UIButton *)ut_find(ut_surface(),@"list.starred")).configuration.title.length;},@"零星标不占用数字名额");
    ut_tap([@"list." stringByAppendingString:longList[@"list_id"]]);ut_wait(^BOOL{[ut_surface()layoutIfNeeded];UIScrollView *strip=(UIScrollView *)ut_find(ut_surface(),@"home.tabs");UIView *selected=ut_find(ut_surface(),[@"list." stringByAppendingString:longList[@"list_id"]]);CGRect rect=[selected convertRect:selected.bounds toView:strip];NSDictionary *probe=@{@"selected":NSStringFromCGRect(rect),@"viewport":NSStringFromCGRect(strip.bounds)};[[NSJSONSerialization dataWithJSONObject:probe options:0 error:nil]writeToFile:[ut_docs stringByAppendingPathComponent:@"TabVisibility.json"] atomically:YES];return CGRectGetMinX(rect)>=CGRectGetMinX(strip.bounds)-1 && CGRectGetMaxX(rect)<=CGRectGetMaxX(strip.bounds)+1;},@"远端长清单选中后完整滚入可见区");
    __block UIButton *previousStar;ut_ui(^{UIScrollView *strip=(UIScrollView *)ut_find(ut_surface(),@"home.tabs");[strip setContentOffset:CGPointZero animated:NO];previousStar=(UIButton *)ut_find(ut_surface(),@"list.starred");[(TaskHome *)ut_nav.viewControllers.firstObject rfrsh];});
    ut_wait(^BOOL{return ut_find(ut_surface(),@"list.starred")!=previousStar;},@"等待普通数据刷新重建页签");ut_ui(^{ut_req(fabs(((UIScrollView *)ut_find(ut_surface(),@"home.tabs")).contentOffset.x)<1,@"数据刷新不打断用户横向浏览位置");});ut_tap(@"list.today");ut_tabgeo();
    ut_ui(^{ut_req(ut_find(ut_surface(),[@"task." stringByAppendingString:b[@"task_id"]])!=nil,@"今日律跨清单综合展示");ut_req(ut_find(ut_surface(),[@"task." stringByAppendingString:future[@"task_id"]])==nil,@"未来任务不混入今日律");});
    ut_ui(^{UIButton *circle=(UIButton *)ut_find(ut_surface(),[@"task." stringByAppendingString:a[@"task_id"]]);ut_req(!circle.hidden && !circle.enabled,@"今日律只保留待到期提交圆圈");ut_req(ut_find(ut_surface(),[@"star." stringByAppendingString:a[@"task_id"]]).hidden,@"今日律不显示星标操作");UITableView *table=ut_table();[table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];ut_req([ut_top()isKindOfClass:TaskHome.class],@"今日律点正文不能进入编辑");});
    ut_shot(@"today-dark-320.png",320,693,NO);ut_shot(@"today-large-320.png",320,850,YES);
    ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;});ut_shot(@"today-light-375.png",375,850,NO);ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;});
    ut_tap([@"list." stringByAppendingString:TS_RTN_LST]);ut_wait(^BOOL{return [ut_nav.topViewController isKindOfClass:TaskHome.class] && !ut_nav.transitionCoordinator;},@"常律页签在首页直接切换");
    ut_ui(^{ut_req(ut_nav.viewControllers.count==1,@"切换常律不增加导航层级");ut_req(!ut_find(ut_surface(),@"home.toolbar").hidden && ((UIButton *)ut_find(ut_surface(),@"home.create")).enabled,@"常律保留首页新增入口");ut_req(ut_find(ut_surface(),[@"list." stringByAppendingString:TS_RTN_LST]).accessibilityTraits & UIAccessibilityTraitSelected,@"常律页签正确选中");for(UITableViewCell *cell in ut_table().visibleCells)for(NSDictionary *task in [ut_store lsPnd:nil])if([task[@"list_id"]isEqual:TS_RTN_LST]){UIView *check=ut_find(cell,[@"task." stringByAppendingString:task[@"task_id"]]);if(check)ut_req(check.hidden && !ut_find(cell,[@"star." stringByAppendingString:task[@"task_id"]]),@"常律行仅编辑不提供完成和星标");}});
    ut_tap(@"home.more");ut_wait(^BOOL{return ut_find(ut_surface(),@"rules.import")!=nil;},@"常律菜单保留导入入口");ut_tap(@"rules.import");ut_wait(^BOOL{return [ut_top()isKindOfClass:UIDocumentPickerViewController.class] && !ut_top().isBeingPresented;},@"常律导入打开原生文件选择器");
    NSUInteger importCount=[ut_store lsTsks:nil].count;
    ut_ui(^{UIDocumentPickerViewController *picker=(UIDocumentPickerViewController *)ut_top();[picker.delegate documentPickerWasCancelled:picker];[picker dismissViewControllerAnimated:NO completion:nil];});
    ut_wait(^BOOL{return ut_find(ut_surface(),@"home.more") && !ut_top().presentedViewController;},@"取消导入返回常律管理");ut_req([ut_store lsTsks:nil].count==importCount,@"取消导入不写任务");
    NSURL *file=[NSURL fileURLWithPath:[ut_docs stringByAppendingPathComponent:@"calendar-scope.md"]];
    ut_req([@"# TrollTask常律模板v1\n## 周一\n- 07:00~07:30 [工作] 日历入口导入验收\n" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil],@"创建独立时间表夹具");
    ut_tap(@"home.more");ut_wait(^BOOL{return ut_find(ut_surface(),@"rules.import")!=nil;},@"常律菜单保留导入入口");ut_tap(@"rules.import");ut_wait(^BOOL{return [ut_top()isKindOfClass:UIDocumentPickerViewController.class] && !ut_top().isBeingPresented;},@"常律导入可再次打开");
    ut_ui(^{UIDocumentPickerViewController *picker=(UIDocumentPickerViewController *)ut_top();[picker.delegate documentPicker:picker didPickDocumentsAtURLs:@[file]];});
    ut_wait(^BOOL{return [ut_top()isKindOfClass:UIAlertController.class] && [ut_top().title isEqual:@"已导入常律"] && !ut_top().isBeingPresented;},@"常律导入仍沿用原事务成功返回");
    NSDictionary *imported=nil;for(NSDictionary *row in [ut_store lsTsks:nil])if([row[@"title"]isEqual:@"日历入口导入验收"])imported=row;
    ut_req(imported && [imported[@"routine_enabled"]boolValue],@"导入常律直接启用");ut_ui(^{[ut_top()dismissViewControllerAnimated:NO completion:nil];});ut_req([ut_store delTsk:imported[@"task_id"] error:nil],@"清理独立导入夹具");
    ut_wait(^BOOL{return [ut_top()isKindOfClass:TaskHome.class] && !ut_top().presentedViewController;},@"导入结果退出后回到常律首页");
    ut_ui(^{ut_req(!ut_find(ut_surface(),@"agenda.timeline"),@"常律管理不混入执行时间轴");ut_req(!ut_find(ut_top().view,@"home.agenda"),@"常律清单隐藏首页日历");ut_req(ut_nav.viewControllers.count==1,@"导入退出仍停留常律首页");[ut_nav popToRootViewControllerAnimated:NO];});ut_home();
    ut_rte(work);ut_ui(^{ut_req(!ut_find(ut_surface(),@"edit.star") && !ut_find(ut_surface(),@"edit.complete") && !ut_find(ut_surface(),@"edit.series"),@"常律详情只有编辑而无星标或完成操作");[ut_nav popToRootViewControllerAnimated:NO];});ut_home();
    ut_tap([@"list." stringByAppendingString:TS_DFLT_LST]);ut_wait(^BOOL{return [(UIButton *)ut_find(ut_surface(),@"home.create") isEnabled];},@"切换普通清单后恢复创建入口");
    ut_ui(^{[ut_surface()layoutIfNeeded];UIButton *add=(UIButton *)ut_find(ut_surface(),@"home.create");ut_req(!ut_find(ut_surface(),@"home.toolbar").hidden && CGSizeEqualToSize(add.bounds.size,CGSizeMake(56,56)),@"普通清单恢复56点圆形创建按钮");ut_req(CGSizeEqualToSize(add.imageView.image.size,CGSizeMake(32,32)) && fabs(add.imageView.bounds.size.width-32)<1,@"创建加号采用32点同源图形");ut_req(fabs(CGRectGetMidX([add.imageView convertRect:add.imageView.bounds toView:add])-CGRectGetMidX(add.bounds))<1 && fabs(CGRectGetMidY([add.imageView convertRect:add.imageView.bounds toView:add])-CGRectGetMidY(add.bounds))<1,@"放大加号仍在圆形中央");ut_req(fabs(CGRectGetMaxY(ut_top().view.safeAreaLayoutGuide.layoutFrame)-CGRectGetMaxY(ut_table().frame)-56)<1,@"普通清单保留底栏操作空间");});
    ut_ui(^{ut_req(!ut_find(ut_surface(),@"home.agenda"),@"普通清单只呈现列表");[ut_surface() layoutIfNeeded];NSDictionary *headerProbe=@{@"before_title":NSStringFromCGPoint(headingCenter),@"after_title":NSStringFromCGPoint(ut_find(ut_surface(),@"home.title").center),@"before_settings":NSStringFromCGRect(settingsFrame),@"after_settings":NSStringFromCGRect(ut_find(ut_surface(),@"home.settings").frame)};[[NSJSONSerialization dataWithJSONObject:headerProbe options:0 error:nil]writeToFile:[ut_docs stringByAppendingPathComponent:@"HeaderStable.json"] atomically:YES];ut_req(fabs(headingCenter.x-ut_find(ut_surface(),@"home.title").center.x)<0.000001 && fabs(headingCenter.y-ut_find(ut_surface(),@"home.title").center.y)<0.000001 && CGRectEqualToRect(settingsFrame,ut_find(ut_surface(),@"home.settings").frame),@"切换清单不移动标题与设置");});
    ut_shot(@"inventory-list-320.png",320,693,NO);
    ut_tap(@"list.starred");ut_ui(^{ut_req(!ut_find(ut_surface(),@"home.agenda"),@"星标清单只呈现列表");});
    ut_tap([@"list." stringByAppendingString:list[@"list_id"]]);ut_ui(^{ut_req(!ut_find(ut_surface(),@"home.agenda"),@"自建清单只呈现列表");});
    ut_tap(@"list.today");
    ut_ui(^{[ut_surface()layoutIfNeeded];ut_req(ut_find(ut_surface(),@"home.toolbar").hidden && fabs(CGRectGetMaxY(ut_table().frame)-CGRectGetMaxY(ut_top().view.safeAreaLayoutGuide.layoutFrame))<1,@"返回今日律再次收起底栏并释放正文空间");});
    ut_tap([@"list." stringByAppendingString:TS_DFLT_LST]);
    ut_wait(^BOOL{return ut_find(ut_surface(),[@"task." stringByAppendingString:a[@"task_id"]])!=nil;},@"原清单任务行完成绑定");
    ut_ui(^{UITableView *table=ut_table();[table reloadData];[table layoutIfNeeded];UIView *check=nil;for(UITableViewCell *cell in table.visibleCells){UIView *found=ut_find(cell,[@"task." stringByAppendingString:a[@"task_id"]]);if(found){check=found;break;}}ut_req(check.hidden,[NSString stringWithFormat:@"普通清单没有完成圆圈：%@，首页%@",check,((UILabel *)ut_find(ut_surface(),@"home.title")).text]);ut_req(!ut_find(ut_surface(),[@"star." stringByAppendingString:a[@"task_id"]]).hidden,@"普通清单保留星标");});
    // 普通创建必须停在评估页，返回不写库。
    ut_tap(@"home.create");ut_title(@"评估创建验收");ut_tap(@"edit.save");
    ut_wait(^BOOL{return ut_find(ut_surface(),@"intake.start")!=nil && !ut_nav.transitionCoordinator;},@"快捷创建统一进入评估门禁");
    NSUInteger before=[ut_store lsTsks:nil].count;
    ut_ui(^{UIDatePicker *start=(UIDatePicker *)ut_find(ut_surface(),@"intake.start"),*end=(UIDatePicker *)ut_find(ut_surface(),@"intake.end");start.date=[NSDate dateWithTimeIntervalSince1970:day+86400+9*3600];end.date=[NSDate dateWithTimeIntervalSince1970:day+86400+12*3600];((UIDatePicker *)ut_find(ut_surface(),@"intake.start.time")).date=start.date;((UIDatePicker *)ut_find(ut_surface(),@"intake.end.time")).date=end.date;[end sendActionsForControlEvents:UIControlEventValueChanged];((UITextField *)ut_find(ut_surface(),@"intake.minutes")).text=@"30";});

    ut_ui(^{UIButton *button=(UIButton *)ut_find(ut_surface(),@"intake.save");ut_req(button && button.enabled,[NSString stringWithFormat:@"保存门禁可操作：%@ %@ %@",ut_top().class,button.accessibilityValue,button.currentTitle]);});
    ut_tap(@"intake.save");
    ut_wait(^BOOL{return [ut_store lsTsks:nil].count==before+1 || [ut_top() isKindOfClass:UIAlertController.class] || [ut_top() isKindOfClass:TaskHome.class];},@"评估保存有可见结果");
    ut_req([ut_store lsTsks:nil].count<=before+1,@"一次确认最多创建一个正式任务");
    if([ut_top() isKindOfClass:UIAlertController.class])ut_ui(^{[ut_top() dismissViewControllerAnimated:NO completion:nil];});
    ut_ui(^{[ut_nav popToRootViewControllerAnimated:NO];});ut_home();
    NSDictionary *created=nil;for(NSDictionary *row in [ut_store lsTsks:nil])if([row[@"title"]isEqual:@"评估创建验收"])created=row;
    if(created){ut_req([created[@"planning_mode"]isEqual:@"window"],@"确认后正式保存窗口任务");
        ut_edt(created);ut_ui(^{ut_req(!ut_find(ut_surface(),@"edit.complete") && ut_action(ut_surface(),@"detail.star") && ut_action(ut_surface(),@"detail.history"),@"普通详情菜单保留星标与记录且不能绕过HUD完成");});ut_tap(@"detail.edit");ut_wait(^BOOL{return ut_find(ut_surface(),@"intake.start")!=nil && !ut_nav.transitionCoordinator;},@"已创建任务可重新编辑评估");ut_shot(@"intake-dark-320.png",320,850,NO);ut_shot(@"intake-large-320.png",320,1000,YES);ut_ui(^{[ut_nav popToRootViewControllerAnimated:NO];});ut_home();}
    // 未来清单保留自己的库存，今日不是新建数据库或复制任务。
    ut_tap([@"list." stringByAppendingString:TS_DFLT_LST]);ut_wait(^BOOL{return ut_find(ut_surface(),[@"task." stringByAppendingString:future[@"task_id"]])!=nil;},@"我的任务仍展示未来库存");ut_ui(^{ut_req(ut_find(ut_surface(),[@"task." stringByAppendingString:a[@"task_id"]])!=nil,@"今日任务在原清单仍有编辑入口");});ut_tap(@"list.today");
    // 真实提醒窗口漏显示时，圆圈重新显示原轮次且保留附件。
    __block TTTaskHUD *hud;__block NSDictionary *active;__block NSUInteger reopened=0;
    ut_ui(^{hud=[TTTaskHUD new];UIViewController *host=ut_window.rootViewController;[host addChildViewController:hud];hud.view.frame=host.view.bounds;[host.view addSubview:hud.view];[hud didMoveToParentViewController:host];hud.view.hidden=YES;__weak TTTaskHUD *weakHUD=hud;hud.windowMode=^(NSInteger mode){weakHUD.view.hidden=mode==0;};ut_req(lb_svcfg(@{@"enabled":@YES}),@"启用隔离提醒服务");ut_sched=[[TaskReminder alloc]initAt:ut_store.path handler:^(NSDictionary *value,NSError *error){active=value;if([value[@"manual_reopen"]boolValue])reopened++;[weakHUD display:value error:error];}cleanup:^{[weakHUD stop];}finish:^(__unused BOOL r){}];hud.reminder=ut_sched;ut_req([ut_sched start:nil],@"启动真实补弹调度链路");});
    NSDictionary *missed=[ut_store crtTsk:@{@"title":@"补弹验收甲",@"due_at":@(NSDate.date.timeIntervalSince1970-60)} error:nil];
    ut_wait(^BOOL{return [active[@"task_id"]isEqual:missed[@"task_id"]] && hud.mode==1;},@"调度器认领原有到期轮次");NSString *occ=active[@"occurrence_id"];
    ut_ui(^{[(UIButton *)ut_find(hud.view,@"hud.complete") sendActionsForControlEvents:UIControlEventTouchUpInside];UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(20,20)];UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *c){(void)c;[UIColor.orangeColor setFill];UIRectFill(CGRectMake(0,0,20,20));}];[hud acceptImage:image method:@"image" occID:occ];hud.view.hidden=YES;[(TaskHome *)ut_nav.viewControllers.firstObject rfrsh];});
    NSDictionary *next=[ut_store crtTsk:@{@"title":@"补弹验收乙",@"due_at":@(NSDate.date.timeIntervalSince1970-30)} error:nil];
    ut_tap([@"task." stringByAppendingString:missed[@"task_id"]]);ut_wait(^BOOL{NSDictionary *probe=@{@"reopened":@(reopened),@"hidden":@(hud.view.hidden),@"active":active ?: @{},@"top":ut_top().title ?: @"",@"note":[TaskToday note:ut_store]};[[NSJSONSerialization dataWithJSONObject:probe options:0 error:nil]writeToFile:[ut_docs stringByAppendingPathComponent:@"RetryProbe.json"] atomically:YES];return reopened>0 && !hud.view.hidden;},@"今日圆圈通过Darwin和真实Scheduler恢复漏显HUD");
    ut_ui(^{ut_req([active[@"occurrence_id"]isEqual:occ] && ut_hcnt(hud)==1 && !ut_find(hud.view,@"hud.choices").hidden,@"补弹不换轮次、不丢附件且保留提交状态");ut_req([[ut_store rdTsk:missed[@"task_id"] error:nil][@"status"]isEqual:@"needsAction"],@"圆圈只补弹不直接完成任务");[(UIButton *)ut_find(hud.view,@"hud.back") sendActionsForControlEvents:UIControlEventTouchUpInside];});
    ut_wait(^BOOL{return [active[@"task_id"]isEqual:next[@"task_id"]];},@"HUD附件提交后才依次展示下一项");ut_req([ut_store lsOcc:missed[@"task_id"] error:nil].count==1 && [[ut_store lsOcc:missed[@"task_id"] error:nil][0][@"status"]isEqual:@"resolved"],@"最终提交只有一条Resolved记录");
    ut_ui(^{[ut_sched stop];ut_sched=nil;[hud.view removeFromSuperview];[hud removeFromParentViewController];hud.windowMode=nil;hud=nil;});
    for(NSDictionary *row in @[created,a,b,future,work,missed,next])ut_req([ut_store delTsk:row[@"task_id"] error:nil],@"清理本次独立测试记录");ut_req([ut_store delLst:list[@"list_id"] error:nil] && [ut_store delLst:longList[@"list_id"] error:nil],@"清理专用清单");
}
