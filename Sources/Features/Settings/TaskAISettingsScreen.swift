// 提供可修改的服务地址、模型与可选密钥。
@objc(TaskAISettings) final class TaskAISettingsScreen:TaskScreen {
    private let endpoint=UITextView(),model=UITextField(),hard=UITextField(),best=UITextField(),key=UITextField()
    // 创建统一表单，不探测或修改Mac服务配置。
    override func viewDidLoad() {
        super.viewDidLoad();title="助手设置";let values=TaskAIConfig.ld()
        for (field,id,name) in [(model,"model","默认模型"),(hard,"hard_model","复杂模型"),(best,"ddl_model","赶DDL模型"),(key,"key","密钥")] { tu_fld(field);field.font=lb_fnt(.body,traitCollection);field.adjustsFontForContentSizeCategory=true;field.textColor=TaskTheme.ink;field.autocapitalizationType = .none;field.autocorrectionType = .no;field.accessibilityIdentifier="assistant."+id;field.accessibilityLabel=name;field.text=values[id] as? String;
             }
        tu_fld(endpoint);endpoint.font=lb_fnt(.body,traitCollection);endpoint.adjustsFontForContentSizeCategory=true;endpoint.textColor=TaskTheme.ink;endpoint.autocapitalizationType = .none;endpoint.autocorrectionType = .no;endpoint.keyboardType = .URL;endpoint.isScrollEnabled=false;endpoint.textContainer.lineBreakMode = .byCharWrapping;endpoint.accessibilityIdentifier="assistant.endpoint";endpoint.accessibilityLabel="服务地址";endpoint.text=values["endpoint"] as? String
        key.isSecureTextEntry=true;key.attributedPlaceholder=tu_phl("可留空");key.accessibilityHint="可留空"
        let save=tu_btn("完成",nil,self,#selector(sv));save.accessibilityIdentifier="assistant.config.save"
        let heading=tu_lbl(title);heading.font=lb_fnt(.headline,traitCollection)
        let back=tu_ibtn("back","返回设置","assistant.config.back",self,#selector(bck));let header=hdr(heading,back,save)
        let rows=zip(["服务地址","默认模型","复杂模型","赶DDL模型","密钥"],[endpoint,model,hard,best,key] as [UIView]).map { name,field in let row=tu_stk([tu_lbl(name),field]);row.spacing=8;return row }
        let fields=tu_stk(rows);fields.spacing=16;_ = tu_form(self,fields,"assistant.config",top:header)
    }
    // 校验错误保留当前输入。
    @objc private func sv() { do {try TaskAIConfig.sv(["endpoint":endpoint.text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "","model":model.text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "","hard_model":hard.text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "glm-5.3","ddl_model":best.text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "glm-5.3","key":key.text ?? ""]);navigationController?.popViewController(animated:true)} catch{tu_err(self,error)} }
}