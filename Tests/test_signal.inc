// 用真实UIKit与同库服务验证静音、有限截止和摘要布局。
static void ut_signal(void) {
    NSString *path=[ut_docs stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".sqlite3"]];
    TaskStore *writer=[[TaskStore alloc] initAt:path error:nil];
    NSDictionary *task=[writer crtTsk:@{@"title":@"字段联动",@"due_at":@(NSDate.date.timeIntervalSince1970-10),@"urgency":@3,@"difficulty":@3,@"planned_duration":@1500} error:nil];
    NSDictionary *low=[writer crtTsk:@{@"title":@"排队声振",@"due_at":@(NSDate.date.timeIntervalSince1970-9),@"urgency":@1} error:nil];
    __block TTTaskHUD *hud; __block TaskReminder *service; __block UIWindow *window; __block NSDictionary *active; __block UIViewController *host;
    // 每次重建使用同一真实服务路径与窗口生命周期。
    void (^start)(void)=^{ ut_ui(^{
        lb_svcfg(@{@"enabled":@YES});hud=[TTTaskHUD new]; window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];host=[UIViewController new];window.rootViewController=host;
        [hud signalAudio:YES];
        [host addChildViewController:hud];hud.view.frame=host.view.bounds;hud.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[host.view addSubview:hud.view];[hud didMoveToParentViewController:host];
        [window makeKeyAndVisible]; __weak TTTaskHUD *weak=hud;
        service=[[TaskReminder alloc] initAt:path handler:^(NSDictionary *a,NSError *e){active=a;[weak display:a error:e];} cleanup:^{[weak stop];} finish:^(__unused BOOL r){}];
        hud.reminder=service; ut_req([service start:nil],@"声振夹具启动真实服务");
    }); };
    start();
    ut_wait(^BOOL { return [hud.signalState[@"playing"] boolValue]; },@"模拟器原生AVAudioPlayer实际进入播放");
    NSDictionary *playing=hud.signalState,*info=playing[@"audioInfo"];NSNumber *originalRun=playing[@"generation"];
    ut_req(fabs([info[@"duration"] doubleValue]-5)<0.001 && [info[@"loops"] intValue]==5 && [info[@"volume"] floatValue]==0,@"实际五秒音源有限循环且模拟器无声输出");
    ut_wait(^BOOL { return [writer lsOcc:task[@"task_id"] error:nil].firstObject[@"signal_at"]!=NSNull.null && [writer lsOcc:task[@"task_id"] error:nil].count==1; },@"真实呈现才建立声振预算");
    NSNumber *stamp=[writer lsOcc:task[@"task_id"] error:nil].firstObject[@"signal_at"];
    ut_wait(^BOOL{return [writer lsOcc:low[@"task_id"] error:nil].count==1;},@"同刻后续任务已进入队列");
    ut_req([writer lsOcc:low[@"task_id"] error:nil].firstObject[@"signal_at"]==NSNull.null,@"等待项不提前消耗声振预算");
    ut_ui(^{
        UIStackView *traits=(UIStackView *)ut_find(hud.view,@"hud.traits");
        ut_req(!traits.hidden && traits.arrangedSubviews.count==3,@"HUD展示紧急难度和投入");
        ut_req([[(UILabel *)traits.arrangedSubviews.lastObject text] isEqual:@"预计25分钟"],@"预计投入与原字段一致");
        for(NSNumber *large in @[@NO,@YES]) for(NSValue *size in @[[NSValue valueWithCGSize:CGSizeMake(320,693)],[NSValue valueWithCGSize:CGSizeMake(375,812)],[NSValue valueWithCGSize:CGSizeMake(768,1024)]]) {
            [host setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:large.boolValue?UIContentSizeCategoryAccessibilityExtraExtraExtraLarge:UIContentSizeCategoryLarge] forChildViewController:hud];
            window.frame=(CGRect){CGPointZero,size.CGSizeValue};host.view.frame=window.bounds;hud.view.frame=host.view.bounds;
            [host.view setNeedsLayout];[host.view layoutIfNeeded];[hud.view setNeedsLayout];[hud.view layoutIfNeeded];[hud.view layoutIfNeeded];ut_bounds(hud.view,hud.view);
            ut_req(traits.arrangedSubviews.count==3,@"窄屏与大字完整保留三项字段");
        }
        [hud.view layoutIfNeeded];ut_bounds(hud.view,hud.view);
        for(NSUInteger n=0;n<30;n++) [hud signalSample:@{@"time":@(n/10.0),@"gravity":@[@0,@0,@(-1)],@"acceleration":@[@0.4,@0,@0],@"generation":originalRun}];
    });
    ut_req([hud.signalState[@"active"] boolValue],@"桌面震动样本不会误静音");
    ut_ui(^{
        [hud signalSample:@{@"time":@3.0,@"gravity":@[@0,@(-0.8),@(-0.6)],@"acceleration":@[@0.3,@0,@0],@"generation":originalRun}];
        [hud signalSample:@{@"time":@3.1,@"gravity":@[@0,@(-0.8),@(-0.6)],@"acceleration":@[@0,@0,@0],@"generation":originalRun}];
        [hud signalSample:@{@"time":@3.6,@"gravity":@[@0,@(-0.8),@(-0.6)],@"acceleration":@[@0,@0,@0],@"generation":originalRun}];
    });
    ut_wait(^BOOL{return [[writer lsOcc:task[@"task_id"] error:nil].firstObject[@"signal_ack"] boolValue];},@"运动回调抬起判定贯通同库静音");
    NSDictionary *quiet=hud.signalState;
    ut_req([quiet[@"reason"] isEqual:@"pickup"] && ![quiet[@"playing"] boolValue] && ![quiet[@"audio"] boolValue] && ![quiet[@"beat"] boolValue] && ![quiet[@"deadline"] boolValue],@"抬起释放播放器会话与两个计时器");
    for(NSUInteger n=0;n<40;n++) notify_post(writer.changeNote.UTF8String);
    ut_ui(^{for(NSUInteger n=0;n<20;n++) [hud display:active error:nil];});
    usleep(150000);
    NSDictionary *row=[writer lsOcc:task[@"task_id"] error:nil].firstObject;
    ut_req([row[@"signal_at"] isEqual:stamp] && [row[@"signal_ack"] boolValue],@"重复通知和重复呈现不重置预算");
    ut_req([row[@"status"] isEqual:@"presented"] && [[writer rdTsk:task[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"],@"静音不解除提醒或完成任务");
    ut_ui(^{[service stop];ut_req(![hud.signalState[@"active"] boolValue],@"服务停止等待声振资源清理");window.hidden=YES;window.rootViewController=nil;}); service=nil;hud=nil;window=nil;active=nil;
    start();ut_wait(^BOOL{return active!=nil && hud.mode==1;},@"重建后恢复同一全屏提醒");
    usleep(100000);row=[writer lsOcc:task[@"task_id"] error:nil].firstObject;
    ut_req([row[@"signal_at"] isEqual:stamp] && [row[@"signal_ack"] boolValue],@"HUD重建保留静音与原时限");
    ut_req([writer delTsk:task[@"task_id"] error:nil],@"仅清理字段联动夹具");
    ut_wait(^BOOL{return [writer lsOcc:low[@"task_id"] error:nil].count==1 && [writer lsOcc:low[@"task_id"] error:nil].firstObject[@"signal_at"]!=NSNull.null;},@"下一项独立建立预算");
    ut_wait(^BOOL{return [hud.signalState[@"active"] boolValue];},@"下一项声振启动");
    ut_ui(^{
        [hud signalSample:@{@"time":@8.0,@"gravity":@[@0,@0,@(-1)],@"acceleration":@[@0,@0,@0],@"generation":originalRun}];
        [hud signalSample:@{@"time":@8.1,@"gravity":@[@0,@(-0.8),@(-0.6)],@"acceleration":@[@0.3,@0,@0],@"generation":originalRun}];
        [hud signalSample:@{@"time":@8.6,@"gravity":@[@0,@(-0.8),@(-0.6)],@"acceleration":@[@0,@0,@0],@"generation":originalRun}];
    });
    ut_req([hud.signalState[@"active"] boolValue],@"退役轮次的运动回调不能静音下一项");
    // 主线程故意阻塞，独立队列仍须在五秒后停声振。
    ut_ui(^{usleep(5300000);});
    ut_req([[writer lsOcc:low[@"task_id"] error:nil].firstObject[@"signal_ack"] boolValue],@"主线程阻塞仍按五秒独立截止静音");
    quiet=hud.signalState;
    ut_req([quiet[@"pulses"] intValue]==1 && [quiet[@"reason"] isEqual:@"timeout"] && ![quiet[@"playing"] boolValue],@"低档仅一次振动调度且播放器按时停止");
    ut_req([writer delTsk:low[@"task_id"] error:nil],@"清理低档夹具");
    NSDictionary *resuming=[writer crtTsk:@{@"title":@"恢复声振",@"due_at":@(NSDate.date.timeIntervalSince1970-1),@"urgency":@3} error:nil];
    ut_wait(^BOOL{return [hud.signalState[@"active"] boolValue] && [writer lsOcc:resuming[@"task_id"] error:nil].firstObject[@"signal_at"]!=NSNull.null;},@"恢复测试声振已经启动");
    ut_wait(^BOOL{return [hud.signalState[@"pulses"] intValue]==1;},@"首次呈现只触发一次即时振动");
    NSNumber *originalStamp=[writer lsOcc:resuming[@"task_id"] error:nil].firstObject[@"signal_at"];
    usleep(200000);ut_ui(^{[service stop];ut_req(![hud.signalState[@"playing"] boolValue],@"旧播放器退出后才重建");window.hidden=YES;window.rootViewController=nil;});service=nil;hud=nil;window=nil;active=nil;
    start();ut_wait(^BOOL{return [hud.signalState[@"playing"] boolValue];},@"未确认的声振在模拟器恢复续播");
    ut_req([[writer lsOcc:resuming[@"task_id"] error:nil].firstObject[@"signal_at"] isEqual:originalStamp] && [hud.signalState[@"audioInfo"][@"offset"] doubleValue]>0.1,@"恢复使用原时刻与音频偏移");
    usleep(150000);
    ut_req([hud.signalState[@"pulses"] intValue]==0,@"恢复不重复补发当前五秒段振动");
    ut_wait(^BOOL{return [hud.signalState[@"pulses"] intValue]==1;},@"恢复后下一振仍在原时间轴触发");
    ut_req(NSDate.date.timeIntervalSince1970-originalStamp.doubleValue>=4.8,@"后续振动没有提前到原五秒刻度之前");
    ut_ui(^{[NSNotificationCenter.defaultCenter postNotificationName:AVAudioSessionInterruptionNotification object:nil userInfo:@{AVAudioSessionInterruptionTypeKey:@(AVAudioSessionInterruptionTypeBegan)}];});
    ut_wait(^BOOL{return [hud.signalState[@"reason"] isEqual:@"interruption"] && ![hud.signalState[@"active"] boolValue];},@"原生音频中断通知清理声振");
    ut_req([writer delTsk:resuming[@"task_id"] error:nil],@"清理恢复夹具");
    NSDictionary *touch=[writer crtTsk:@{@"title":@"操作静音",@"due_at":@(NSDate.date.timeIntervalSince1970-1)} error:nil];
    ut_wait(^BOOL{return [hud.signalState[@"active"] boolValue] && [writer lsOcc:touch[@"task_id"] error:nil].firstObject[@"signal_at"]!=NSNull.null;},@"操作测试建立中档声振");
    ut_ui(^{[(UIButton *)ut_find(hud.view,@"hud.complete") sendActionsForControlEvents:UIControlEventTouchDown];});
    ut_wait(^BOOL{return [hud.signalState[@"reason"] isEqual:@"interaction"] && [[writer lsOcc:touch[@"task_id"] error:nil].firstObject[@"signal_ack"] boolValue];},@"按下按钮原生事件立即静音");
    ut_req([writer delTsk:touch[@"task_id"] error:nil],@"清理按钮夹具");
    NSDictionary *background=[writer crtTsk:@{@"title":@"背景静音",@"due_at":@(NSDate.date.timeIntervalSince1970-1)} error:nil];
    ut_wait(^BOOL{return [hud.signalState[@"active"] boolValue] && [writer lsOcc:background[@"task_id"] error:nil].firstObject[@"signal_at"]!=NSNull.null;},@"背景操作前建立声振");
    __block CGPoint point;ut_ui(^{point=CGPointMake(8,hud.view.safeAreaInsets.top+8);});
    ut_htch(window,point,UITouchPhaseBegan);ut_htch(window,point,UITouchPhaseEnded);
    ut_wait(^BOOL{return [hud.signalState[@"reason"] isEqual:@"interaction"] && ![hud.signalState[@"active"] boolValue];},@"真实背景触摸只静音");
    ut_ui(^{ut_req(hud.mode==1,@"背景触摸不意外解除全屏");});
    ut_req([writer delTsk:background[@"task_id"] error:nil],@"清理背景夹具");
    NSString *longNotes=[@"滚动声振验收\n" stringByPaddingToLength:1000 withString:@"滚动后仍需附件提交。\n" startingAtIndex:0];
    NSDictionary *scrolling=[writer crtTsk:@{@"title":@"滚动静音",@"notes":longNotes,@"due_at":@(NSDate.date.timeIntervalSince1970-1)} error:nil];
    ut_wait(^BOOL{return [hud.signalState[@"active"] boolValue] && [writer lsOcc:scrolling[@"task_id"] error:nil].firstObject[@"signal_at"]!=NSNull.null;},@"滚动操作前建立声振");
    ut_ui(^{[hud.view setNeedsLayout];[hud.view layoutIfNeeded];UIScrollView *body=(UIScrollView *)ut_find(hud.view,@"hud.details");CGRect frame=[body convertRect:body.bounds toView:window];point=CGPointMake(CGRectGetMidX(frame),CGRectGetMaxY(frame)-40);});
    ut_htch(window,point,UITouchPhaseBegan);
    for(NSUInteger n=1;n<=4;n++) ut_htch(window,CGPointMake(point.x,point.y-30*n),UITouchPhaseMoved);
    ut_htch(window,CGPointMake(point.x,point.y-120),UITouchPhaseEnded);
    ut_wait(^BOOL{return [hud.signalState[@"reason"] isEqual:@"interaction"] && ![hud.signalState[@"active"] boolValue];},@"真实正文滑动静音且保留原生滚动");
    ut_ui(^{ut_req(hud.mode==1,@"到期静音后全屏仍保留");[service stop];window.hidden=YES;window.rootViewController=nil;[ut_window makeKeyAndVisible];});
}
