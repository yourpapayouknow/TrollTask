// 在真实UIKit中固化正式常律并检查只读今日律与七天列表。
static void ut_weekly(void) {
    NSError *error=nil;
    NSURL *url=[NSBundle.mainBundle URLForResource:@"WeeklyRoutine" withExtension:@"json"];
    NSDictionary *document=url ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:&error] : nil;
    ut_req(document!=nil,@"安装包包含正式周表资源");
    NSDictionary *result=[TaskRoutineImport formal:ut_store document:document anchor:[NSDate dateWithTimeIntervalSinceNow:-8*86400] zone:NSTimeZone.localTimeZone.name error:&error];
    ut_req([result[@"added"] unsignedIntegerValue]==[document[@"entries"] count],error.localizedDescription ?: @"全部正式常律已写入");
    [ut_store.path writeToFile:[ut_docs stringByAppendingPathComponent:@"FormalStore.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    ut_ui(^{[(TaskHome *)ut_nav.viewControllers.firstObject rfrsh];});ut_home();
    ut_tap(@"list.today");
    NSArray *today=[TaskToday rows:ut_store at:NSDate.date.timeIntervalSince1970 zone:NSTimeZone.localTimeZone.name error:&error];
    ut_wait(^BOOL{UITableView *table=(UITableView *)ut_find(ut_surface(),@"home.list");return [table numberOfRowsInSection:0]>10;},@"正式常律出现在今日执行清单");
    ut_ui(^{ut_req(today.count>10,@"当天只派生当天事项");ut_req(ut_find(ut_surface(),@"home.toolbar").hidden && !((UIButton *)ut_find(ut_surface(),@"home.create")).enabled,@"今日律没有创建入口");});
    ut_shot(@"formal-today-dark-320.png",320,693,NO);
    ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;});ut_shot(@"formal-today-light-375.png",375,850,NO);
    ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;});
    ut_tap([@"list." stringByAppendingString:TS_RTN_LST]);
    ut_wait(^BOOL{return ut_table().numberOfSections==7 && !ut_nav.transitionCoordinator;},@"常律页签直接切换首页模板清单");
    ut_ui(^{UITableView *table=(UITableView *)ut_find(ut_surface(),@"home.list");NSInteger total=0;for(NSInteger section=0;section<table.numberOfSections;section++){NSInteger rows=[table numberOfRowsInSection:section];total+=rows-(rows+5)/6;}ut_req(total==(NSInteger)[document[@"entries"] count],@"正式常律全部可编辑且没有草稿重复");});
    ut_ui(^{NSMutableArray *probe=[NSMutableArray new];for(NSDictionary *task in [ut_store lsPnd:nil]){UIView *check=ut_find(ut_surface(),[@"task." stringByAppendingString:task[@"task_id"]]);if(!check)continue;UIView *cell=check;while(cell && ![cell isKindOfClass:UITableViewCell.class])cell=cell.superview;[probe addObject:@{@"title":task[@"title"],@"hidden":@(check.hidden),@"visible_cell":@([ut_table().visibleCells containsObject:(UITableViewCell *)cell]),@"rect":NSStringFromCGRect([check convertRect:check.bounds toView:ut_window])}];}[[NSJSONSerialization dataWithJSONObject:probe options:NSJSONWritingPrettyPrinted error:nil]writeToFile:[ut_docs stringByAppendingPathComponent:@"RoutineCellProbe.json"] atomically:YES];});
    ut_ui(^{ut_req(ut_nav.viewControllers.count==1 && ut_nav.navigationBarHidden,@"常律与普通清单同层且不出现返回栏");ut_req(ut_find(ut_surface(),[@"list." stringByAppendingString:TS_RTN_LST]).accessibilityTraits & UIAccessibilityTraitSelected,@"常律页签有真实选中态");for(UITableViewCell *cell in ut_table().visibleCells)for(NSDictionary *task in [ut_store lsPnd:nil])if([task[@"list_id"]isEqual:TS_RTN_LST]){UIView *check=ut_find(cell,[@"task." stringByAppendingString:task[@"task_id"]]);if(check)ut_req(check.hidden && !ut_find(cell,[@"star." stringByAppendingString:task[@"task_id"]]),@"正式模板没有星标或完成入口");}});
    ut_shot(@"formal-rules-dark-320.png",320,693,NO);ut_shot(@"formal-rules-large-320.png",320,850,YES);
    ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;});ut_shot(@"formal-rules-light-375.png",375,850,NO);ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;});
    NSUInteger ruleCount=[ut_store lsTsks:nil].count;ut_tap(@"home.create");ut_wait(^BOOL{return ut_find(ut_surface(),@"edit.repeat") && !ut_nav.transitionCoordinator;},@"常律首页加号打开底部草稿");ut_tap(@"edit.cancel");ut_home();ut_req([ut_store lsTsks:nil].count==ruleCount,@"取消新建模板不落库");
    for(NSInteger step=0;step<3;step++){ut_tap(@"list.today");ut_tap([@"list." stringByAppendingString:TS_RTN_LST]);ut_ui(^{ut_req(ut_nav.viewControllers.count==1,@"连续切换不叠加常律页面");});}
    ut_ui(^{UITableView *table=(UITableView *)ut_find(ut_surface(),@"home.list");[table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:3]];});
    ut_wait(^BOOL{return ut_find(ut_surface(),@"routine.enabled") && !ut_nav.transitionCoordinator;},@"正式常律沿用既有编辑器");
    ut_ui(^{ut_req([(UISwitch *)ut_find(ut_surface(),@"routine.enabled") isOn],@"正式事项已启用");});ut_shot(@"formal-edit-dark-320.png",320,693,NO);
    ut_ui(^{[ut_nav popToRootViewControllerAnimated:NO];});ut_home();ut_tap(@"list.today");
    ut_ui(^{ut_req(!ut_find(ut_surface(),@"home.agenda") && !ut_find(ut_surface(),@"agenda.timeline"),@"今日律的正式事项只从列表查看");});
    long long revision=[ut_store revision:nil];
    ut_req([TaskRoutineImport formal:ut_store document:document anchor:NSDate.date zone:NSTimeZone.localTimeZone.name error:&error]!=nil && [ut_store revision:nil]==revision,@"重复启动不重复写入或变更启用状态");
    ut_ui(^{[ut_nav popToRootViewControllerAnimated:NO];});ut_home();
}

