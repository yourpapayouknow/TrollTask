// 在真实UIKit中验收常驻入口、编辑、草稿预览和归档返回。
static void ut_rtn(void) {
    // 自动分配显示实际时段，原有定时提醒仍显示原轮次。
    ut_ui(^{
        TTTaskHUD *hud=[TTTaskHUD new];double cycle=1793030400,scheduled=cycle+17*3600;
        NSMutableDictionary *task=[@{@"title":@"日程时刻验收",@"notes":@"",@"due_at":NSNull.null,@"schedule_kind":@"none",@"urgency":@0,@"difficulty":@0} mutableCopy];
        NSMutableDictionary *alert=[@{@"occurrence_id":NSUUID.UUID.UUIDString,@"task":task,@"cycle_at":@(cycle),@"scheduled_at":@(scheduled),@"kind":@"plan"} mutableCopy];
        NSDateFormatter *format=[NSDateFormatter new];format.locale=[[NSLocale alloc]initWithLocaleIdentifier:@"zh_CN"];format.dateFormat=@"yyyy-MM-dd HH:mm";
        [hud display:alert error:nil];UILabel *planned=(UILabel *)ut_find(hud.view,@"hud.planned");
        ut_req([planned.text isEqual:[@"日程安排：" stringByAppendingString:[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:scheduled]]]],@"日程HUD显示实际安排时刻而非轮次零点");
        task[@"due_at"]=@(cycle);task[@"schedule_kind"]=@"timed";alert[@"task"]=task;alert[@"occurrence_id"]=NSUUID.UUID.UUIDString;
        [hud display:alert error:nil];ut_req([planned.text isEqual:[@"原计划：" stringByAppendingString:[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:cycle]]]],@"原定时HUD仍显示不可变轮次时刻");[hud stop];
    });
    ut_home();ut_tap([@"list." stringByAppendingString:TS_RTN_LST]);
    ut_wait(^BOOL{return ut_find(ut_surface(),@"home.list") && !ut_nav.transitionCoordinator;},@"常律页签直接进入列表");
    ut_tap(@"home.create");ut_title(@"常律页面验收");
    ut_ui(^{
        ut_req(ut_find(ut_surface(),@"routine.kind") && ut_find(ut_surface(),@"routine.end") && ut_find(ut_surface(),@"routine.enabled"),@"常律共用编辑器并提供类型结束及启用");
        ut_req(ut_find(ut_surface(),@"edit.clearDate").hidden && (!ut_find(ut_surface(),@"edit.subtask") || ut_find(ut_surface(),@"edit.subtask").hidden),@"常律不提供破坏时间或子任务入口");
        UIDatePicker *end=(UIDatePicker *)ut_find(ut_surface(),@"routine.end");end.date=[NSCalendar.currentCalendar dateBySettingHour:9 minute:30 second:0 ofDate:end.date options:0];[end sendActionsForControlEvents:UIControlEventValueChanged];
    });ut_tap(@"routine.work");ut_tap(@"edit.repeat");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskRepeat.class];},@"常律进入共用重复页");
    ut_ui(^{ut_req(!ut_find(ut_surface(),@"repeat.type.none"),@"常律不能移除重复留下半成品");});
    ut_tap(@"repeat.type.workdays");ut_save();
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskHome.class] && !ut_nav.transitionCoordinator;},@"保存常律返回列表");
    NSDictionary *routine=nil;for(NSDictionary *row in [ut_store lsPnd:nil])if([row[@"title"] isEqual:@"常律页面验收"])routine=row;
    ut_req([routine[@"list_id"] isEqual:TS_RTN_LST] && [routine[@"routine_kind"] isEqual:@"work"] && [routine[@"routine_end"] integerValue]==570,@"编辑时段类型和结束时刻完整保存");
    ut_req([[routine[@"recurrence"] firstObject] containsString:@"BYDAY=MO,TU,WE,TH,FR"],@"常律工作日复用原重复规则");
    ut_tap(@"home.more");ut_tap(@"rules.import");ut_wait(^BOOL{return [ut_top() isKindOfClass:UIDocumentPickerViewController.class] && !ut_top().isBeingPresented;},@"时间表使用原生文件选择器");
    ut_ui(^{UIDocumentPickerViewController *picker=(UIDocumentPickerViewController *)ut_top();[picker.delegate documentPickerWasCancelled:picker];[ut_top() dismissViewControllerAnimated:NO completion:nil];});
    NSString *text=@"## 周一\n1. 7:00~7:30 界面导入草稿\n";
    NSURL *file=[NSURL fileURLWithPath:[ut_docs stringByAppendingPathComponent:@"ui-routines.md"]];
    ut_req([text writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil],@"创建独立导入文本夹具");
    ut_tap(@"home.more");ut_tap(@"rules.import");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:UIDocumentPickerViewController.class] && !ut_top().isBeingPresented;},@"导入文件选择器就绪");
    ut_ui(^{UIDocumentPickerViewController *picker=(UIDocumentPickerViewController *)ut_top();[picker.delegate documentPicker:picker didPickDocumentsAtURLs:@[file]];});
    ut_wait(^BOOL{return [ut_top() isKindOfClass:UIAlertController.class] && [ut_top().title isEqual:@"已导入草稿"];},@"文件选择交回后异步导入并显示结果");
    NSDictionary *imported=nil;for(NSDictionary *row in [ut_store lsTsks:nil])if([row[@"title"] isEqual:@"界面导入草稿"])imported=row;
    ut_req(imported && ![imported[@"routine_enabled"] boolValue],@"UI导入不自动启用真实提醒");
    ut_ui(^{[ut_top() dismissViewControllerAnimated:NO completion:nil];});
    ut_req([ut_store delTsk:imported[@"task_id"] error:nil],@"清理界面导入夹具");
    NSDictionary *unknown=[ut_store crtTsk:@{@"title":@"结束待确认",@"list_id":TS_RTN_LST,@"routine_kind":@"fixed",@"routine_enabled":@0,@"due_at":routine[@"due_at"],@"recurrence_type":@"daily"} error:nil];ut_req(unknown!=nil,@"建立未知结束草稿");
    ut_tap(@"home.more");ut_tap(@"agenda.issues");
    ut_wait(^BOOL{return ut_find(ut_surface(),@"agenda.problem.0") && !ut_nav.transitionCoordinator;},@"未确认时段从常律选项可达");
    ut_tap(@"agenda.problem.0");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskEdit.class] && !ut_nav.transitionCoordinator;},@"待处理行可进入原编辑器");
    ut_ui(^{ut_req(ut_find(ut_surface(),@"edit.complete").hidden,@"未启用草稿不显示无效完成按钮");});
    ut_ui(^{UISwitch *enabled=(UISwitch *)ut_find(ut_surface(),@"routine.enabled");enabled.on=YES;[enabled sendActionsForControlEvents:UIControlEventValueChanged];});ut_save();
    ut_wait(^BOOL{return [ut_top() isKindOfClass:UIAlertController.class];},@"缺失结束时间不能仅开开关启用");
    ut_req([ut_store rdTsk:unknown[@"task_id"] error:nil][@"routine_end"]==NSNull.null,@"无效启用保持草稿原值");
    ut_ui(^{[ut_top() dismissViewControllerAnimated:NO completion:nil];});ut_tap(@"routine.end.confirm");ut_save();ut_home();
    ut_req([[ut_store rdTsk:unknown[@"task_id"] error:nil][@"routine_enabled"] boolValue],@"明确确认结束后才可启用");
    ut_req([ut_store delTsk:unknown[@"task_id"] error:nil] && [ut_store delTsk:routine[@"task_id"] error:nil],@"只清理本次常律夹具");
    // 归档凭证仍由原状态机写入，预览不完成其他待办。
    NSDictionary *task=[ut_store crtTsk:@{@"title":@"归档凭证验收",@"due_at":@(NSDate.date.timeIntervalSince1970-1)} error:nil];
    NSDictionary *snapshot=[ut_store planAt:NSDate.date.timeIntervalSince1970 error:nil],*candidate=nil;
    for(NSDictionary *item in snapshot[@"alerts"])if([item[@"task_id"] isEqual:task[@"task_id"]])candidate=item;
    NSDictionary *occ=[ut_store claim:candidate revision:[snapshot[@"revision"] longLongValue] at:NSDate.date.timeIntervalSince1970 error:nil];
    ut_req([ut_store chkOcc:occ[@"occurrence_id"] attachments:@[@{@"method":@"file",@"name":@"验收.txt",@"content_type":@"public.plain-text",@"image":[@"归档原始文件" dataUsingEncoding:NSUTF8StringEncoding]}] error:nil],@"原子保存归档凭证");
    ut_edt([ut_store rdTsk:task[@"task_id"] error:nil]);ut_tap(@"edit.more");ut_tap(@"edit.history");ut_tap(occ[@"occurrence_id"]);
    ut_wait(^BOOL{return ut_find(ut_surface(),@"proof.table")!=nil && !ut_nav.transitionCoordinator;},@"完成记录进入可用归档页");
    ut_tap(@"proof.item.0");ut_wait(^BOOL{return [NSStringFromClass(ut_top().class) containsString:@"QLPreviewController"] && !ut_nav.transitionCoordinator;},@"点击附件进入系统QuickLook");
    ut_ui(^{[ut_nav popToRootViewControllerAnimated:NO];});ut_home();
    ut_req([ut_store delTsk:task[@"task_id"] error:nil],@"归档测试结束不留活动任务");
}
