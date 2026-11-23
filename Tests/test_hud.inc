static NSMutableDictionary *ut_layout;

// 记录真实组件几何和滚动偏移。
static NSDictionary *ut_hgeo(TTTaskHUD *hud) {
    NSMutableDictionary *result=[NSMutableDictionary new];
    for (NSString *key in @[@"hud.card",@"hud.title",@"hud.planned",@"hud.notes",@"hud.complete",@"hud.snooze",@"hud.choices",@"hud.attachments",@"hud.back",@"hud.details"]) {
        UIView *view=ut_find(hud.view,key);if (!view) continue;
        CGRect frame=[view convertRect:view.bounds toView:hud.view];BOOL visible=YES;
        for (UIView *parent=view;parent;parent=parent.superview) if (parent.hidden) visible=NO;
        NSMutableDictionary *item=[@{@"frame":@[@(frame.origin.x),@(frame.origin.y),@(frame.size.width),@(frame.size.height)],@"visible":@(visible)} mutableCopy];
        if ([view isKindOfClass:UIScrollView.class]) {UIScrollView *scroll=(UIScrollView *)view;item[@"offset"]=@[@(scroll.contentOffset.x),@(scroll.contentOffset.y)];}
        result[key]=item;
    }
    return result;
}

// 统计当前可见的附件图标。
static NSUInteger ut_hcnt(TTTaskHUD *hud) {
    NSUInteger count=0;for (NSUInteger index=0;index<TS_ATT_MAX;index++) { UIView *view=ut_find(hud.view,[NSString stringWithFormat:@"hud.attachment.%lu",(unsigned long)index]);if (view && !view.hidden) count++; }return count;
}

// 比较同一提醒操作前后的真实边界与阅读位置。
static void ut_hsame(NSDictionary *before,NSDictionary *after,NSArray<NSString *> *keys,NSString *state) {
    for (NSString *key in keys) {
        NSArray *a=before[key][@"frame"],*b=after[key][@"frame"];BOOL same=a.count==4 && b.count==4;
        for (NSUInteger i=0;i<4 && same;i++) same=fabs([a[i] doubleValue]-[b[i] doubleValue])<1;
        if ([key isEqual:@"hud.details"] || [key isEqual:@"hud.attachments"]) same= same && [before[key][@"offset"] isEqual:after[key][@"offset"]];
        ut_req(same,[NSString stringWithFormat:@"%@不跳变：%@",state,key]);
    }
}

// 在隔离库缩短真实轮次的等待时间。
static void ut_hdue(NSString *path, NSString *id) {
    sqlite3 *db=NULL; ut_req(sqlite3_open(path.fileSystemRepresentation,&db)==SQLITE_OK,@"打开收起验证库");
    sqlite3_busy_timeout(db,5000);
    sqlite3_stmt *stmt=NULL;
    ut_req(sqlite3_prepare_v2(db,"UPDATE reminder_occurrences SET hold_until=?,next_fire_at=? WHERE occurrence_id=?",-1,&stmt,NULL)==SQLITE_OK,@"准备收起截止更新");
    double end=NSDate.date.timeIntervalSince1970+0.5; sqlite3_bind_double(stmt,1,end);sqlite3_bind_double(stmt,2,end);sqlite3_bind_text(stmt,3,id.UTF8String,-1,SQLITE_TRANSIENT);
    ut_req(sqlite3_step(stmt)==SQLITE_DONE,@"提交验证截止更新");sqlite3_finalize(stmt);sqlite3_close(db);
}