// 在生产UIApplicationMain入口启动后核对首次迁移或跨进程重开。
static void ut_lcheck(BOOL reopen) {
    BOOL passed=YES;NSString *failure=@"";
    @try {
        ut_ui(^{ut_window=[(id)UIApplication.sharedApplication.delegate valueForKey:@"window"];ut_nav=(UINavigationController *)ut_window.rootViewController;ut_req([NSStringFromClass(UIApplication.sharedApplication.delegate.class) isEqual:@"LBAppDel"],@"UIApplicationMain使用真实TaskApp委托");ut_req([ut_nav.topViewController isKindOfClass:TaskHome.class],@"生产启动入口呈现真实首页");});
        ut_home();
        NSString *statePath=[ut_docs stringByAppendingPathComponent:@"ColdLaunch.json"];
        NSMutableDictionary *state=[[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:statePath] options:NSJSONReadingMutableContainers error:nil] mutableCopy];
        NSArray *tasks=[ut_store lsTsks:nil];NSMutableArray *official=[NSMutableArray new];NSUInteger archived=0;
        for(NSDictionary *task in tasks){NSString *source=[task[@"routine_source"] isKindOfClass:NSString.class] ? task[@"routine_source"] : @"";if([source hasPrefix:@"formal:"])[official addObject:task];if([source hasPrefix:@"md:legacy-weekly.md:"] && [task[@"deleted"] boolValue])archived++;}
        ut_req(official.count==[state[@"rules"] unsignedIntegerValue],@"真实首启自动生成整套正式常律");
        if(!reopen){
            ut_req(archived==[state[@"drafts"] unsignedIntegerValue],@"真实首启归档同来源禁用草稿");
            for(NSDictionary *task in official)ut_req([task[@"routine_enabled"] boolValue] && ![task[@"deleted"] boolValue] && [task[@"due_at"] doubleValue]>=[state[@"started_at"] doubleValue],@"首启常律启用且不补弹安装前提醒");
            ut_req([[ut_store rdTsk:state[@"ordinary"] error:nil][@"title"] isEqual:@"保留原任务"],@"首启保留普通清单原任务");
            ut_req([ut_store updTsk:official[0][@"task_id"] fields:@{@"title":@"保留我的调整",@"routine_enabled":@0} error:nil],@"模拟用户编辑并停用");
            ut_req([ut_store delTsk:official[1][@"task_id"] error:nil],@"模拟用户删除单条规则");
            ut_req([ut_store cmplNxt:official[2][@"task_id"] error:nil],@"模拟完成一个正式轮次");
            state[@"expected"]=[ut_store snapshot:nil];
            ut_req([[NSJSONSerialization dataWithJSONObject:state options:0 error:nil] writeToFile:statePath atomically:YES],@"跨进程保存用户状态基线");
        }else{
            ut_req([[ut_store snapshot:nil] isEqual:state[@"expected"]],@"新进程首启不覆盖编辑停用删除及已完成轮次");
            ut_req([ut_store lsTsks:nil].count==[state[@"expected"][@"tasks"] count],@"重开没有新增重复事项或复活归档草稿");
        }
        ut_ui(^{[(TaskHome *)ut_nav.topViewController rfrsh];});ut_home();
        __block CGSize viewport;ut_ui(^{viewport=ut_window.bounds.size;});
        ut_shot(reopen ? @"cold-reopen-native.png":@"cold-first-native.png",viewport.width,viewport.height,NO);
        ut_ui(^{ut_req(ut_find(ut_surface(),@"home.toolbar").hidden && !((UIButton *)ut_find(ut_surface(),@"home.create")).enabled,@"真实首页今日律仍只读");});
    }@catch(NSException *error){passed=NO;failure=error.reason;}
    __block NSString *device,*runtime;ut_ui(^{device=UIDevice.currentDevice.model;runtime=UIDevice.currentDevice.systemVersion;});
    NSDictionary *report=@{@"passed":@(passed),@"failure":failure,@"checks":ut_checks,@"device":device,@"runtime":runtime,@"arguments":ut_args,@"database":ut_store.path,@"process_id":@(NSProcessInfo.processInfo.processIdentifier),@"finished_at":@(NSDate.date.timeIntervalSince1970)};
    [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[ut_docs stringByAppendingPathComponent:@"UITestReport.json"] atomically:YES];
}

