// 为逐页设计审查保存真实控件属性，不将截图成功等同于设计通过。
static void ut_pgdata(NSString *name, UIView *root, UINavigationController *nav) {
    if(![ut_args containsObject:@"--design-pages"])return;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:root],*rows=[NSMutableArray new];
    for(UIBarButtonItem *item in [(nav.topViewController.navigationItem.leftBarButtonItems ?: @[]) arrayByAddingObjectsFromArray:nav.topViewController.navigationItem.rightBarButtonItems ?: @[]])if(item.customView)[pending addObject:item.customView];
    while(pending.count){UIView *view=pending.lastObject;[pending removeLastObject];if(view.hidden || view.alpha<0.01)continue;
        NSString *key=view.accessibilityIdentifier ?: [NSString stringWithFormat:@"%@-%lu",view.class,(unsigned long)rows.count];
        NSMutableDictionary *row=[@{@"id":key,@"class":NSStringFromClass(view.class),@"frame":NSStringFromCGRect([view convertRect:view.bounds toView:root]),@"score":@100} mutableCopy];NSMutableArray *issues=[NSMutableArray new];
        if([view isMemberOfClass:UIStackView.class]){CGFloat gap=((UIStackView *)view).spacing;row[@"spacing"]=@(gap);if(![@[@4,@8,@16,@24]containsObject:@(gap)])[issues addObject:@"组件间距不符层级"];}
        if([view isKindOfClass:UIButton.class]){UIButton *button=(UIButton *)view;UIButtonConfiguration *cfg=button.configuration;row[@"title"]=cfg.title ?: [button titleForState:UIControlStateNormal] ?: @"";row[@"subtitle"]=cfg.subtitle ?: @"";
            if(cfg){row[@"radius"]=@(cfg.background.cornerRadius);row[@"padding"]=@[@(cfg.contentInsets.top),@(cfg.contentInsets.leading),@(cfg.contentInsets.bottom),@(cfg.contentInsets.trailing)];row[@"image_gap"]=@(cfg.imagePadding);
                if((cfg.contentInsets.top!=8 && cfg.contentInsets.top!=12) || cfg.contentInsets.bottom!=cfg.contentInsets.top)[issues addObject:@"按钮垂直内边距不符组件"];
                if(cfg.image && cfg.title.length && cfg.imagePadding!=8)[issues addObject:@"图文间距非8"];
                if(cfg.background.cornerRadius!=12 && ![key isEqual:@"home.create"])[issues addObject:@"按钮圆角不符组件定义"];
            }
            if(view.accessibilityIdentifier && (view.bounds.size.width<44 || view.bounds.size.height<44))[issues addObject:@"触摸区域不足44"];
            if([key isEqual:@"hud.complete"] || [key isEqual:@"hud.snooze"]){row[@"lines"]=@(button.titleLabel.numberOfLines);if(button.titleLabel.numberOfLines!=1)[issues addObject:@"HUD操作文字未保持单行"];}
            row[@"font"]=@(button.titleLabel.font.pointSize);row[@"issues"]=issues;row[@"score"]=@(100-5*issues.count);[rows addObject:row];continue;
        }
        if([view isKindOfClass:UITextView.class]){UITextView *field=(UITextView *)view;row[@"padding"]=NSStringFromUIEdgeInsets(field.textContainerInset);row[@"font"]=@(field.font.pointSize);if(view.accessibilityIdentifier && !UIEdgeInsetsEqualToEdgeInsets(field.textContainerInset,field.layer.cornerRadius>0 ? UIEdgeInsetsMake(8,12,8,12):UIEdgeInsetsMake(8,8,8,8)))[issues addObject:@"输入内容内边距不符组件"];}
        if([view isKindOfClass:UIDatePicker.class]){row[@"intrinsic"]=NSStringFromCGSize(view.intrinsicContentSize);row[@"fit_zero"]=NSStringFromCGSize([view sizeThatFits:CGSizeZero]);row[@"fit_compressed"]=NSStringFromCGSize([view systemLayoutSizeFittingSize:UILayoutFittingCompressedSize]);}
        if([view isKindOfClass:UITextField.class]){UITextField *field=(UITextField *)view;row[@"padding"]=@[@(field.leftView.bounds.size.width),@(field.rightView.bounds.size.width)];if(field.layer.cornerRadius>0 && (field.leftView.bounds.size.width!=12 || field.rightView.bounds.size.width!=12))[issues addObject:@"输入框文字侧边距非12"];}
        if([view isKindOfClass:UILabel.class]){UILabel *label=(UILabel *)view;row[@"text"]=label.text ?: @"";row[@"font"]=@(label.font.pointSize);
            if([label.text isEqual:@"检查所有子页的对齐与阅读体验"]){UIView *cell=view;while(cell && ![cell isKindOfClass:UITableViewCell.class])cell=cell.superview;NSMutableArray *parts=[NSMutableArray arrayWithArray:cell.subviews ?: @[]];NSMutableArray *offsets=[NSMutableArray new];
                while(parts.count){UIView *part=parts.lastObject;[parts removeLastObject];if(part.hidden)continue;if([part isKindOfClass:UIButton.class] && ([part.accessibilityIdentifier hasPrefix:@"star."] || [part.accessibilityIdentifier hasPrefix:@"task."])){UIButton *button=(UIButton *)part;CGRect text=[label convertRect:label.bounds toView:root];CGPoint image=[button.imageView convertPoint:CGPointMake(CGRectGetMidX(button.imageView.bounds),CGRectGetMidY(button.imageView.bounds)) toView:root];CGFloat delta=image.y-text.origin.y-label.font.lineHeight/2;[offsets addObject:@(delta)];if(fabs(delta)>1.5)[issues addObject:@"图标未对齐标题首行"];continue;}[parts addObjectsFromArray:part.subviews];}row[@"first_line_offsets"]=offsets;
            }
        }
        if([view isKindOfClass:UITableViewCell.class]){UITableViewCell *cell=(UITableViewCell *)view;if([cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]){UIListContentConfiguration *cfg=(UIListContentConfiguration *)cell.contentConfiguration;row[@"text"]=cfg.text ?: @"";row[@"subtitle"]=cfg.secondaryText ?: @"";row[@"padding"]=@[@(cfg.directionalLayoutMargins.top),@(cfg.directionalLayoutMargins.leading),@(cfg.directionalLayoutMargins.bottom),@(cfg.directionalLayoutMargins.trailing)];row[@"image_gap"]=@(cfg.imageToTextPadding);if(cfg.directionalLayoutMargins.top!=12 || cfg.directionalLayoutMargins.bottom!=12)[issues addObject:@"列表垂直内边距非12"];if(cfg.image && cfg.imageToTextPadding!=12 && cfg.imageToTextPadding!=16)[issues addObject:@"列表图文间距不符组件"];}}
        row[@"issues"]=issues;row[@"score"]=@(100-5*issues.count);if(issues.count || view.accessibilityIdentifier || [view isMemberOfClass:UIStackView.class] || [view isKindOfClass:UILabel.class])[rows addObject:row];
        BOOL calendar=NO;if(@available(iOS 16.0,*))calendar=[view isKindOfClass:UICalendarView.class];
        if([view isKindOfClass:UIControl.class] || [view isKindOfClass:UITextView.class] || calendar || [view isKindOfClass:UIPickerView.class] || [NSStringFromClass(view.class) containsString:@"UIListContentView"])continue;
        [pending addObjectsFromArray:view.subviews];
    }
    NSDictionary *report=@{@"page":name,@"controller":NSStringFromClass(ut_top().class),@"category":root.traitCollection.preferredContentSizeCategory,@"style":@(root.traitCollection.userInterfaceStyle),@"width":@(root.bounds.size.width),@"elements":rows,@"note":@"仅对可确定属性扣分，文字、层次、对比及原生面板另作人工审查"};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]writeToFile:[ut_docs stringByAppendingPathComponent:[@"PageAudit-" stringByAppendingString:[name stringByAppendingString:@".json"]]] atomically:YES];
}
// 保存自然呈现的抽屉与菜单，保持原有屏幕尺寸。
static void ut_dwin(NSString *name) {
    ut_wait(^BOOL{return !ut_top().isBeingPresented && !ut_nav.transitionCoordinator;},@"设计截图等待转场");
    ut_ui(^{[ut_window layoutIfNeeded];UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithSize:ut_window.bounds.size];[[renderer PNGDataWithActions:^(__unused UIGraphicsImageRendererContext *context){[ut_window drawViewHierarchyInRect:ut_window.bounds afterScreenUpdates:YES];}]writeToFile:[ut_docs stringByAppendingPathComponent:[@"screens/" stringByAppendingString:[name stringByAppendingString:@".png"]]] atomically:YES];ut_pgdata(name,ut_top().view,ut_top().navigationController ?: ut_nav);});
}
// 完整页面检查窄屏和辅助大字，保留失败截图后继续其他页面。
static void ut_dpage(NSString *name) {
    ut_wait(^BOOL{UIViewController *top=ut_top();return !top.isBeingPresented && !top.isBeingDismissed && !(top.navigationController ?: ut_nav).transitionCoordinator && top.view.window!=nil;},@"页面采集等待当前导航完成");
    for(NSNumber *large in @[@NO,@YES]){__block CGRect frame,windowFrame,hostFrame;ut_ui(^{frame=(ut_top().navigationController ?: ut_nav).view.frame;windowFrame=ut_window.frame;hostFrame=ut_window.rootViewController.view.frame;ut_window.frame=CGRectMake(0,0,320,850);ut_window.rootViewController.view.frame=ut_window.bounds;[ut_window layoutIfNeeded];});@try{ut_shot([name stringByAppendingString:large.boolValue ? @"-large.png":@"-320.png"],320,850,large.boolValue);}@catch(NSException *error){NSString *path=[ut_docs stringByAppendingPathComponent:[@"PageFailure-" stringByAppendingString:[name stringByAppendingString:large.boolValue ? @"-large.txt":@"-320.txt"]]];[error.reason writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];}@finally{ut_ui(^{UINavigationController *nav=ut_top().navigationController ?: ut_nav;if(@available(iOS 17.0,*))[ut_top().traitOverrides removeTrait:UITraitPreferredContentSizeCategory.class];[nav setOverrideTraitCollection:nil forChildViewController:ut_top()];ut_window.frame=windowFrame;ut_window.rootViewController.view.frame=hostFrame;nav.view.frame=frame;[ut_window layoutIfNeeded];[nav.view layoutIfNeeded];});}}
}
// 只在隔离宿主返回首页，不修改真实手机。
static void ut_droot(void) {
    ut_wait(^BOOL{return !(ut_top().navigationController ?: ut_nav).transitionCoordinator;},@"返回前等待子页转场");ut_ui(^{[ut_nav dismissViewControllerAnimated:NO completion:nil];[ut_nav popToRootViewControllerAnimated:NO];[ut_window endEditing:YES];});ut_home();
}
// 验证系统默认、固定时区与旧任务各自的时间语义。
static void ut_dflds(void) {
    NSString *key=@"task.defaultTimeZone";NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    NSString *original=[prefs stringForKey:key];[prefs removeObjectForKey:key];
    @try {
        ut_tap(@"home.settings");ut_tap(@"settings.timezone");
        ut_wait(^BOOL{return ((UITableViewCell *)ut_find(ut_surface(),@"timezone.system")).accessoryType==UITableViewCellAccessoryCheckmark;},@"默认勾选跟随系统");
        ut_ui(^{UISearchBar *search=(UISearchBar *)ut_find(ut_surface(),@"timezone.search");search.text=@"无匹配测试";[search.delegate searchBar:search textDidChange:search.text];});
        ut_wait(^BOOL{UITableView *table=(UITableView *)ut_find(ut_surface(),@"timezone.list");UITableViewCell *cell=table.visibleCells.firstObject;return [((UIListContentConfiguration *)cell.contentConfiguration).text isEqual:@"无匹配时区"];},@"无结果不修改默认时区");
        ut_req(![prefs stringForKey:key],@"搜索没有写入时区设置");
        ut_ui(^{UISearchBar *search=(UISearchBar *)ut_find(ut_surface(),@"timezone.search");search.text=@"纽约";[search.delegate searchBar:search textDidChange:search.text];});
        ut_tap(@"timezone.America/New_York");
        ut_wait(^BOOL{return [[(UIButton *)ut_find(ut_surface(),@"settings.timezone") configuration].subtitle isEqual:@"纽约"];},@"点选后设置显示纽约");
        ut_req([[prefs stringForKey:key]isEqual:@"America/New_York"],@"保存系统时区标识");
        ut_tap(@"settings.close");ut_home();

        ut_tap(@"home.create");ut_title(@"新任务时区");ut_tap(@"edit.date");ut_win_done();
        ut_ui(^{ut_req(!ut_find(ut_surface(),@"edit.timezone") && [[(UIDatePicker *)ut_find(ut_surface(),@"window.picker") timeZone].name isEqual:@"America/New_York"],@"新任务窗口使用默认时区，无须输入");});
        ut_tap(@"edit.save");ut_wait(^BOOL{return [[(UIDatePicker *)ut_find(ut_surface(),@"intake.start") timeZone].name isEqual:@"America/New_York"];},@"创建评估沿用新任务时区");
        ut_ui(^{[ut_top().navigationController popViewControllerAnimated:NO];});ut_cncl();

        NSDateFormatter *fmt=[NSDateFormatter new];fmt.timeZone=[NSTimeZone timeZoneWithName:@"Asia/Shanghai"];fmt.dateFormat=@"yyyy-MM-dd HH:mm";
        NSDictionary *task=[ut_store crtTsk:@{@"title":@"原任务时区",@"due_at":@([fmt dateFromString:@"2026-11-01 00:00"].timeIntervalSince1970),@"schedule_kind":@"date",@"timezone_id":@"Asia/Shanghai",@"planned_duration":@1800} error:nil];
        ut_req(task!=nil,@"创建隔离时区回归任务");
        ut_adm(task);
        ut_ui(^{UIDatePicker *day=(UIDatePicker *)ut_find(ut_surface(),@"intake.start");ut_req([day.timeZone.name isEqual:@"Asia/Shanghai"] && [[fmt stringFromDate:day.date]isEqual:@"2026-11-01 00:00"] && [[(UITextField *)ut_find(ut_surface(),@"intake.minutes")text]isEqual:@"30"],@"旧任务时区和本地日期不受设置影响");});
        long long revision=[ut_store revision:nil];ut_tap(@"intake.save");
        ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskDetailScreen.class] && !ut_top().presentedViewController;},@"保存返回详情");
        ut_req([ut_store revision:nil]==revision && [[ut_store rdTsk:task[@"task_id"] error:nil][@"timezone_id"]isEqual:@"Asia/Shanghai"],@"未改动旧任务时不重写时区");
        ut_tap(@"detail.back");ut_home();
        ut_req([ut_store delTsk:task[@"task_id"] error:nil],@"清理隔离时区夹具");

        ut_tap(@"home.settings");ut_tap(@"settings.timezone");ut_tap(@"timezone.system");ut_tap(@"settings.close");ut_home();
        ut_req(![prefs stringForKey:key],@"可切回跟随系统");
        ut_tap(@"home.create");ut_title(@"系统时区");ut_tap(@"edit.date");ut_win_done();
        ut_ui(^{ut_req([[(UIDatePicker *)ut_find(ut_surface(),@"window.picker") timeZone]isEqual:NSTimeZone.localTimeZone],@"新建任务重新使用系统时区");});
        ut_tap(@"edit.cancel");ut_home();
    } @finally {if(original)[prefs setObject:original forKey:key];else [prefs removeObjectForKey:key];}
}
// 通过真实入口遍历主App及各级子页，测试任务只存在于隔离库。
static void ut_dpages(void) {
    for(NSString *file in [[NSFileManager defaultManager]contentsOfDirectoryAtPath:ut_docs error:nil])if([file hasPrefix:@"PageAudit-"] || [file hasPrefix:@"PageFailure-"])[[NSFileManager defaultManager]removeItemAtPath:[ut_docs stringByAppendingPathComponent:file] error:nil];
    if([ut_args containsObject:@"--date-probe"]){ut_tap([@"list." stringByAppendingString:TS_DFLT_LST]);ut_tap(@"home.create");ut_title(@"日期布局测量");ut_tap(@"edit.date");ut_win_done();ut_tap(@"edit.save");ut_wait(^BOOL{return ut_find(ut_surface(),@"intake.start")!=nil;},@"测量日期组合行");ut_dpage(@"date-probe");ut_droot();return;}
    ut_home();ut_dpage(@"today-empty");ut_tap([@"list." stringByAppendingString:TS_DFLT_LST]);ut_dpage(@"inventory-empty");
    ut_tap(@"home.lists");ut_dwin(@"list-drawer");ut_tap(@"list.create");ut_wait(^BOOL{return ut_find(ut_surface(),@"list.name")!=nil;},@"清单名称页就绪");ut_dpage(@"list-name");ut_droot();
    ut_tap(@"home.more");ut_dwin(@"sort-drawer");long long version=[ut_store revision:nil];ut_ui(^{UITableViewController *menu=(UITableViewController *)ut_top();UITableViewCell *cell=(UITableViewCell *)ut_find(menu.view,@"list.delete");UIListContentConfiguration *content=(UIListContentConfiguration *)cell.contentConfiguration;ut_req(!content.secondaryText.length && cell.accessibilityHint.length && (cell.accessibilityTraits & UIAccessibilityTraitNotEnabled),@"禁用原因移入悬浮提示且保留禁用语义");[menu.tableView.delegate tableView:menu.tableView didSelectRowAtIndexPath:[menu.tableView indexPathForCell:cell]];ut_req(ut_top()==menu,@"禁用项点击不会关闭或执行");});ut_req([ut_store revision:nil]==version,@"禁用项点击不修改数据库");ut_tap(@"sort.date");ut_droot();
    ut_tap(@"home.create");ut_title(@"设计审查任务");ut_dwin(@"quick-create");ut_tap(@"edit.date");ut_dpage(@"todo-window");ut_tap(@"window.choose");ut_dpage(@"todo-deadline");ut_droot();
    NSDictionary *task=[ut_store crtTsk:@{@"title":@"检查所有子页的对齐与阅读体验",@"notes":@"此处是用户填写的长说明，检查换行、正文边距和可读性。",@"due_at":@([[NSDate date]timeIntervalSince1970]+120),@"planned_duration":@1800} error:nil];ut_req(task!=nil,@"创建隔离设计任务");
    ut_ui(^{[(TaskHome *)ut_nav.viewControllers.firstObject rfrsh];});ut_wait(^BOOL{return ut_find(ut_surface(),[@"star." stringByAppendingString:task[@"task_id"]])!=nil;},@"普通清单数据就绪");ut_dpage(@"inventory-populated");
    ut_tap(@"list.today");ut_dpage(@"today-populated");ut_tap([@"list." stringByAppendingString:TS_DFLT_LST]);
    ut_edt(task);ut_dpage(@"task-detail");ut_tap(@"detail.edit");ut_dpage(@"task-edit");ut_droot();
    NSDictionary *rtnTask=[ut_store crtTsk:@{@"title":@"设计常律",@"list_id":TS_RTN_LST,@"routine_kind":@"fixed",@"routine_enabled":@1,@"routine_end":@570,@"due_at":@([[NSDate date]timeIntervalSince1970]),@"recurrence_type":@"daily",@"recurrence":@[@"RRULE:FREQ=DAILY;INTERVAL=1"]} error:nil];ut_req(rtnTask!=nil,@"创建隔离常律");
    ut_rte(rtnTask);ut_tap(@"edit.date");ut_wait(^BOOL{return ut_find(ut_surface(),@"calendar.month")!=nil;},@"月历页就绪");ut_dpage(@"calendar-month");ut_tap(@"calendar.timed");ut_dpage(@"calendar-clock");ut_tap(@"calendar.done");ut_tap(@"edit.repeat");ut_wait(^BOOL{return ut_find(ut_surface(),@"repeat.type.custom")!=nil;},@"重复预设就绪");ut_dpage(@"repeat-presets");ut_tap(@"repeat.type.custom");ut_dpage(@"repeat-custom");ut_tap(@"repeat.end");ut_dpage(@"repeat-end");ut_tap(@"repeat.end.until");ut_dpage(@"repeat-until");ut_tap(@"repeat.end.count");ut_dpage(@"repeat-count");ut_ui(^{[ut_top().navigationController popViewControllerAnimated:NO];});ut_tap(@"repeat.raw");ut_dpage(@"repeat-raw");ut_droot();
        ut_tap([@"list." stringByAppendingString:TS_RTN_LST]);ut_wait(^BOOL{return [ut_top()isKindOfClass:TaskHome.class] && !ut_nav.transitionCoordinator;},@"常律首页就绪");ut_dpage(@"routine-rules");ut_tap(@"home.create");ut_dpage(@"routine-edit");ut_tap(@"edit.more");ut_dpage(@"routine-advanced");ut_dpage(@"routine-advanced-bottom");ut_droot();
        ut_tap([@"list." stringByAppendingString:TS_DFLT_LST]);ut_tap(@"home.create");ut_title(@"创建评估界面检查");ut_tap(@"edit.date");ut_win_done();ut_tap(@"edit.save");ut_wait(^BOOL{return ut_find(ut_surface(),@"intake.start")!=nil;},@"创建评估页就绪");ut_dpage(@"admission-editing");ut_droot();
    ut_sttng();ut_droot();
    if([ut_args containsObject:@"--design-light"]){ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;[ut_nav pushViewController:[NSClassFromString(@"TaskAISettings")new] animated:NO];});ut_dpage(@"assistant-config-light");ut_droot();}
    NSDictionary *occ=[ut_store crtOcc:task[@"task_id"] at:task[@"due_at"] error:nil];
    ut_ui(^{TTTaskHUD *hud=[TTTaskHUD new];[ut_nav pushViewController:hud animated:NO];[ut_nav setNavigationBarHidden:YES animated:NO];[hud signalAudio:NO];[hud display:@{@"task_id":task[@"task_id"],@"occurrence_id":occ[@"occurrence_id"],@"cycle_at":task[@"due_at"],@"scheduled_at":task[@"due_at"],@"task":task,@"occurrence":occ} error:nil];});ut_dpage(@"hud-reminder");ut_tap(@"hud.complete");ut_dpage(@"hud-submit");ut_ui(^{TTTaskHUD *hud=(TTTaskHUD *)ut_top();[hud acceptImage:lb_icon(@"pic") method:@"library" occID:occ[@"occurrence_id"]];});ut_dpage(@"hud-attachment");ut_ui(^{[(TTTaskHUD *)ut_top()stop];});ut_droot();
    ut_req([ut_store cmplTsk:task[@"task_id"] error:nil],@"创建隔离完成记录");
    NSDictionary *record=[ut_store lsOcc:task[@"task_id"] error:nil].firstObject;
    if(![record[@"action"]isEqual:@"complete"])ut_req([ut_store updOcc:occ[@"occurrence_id"] fields:@{@"action":@"complete",@"handled_at":@(NSDate.date.timeIntervalSince1970)} error:nil],@"设置隔离归档记录");
    ut_edt([ut_store rdTsk:task[@"task_id"] error:nil]);ut_tap(@"detail.history");ut_dwin(@"history-drawer");ut_tap(occ[@"occurrence_id"]);ut_wait(^BOOL{return ut_find(ut_surface(),@"proof.table")!=nil;},@"归档附件页就绪");ut_dpage(@"proof-list");ut_droot();
        ut_req([ut_store delTsk:task[@"task_id"] error:nil],@"清理隔离设计任务");
}