// 检查真实UIKit控件边界并保存各尺寸渲染。
static void ut_hshot(TTTaskHUD *hud,UIViewController *host,UIWindow *window,CGSize size,BOOL large,NSString *name,NSString *occID) {
    ut_ui(^{
        [host setOverrideTraitCollection:[UITraitCollection traitCollectionWithPreferredContentSizeCategory:large?UIContentSizeCategoryAccessibilityExtraExtraExtraLarge:UIContentSizeCategoryLarge] forChildViewController:hud];
        window.frame=CGRectMake(0,0,size.width,size.height);host.view.frame=window.bounds;hud.view.frame=host.view.bounds;
        [host.view setNeedsLayout];[host.view layoutIfNeeded];[hud.view setNeedsLayout];[hud.view layoutIfNeeded];[hud.view layoutIfNeeded];
        ut_bounds(hud.view,hud.view);CGRect safe=UIEdgeInsetsInsetRect(hud.view.bounds,hud.view.safeAreaInsets);
        UIView *card=ut_find(hud.view,@"hud.card");CGRect frame=[card convertRect:card.bounds toView:hud.view];
        ut_req([card isKindOfClass:UIVisualEffectView.class] && ((UIVisualEffectView *)card).effect!=nil,@"HUD使用原生磨砂材质");
        ut_req([(UILabel *)ut_find(hud.view,@"hud.title") font].pointSize>=28 && [(UILabel *)ut_find(hud.view,@"hud.notes") font].pointSize>=20,@"HUD标题与正文保持大字");
        ut_req(card && CGRectContainsRect(CGRectInset(safe,-1,-1),frame),@"居中弹窗在安全区内");
        ut_req(frame.size.width<safe.size.width && frame.size.height<safe.size.height,@"内容不是铺满屏幕");
        ut_req(ut_find(hud.view,@"theme.gradient")==nil,@"常驻HUD没有渐变动画图层");
        for (NSString *id in @[@"hud.complete",@"hud.snooze"]) {
            UIView *button=ut_find(hud.view,id);CGRect frame=[button convertRect:button.bounds toView:hud.view];
            ut_req(CGRectContainsRect(CGRectInset(safe,-1,-1),frame),[@"HUD主操作在安全区：" stringByAppendingString:name]);ut_req(frame.size.height>=43,@"HUD最小触摸高度");
        }
        UIButton *submit=(UIButton *)ut_find(hud.view,@"hud.complete"), *delay=(UIButton *)ut_find(hud.view,@"hud.snooze");
        CGRect left=[submit convertRect:submit.bounds toView:hud.view], right=[delay convertRect:delay.bounds toView:hud.view];
        ut_req([submit.configuration.title isEqual:@"提交"] && fabs(CGRectGetMidY(left)-CGRectGetMidY(right))<1 && CGRectGetMaxX(left)<=CGRectGetMinX(right),@"提交与延后始终左右并排");
        UIScrollView *scroll=(UIScrollView *)ut_find(hud.view,@"hud.details");
        ut_req(scroll.bounds.size.height>=MIN(120,frame.size.height*0.4) && scroll.contentSize.width<=scroll.bounds.size.width+1,@"最大字号仍保留正文阅读区且不横向溢出");
        ut_req(submit.titleLabel.font.pointSize>=20 && submit.titleLabel.font.pointSize<=32 && delay.titleLabel.font.pointSize<=32,@"HUD按钮保留大字并限制辅助字号上限");
        [scroll setContentOffset:CGPointZero animated:NO];
        NSMutableDictionary *geometry=[@{@"default":ut_hgeo(hud)} mutableCopy];
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:hud.view.bounds.size];
        NSData *png=[renderer PNGDataWithActions:^(UIGraphicsImageRendererContext *c){[hud.view.layer renderInContext:c.CGContext];}];
        ut_req([png writeToFile:[ut_docs stringByAppendingPathComponent:[@"screens/" stringByAppendingString:name]] atomically:YES],@"保留全屏原生渲染");
        // 保留用户阅读位置，切换时不自动滚到末尾。
        [scroll setContentOffset:CGPointMake(0,MIN(70,MAX(0,scroll.contentSize.height-scroll.bounds.size.height))) animated:NO];
        geometry[@"reading"]=ut_hgeo(hud);
        // 检查各尺寸与大字体下的三图标布局。
        [submit sendActionsForControlEvents:UIControlEventTouchUpInside];[hud.view layoutIfNeeded];[hud.view layoutIfNeeded];
        geometry[@"choosing"]=ut_hgeo(hud);
        UIStackView *choices=(UIStackView *)ut_find(hud.view,@"hud.choices");
        ut_req(!choices.hidden && choices.axis==UILayoutConstraintAxisHorizontal && choices.arrangedSubviews.count==3 && ut_find(hud.view,@"hud.camera")==nil && submit.superview.hidden,@"方式选择隐藏主操作并显示一排三图标");
        CGRect grid=[choices convertRect:choices.bounds toView:hud.view], details=[scroll convertRect:scroll.bounds toView:hud.view];
        ut_req(CGRectGetMinY(grid)>=CGRectGetMaxY(details),@"方式选择位于正文滚动区下方");
        ut_hsame(geometry[@"reading"],geometry[@"choosing"],@[@"hud.card",@"hud.title",@"hud.planned",@"hud.notes",@"hud.details"],@"打开方式选择");
        ut_req(fabs(grid.origin.y-left.origin.y)<1 && fabs(grid.size.height-left.size.height)<1 && fabs(grid.size.width-(CGRectGetMaxX(right)-left.origin.x))<1,@"三图标原位替换主操作区域");
        for (UIButton *button in choices.arrangedSubviews) ut_req(button.configuration.title.length==0 && button.configuration.image!=nil && button.accessibilityLabel.length>0 && button.bounds.size.width>=44 && button.bounds.size.height>=44,@"三个入口只有图标并保留无障碍名称");
        ut_bounds(hud.view,hud.view);
        // 各尺寸与字号下检查附件添加和删除，均不提交数据库。
        UIGraphicsImageRenderer *sample=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(20,20)];
        UIImage *image=[sample imageWithActions:^(UIGraphicsImageRendererContext *c){(void)c;[UIColor.greenColor setFill];UIRectFill(CGRectMake(0,0,20,20));}];
        [hud acceptImage:image method:@"image" occID:occID];[hud.view layoutIfNeeded];[hud.view layoutIfNeeded];
        geometry[@"attached"]=ut_hgeo(hud);
        NSArray *stable=@[@"hud.card",@"hud.title",@"hud.planned",@"hud.notes",@"hud.details",@"hud.attachments",@"hud.choices",@"hud.back"];
        ut_hsame(geometry[@"choosing"],geometry[@"attached"],stable,@"各尺寸添加附件");
        for (NSUInteger index=1;index<TS_ATT_MAX;index++) [hud acceptImage:image method:@"image" occID:occID];
        [hud.view layoutIfNeeded];geometry[@"six"]=ut_hgeo(hud);ut_hsame(geometry[@"choosing"],geometry[@"six"],stable,@"各尺寸六附件");
        ut_req(ut_hcnt(hud)==TS_ATT_MAX && ![(UIButton *)ut_find(hud.view,@"hud.image") isEnabled],@"六附件禁用继续上传");
        [hud acceptImage:image method:@"camera" occID:occID];ut_req(ut_hcnt(hud)==TS_ATT_MAX,@"第七个附件被拒绝");
        for (NSUInteger index=0;index<TS_ATT_MAX;index++) {
            UIButton *chip=(UIButton *)ut_find(hud.view,[NSString stringWithFormat:@"hud.attachment.%lu",(unsigned long)index]);
            ut_req(chip.configuration.title.length==0 && chip.configuration.image!=nil && chip.accessibilityLabel.length>0 && chip.bounds.size.width>=44 && chip.bounds.size.height>=44,@"附件气泡只有图标及独立删除入口");
            UIScrollView *row=(UIScrollView *)ut_find(hud.view,@"hud.attachments");CGRect frame=[chip convertRect:chip.bounds toView:row];
            ut_req(fabs(frame.origin.y)<1 && fabs(frame.size.height-44)<1 && CGRectGetMaxX(frame)<=row.contentSize.width+1,@"六附件保持一排且触摸框完整");
        }
        UIScrollView *row=(UIScrollView *)ut_find(hud.view,@"hud.attachments");
        [row setContentOffset:CGPointMake(MAX(0,row.contentSize.width-row.bounds.size.width),0) animated:NO];
        UIView *last=ut_find(hud.view,@"hud.attachment.5");CGRect lastFrame=[last convertRect:last.bounds toView:row];
        ut_req(CGRectContainsRect(CGRectInset(row.bounds,-1,-1),lastFrame),@"极窄屏横向滚动可访问最后附件");
        [row setContentOffset:CGPointZero animated:NO];
        for (NSUInteger index=0;index<TS_ATT_MAX;index++) [(UIButton *)ut_find(hud.view,@"hud.attachment.0") sendActionsForControlEvents:UIControlEventTouchUpInside];[hud.view layoutIfNeeded];
        geometry[@"removed"]=ut_hgeo(hud);ut_hsame(geometry[@"choosing"],geometry[@"removed"],stable,@"各尺寸删除附件");
        [(UIButton *)ut_find(hud.view,@"hud.back") sendActionsForControlEvents:UIControlEventTouchUpInside];[hud.view layoutIfNeeded];
        [hud.view layoutIfNeeded];geometry[@"returned"]=ut_hgeo(hud);ut_layout[name]=geometry;
        ut_hsame(geometry[@"reading"],geometry[@"returned"],@[@"hud.card",@"hud.title",@"hud.planned",@"hud.notes",@"hud.details",@"hud.complete",@"hud.snooze"],@"返回提醒");
        ut_req(choices.hidden && !submit.superview.hidden,@"返回恢复提交与延后");
        [host setOverrideTraitCollection:nil forChildViewController:hud];
    });
}