// 只替换测试存储路径，保留生产委托、资源和启动生命周期。
static void ut_lprep(void) {
    ut_docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;ut_checks=[NSMutableArray new];
    [NSFileManager.defaultManager createDirectoryAtPath:[ut_docs stringByAppendingPathComponent:@"screens"] withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL reopen=[ut_args containsObject:@"--launch-reopen"];NSString *statePath=[ut_docs stringByAppendingPathComponent:@"ColdLaunch.json"];
    NSMutableDictionary *state=reopen ? [[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:statePath] options:NSJSONReadingMutableContainers error:nil] mutableCopy] : [NSMutableDictionary new];
    ut_req(!reopen || state[@"file"]!=nil,@"重开夹具读取已持久化数据库文件名");
    if(!reopen)state[@"file"]=[@"ColdLaunch-" stringByAppendingString:[NSUUID.UUID.UUIDString stringByAppendingString:@".sqlite3"]];
    NSError *issue=nil;ut_store=[[TaskStore alloc] initAt:[ut_docs stringByAppendingPathComponent:state[@"file"]] error:&issue];ut_req(ut_store!=nil,issue.localizedDescription ?: @"打开隔离同库");
    lb_tstpath=[ut_docs stringByAppendingPathComponent:@"cold-launch.plist"];lb_tstlock="/tmp/trolltask-cold-launch.lock";ut_req(lb_svcfg(@{@"enabled":@NO}),@"冷启动使用隔离服务配置");
    if(!reopen){
        NSURL *url=[NSBundle.mainBundle URLForResource:@"WeeklyRoutine" withExtension:@"json"];
        NSDictionary *document=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:nil];
        NSDictionary *imported=[TaskRoutineImport formal:ut_store document:document anchor:NSDate.date zone:NSTimeZone.localTimeZone.name error:&issue];
        ut_req(imported!=nil,issue.localizedDescription ?: @"正式常律夹具");
        NSDictionary *task=[ut_store crtTsk:@{@"title":@"保留原任务"} error:&issue];ut_req(task!=nil,issue.localizedDescription ?: @"原任务夹具");
        state[@"ordinary"]=task[@"task_id"];state[@"rules"]=@([document[@"entries"] count]);state[@"drafts"]=imported[@"added"];state[@"started_at"]=@(NSDate.date.timeIntervalSince1970);
        ut_req([[NSJSONSerialization dataWithJSONObject:state options:0 error:nil] writeToFile:statePath atomically:YES],@"持久化首次启动夹具");
    }
    Method shared=class_getClassMethod(TaskStore.class,@selector(shrd:));method_setImplementation(shared,imp_implementationWithBlock(^TaskStore *(__unused id receiver,__unused NSError **error){return ut_store;}));
    __block id token=nil;token=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(__unused NSNotification *notification){[NSNotificationCenter.defaultCenter removeObserver:token];token=nil;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ut_lcheck(reopen);});}];
}


