// 保存助手连接设置，密钥只存系统钥匙串。
enum TaskAIConfig {
    // 读取现有Tailscale服务与可选认证。
    static func ld()->TaskFields {
        // 只迁移既有默认档，用户后续仍可修改每档真实模型ID。
        if UserDefaults.standard.integer(forKey:"assistant.tiers")==0 {if UserDefaults.standard.string(forKey:"assistant.model")=="fast-model"{UserDefaults.standard.set("deepseek-v4.1-flash",forKey:"assistant.model")};UserDefaults.standard.set(1,forKey:"assistant.tiers")}
        let key=(try? TaskKeychain.rd("assistant")).flatMap{String(data:$0,encoding:.utf8)} ?? ""
        return ["endpoint":UserDefaults.standard.string(forKey:"assistant.endpoint") ?? "http://100.121.131.101:8765/v1","model":UserDefaults.standard.string(forKey:"assistant.model") ?? "deepseek-v4.1-flash","hard_model":UserDefaults.standard.string(forKey:"assistant.hard_model") ?? "glm-5.3","ddl_model":UserDefaults.standard.string(forKey:"assistant.ddl_model") ?? "glm-5.3","key":key]
    }
    // 先验证连接信息再保存，认证失败保留原密钥。
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
final class TaskStepEdit:TaskScreen {
    private let name=UITextView(),notes=UITextView(),minutes=UITextField()
    private var fields:TaskFields
    private let reply:(TaskFields?)->Void
    // 保留草稿UUID和未修改字段。
    init(_ fields:TaskFields,reply:@escaping(TaskFields?)->Void) { self.fields=fields;self.reply=reply;super.init(nibName:nil,bundle:nil);preferredContentSize=CGSize(width:540,height:UIScreen.main.bounds.height) }
    // 禁用归档初始化。
    required init?(coder:NSCoder) { fatalError("Use init(_:reply:)") }
    // 在紧凑面板中保持可用高度。
    override func viewWillAppear(_ animated:Bool) { super.viewWillAppear(animated); preferredContentSize=CGSize(width:540,height:UIScreen.main.bounds.height) }
    // 使用现有字体、表单和按钮形状。
    override func viewDidLoad() {
        super.viewDidLoad();title="修改子任务"
        for (field,id) in [(name,"title"),(notes,"notes")] { tu_fld(field);field.font=lb_fnt(.body,traitCollection);field.textColor=TaskTheme.ink;field.isScrollEnabled=false;if field === notes {field.heightAnchor.constraint(greaterThanOrEqualToConstant:72).isActive=true};field.accessibilityIdentifier="step."+id;field.text=fields[id] as? String ?? "" }
        tu_fld(minutes);minutes.font=lb_fnt(.body,traitCollection);minutes.textColor=TaskTheme.ink;minutes.keyboardType = .numberPad;minutes.accessibilityIdentifier="step.minutes";minutes.accessibilityLabel="预计耗时";minutes.attributedPlaceholder=tu_phl("分钟");if let value=fields["planned_duration"] as? NSNumber { minutes.text=String(Int(ceil(value.doubleValue/60))) }
        _ = tu_form(self,tu_stk([tu_stk([tu_lbl("标题"),name]),tu_stk([tu_lbl("步骤"),notes]),tu_stk([tu_lbl("预计耗时"),minutes])]),"step.content")
        let save=tu_btn("完成",nil,self,#selector(sv));save.accessibilityIdentifier="step.save";navigationItem.rightBarButtonItem=UIBarButtonItem(customView:save)
    }
    // 修改草稿后返回原步骤列表。
    @objc private func sv() {
        do {try TaskStore.vldTxt(name.text ?? "",notes:notes.text ?? "");guard let duration=Int(minutes.text ?? ""),(1...525600).contains(duration) else{throw TaskAI.err("请输入有效分钟")};fields["title"]=name.text;fields["notes"]=notes.text;fields["planned_duration"]=duration*60;reply(fields);navigationController?.popViewController(animated:true)}catch{tu_err(self,error)}
    }
}
