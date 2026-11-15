// 保存助手连接设置，密钥只存系统钥匙串。
enum TaskAIConfig {
    // 读取现有Tailscale服务与可选认证。
    static func ld()->TaskFields {
        // 只迁移旧默认档，用户后续仍可修改每档真实模型ID。
        if UserDefaults.standard.integer(forKey:"assistant.tiers")==0 {if UserDefaults.standard.string(forKey:"assistant.model")=="fast-model"{UserDefaults.standard.set("deepseek-v4.1-flash",forKey:"assistant.model")};UserDefaults.standard.set(1,forKey:"assistant.tiers")}
        let key=(try? TaskKeychain.rd("assistant")).flatMap{String(data:$0,encoding:.utf8)} ?? ""
        return ["endpoint":UserDefaults.standard.string(forKey:"assistant.endpoint") ?? "http://100.121.131.101:8765/v1","model":UserDefaults.standard.string(forKey:"assistant.model") ?? "deepseek-v4.1-flash","hard_model":UserDefaults.standard.string(forKey:"assistant.hard_model") ?? "glm-5.3","ddl_model":UserDefaults.standard.string(forKey:"assistant.ddl_model") ?? "glm-5.3","key":key]
    }
    // 先验证连接信息再保存，认证失败不覆盖旧密钥。
    static func sv(_ config:TaskFields) throws {
        _ = try TaskAI.req(["goal":"验证设置"],config)
        let key=config["key"] as? String ?? ""
        try TaskKeychain.sv("assistant",key.isEmpty ? nil : Data(key.utf8))
        UserDefaults.standard.set(config["endpoint"],forKey:"assistant.endpoint");UserDefaults.standard.set(config["model"],forKey:"assistant.model");for key in ["hard_model","ddl_model"]{if let value=config[key] as? String,!value.isEmpty{UserDefaults.standard.set(value,forKey:"assistant."+key)}}
    }
}

