// 手动编辑单个建议，确认之前不写入任务数据库。
final class TaskStepEditScreen:TaskScreen {
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