// 验证真实服务到Swift全屏、打卡和边栏的完整链路。
// 向同一上游UIKit路由发送真实触摸阶段。
static void ut_htch(UIWindow *window, CGPoint point, UITouchPhase phase) {
    ut_ui(^{[TSEventFetcher receiveAXEventID:1 atGlobalCoordinate:point withTouchPhase:phase inWindow:window onView:[window hitTest:point withEvent:nil]];});
    usleep(40000);
}

// 对照空缓存和尚未填充载荷的原生缓存事件。
static void ut_evc(BOOL cached) {
    __block UIWindow *window,*previous;__block UIScrollView *scroll;__block NSUInteger count=0;
    Method getter=class_getInstanceMethod(UIApplication.class,@selector(_touchesEvent));
    IMP original=method_getImplementation(getter);
    UIEvent *event=cached?[[objc_getClass("UITouchesEvent") alloc] _init]:nil;
    IMP empty=imp_implementationWithBlock(^UIEvent *(UIApplication *app){(void)app;return event;});
    ut_ui(^{
        previous=ut_nav.view.window;[TSEventFetcher stop];
        window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];window.windowLevel=UIWindowLevelAlert+200;
        window.rootViewController=[UIViewController new];
        UIButton *button=[UIButton buttonWithConfiguration:UIButtonConfiguration.plainButtonConfiguration primaryAction:[UIAction actionWithHandler:^(__unused UIAction *action){count++;}]];
        button.frame=CGRectMake(40,100,200,44);[window.rootViewController.view addSubview:button];
        scroll=[[UIScrollView alloc] initWithFrame:CGRectMake(40,160,240,300)];scroll.contentSize=CGSizeMake(240,1800);
        [window.rootViewController.view addSubview:scroll];[window makeKeyAndVisible];
        method_setImplementation(getter,empty);
    });
    @try {
        ut_htch(window,CGPointMake(140,122),UITouchPhaseBegan);ut_htch(window,CGPointMake(140,122),UITouchPhaseEnded);
        ut_wait(^BOOL{return count==1;},@"系统触摸事件为空时仍触发一次原生按钮动作");
        // 用真实拖动检查抬手、惯性与顶部回弹。
        ut_htch(window,CGPointMake(140,420),UITouchPhaseBegan);
        for (NSInteger index=1;index<=8;index++) ut_htch(window,CGPointMake(140,420-index*30),UITouchPhaseMoved);
        __block CGFloat lifted;ut_ui(^{lifted=scroll.contentOffset.y;});
        ut_htch(window,CGPointMake(140,180),UITouchPhaseEnded);
        ut_wait(^BOOL{return !scroll.dragging && !scroll.tracking;},@"滚动抬手结束拖动状态");
        usleep(200000);ut_ui(^{ut_req(scroll.contentOffset.y>lifted+5,@"滚动抬手后保留原生惯性");});
        ut_ui(^{[scroll setContentOffset:CGPointZero animated:NO];});
        ut_htch(window,CGPointMake(140,240),UITouchPhaseBegan);
        for (NSInteger index=1;index<=5;index++) ut_htch(window,CGPointMake(140,240+index*30),UITouchPhaseMoved);
        ut_ui(^{ut_req(scroll.contentOffset.y<0,@"顶部拖动进入原生回弹范围");});
        ut_htch(window,CGPointMake(140,390),UITouchPhaseEnded);
        ut_wait(^BOOL{return !scroll.dragging && !scroll.decelerating && fabs(scroll.contentOffset.y)<1;},@"滚动抬手后回到顶部边界");
    } @finally {
        ut_ui(^{method_setImplementation(getter,original);imp_removeBlock(empty);[TSEventFetcher stop];window.hidden=YES;window.rootViewController=nil;[previous makeKeyAndVisible];});
    }
}

// 验证空缓存与原生缓存的触摸回归。
static void ut_evt(void) { ut_evc(NO);ut_evc(YES); }