// 提供可修改的服务地址、模型与可选密钥。
@objc(TaskAISettings) final class TaskAISettings:TaskScreen {
    private let endpoint=UITextView(),model=UITextField(),hard=UITextField(),best=UITextField(),key=UITextField()
    // 创建统一表单，不探测或修改Mac服务配置。
    override func viewDidLoad() {
        super.viewDidLoad();title="助手设置";let values=TaskAIConfig.ld()
        for (field,id,name) in [(model,"model","默认模型"),(hard,"hard_model","复杂模型"),(best,"ddl_model","赶DDL模型"),(key,"key","密钥")] { tu_fld(field);field.font=lb_fnt(.body,traitCollection);field.adjustsFontForContentSizeCategory=true;field.textColor=TaskTheme.ink;field.autocapitalizationType = .none;field.autocorrectionType = .no;field.accessibilityIdentifier="assistant."+id;field.accessibilityLabel=name;field.text=values[id] as? String;
             }
        tu_fld(endpoint);endpoint.font=lb_fnt(.body,traitCollection);endpoint.adjustsFontForContentSizeCategory=true;endpoint.textColor=TaskTheme.ink;endpoint.autocapitalizationType = .none;endpoint.autocorrectionType = .no;endpoint.keyboardType = .URL;endpoint.isScrollEnabled=false;endpoint.textContainer.lineBreakMode = .byCharWrapping;endpoint.accessibilityIdentifier="assistant.endpoint";endpoint.accessibilityLabel="服务地址";endpoint.text=values["endpoint"] as? String
        key.isSecureTextEntry=true;key.accessibilityHint="可留空";key.addInteraction(UIToolTipInteraction(defaultToolTip:"可留空"))
        let save=tu_btn("完成",nil,self,#selector(sv));save.accessibilityIdentifier="assistant.config.save"
        let heading=tu_lbl(title);heading.font=lb_fnt(.headline,traitCollection)
        let back=tu_ibtn("back","返回设置","assistant.config.back",self,#selector(bck));let header=hdr(heading,back,save)
        let rows=zip(["服务地址","默认模型","复杂模型","赶DDL模型","密钥"],[endpoint,model,hard,best,key] as [UIView]).map { name,field in let row=tu_stk([tu_lbl(name),field]);row.spacing=8;return row }
        let fields=tu_stk(rows);fields.spacing=16;_ = tu_form(self,fields,"assistant.config",top:header)
    }
    // 验证错误保留当前输入。
    @objc private func sv() { do {try TaskAIConfig.sv(["endpoint":endpoint.text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "","model":model.text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "","hard_model":hard.text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "glm-5.3","ddl_model":best.text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "glm-5.3","key":key.text ?? ""]);navigationController?.popViewController(animated:true)} catch{tu_err(self,error)} }
}

// 手动编辑单个建议，确认之前不写入任务数据库。
private final class TaskStepEdit:TaskScreen {
    private let name=UITextView(),notes=UITextView(),minutes=UITextField()
    private var fields:TaskFields
    private let reply:(TaskFields?)->Void
    // 保留草稿UUID和未修改字段。
    init(_ fields:TaskFields,reply:@escaping(TaskFields?)->Void) { self.fields=fields;self.reply=reply;super.init(nibName:nil,bundle:nil) }
    // 禁用归档初始化。
    required init?(coder:NSCoder) { fatalError("Use init(_:reply:)") }
    // 使用现有字体、表单和按钮形状。
    override func viewDidLoad() {
        super.viewDidLoad();title="编辑步骤"
        for (field,id) in [(name,"title"),(notes,"notes")] { tu_fld(field);field.font=lb_fnt(.body,traitCollection);field.textColor=TaskTheme.ink;field.isScrollEnabled=false;if field === notes {field.heightAnchor.constraint(greaterThanOrEqualToConstant:72).isActive=true};field.accessibilityIdentifier="step."+id;field.text=fields[id] as? String ?? "" }
        tu_fld(minutes);minutes.font=lb_fnt(.body,traitCollection);minutes.textColor=TaskTheme.ink;minutes.keyboardType = .numberPad;minutes.accessibilityIdentifier="step.minutes";minutes.attributedPlaceholder=tu_phl("分钟");if let value=fields["planned_duration"] as? NSNumber { minutes.text=String(Int(ceil(value.doubleValue/60))) }
        _ = tu_form(self,tu_stk([tu_stk([tu_lbl("标题"),name]),tu_stk([tu_lbl("用时"),minutes]),tu_stk([tu_lbl("备注"),notes])]),"step.content")
        let save=tu_btn("完成",nil,self,#selector(sv));save.accessibilityIdentifier="step.save";navigationItem.rightBarButtonItem=UIBarButtonItem(customView:save)
    }
    // 修改草稿后返回原步骤列表。
    @objc private func sv() {
        do {try TaskStore.vldTxt(name.text ?? "",notes:notes.text ?? "");guard let duration=Int(minutes.text ?? ""),(1...525600).contains(duration) else{throw TaskAI.err("请输入有效分钟")};fields["title"]=name.text;fields["notes"]=notes.text;fields["planned_duration"]=duration*60;reply(fields);navigationController?.popViewController(animated:true)}catch{tu_err(self,error)}
    }
}

// 智能创建和长任务拆分共用可编辑、可取消的草稿。
@objc(TaskAssistantScreen) final class TaskAssistantScreen:TaskScreen,UITableViewDataSource,UITableViewDelegate,UITextViewDelegate {
    private let store:TaskStore,taskID:String?,listID:String,maxMinutes:Int?,automatic:Bool
    private let name=UITextField(),goal=UITextView(),table=UITableView(frame:.zero,style:.plain)
    private var draftInput:TaskFields?,draftReply:(([TaskFields])->Void)?
    private var parts:[TaskFields]=[],expected:TaskFields?,sourceTask:TaskFields?,completed=Set<String>()
    private var request:URLSessionDataTask?,generation=UUID(),started=false,saving=false
    private var generate:UIButton!,save:UIButton!,manual:UIButton!,reorder:UIButton!,header:UIView!,nameHeight:NSLayoutConstraint?
    // 只携带当前任务，现有子任务直接复用，不重复请求AI。
    init(store:TaskStore,taskID:String?=nil,listID:String=TS_DFLT_LST,maxMinutes:Int?=nil,automatic:Bool=false) { self.store=store;self.taskID=taskID;self.listID=listID;self.maxMinutes=maxMinutes;self.automatic=automatic;super.init(nibName:nil,bundle:nil) }
    // 编辑尚未创建任务的步骤，保存只交回父级草稿。
    convenience init(store:TaskStore,draft:TaskFields,parts:[TaskFields],reply:@escaping([TaskFields])->Void){self.init(store:store);draftInput=draft;self.parts=parts;draftReply=reply;if let all=try? store.lsTsks() as? [TaskFields]{completed=Set(all.filter{$0["status"] as? String=="completed"}.map{$0["task_id"] as! String})}}
    // 为原生验收和共用入口保留默认构造。
    @objc(initWithStore:task:) convenience init(store:TaskStore,task:String?) { self.init(store:store,taskID:task) }
    // 禁用归档初始化。
    required init?(coder:NSCoder) { fatalError("Use init(store:taskID:)") }
    // 建立常驻手动入口，网络请求不锁住编辑。
    override func viewDidLoad() {
        super.viewDidLoad();title=draftReply != nil ? "编辑子任务":taskID==nil ? "智能创建":"拆分任务"
        tu_fld(name);name.font=lb_fnt(.body,traitCollection);name.adjustsFontForContentSizeCategory=true;name.textColor=TaskTheme.ink;name.attributedPlaceholder=tu_phl("任务标题");name.accessibilityIdentifier="assistant.title"
        nameHeight=name.heightAnchor.constraint(equalToConstant:max(44,ceil(name.font!.lineHeight)+16));nameHeight?.isActive=true;name.addTarget(self,action:#selector(chg),for:.editingChanged);goal.delegate=self
        tu_fld(goal);goal.font=lb_fnt(.body,traitCollection);goal.adjustsFontForContentSizeCategory=true;goal.textColor=TaskTheme.ink;goal.accessibilityLabel="目标与说明";goal.accessibilityIdentifier="assistant.goal";goal.heightAnchor.constraint(equalToConstant:96).isActive=true
        generate=tu_btn("智能生成","subtask",self,#selector(gen));generate.accessibilityIdentifier="assistant.generate"
        manual=tu_btn("手动添加","add",self,#selector(add));manual.accessibilityIdentifier="assistant.manual"
        reorder=tu_btn("调整顺序",nil,self,#selector(ord));reorder.accessibilityIdentifier="assistant.reorder"
        let settings=tu_btn("助手设置","settings",self,#selector(cfg));settings.accessibilityIdentifier="assistant.settings"
        let buttons=tu_stk([generate,manual,reorder,settings]);buttons.axis = .vertical;buttons.distribution = .fillEqually
        header=UIView();let fields=tu_stk([name,tu_stk([tu_lbl("任务说明"),goal]),buttons]);fields.spacing=16;fields.setCustomSpacing(TaskTheme.section,after:goal.superview!);header.addSubview(fields);tu_wdth(fields,header);NSLayoutConstraint.activate([fields.topAnchor.constraint(equalTo:header.topAnchor,constant:16),fields.bottomAnchor.constraint(equalTo:header.bottomAnchor,constant:-16)])
        table.dataSource=self;table.delegate=self;table.backgroundColor = .clear;table.rowHeight=UITableView.automaticDimension;table.estimatedRowHeight=72;table.keyboardDismissMode = .interactive;table.accessibilityIdentifier="assistant.steps";view.addSubview(table);tu_wdth(table,view,inset:0);table.tableHeaderView=header
        NSLayoutConstraint.activate([table.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),table.bottomAnchor.constraint(equalTo:view.keyboardLayoutGuide.topAnchor)])
        save=tu_btn(draftReply != nil ? "完成步骤":taskID==nil ? "评估任务":"评估拆分",nil,self,#selector(sv));save.accessibilityIdentifier="assistant.save"
        navigationItem.rightBarButtonItem=UIBarButtonItem(customView:save)
        ld();state()
    }
    // 每个入口自行恢复导航，避免继承首页隐藏状态而失去保存按钮。
    override func viewWillAppear(_ animated:Bool) { super.viewWillAppear(animated);navigationController?.setNavigationBarHidden(false,animated:false) }
    // 表头随宽度和动态字体测量，键盘弹出后仍可滚到每个步骤。
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews();nameHeight?.constant=max(44,ceil(name.font!.lineHeight)+16);guard let header,table.bounds.width>0 else{return};let size=header.systemLayoutSizeFitting(CGSize(width:table.bounds.width,height:0),withHorizontalFittingPriority:.required,verticalFittingPriority:.fittingSizeLevel);if header.frame.size != size {header.frame=CGRect(origin:.zero,size:size);table.tableHeaderView=header} }
    // 仅首次进入缺少子任务的长任务时自动生成建议。
    override func viewDidAppear(_ animated:Bool) { super.viewDidAppear(animated);if automatic && !started && parts.isEmpty {started=true;gen()} }
    // 退出或转入手动编辑时取消迟到结果。
    override func viewWillDisappear(_ animated:Bool) { super.viewWillDisappear(animated);stop() }
    // 用户修改输入即取消旧建议，迟到结果不能覆盖手动编辑。
    @objc private func chg() {stop()}
    // 备注输入与手动步骤使用同一取消规则。
    func textViewDidChange(_ textView:UITextView) {stop()}
    // 重新读取显式保存的版本，原有完成步骤保持只读。
    private func ld() {
        if let draftInput{name.text=draftInput["title"] as? String;goal.text=draftInput["notes"] as? String;sourceTask=draftInput;table.reloadData();return}
        guard let taskID else{return}
        do { let draft=try TaskDivision.drft(store,task:taskID) as! TaskFields;expected=draft;sourceTask=draft["task"] as? TaskFields;name.text=sourceTask?["title"] as? String;goal.text=sourceTask?["notes"] as? String
            let children=draft["children"] as! [TaskFields];completed=Set(children.filter{$0["status"] as? String=="completed"}.map{$0["task_id"] as! String});parts=children.map {row in Dictionary(uniqueKeysWithValues:["task_id","title","notes","planned_duration"].map{($0,row[$0]!)})};table.reloadData()
        } catch {save?.isEnabled=false;tu_err(self,error)}
    }
    // 状态按钮同时保留离线编辑权利。
    private func state() { navigationItem.setHidesBackButton(saving,animated:false);var config=generate.configuration;config?.title=request==nil ? "智能生成":"取消生成";generate.configuration=config;generate.isEnabled=(expected?["children"] as? [TaskFields] ?? []).isEmpty && completed.intersection(Set(parts.compactMap{$0["task_id"] as? String})).isEmpty && !saving;save.isEnabled = !parts.isEmpty && !saving && (taskID==nil || expected != nil);manual.isEnabled = !saving && parts.count<64;reorder.isEnabled = parts.count>1 && !saving }
    // 丢弃过时的网络建议但保留本地草稿。
    private func stop() {generation=UUID();request?.cancel();request=nil;if isViewLoaded{state()} }
    // 打开可随时修改的连接设置。
    @objc private func cfg() {stop();navigationController?.pushViewController(TaskAISettings(),animated:true)}
    // 生成结果仅替换草稿，服务错误立即提供手动入口。
    @objc private func gen() {
        if request != nil {stop();return};guard !saving else{return};view.endEditing(true)
        let title=name.text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else{tu_err(self,TaskAI.err("请先填写任务目标"));return}
        var input:TaskFields=["title":title]
        if let amount=sourceTask?["planned_duration"] as? NSNumber {input["total_minutes"]=Int(ceil(amount.doubleValue/60))}
        if let maxMinutes,maxMinutes>0 {input["max_minutes"]=maxMinutes}
        let token=UUID();generation=token
        request=TaskAI.gen(input as NSDictionary,config:TaskAIConfig.ld() as NSDictionary) { [weak self] result,error in
            DispatchQueue.main.async {guard let self,self.generation==token,self.view.window != nil else{return};self.request=nil;self.state()
                if let error {let alert=UIAlertController(title:error.localizedDescription,message:nil,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"继续编辑",style:.cancel));alert.addAction(UIAlertAction(title:"手动添加",style:.default){[weak self] _ in self?.add()});self.present(alert,animated:true);return}
                guard let result=result as? TaskFields,let steps=result["steps"] as? [TaskFields] else{return}
                self.name.text=result["title"] as? String;self.parts=steps.map{var row=$0;row["task_id"]=UUID().uuidString.lowercased();return row};self.table.reloadData();self.state()
            }
        };state()
    }
    // 新增手动步骤不依赖连接状态。
    @objc private func add() {stop();let draft:TaskFields=["task_id":UUID().uuidString.lowercased(),"title":"","notes":""];navigationController?.pushViewController(TaskStepEdit(draft){[weak self] row in guard let self,let row else{return};self.parts.append(row);self.table.reloadData();self.state()},animated:true)}
    // 调整草稿顺序不提前更新数据库。
    @objc private func ord() {stop();table.setEditing(!table.isEditing,animated:true)}
    // 保存建议之前仍使用原存储的文本校验和事务。
    @objc private func sv() {
        guard !saving,!parts.isEmpty else{return};stop();view.endEditing(true)
        do {try TaskStore.vldTxt(name.text ?? "",notes:goal.text ?? "")}catch{tu_err(self,error);return}
        if let draftReply{draftReply(parts);navigationController?.popViewController(animated:true);return}
        if let taskID,let expected{do{let latest=try TaskDivision.drft(store,task:taskID) as! TaskFields;guard NSDictionary(dictionary:["rows":expected["signature"]!]).isEqual(to:["rows":latest["signature"]!]) else{throw TaskAI.err("任务已变更，请重载")}}catch{let alert=UIAlertController(title:"任务已变更",message:nil,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"保留草稿",style:.cancel));alert.addAction(UIAlertAction(title:"重新载入",style:.destructive){[weak self] _ in self?.ld();self?.state()});present(alert,animated:true);return}}
        var fields=sourceTask?.filter{TaskIntake.keys.contains($0.key)} ?? ["list_id":listID,"timezone_id":TimeZone.current.identifier]
        if let taskID{fields["task_id"]=taskID};fields["title"]=name.text ?? "";fields["notes"]=goal.text ?? "";fields["planned_duration"]=parts.reduce(0.0){$0+(($1["planned_duration"] as? NSNumber)?.doubleValue ?? 0)}
        let page=TaskAdmissionScreen(store:store,fields:fields,parts:parts){[weak self] in guard let self,let nav=self.navigationController,let index=nav.viewControllers.firstIndex(where:{$0===self}),index>0 else{return};nav.popToViewController(nav.viewControllers[index-1],animated:true)}
        navigationController?.pushViewController(page,animated:true)
    }

    // 返回当前草稿步骤。
    func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int {parts.count}
    // 显示完整步骤标题和分钟，不以序号代替时刻。
    func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell {
        let row=parts[indexPath.row],cell=UITableViewCell(style:.subtitle,reuseIdentifier:nil);cell.backgroundColor = .clear;var content=tu_cell();content.text=row["title"] as? String;content.textProperties.font=lb_fnt(.body,traitCollection);content.textProperties.color=TaskTheme.ink;content.textProperties.numberOfLines=0
        if let duration=row["planned_duration"] as? NSNumber {content.secondaryText="\(Int(ceil(duration.doubleValue/60)))分钟"};content.secondaryTextProperties.color=TaskTheme.muted;content.image=lb_icon(completed.contains(row["task_id"] as! String) ? "check_circle":"subtask");content.imageProperties.tintColor=lb_acnt();cell.contentConfiguration=content;cell.accessibilityIdentifier="assistant.step.\(indexPath.row)";cell.accessoryType = .disclosureIndicator;return cell
    }
    // 已完成步骤不被新建议覆盖，其他步骤随时手动修改。
    func tableView(_ tableView:UITableView,didSelectRowAt indexPath:IndexPath) {tableView.deselectRow(at:indexPath,animated:true);guard !saving else{return};stop();let index=indexPath.row;guard !completed.contains(parts[index]["task_id"] as! String) else{tu_err(self,TaskAI.err("完成步骤保留原记录"));return};navigationController?.pushViewController(TaskStepEdit(parts[index]){[weak self] row in guard let self,let row else{return};self.parts[index]=row;self.table.reloadData();self.state()},animated:true)}
    // 完成步骤不参与删除和重排。
    func tableView(_ tableView:UITableView,canEditRowAt indexPath:IndexPath)->Bool {!saving && !completed.contains(parts[indexPath.row]["task_id"] as! String)}
    // 删除仅修改待确认草稿。
    func tableView(_ tableView:UITableView,commit editingStyle:UITableViewCell.EditingStyle,forRowAt indexPath:IndexPath) {guard editingStyle == .delete else{return};stop();parts.remove(at:indexPath.row);tableView.reloadData();state()}
    // 保持顺序编辑可用。
    func tableView(_ tableView:UITableView,canMoveRowAt indexPath:IndexPath)->Bool {self.tableView(tableView,canEditRowAt:indexPath)}
    // 不移动到已完成步骤的位置。
    func tableView(_ tableView:UITableView,targetIndexPathForMoveFromRowAt source:IndexPath,toProposedIndexPath destination:IndexPath)->IndexPath {completed.contains(parts[destination.row]["task_id"] as! String) ? source:destination}
    // 重排在确认后统一提交。
    func tableView(_ tableView:UITableView,moveRowAt source:IndexPath,to destination:IndexPath) {let row=parts.remove(at:source.row);parts.insert(row,at:destination.row)}
}