// 验证常律重复设置在已有编辑、新建和子页返回后均可达。
static void ut_rptedit(void) {
    NSError *error=nil;NSCalendar *calendar=NSCalendar.currentCalendar;
    NSDate *tomorrow=[calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:NSDate.date options:0];
    NSDate *start=[calendar dateBySettingHour:9 minute:0 second:0 ofDate:tomorrow options:0];
    NSDictionary *routine=[ut_store crtTsk:@{@"title":@"周期编辑验收",@"list_id":TS_RTN_LST,@"routine_kind":@"fixed",@"routine_enabled":@1,@"routine_end":@600,@"planned_duration":@3600,@"due_at":@(start.timeIntervalSince1970),@"timezone_id":NSTimeZone.localTimeZone.name,@"recurrence_type":@"custom",@"recurrence":@[@"RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR"]} error:&error];
    ut_req(routine!=nil,error.localizedDescription ?: @"创建已有常律夹具");ut_edt(routine);
    ut_ui(^{ut_req(((UIButton *)ut_find(ut_surface(),@"edit.repeat")).enabled,@"已有常律的重复设置必须可点击");});
    ut_shot(@"routine-repeat-enabled-320.png",320,693,NO);
    ut_tap(@"edit.repeat");ut_wait(^BOOL{return [ut_top()isKindOfClass:TaskRepeat.class] && !ut_top().isBeingPresented;},@"已有常律进入共用重复页");
    ut_ui(^{ut_req(!ut_find(ut_surface(),@"repeat.type.none"),@"常律仍禁止移除重复");});
    ut_tap(@"repeat.type.workdays");ut_wait(^BOOL{return [ut_top()isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController;},@"选择重复后返回原编辑页");
    ut_ui(^{ut_req(((UIButton *)ut_find(ut_surface(),@"edit.repeat")).enabled,@"子页返回刷新后重复入口仍启用");});
    ut_req([[ut_store rdTsk:routine[@"task_id"] error:nil][@"recurrence"]isEqual:routine[@"recurrence"]],@"修改重复草稿不提前写库");
    ut_tap(@"edit.back");ut_home();
    NSDictionary *saved=[ut_store rdTsk:routine[@"task_id"] error:nil];
    ut_req([[saved[@"recurrence"] firstObject] containsString:@"BYDAY=MO,TU,WE,TH,FR"],@"编辑返回正确保存工作日规则");
    for(NSString *key in @[@"title",@"due_at",@"routine_kind",@"routine_end",@"routine_enabled",@"planned_duration",@"timezone_id"])ut_req([saved[key]isEqual:routine[key]],[@"重复修改保留" stringByAppendingString:key]);
    ut_edt(saved);ut_tap(@"edit.repeat");ut_tap(@"repeat.cancel");ut_wait(^BOOL{return [ut_top()isKindOfClass:TaskEdit.class] && !ut_top().presentedViewController;},@"取消重复页返回编辑");
    ut_ui(^{ut_req(((UIButton *)ut_find(ut_surface(),@"edit.repeat")).enabled,@"取消后常律重复入口仍启用");[ut_nav popToRootViewControllerAnimated:NO];});ut_home();
    ut_req([[ut_store rdTsk:routine[@"task_id"] error:nil]isEqual:saved],@"取消重复编辑不改变常律");
    NSDictionary *parent=[ut_store crtTsk:@{@"title":@"普通父级验收"} error:&error];
    NSDictionary *child=parent ? [ut_store crtTsk:@{@"title":@"普通子项验收",@"parent_id":parent[@"task_id"]} error:&error] : nil;
    ut_req(child!=nil,error.localizedDescription ?: @"创建普通父子任务夹具");ut_edt(parent);
    ut_ui(^{ut_req(!((UIButton *)ut_find(ut_surface(),@"edit.repeat")).enabled,@"普通含子任务的父级仍禁用重复");[ut_nav popToRootViewControllerAnimated:NO];});ut_home();ut_edt(child);
    ut_ui(^{ut_req(!((UIButton *)ut_find(ut_surface(),@"edit.repeat")).enabled,@"普通子任务仍禁用重复");[ut_nav popToRootViewControllerAnimated:NO];});ut_home();
    NSDictionary *leaf=[ut_store crtTsk:@{@"title":@"普通单项验收"} error:&error];ut_req(leaf!=nil,@"创建普通独立任务夹具");ut_edt(leaf);
    ut_ui(^{ut_req(((UIButton *)ut_find(ut_surface(),@"edit.repeat")).enabled,@"普通无子任务项仍可设重复");[ut_nav popToRootViewControllerAnimated:NO];});ut_home();
    ut_tap([@"list." stringByAppendingString:TS_RTN_LST]);ut_tap(@"home.create");
    ut_wait(^BOOL{return ut_find(ut_surface(),@"edit.repeat") && !ut_nav.transitionCoordinator;},@"新建常律就绪");
    ut_ui(^{ut_req(((UIButton *)ut_find(ut_surface(),@"edit.repeat")).enabled,@"新建常律保留重复入口");});
    NSUInteger count=[ut_store lsTsks:nil].count;ut_tap(@"edit.repeat");ut_tap(@"repeat.cancel");ut_tap(@"edit.cancel");ut_home();ut_req([ut_store lsTsks:nil].count==count,@"取消新建常律不写库");
}

// 验证常律同页列表、分组、时刻及旧界面偏好。
static void ut_rtnview(void){
    NSError *error=nil;NSCalendar *calendar=NSCalendar.currentCalendar;
    NSDate *day=[calendar startOfDayForDate:NSDate.date];
    NSMutableArray *tasks=[NSMutableArray new];
    for(NSInteger index=0;index<13;index++){
        NSDate *base=[calendar dateByAddingUnit:NSCalendarUnitDay value:index<11 ? 0:1 toDate:day options:0];double start=base.timeIntervalSince1970+10*3600+(index<11 ? index:index-11)*12*60;
        NSDictionary *task=[ut_store crtTsk:@{@"title":[NSString stringWithFormat:@"常律事项%ld",(long)index+1],@"list_id":TS_RTN_LST,@"routine_kind":@"fixed",@"routine_enabled":@1,@"routine_end":@(10*60+(index<11 ? index:index-11)*12+10),@"due_at":@(start),@"timezone_id":NSTimeZone.localTimeZone.name,@"recurrence_type":@"daily"} error:&error];ut_req(task!=nil,error.localizedDescription ?: @"常律分组夹具");[tasks addObject:task];
    }
    ut_req([ut_store crtTsk:@{@"title":@"普通清单任务"} error:&error]!=nil,@"普通任务过滤夹具");
    ut_ui(^{[(TaskHome *)ut_nav.viewControllers.firstObject rfrsh];});ut_home();ut_tap([@"list."stringByAppendingString:TS_RTN_LST]);
    ut_wait(^BOOL{return ut_table().numberOfSections==7 && [ut_table()numberOfRowsInSection:3]==14;},@"首日十一项与三个时间分隔，次日独立分区");
    NSDictionary *before=[ut_store snapshot:nil];long long revision=[ut_store revision:nil];
    ut_ui(^{[ut_nav.view layoutIfNeeded];ut_req(!ut_find(ut_surface(),@"routine.view") && !ut_table().hidden,@"常律直接显示列表且没有模式切换");ut_req(ut_nav.viewControllers.count==1 && ut_nav.navigationBarHidden,@"常律没有额外导航层级");
        for(NSInteger section=3;section<5;section++){NSArray *rows=@[@0,@6,@12];NSInteger count=[ut_table()numberOfRowsInSection:section];for(NSInteger row=0;row<count;row++){NSIndexPath *path=[NSIndexPath indexPathForRow:row inSection:section];UITableViewCell *cell=[ut_table().dataSource tableView:ut_table()cellForRowAtIndexPath:path];if([rows containsObject:@(row)]){ut_req([cell.accessibilityIdentifier hasPrefix:@"routine.mark."],@"每组前有起始时间分隔线");UILabel *label=(UILabel *)((UIStackView *)cell.contentView.subviews.firstObject).arrangedSubviews.firstObject;ut_req(label.text.length==5 && [label.text containsString:@":"],@"时间线仅标起点不重复结束时刻");}else ut_req([cell.accessibilityIdentifier hasPrefix:@"routine.task."],@"真实常律行可编辑");}}
        UIView *first=[ut_table().dataSource tableView:ut_table()cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:3]];ut_req([ut_find(first,[@"task."stringByAppendingString:tasks[0][@"task_id"]])isHidden],@"常律模板无完成圆圈");
    });
    ut_ui(^{
        UITableView *table=ut_table();
        [table layoutIfNeeded];
        UITableViewCell *cell=[table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:3]];
        UIView *card=ut_find(cell,@"routine.card");
        ut_req(card && !card.hidden && card.layer.cornerRadius>=16 && card.layer.shadowOpacity>0 && card.layer.shadowPath,@"单项卡片具有实际圆角和阴影");
        UIButton *remove=(UIButton *)ut_find(cell,[@"routine.delete." stringByAppendingString:tasks[0][@"task_id"]]);
        CGRect hit=[remove convertRect:remove.bounds toView:card];
        ut_req(remove.enabled && remove.configuration.image && hit.size.width>=44 && hit.size.height>=44 && CGRectContainsRect(card.bounds,hit),@"卡片右侧删除命中区完整位于卡片内");
        [table setContentOffset:CGPointMake(0,CGRectGetMinY([table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:3]])) animated:NO];
        [table layoutIfNeeded];
        UIView *root=ut_top().view,*date=ut_find(table,@"routine.day.3").superview;
        CGRect dateFrame=[date convertRect:date.bounds toView:root], tableFrame=[table convertRect:table.bounds toView:root];
        CGRect tabsFrame=[ut_find(root,@"home.tabs") convertRect:ut_find(root,@"home.tabs").bounds toView:root];
        ut_req(date && table.contentOffset.y>0 && fabs(CGRectGetMinY(dateFrame)-CGRectGetMaxY(tabsFrame))<1 && fabs(CGRectGetMinY(dateFrame)-CGRectGetMinY(tableFrame))<1 && CGColorGetAlpha(date.backgroundColor.CGColor)==1,@"滚动中日期吸附到页签下缘且完整遮挡");
    });
    ut_shot(@"routine-list-pinned-320.png",320,693,NO);
    ut_ui(^{[ut_table() scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3] atScrollPosition:UITableViewScrollPositionTop animated:NO];});
    ut_shot(@"routine-list-dark-320.png",320,693,NO);ut_shot(@"routine-list-large-320.png",320,850,YES);
    ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;});ut_shot(@"routine-list-light-375.png",375,850,NO);ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;});
    ut_ui(^{[ut_table()scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:4]atScrollPosition:UITableViewScrollPositionTop animated:NO];});ut_shot(@"routine-list-next-day-320.png",320,693,NO);
    ut_ui(^{[ut_table().delegate tableView:ut_table()didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:3]];ut_req([ut_nav.topViewController isKindOfClass:TaskHome.class],@"时间分隔行不能误编辑");[ut_table().delegate tableView:ut_table()didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:3]];});
    ut_wait(^BOOL{return [ut_top()isKindOfClass:TaskEdit.class] && !ut_nav.transitionCoordinator;},@"分组后的任务仍进入原编辑器");ut_ui(^{ut_req(((UIButton *)ut_find(ut_surface(),@"edit.repeat")).enabled,@"原有重复设置可达");});ut_tap(@"edit.back");ut_home();
    ut_req([[ut_store snapshot:nil]isEqual:before] && [ut_store revision:nil]==revision,@"滚动和取消编辑不改任务和历史");
    ut_tap([@"list."stringByAppendingString:TS_DFLT_LST]);ut_ui(^{ut_req(!ut_find(ut_surface(),@"home.agenda") && !ut_table().hidden,@"普通清单保持列表");});
    ut_tap(@"list.today");ut_ui(^{ut_req(!ut_find(ut_surface(),@"home.agenda") && ut_find(ut_surface(),@"home.toolbar").hidden,@"今日律只读且无日历入口");});
    __block UIViewController *previous;
    ut_ui(^{previous=ut_nav.topViewController;[NSUserDefaults.standardUserDefaults setBool:YES forKey:[ut_store.changeNote stringByAppendingString:@".routine.calendar"]];[ut_nav setViewControllers:@[[[TaskHome alloc]initWithStore:ut_store settings:nil]] animated:NO];});
    ut_wait(^BOOL{return !previous.view.window && ut_find(ut_nav.topViewController.view,[@"list."stringByAppendingString:TS_RTN_LST])!=nil;},@"新首页完成加载且旧视图已撤下");
    ut_tap([@"list."stringByAppendingString:TS_RTN_LST]);ut_wait(^BOOL{return !ut_find(ut_surface(),@"routine.view") && !ut_table().hidden && ut_table().numberOfSections==7;},@"旧日历偏好升级后直接显示常律列表");
}
