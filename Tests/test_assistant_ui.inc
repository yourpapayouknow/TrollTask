// 在真实UIKit中验证手动拆分、既有子任务和设置返回闭环。
static void ut_ast(void) {
    ut_home();
    // 原生构造与正常产品入口使用同一页面和数据库。
    ut_ui(^{[ut_nav pushViewController:[[TaskAssistantScreen alloc]initWithStore:ut_store task:nil] animated:NO];});
    ut_wait(^BOOL{return ut_find(ut_surface(),@"assistant.title")!=nil;},@"智能创建可编辑目标");
    ut_ui(^{UITextField *name=(UITextField *)ut_find(ut_surface(),@"assistant.title");name.text=@"手动拆分验收";[name sendActionsForControlEvents:UIControlEventEditingChanged];});
    long long before=[ut_store revision:nil];
    // 故意关闭可用端口，验证真实URLSession错误仍保留手动入口。
    ut_ui(^{[NSUserDefaults.standardUserDefaults setObject:@"http://127.0.0.1:9/v1" forKey:@"assistant.endpoint"];});
    ut_tap(@"assistant.generate");ut_wait(^BOOL{return [ut_top()isKindOfClass:UIAlertController.class];},@"连接失败进入手动退化提示");
    ut_ui(^{ut_req([ut_top().title isEqual:@"服务暂不可达"],@"离线提示为可理解状态");[ut_top()dismissViewControllerAnimated:NO completion:nil];[NSUserDefaults.standardUserDefaults removeObjectForKey:@"assistant.endpoint"];});
    ut_req([ut_store revision:nil]==before,@"断线没有提前修改任务");ut_tap(@"assistant.manual");ut_wait(^BOOL{return ut_find(ut_surface(),@"step.title")!=nil && !ut_nav.transitionCoordinator;},@"手动步骤编辑完成呈现");
    ut_ui(^{((UITextView *)ut_find(ut_surface(),@"step.title")).text=@"先整理资料";((UITextView *)ut_find(ut_surface(),@"step.notes")).text=@"保留手动修改";((UITextField *)ut_find(ut_surface(),@"step.minutes")).text=@"20";});
    ut_tap(@"step.save");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskAssistantScreen.class] && !ut_nav.transitionCoordinator;},@"手动步骤返回原草稿");
    ut_req([ut_store revision:nil]==before,@"确认前不提前创建父子任务");
    ut_tap(@"assistant.settings");ut_wait(^BOOL{return ut_find(ut_surface(),@"assistant.key")!=nil && !ut_nav.transitionCoordinator;},@"助手设置完成呈现");
    ut_ui(^{ut_req([(UITextField *)ut_find(ut_surface(),@"assistant.key") isSecureTextEntry],@"密钥字段使用系统隐藏输入");ut_req([((UITextField *)ut_find(ut_surface(),@"assistant.endpoint")).text containsString:@"8765"],@"默认连接用户指定的Mac端口");});
    ut_ui(^{((UITextField *)ut_find(ut_surface(),@"assistant.key")).text=@"ui-fixture-key";});
    ut_tap(@"assistant.config.save");
    ut_wait(^BOOL{return [ut_top() isKindOfClass:TaskAssistantScreen.class] && !ut_nav.transitionCoordinator;},@"配置保存返回并保留手动草稿");
    ut_ui(^{UITableView *table=(UITableView *)ut_find(ut_surface(),@"assistant.steps");ut_req([table numberOfRowsInSection:0]==1,@"设置返回不丢失步骤");});
    ut_tap(@"assistant.settings");ut_wait(^BOOL{return ut_find(ut_surface(),@"assistant.key")!=nil && !ut_nav.transitionCoordinator;},@"助手设置完成呈现");ut_ui(^{ut_req([((UITextField *)ut_find(ut_surface(),@"assistant.key")).text isEqual:@"ui-fixture-key"],@"钥匙串能够保存并取回密钥");((UITextField *)ut_find(ut_surface(),@"assistant.key")).text=@"";});ut_tap(@"assistant.config.save");
    ut_wait(^BOOL{return [ut_top()isKindOfClass:TaskAssistantScreen.class] && !ut_nav.transitionCoordinator;},@"清空测试密钥后返回草稿");
    ut_shot(@"assistant-dark-320.png",320,693,NO);ut_shot(@"assistant-large-320.png",320,850,YES);
    ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleLight;});ut_shot(@"assistant-light-375.png",375,850,NO);
    ut_ui(^{ut_nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;});ut_tap(@"assistant.save");ut_home();
    NSDictionary *parent=nil,*child=nil;for(NSDictionary *row in [ut_store lsTsks:nil]){if([row[@"title"]isEqual:@"手动拆分验收"])parent=row;if([row[@"title"]isEqual:@"先整理资料"])child=row;}
    ut_req(parent && child && [child[@"parent_id"]isEqual:parent[@"task_id"]],@"确认后一次写入同一任务树");
    ut_ui(^{[ut_nav pushViewController:[[TaskAssistantScreen alloc]initWithStore:ut_store task:parent[@"task_id"]] animated:NO];});
    ut_wait(^BOOL{return ut_find(ut_surface(),@"assistant.step.0")!=nil;},@"已有子任务直接显示不重新调用AI");
    ut_ui(^{ut_req(![(UIButton *)ut_find(ut_surface(),@"assistant.generate") isEnabled],@"已有步骤不被生成按钮覆盖");});
    ut_tap(@"assistant.step.0");ut_wait(^BOOL{return ut_find(ut_surface(),@"step.title")!=nil && !ut_nav.transitionCoordinator;},@"步骤编辑完成呈现");ut_ui(^{((UITextView *)ut_find(ut_surface(),@"step.title")).text=@"修改后的步骤";});ut_tap(@"step.save");
    ut_wait(^BOOL{return [ut_top()isKindOfClass:TaskAssistantScreen.class] && !ut_nav.transitionCoordinator;},@"原步骤可手动修改");
    ut_tap(@"assistant.save");ut_home();
    ut_req([[ut_store rdTsk:child[@"task_id"] error:nil][@"title"]isEqual:@"修改后的步骤"],@"修改保留原子任务UUID");
    ut_edt([ut_store rdTsk:parent[@"task_id"] error:nil]);ut_tap(@"edit.more");ut_tap(@"edit.split");
    ut_wait(^BOOL{return [ut_top()isKindOfClass:TaskAssistantScreen.class] && !ut_nav.transitionCoordinator;},@"原任务详情可以接续智能拆分");
    ut_ui(^{ut_req([ut_nav.viewControllers filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id item,NSDictionary *bindings){(void)bindings;return [item isKindOfClass:TaskEdit.class];}]].count==0,@"拆分替换旧详情快照");[ut_nav popToRootViewControllerAnimated:NO];});ut_home();
    ut_req([ut_store delTsk:parent[@"task_id"] error:nil],@"清理独立助手验收任务");
    // 从手机通过Tailscale发送单条合成目标，不发送其他任务。
    NSDictionary *online=[ut_store crtTsk:@{@"title":@"整理六份课程笔记",@"notes":@"按章节分类、检查遗漏并输出索引",@"planned_duration":@1800} error:nil];long long version=[ut_store revision:nil];
    ut_ui(^{[ut_nav pushViewController:[[TaskAssistantScreen alloc]initWithStore:ut_store task:online[@"task_id"]] animated:NO];});ut_tap(@"assistant.generate");
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:90];__block BOOL ready=NO,failed=NO;
    while(!ready && !failed && end.timeIntervalSinceNow>0){ut_ui(^{ready=[(UITableView *)ut_find(ut_surface(),@"assistant.steps") numberOfRowsInSection:0]>0;failed=[ut_top()isKindOfClass:UIAlertController.class];});if(!ready && !failed)usleep(100000);}
    ut_req(ready && !failed,@"手机通过Tailscale取得真实AI草稿");ut_req([ut_store revision:nil]==version,@"真实AI生成也不会提前保存");
    ut_tap(@"assistant.step.0");ut_wait(^BOOL{return ut_find(ut_surface(),@"step.title")!=nil && !ut_nav.transitionCoordinator;},@"步骤编辑完成呈现");ut_ui(^{((UITextView *)ut_find(ut_surface(),@"step.title")).text=@"人工确认后的第一步";});ut_tap(@"step.save");
    ut_wait(^BOOL{return [ut_top()isKindOfClass:TaskAssistantScreen.class] && !ut_nav.transitionCoordinator;},@"真实AI建议始终允许手动修改");ut_tap(@"assistant.save");ut_home();
    BOOL edited=NO;for(NSDictionary *row in [ut_store lsTsks:nil])if([row[@"parent_id"]isEqual:online[@"task_id"]] && [row[@"title"]isEqual:@"人工确认后的第一步"])edited=YES;
    ut_req(edited,@"确认后写入修改过的真实AI步骤");ut_req([ut_store delTsk:online[@"task_id"] error:nil],@"清理真实AI合成验收目标");
}