// 验证真实服务到Swift全屏、打卡和边栏的完整链路。
// 在主队列动作之间等待真实Darwin回调，核对同库交接与窗口恢复。
static void ut_caphud(TTTaskHUD *hud,UIWindow *window,TaskStore *writer,NSDictionary *task) {
    __block NSDictionary *geometry;__block NSString *token;__block UIAction *source;__block NSDictionary *proof;
    ut_ui(^{
        [(UIButton *)ut_find(hud.view,@"hud.complete") sendActionsForControlEvents:UIControlEventTouchUpInside];
        UIButton *upload=(UIButton *)ut_find(hud.view,@"hud.image");source=(UIAction *)upload.menu.children[0];
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(20,20)];
        UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *c){(void)c;[UIColor.greenColor setFill];UIRectFill(CGRectMake(0,0,20,20));}];
        proof=@{@"method":@"image",@"image":UIImageJPEGRepresentation(image,0.85)};
        [hud.view layoutIfNeeded];geometry=ut_hgeo(hud);hud.globalCapture=YES;hud.captureLaunch=^BOOL{return YES;};
        [[UIButton buttonWithConfiguration:UIButtonConfiguration.plainButtonConfiguration primaryAction:source] sendActionsForControlEvents:UIControlEventTouchUpInside];
        token=[writer rdCap:nil error:nil][@"token"];
        ut_req(window.hidden && token!=nil,@"全局采集隐藏窗口并建立唯一同库请求");
    });
    // 采集App持有面板时下一条到期，仍须接回当前轮次。
    NSDictionary *waiting=[writer crtTsk:@{@"title":@"采集中下一条",@"due_at":@(NSDate.date.timeIntervalSince1970+0.1)} error:nil];
    ut_wait(^BOOL{return [writer lsOcc:waiting[@"task_id"] error:nil].count==1;},@"采集期间下一条按时入队");
    for (NSUInteger i=0;i<20;i++) notify_post(writer.changeNote.UTF8String);
    ut_ui(^{ut_req(window.hidden && [[writer rdCap:nil error:nil][@"token"] isEqual:token],@"后续到期及重复通知不抢占前台采集");});
    ut_req([writer ackCap:token error:nil],@"前台采集认领同库请求");
    ut_req([writer finCap:token attachments:@[proof,proof,proof,proof,proof,proof] issue:nil error:nil],@"前台交回六附件但不完成任务");
    notify_post(TS_CAPTURE_NOTE);
    ut_wait(^BOOL{return !window.hidden;},@"真实Darwin结果恢复全局HUD窗口");
    ut_ui(^{
        [hud.view layoutIfNeeded];[hud.view layoutIfNeeded];
        ut_req([writer rdCap:token error:nil].count==0,@"交回后清除临时结果");
        ut_req(![(UIButton *)ut_find(hud.view,@"hud.attachment.5") isHidden] && ![(UIButton *)ut_find(hud.view,@"hud.image") isEnabled],@"交接六附件保持单行与名额");
        ut_req([[writer rdTsk:task[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"],@"采集交接不替代HUD对勾完成");
        ut_req([[(UILabel *)ut_find(hud.view,@"hud.title") text] isEqual:[writer rdTsk:task[@"task_id"] error:nil][@"title"]],@"附件仍回到原任务");
        ut_hsame(geometry,ut_hgeo(hud),@[@"hud.card",@"hud.title",@"hud.planned",@"hud.notes",@"hud.details",@"hud.attachments",@"hud.choices",@"hud.back"],@"前台采集恢复");
        for (NSInteger i=5;i>=0;i--) [(UIButton *)ut_find(hud.view,[NSString stringWithFormat:@"hud.attachment.%ld",(long)i]) sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
    ut_req([writer delTsk:waiting[@"task_id"] error:nil],@"清理排队验证待办");
    // 图片读取失败时保留选择入口，重试和取消不退回初始操作。
    for (NSString *issue in @[@"图片读取失败",@""]) {
        ut_ui(^{
            [[UIButton buttonWithConfiguration:UIButtonConfiguration.plainButtonConfiguration primaryAction:source] sendActionsForControlEvents:UIControlEventTouchUpInside];
            token=[writer rdCap:nil error:nil][@"token"];ut_req(window.hidden && token!=nil,@"失败后可再次发起图片采集");
        });
        ut_req([writer ackCap:token error:nil] && [writer finCap:token attachments:@[] issue:issue.length?issue:nil error:nil],@"交回失败或取消结果");notify_post(TS_CAPTURE_NOTE);
        ut_wait(^BOOL{return !window.hidden;},@"失败和取消恢复同一HUD");
        ut_ui(^{
            [hud.view layoutIfNeeded];
            ut_req(!ut_find(hud.view,@"hud.choices").hidden && ut_find(hud.view,@"hud.complete").superview.hidden && ut_hcnt(hud)==0,@"失败或取消保留三图标选择而不回到初始弹窗");
            ut_hsame(geometry,ut_hgeo(hud),@[@"hud.card",@"hud.details",@"hud.attachments",@"hud.choices"],@"失败取消恢复");
        });
    }
    ut_ui(^{
        hud.captureLaunch=^BOOL{return NO;};
        [[UIButton buttonWithConfiguration:UIButtonConfiguration.plainButtonConfiguration primaryAction:source] sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req(!window.hidden && [writer rdCap:nil error:nil].count==0 && hud.mode==1,@"采集App启动失败立即恢复提醒且不留请求");
        hud.globalCapture=NO;hud.captureLaunch=nil;
        [(UIButton *)ut_find(hud.view,@"hud.back") sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
}

// 驱动原生文件多选结果并等待系统面板撤下。
static void ut_flpick(TTTaskHUD *hud,UIAction *source,NSArray<NSURL *> *urls) {
    if (source) ut_ui(^{[[UIButton buttonWithConfiguration:UIButtonConfiguration.plainButtonConfiguration primaryAction:source] sendActionsForControlEvents:UIControlEventTouchUpInside];});
    ut_wait(^BOOL{return [hud.presentedViewController isKindOfClass:UIDocumentPickerViewController.class] && !hud.presentedViewController.isBeingPresented;},@"普通文件入口呈现原生文档选择器");
    ut_ui(^{
        UIDocumentPickerViewController *picker=(UIDocumentPickerViewController *)hud.presentedViewController;
        ut_req(picker.allowsMultipleSelection,@"原生文件选择器开启多选");
        if (urls) [(id<UIDocumentPickerDelegate>)hud documentPicker:picker didPickDocumentsAtURLs:urls];
        else [(id<UIDocumentPickerDelegate>)hud documentPickerWasCancelled:picker];
    });
    ut_wait(^BOOL{return hud.presentedViewController==nil;},@"文件批次交回后撤下系统面板");
}

// 用真实文件核对批量追加、剩余名额和整批一次交回。
static void ut_flprf(TTTaskHUD *hud,TaskStore *writer,NSDictionary *task) {
    __block NSDictionary *geometry;__block UIAction *source;
    NSMutableArray<NSURL *> *urls=[NSMutableArray new];
    NSArray *contents=@[[NSData dataWithBytes:(unsigned char[]){0,255,1,0,42} length:5],[@"%PDF-1.4\nfile" dataUsingEncoding:NSUTF8StringEncoding],[NSData data]];
    for (NSUInteger i=0;i<contents.count;i++) {
        NSURL *url=[NSURL fileURLWithPath:[ut_docs stringByAppendingPathComponent:[NSString stringWithFormat:@"普通附件%lu.bin",(unsigned long)i]]];
        ut_req([contents[i] writeToURL:url atomically:YES],@"准备普通二进制、PDF和空文件");[urls addObject:url];
    }
    NSURL *missing=[NSURL fileURLWithPath:[ut_docs stringByAppendingPathComponent:@"不存在的附件.bin"]];
    [NSFileManager.defaultManager removeItemAtURL:missing error:nil];
    ut_ui(^{
        [(UIButton *)ut_find(hud.view,@"hud.complete") sendActionsForControlEvents:UIControlEventTouchUpInside];
        [hud.view layoutIfNeeded];geometry=ut_hgeo(hud);source=(UIAction *)[(UIButton *)ut_find(hud.view,@"hud.image") menu].children[3];
    });
    NSArray *batches=@[urls,@[missing,urls[0]],urls,@[urls[1],urls[2]]];
    NSArray *counts=@[@3,@4,@4,@6];
    for (NSUInteger i=0;i<batches.count;i++) {
        ut_flpick(hud,source,batches[i]);
        ut_ui(^{
            [hud.view layoutIfNeeded];
            ut_req(ut_hcnt(hud)==[counts[i] unsignedIntegerValue],@"批量读取全部文件、部分失败保留有效项、超额整批拒绝");
            ut_req(!ut_find(hud.view,@"hud.choices").hidden && ut_find(hud.view,@"hud.complete").superview.hidden && [(UIButton *)ut_find(hud.view,@"hud.attachment.0") configuration].title.length==0,@"普通文件气泡仅图标且保留选择状态");
            ut_req([[(UIButton *)ut_find(hud.view,@"hud.attachment.0") accessibilityLabel] containsString:@"文件"],@"普通文件图标具有对应无障碍名称");
            ut_hsame(geometry,ut_hgeo(hud),@[@"hud.card",@"hud.details",@"hud.attachments",@"hud.choices"],@"普通文件批量返回");
            ut_req([[writer rdTsk:task[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"],@"选择普通文件不提前完成任务");
        });
    }
    ut_ui(^{ut_req(![(UIButton *)ut_find(hud.view,@"hud.image") isEnabled],@"六附件禁用继续选择");[(UIButton *)ut_find(hud.view,@"hud.attachment.0") sendActionsForControlEvents:UIControlEventTouchUpInside];});
    ut_flpick(hud,source,@[urls[0]]);
    ut_ui(^{ut_req(ut_hcnt(hud)==6,@"删除后可用单个文件补齐剩余名额");for (NSUInteger i=0;i<6;i++) [(UIButton *)ut_find(hud.view,@"hud.attachment.0") sendActionsForControlEvents:UIControlEventTouchUpInside];[(UIButton *)ut_find(hud.view,@"hud.back") sendActionsForControlEvents:UIControlEventTouchUpInside];});
    // 使用真实前台采集入口验证completion不在第一项后提前交回。
    NSArray *cases=@[urls,urls,@[missing,urls[0]],NSNull.null];
    NSArray *limits=@[@3,@2,@2,@1],*expected=@[@3,@0,@1,@0];
    for (NSUInteger i=0;i<cases.count;i++) {
        __block TTTaskHUD *collector;__block NSArray *result;__block NSString *issue;__block NSUInteger calls=0;
        ut_ui(^{
            collector=[TTTaskHUD new];UIViewController *host=hud.parentViewController;[host addChildViewController:collector];collector.view.frame=host.view.bounds;[host.view addSubview:collector.view];[collector didMoveToParentViewController:host];
            [collector capOpen:@{@"occurrence_id":@"file-batch",@"source":@"file",@"capacity":limits[i]} completion:^(NSArray *items,NSString *error){calls++;result=items;issue=error;}];
        });
        ut_flpick(collector,nil,cases[i]==NSNull.null?nil:cases[i]);
        ut_ui(^{
            ut_req(calls==1 && result.count==[expected[i] unsignedIntegerValue],@"前台批量采集仅交回一次完整结果并遵守剩余名额");
            ut_req((i==1 || i==2)?issue.length>0:issue==nil,@"超额或读取失败返回错误，成功及取消不报错");
            for (NSUInteger j=0;j<result.count;j++) {
                NSUInteger sourceIndex=i==2?0:j;
                ut_req([result[j][@"image"] isEqual:contents[sourceIndex]] && [result[j][@"name"] isEqual:urls[sourceIndex].lastPathComponent] && [result[j][@"content_type"] length]>0,@"整批文件原始字节、顺序及元数据保持");
            }
            [collector stop];[collector willMoveToParentViewController:nil];[collector.view removeFromSuperview];[collector removeFromParentViewController];
        });
    }
}

static void ut_hud(void) {
    ut_layout=[NSMutableDictionary new];
    ut_evt();
    NSString *path=[ut_docs stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingString:@".sqlite3"]];TaskStore *writer=[[TaskStore alloc] initAt:path error:nil];
    __block UIWindow *window;__block UIViewController *host;__block TTTaskHUD *hud;__block TaskReminder *service;__block NSDictionary *active;
    // 建立同一安全区容器与真实服务。
    void (^start)(void)=^{
        hud=[TTTaskHUD new];[host addChildViewController:hud];hud.view.frame=host.view.bounds;hud.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [host.view addSubview:hud.view];[hud didMoveToParentViewController:host];
        __weak TTTaskHUD *weakHUD=hud;__weak UIWindow *weakWindow=window;__weak UIViewController *weakHost=host;
        hud.windowMode=^(NSInteger mode){weakWindow.hidden=mode==0;weakWindow.frame=mode==2?CGRectMake(280,200,72,96):UIScreen.mainScreen.bounds;weakHost.view.frame=weakWindow.bounds;weakHUD.view.frame=weakHost.view.bounds;};
        service=[[TaskReminder alloc] initAt:path handler:^(NSDictionary *a,NSError *e){active=a;[weakHUD display:a error:e];} cleanup:^{[weakHUD stop];} finish:^(__unused BOOL r){}];hud.reminder=service;
        ut_req([service start:nil],@"全屏HUD连接真实TaskReminder");
    };
    ut_ui(^{
        lb_svcfg(@{@"enabled":@YES});window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];window.windowLevel=UIWindowLevelAlert+100;
        host=[UIViewController new];window.rootViewController=host;start();
        for (NSValue *v in @[[NSValue valueWithCGSize:CGSizeMake(375,812)],[NSValue valueWithCGSize:CGSizeMake(768,1024)]]) {
            CGRect screen=(CGRect){CGPointZero,v.CGSizeValue};UIEdgeInsets inset=UIEdgeInsetsMake(47,0,34,0);
            CGRect safe=UIEdgeInsetsInsetRect(screen,inset);
            for (NSNumber *o in @[@(UIInterfaceOrientationPortrait),@(UIInterfaceOrientationLandscapeLeft),@(UIInterfaceOrientationLandscapeRight),@(UIInterfaceOrientationPortraitUpsideDown)]) {
                CGRect bar=lb_hudfrm(screen,inset,o.integerValue);
                ut_req(CGRectContainsRect(CGRectInset(safe,-0.1,-0.1),bar),@"边栏各方向均在原生安全区内");
                ut_req(fabs(bar.size.width*bar.size.height-72*96)<0.1,@"边栏旋转保持触摸面积");
            }
        }
    });
    NSString *title=[@"完整待办标题" stringByPaddingToLength:200 withString:@"任务内容" startingAtIndex:0];NSString *notes=[@"完整说明" stringByPaddingToLength:2000 withString:@"详细说明与下一步。" startingAtIndex:0];
    NSDictionary *task=[writer crtTsk:@{@"title":title,@"notes":notes,@"due_at":@(NSDate.date.timeIntervalSince1970-1),@"schedule_kind":@"timed"} error:nil];
    ut_wait(^BOOL{return hud.mode==1 && [active[@"task_id"] isEqual:task[@"task_id"]];},@"实际到期进入独占全屏");__block NSString *id;
    ut_ui(^{
        id=active[@"occurrence_id"];ut_req([[(UILabel *)ut_find(hud.view,@"hud.title") text] isEqual:title] && [[(UILabel *)ut_find(hud.view,@"hud.notes") text] isEqual:notes],@"标题和说明全文保持");
        ut_req(ut_find(hud.view,@"hud.close")==nil && [window hitTest:CGPointMake(2,2) withEvent:nil]!=nil,@"全屏背景命中且没有关闭入口");
        [(UIButton *)ut_find(hud.view,@"hud.complete") sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req(hud.mode==1 && [[writer rdTsk:task[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"],@"点击完成先打卡，不直接关闭");
        [(UIButton *)ut_find(hud.view,@"hud.back") sendActionsForControlEvents:UIControlEventTouchUpInside];ut_req(hud.mode==1,@"取消方式选择保持提醒");
        [hud display:nil error:[NSError errorWithDomain:@"test" code:SQLITE_BUSY userInfo:nil]];ut_req(hud.mode==1,@"数据库失败仍保持全屏");
        [hud display:active error:nil];
    });
    for (NSValue *v in @[[NSValue valueWithCGSize:CGSizeMake(320,568)],[NSValue valueWithCGSize:CGSizeMake(812,375)],[NSValue valueWithCGSize:CGSizeMake(768,1024)],[NSValue valueWithCGSize:CGSizeMake(1024,768)]])
        for (NSNumber *large in @[@NO,@YES]) ut_hshot(hud,host,window,v.CGSizeValue,large.boolValue,[NSString stringWithFormat:@"hud-%.0fx%.0f-%@.png",v.CGSizeValue.width,v.CGSizeValue.height,large.boolValue?@"large":@"normal"],id);
    ut_ui(^{window.frame=UIScreen.mainScreen.bounds;host.view.frame=window.bounds;hud.view.frame=host.view.bounds;[hud display:active error:nil];[host.view layoutIfNeeded];[hud.view layoutIfNeeded];});
    // 恢复实际手机视口和关键窗口后验证输入，尺寸渲染不作为物理触摸坐标。
    ut_ui(^{[window makeKeyAndVisible];});
    ut_hshot(hud,host,window,UIScreen.mainScreen.bounds.size,NO,@"hud-native-touch.png",id);
    // 在没有普通App场景的独立HUD条件下验证首个真实触摸。
    ut_ui(^{
        Method getter=class_getInstanceMethod(UIApplication.class,@selector(connectedScenes));
        IMP original=method_getImplementation(getter);
        IMP empty=imp_implementationWithBlock(^NSSet *(UIApplication *app){(void)app;return [NSSet set];});
        [TSEventFetcher stop];method_setImplementation(getter,empty);
        @try {
            CGPoint point=CGPointMake(2,2);UIView *hit=[window hitTest:point withEvent:nil];
            [TSEventFetcher receiveAXEventID:1 atGlobalCoordinate:point withTouchPhase:UITouchPhaseBegan inWindow:window onView:hit];
            ut_req(hud.mode==1,@"独立HUD没有Scene时首个背景触摸不崩溃");
        } @finally {method_setImplementation(getter,original);imp_removeBlock(empty);}
    });
    ut_htch(window,CGPointMake(2,2),UITouchPhaseEnded);
    // 通过同一原生触摸源点击完成和返回，不直接调用按钮动作。
    __block CGPoint buttonPoint;
    ut_ui(^{UIView *button=ut_find(hud.view,@"hud.complete");buttonPoint=[button convertPoint:CGPointMake(button.bounds.size.width/2,button.bounds.size.height/2) toView:window];});
    ut_htch(window,buttonPoint,UITouchPhaseBegan);ut_htch(window,buttonPoint,UITouchPhaseEnded);
    ut_ui(^{
        ut_req(!ut_find(hud.view,@"hud.choices").hidden && ut_find(hud.view,@"hud.complete").superview.hidden && hud.mode==1,@"真实触摸提交仅打开打卡选择");
        [hud.view layoutIfNeeded];UIView *button=ut_find(hud.view,@"hud.back");
        buttonPoint=[button convertPoint:CGPointMake(button.bounds.size.width/2,button.bounds.size.height/2) toView:window];
    });
    ut_htch(window,buttonPoint,UITouchPhaseBegan);ut_htch(window,buttonPoint,UITouchPhaseEnded);
    ut_ui(^{ut_req(ut_find(hud.view,@"hud.choices").hidden && !ut_find(hud.view,@"hud.complete").superview.hidden && hud.mode==1,@"真实触摸返回保持提醒");});
    ut_ui(^{ut_req(hud.mode==1,@"同一原生触摸路由点击背景不能关闭");});
    __block CGPoint from;ut_ui(^{UIScrollView *s=(UIScrollView *)ut_find(hud.view,@"hud.details");[s setContentOffset:CGPointZero animated:NO];from=[s convertPoint:CGPointMake(s.bounds.size.width/2,s.bounds.size.height/2) toView:window];});
    ut_htch(window,from,UITouchPhaseBegan);for (int i=1;i<=4;i++) ut_htch(window,CGPointMake(from.x,from.y-i*25),UITouchPhaseMoved);ut_htch(window,CGPointMake(from.x,from.y-100),UITouchPhaseEnded);
    ut_wait(^BOOL{return [(UIScrollView *)ut_find(hud.view,@"hud.details") contentOffset].y>0;},@"原生触摸使详细内容可滚动");
    ut_ui(^{ut_req(hud.mode==1,@"普通滑动保持全屏提醒");});
    ut_req([writer updTsk:task[@"task_id"] fields:@{@"title":@"完成今天的学习计划",@"notes":@"复习课程要点，完成练习。\n完成后选择一种方式打卡。"} error:nil],@"修改真实提醒的标题说明");
    ut_wait(^BOOL{return [[(UILabel *)ut_find(hud.view,@"hud.title") text] isEqual:@"完成今天的学习计划"];},@"全屏提醒即时同步最新标题");
    ut_hshot(hud,host,window,CGSizeMake(375,812),NO,@"hud-reading.png",id);
    ut_ui(^{[(UIButton *)ut_find(hud.view,@"hud.snooze") sendActionsForControlEvents:UIControlEventTouchUpInside];});ut_wait(^BOOL{return hud.mode==2;},@"延期提交后收起边栏");
    NSDictionary *row=[writer lsOcc:task[@"task_id"] error:nil].firstObject;ut_req([row[@"defer_count"] intValue]==1 && fabs([row[@"hold_until"] doubleValue]-NSDate.date.timeIntervalSince1970-300)<3,@"五分钟绝对截止和次数持久化");
    ut_ui(^{ut_req(window.bounds.size.width==72 && window.bounds.size.height==96 && [window hitTest:CGPointMake(100,100) withEvent:nil]==nil,@"边栏物理窗口只命中自身");[service stop];[hud willMoveToParentViewController:nil];[hud.view removeFromSuperview];[hud removeFromParentViewController];start();});
    ut_wait(^BOOL{return hud.mode==2;},@"重启且仅有未来收起时恢复边栏");ut_hdue(path,id);notify_post(writer.changeNote.UTF8String);
    ut_wait(^BOOL{return hud.mode==1 && [active[@"occurrence_id"] isEqual:id];},@"绝对截止重弹同一Occurrence");
    ut_ui(^{ut_req(![(UIButton *)ut_find(hud.view,@"hud.snooze") isEnabled],@"重启与重弹不重置延期次数");[(UIButton *)ut_find(hud.view,@"hud.complete") sendActionsForControlEvents:UIControlEventTouchUpInside];[(UIButton *)ut_find(hud.view,@"hud.screenshot") sendActionsForControlEvents:UIControlEventTouchUpInside];});
    ut_wait(^BOOL{return hud.mode==2;},@"截图收起到边栏");row=[writer lsOcc:task[@"task_id"] error:nil].firstObject;
    ut_req([row[@"defer_count"] intValue]==1 && fabs([row[@"hold_until"] doubleValue]-NSDate.date.timeIntervalSince1970-120)<3,@"截图两分钟不破坏唯一延期次数");ut_hdue(path,id);notify_post(writer.changeNote.UTF8String);
    ut_wait(^BOOL{return hud.mode==1;},@"截图等待到时重新全屏");
    ut_caphud(hud,window,writer,task);
    ut_flprf(hud,writer,task);
    ut_ui(^{
        [(UIButton *)ut_find(hud.view,@"hud.complete") sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req(ut_find(hud.view,@"hud.select-screenshot")==nil,@"选择截图不额外占用第五个图标");
        UIButton *upload=(UIButton *)ut_find(hud.view,@"hud.image");NSArray<UIAction *> *sources=(NSArray *)upload.menu.children;
        ut_req(upload.showsMenuAsPrimaryAction && [[sources valueForKey:@"title"] isEqual:@[@"照片图库",@"拍照",@"选择截图",@"选取文件"]] && hud.presentedViewController==nil,@"上传按钮使用原生UIMenu四来源");
        for (UIAction *action in sources) ut_req(action.image!=nil,@"来源菜单保留原生图标");
        if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
            [[UIButton buttonWithConfiguration:UIButtonConfiguration.plainButtonConfiguration primaryAction:sources[1]] sendActionsForControlEvents:UIControlEventTouchUpInside];
            UIButton *submit=(UIButton *)ut_find(hud.view,@"hud.complete");
            ut_req(!submit.superview.hidden && [submit.configuration.title isEqual:@"相机不可用"] && hud.mode==1,@"菜单拍照不可用时保留提醒与重试入口");
            [submit sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(20,20)];UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *c){(void)c;[UIColor.greenColor setFill];UIRectFill(CGRectMake(0,0,20,20));}];
        [hud.view layoutIfNeeded];[hud.view layoutIfNeeded];
        NSMutableDictionary *geometry=[@{@"choosing":ut_hgeo(hud)} mutableCopy];
        [hud acceptImage:image method:@"screenshot" occID:id];[hud.view layoutIfNeeded];[hud.view layoutIfNeeded];
        geometry[@"attached"]=ut_hgeo(hud);
        NSArray *stable=@[@"hud.card",@"hud.title",@"hud.planned",@"hud.notes",@"hud.details",@"hud.attachments",@"hud.choices",@"hud.back"];
        ut_hsame(geometry[@"choosing"],geometry[@"attached"],stable,@"添加附件");
        UIButton *attachment=(UIButton *)ut_find(hud.view,@"hud.attachment.0"),*confirm=(UIButton *)ut_find(hud.view,@"hud.back");
        ut_req(ut_find(hud.view,@"hud.proof")==nil && !attachment.hidden && attachment.configuration.title.length==0 && attachment.configuration.image!=nil,@"附件仅显示可删除图标且无内容预览");
        ut_req(!ut_find(hud.view,@"hud.choices").hidden && ut_find(hud.view,@"hud.complete").superview.hidden && [confirm.accessibilityLabel isEqual:@"提交并完成当前任务"] && [[writer rdTsk:task[@"task_id"] error:nil][@"status"] isEqual:@"needsAction"] && [writer rdChk:id image:NO error:nil]==nil,@"有附件才把返回原位换成对勾且未提前完成");
        UIGraphicsImageRenderer *screen=[[UIGraphicsImageRenderer alloc] initWithSize:hud.view.bounds.size];
        [[screen PNGDataWithActions:^(UIGraphicsImageRendererContext *c){[hud.view.layer renderInContext:c.CGContext];}] writeToFile:[ut_docs stringByAppendingPathComponent:@"screens/hud-attachment.png"] atomically:YES];
        [attachment sendActionsForControlEvents:UIControlEventTouchUpInside];[hud.view layoutIfNeeded];
        geometry[@"removed"]=ut_hgeo(hud);ut_hsame(geometry[@"choosing"],geometry[@"removed"],stable,@"删除附件");
        ut_req(attachment.hidden && [confirm.accessibilityLabel isEqual:@"返回"] && [writer rdChk:id image:NO error:nil]==nil,@"取消附件恢复返回并保持任务未完成");
        [hud acceptImage:image method:@"image" occID:@"stale-occurrence"];ut_req(attachment.hidden,@"过时图片不能添加给当前任务");
        [confirm sendActionsForControlEvents:UIControlEventTouchUpInside];ut_req(ut_find(hud.view,@"hud.choices").hidden && hud.mode==1,@"删除附件后返回仍可恢复主操作");
        [(UIButton *)ut_find(hud.view,@"hud.complete") sendActionsForControlEvents:UIControlEventTouchUpInside];
        [hud acceptImage:image method:@"screenshot" occID:id];[hud.view layoutIfNeeded];
        [hud display:nil error:[NSError errorWithDomain:@"test" code:SQLITE_BUSY userInfo:nil]];[hud.view layoutIfNeeded];
        geometry[@"retry"]=ut_hgeo(hud);ut_hsame(geometry[@"choosing"],geometry[@"retry"],stable,@"失败重试");
        ut_req(!attachment.hidden && confirm.enabled && [confirm.accessibilityLabel isEqual:@"提交并完成当前任务"] && [confirm.accessibilityValue isEqual:@"重试打卡"],@"提交失败保留附件与可重试对勾");
        for (NSUInteger index=1;index<TS_ATT_MAX;index++) [hud acceptImage:image method:@"screenshot" occID:id];
        [hud.view layoutIfNeeded];geometry[@"six"]=ut_hgeo(hud);ut_hsame(geometry[@"choosing"],geometry[@"six"],stable,@"六附件确认");
        ut_req(ut_hcnt(hud)==TS_ATT_MAX,@"提交前保留六个附件");
        [(UIButton *)ut_find(hud.view,@"hud.attachment.2") sendActionsForControlEvents:UIControlEventTouchUpInside];
        ut_req(ut_hcnt(hud)==5 && [confirm.accessibilityLabel isEqual:@"提交并完成当前任务"] && [(UIButton *)ut_find(hud.view,@"hud.image") isEnabled],@"删除中间附件保留对勾并释放名额");
        [hud acceptImage:image method:@"camera" occID:id];[hud.view layoutIfNeeded];ut_req(ut_hcnt(hud)==TS_ATT_MAX,@"补充附件后恢复六个");
        [[screen PNGDataWithActions:^(UIGraphicsImageRendererContext *c){[hud.view.layer renderInContext:c.CGContext];}] writeToFile:[ut_docs stringByAppendingPathComponent:@"screens/hud-six-attachments.png"] atomically:YES];
        ut_layout[@"proof-flow"]=geometry;
        NSData *audit=[NSJSONSerialization dataWithJSONObject:ut_layout options:NSJSONWritingPrettyPrinted error:nil];
        ut_req([audit writeToFile:[ut_docs stringByAppendingPathComponent:@"HUDLayoutAudit.json"] atomically:YES],@"保存状态切换真实几何审计");
        [confirm sendActionsForControlEvents:UIControlEventTouchUpInside];
        // 同一轮次的迟到快照不能解除提交锁或清空附件。
        [hud display:active error:nil];[hud.view layoutIfNeeded];
        ut_req(!confirm.enabled && ![(UIButton *)ut_find(hud.view,@"hud.snooze") isEnabled] && ut_hcnt(hud)==TS_ATT_MAX,@"重复快照保留提交锁和六附件");
        for (NSUInteger i=0;i<20;i++) [confirm sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
    ut_wait(^BOOL{return hud.mode==0 && [[writer rdTsk:task[@"task_id"] error:nil][@"status"] isEqual:@"completed"];},@"图片与完成记录提交后才消失");ut_req([[writer rdChk:id image:NO error:nil][@"method"] isEqual:@"screenshot"] && [writer lsChk:id images:YES error:nil].count==TS_ATT_MAX && [[writer lsChk:id images:NO error:nil].lastObject[@"method"] isEqual:@"camera"],@"六附件按顺序关联当前Occurrence");
    NSDictionary *next=[writer crtTsk:@{@"title":@"边栏删除同步",@"due_at":@(NSDate.date.timeIntervalSince1970-1)} error:nil];
    ut_wait(^BOOL{return hud.mode==1 && [active[@"task_id"] isEqual:next[@"task_id"]];},@"处理后下一任务立即展示");ut_ui(^{[(UIButton *)ut_find(hud.view,@"hud.snooze") sendActionsForControlEvents:UIControlEventTouchUpInside];});
    ut_wait(^BOOL{return hud.mode==2;},@"后续Occurrence拥有独立延期次数");ut_req([writer delTsk:next[@"task_id"] error:nil],@"删除边栏中的任务");ut_wait(^BOOL{return hud.mode==0;},@"Darwin删除立即撤销边栏与未来提醒");
    ut_ui(^{[TSEventFetcher stop];[service stop];window.hidden=YES;window.rootViewController=nil;hud=nil;host=nil;window=nil;service=nil;});
}
