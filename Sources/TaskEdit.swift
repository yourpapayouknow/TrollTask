// 管理独立计划与截止日期，保留绝对时刻和仅日期语义。
final class TaskDate {
    let enabled = UISwitch(), timed = UISwitch(), date = UIDatePicker(), time = UIDatePicker()
    let deadline: Bool
    let view: UIStackView, fields: UIStackView
    // 创建系统日期控件及启用开关。
    init(_ task: TaskFields, deadline: Bool, zone: TimeZone, target: Any) {
        self.deadline = deadline; let prefix = deadline ? "deadline" : "plan"
        let kind = task[deadline ? "deadline_kind" : "schedule_kind"] as? String ?? "none"
        enabled.isOn = kind != "none"; timed.isOn = kind == "timed"
        enabled.accessibilityIdentifier = prefix + ".enabled"; timed.accessibilityIdentifier = prefix + ".timed"
        enabled.accessibilityLabel = deadline ? "截止日期" : "计划日期"; timed.accessibilityLabel = deadline ? "截止时刻" : "计划时刻"
        for toggle in [enabled, timed] { toggle.onTintColor = lb_acnt(); toggle.addTarget(target, action: #selector(TaskEdit.dtChg(_:)), for: .valueChanged) }
        for picker in [date, time] { picker.preferredDatePickerStyle = .compact; picker.timeZone = zone; picker.locale = Locale(identifier: "zh_CN"); picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal); picker.addTarget(target, action: #selector(TaskEdit.dtChg(_:)), for: .valueChanged) }
        date.datePickerMode = .date; time.datePickerMode = .time; date.accessibilityIdentifier = prefix + ".date"; time.accessibilityIdentifier = prefix + ".time"
        var value = (task[deadline ? "deadline_at" : "due_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date()
        if deadline && kind == "date" { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone; value = calendar.date(byAdding: .day, value: -1, to: value)! }
        date.date = value; time.date = value
        fields = tu_stk([date, tu_row(timed.accessibilityLabel!, timed), time]); view = tu_stk([tu_row(enabled.accessibilityLabel!, enabled), fields]); rfrsh()
    }
    // 同步启用状态。
    func rfrsh() { fields.isHidden = !enabled.isOn; time.isHidden = !timed.isOn }
    // 生成独立日期字段，全天截止为次日当地午夜。
    func flds(_ zone: TimeZone) -> TaskFields {
        let key = deadline ? "deadline_at" : "due_at", kind = deadline ? "deadline_kind" : "schedule_kind"
        guard enabled.isOn else { return [key: NSNull(), kind: "none"] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var stamp = calendar.startOfDay(for: date.date)
        if timed.isOn { let clock = calendar.dateComponents([.hour, .minute], from: time.date); stamp = calendar.date(bySettingHour: clock.hour!, minute: clock.minute!, second: 0, of: stamp)! }
        else if deadline { stamp = calendar.date(byAdding: .day, value: 1, to: stamp)! }
        return [key: stamp.timeIntervalSince1970, kind: timed.isOn ? "timed" : "date"]
    }
}

// 用同一原生Swift编辑器承载快捷草稿与完整详情。
@objc(TaskEdit) final class TaskEdit: TaskScreen, UITextViewDelegate {
    private let store: TaskStore, task: TaskFields?, draft: TaskFields
    private let saved: (() -> Void)?
    private var extras: TaskFields, zone: TimeZone, dirty: Set<String> = []
    private let quick: Bool
    private var saving = false, complete = false, series = false
    private let titleField = UITextView(), notes = UITextView(), hint = tu_lbl("新建任务")
    private var plan: TaskDate!, deadline: TaskDate!
    private var save: UIButton!, notesBtn: UIButton!, dateBtn: UIButton!, ddlBtn: UIButton!, starBtn: UIButton!, listBtn: UIButton!, repeatBtn: UIButton!, subBtn: UIButton!
    private var advanced: UIStackView!, detail: UIStackView!
    private let duration = UITextField(), timezone = UITextField()
    // 初始化完整详情。
    @objc(initWithStore:task:saved:) convenience init(store: TaskStore, task: TaskFields?, saved: (() -> Void)?) { self.init(store: store, task: task, draft: nil, quick: false, saved: saved) }
    // 保留原始字段与明确的修改集合。
    @objc(initWithStore:task:draft:quick:saved:) init(store: TaskStore, task: TaskFields?, draft: TaskFields?, quick: Bool, saved: (() -> Void)?) {
        self.store = store; self.task = task; self.draft = draft ?? [:]; self.quick = quick; self.saved = saved
        extras = task ?? ["list_id": TS_DFLT_LST, "parent_id": NSNull(), "starred": 0, "urgency": 0, "difficulty": 0, "recurrence_type": "none", "recurrence_interval": 1, "recurrence": [String](), "timezone_id": TimeZone.current.identifier]
        extras.merge(draft ?? [:]) { _, new in new }; zone = TimeZone(identifier: extras["timezone_id"] as! String) ?? .current
        super.init(nibName: nil, bundle: nil); if quick { preferredContentSize = CGSize(width: 540, height: 240) }
    }
    // 禁用归档初始化。
    required init?(coder: NSCoder) { fatalError("Use init(store:task:saved:)") }
    // 构建完整详情和可展开的额外字段。
    override func viewDidLoad() {
        super.viewDidLoad(); title = task == nil ? "添加待办" : "任务详情"
        save = tu_btn("保存", nil, self, #selector(sv)); save.accessibilityIdentifier = "edit.save"
        if quick { navigationController?.setNavigationBarHidden(true, animated: false) }
        else {
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: tu_ibtn("back", "返回", "edit.back", self, #selector(bk)))
            let more = tu_ibtn("more", "任务选项", "edit.menu", nil, nil)
            var actions = [tu_act("放弃更改", "close", "edit.cancel") { [weak self] in self?.cncl() }]
            if let task = task {
                let remove = tu_act("删除任务", "delete", "edit.delete") { [weak self] in guard let self = self else { return }; tu_cfrm(self, "删除任务及子任务") { [weak self] in self?.dl() } }; remove.attributes = .destructive; actions.append(remove)
                if !(task["recurrence"] as! [String]).isEmpty { actions.append(tu_act("完成整个系列", "check_circle", "edit.series") { [weak self] in self?.complete = true; self?.series = true; self?.sv() }) }
                actions.append(tu_act("完成记录", "list", "edit.history") { [weak self] in self?.hist() })
                if !(task["parent_id"] is NSNull) { actions.append(tu_act("转为独立任务", "subtask", "edit.detach") { [weak self] in self?.extras["parent_id"] = NSNull(); self?.dirty.insert("parent_id") }) }
            }
            more.menu = UIMenu(children: actions); more.showsMenuAsPrimaryAction = true; navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: more)]
        }
        for (field, id, label, style) in [(titleField, "edit.title", "任务标题", UIFont.TextStyle.title2), (notes, "edit.notes", "详细信息", .body)] {
            field.delegate = self; field.accessibilityIdentifier = id; field.accessibilityLabel = label; field.font = lb_fnt(style, nil); field.adjustsFontForContentSizeCategory = true; field.textColor = TaskTheme.ink; field.backgroundColor = .clear
            field.textContainerInset = .init(top: 8, left: 8, bottom: 8, right: 8); field.textContainer.lineFragmentPadding = 0; field.heightAnchor.constraint(equalToConstant: 120).isActive = true
        }
        titleField.text = task?["title"] as? String ?? draft["title"] as? String ?? ""; notes.text = task?["notes"] as? String ?? draft["notes"] as? String ?? ""; notes.isHidden = notes.text.isEmpty
        hint.textColor = TaskTheme.muted; hint.isHidden = !titleField.text.isEmpty; hint.translatesAutoresizingMaskIntoConstraints = false; titleField.addSubview(hint)
        NSLayoutConstraint.activate([hint.leadingAnchor.constraint(equalTo: titleField.leadingAnchor, constant: 8), hint.topAnchor.constraint(equalTo: titleField.topAnchor, constant: 8)])
        plan = TaskDate(task ?? draft, deadline: false, zone: zone, target: self); deadline = TaskDate(task ?? draft, deadline: true, zone: zone, target: self)
        notesBtn = tu_btn(quick ? nil : "添加详细信息", "notes", self, #selector(nts)); notesBtn.accessibilityLabel = "添加详细信息"; notesBtn.accessibilityIdentifier = "edit.details"
        dateBtn = tu_btn(nil, "time", self, #selector(clndr(_:))); dateBtn.accessibilityIdentifier = "edit.date"
        ddlBtn = tu_btn(nil, "target", self, #selector(clndr(_:))); ddlBtn.accessibilityIdentifier = "edit.deadline"
        starBtn = tu_ibtn("star", "添加星标", "edit.star", self, #selector(star))
        listBtn = tu_btn(nil, "down", self, #selector(lsts)); listBtn.accessibilityIdentifier = "edit.list"
        repeatBtn = tu_btn(nil, "repeat", self, #selector(rpt)); repeatBtn.accessibilityIdentifier = "edit.repeat"
        subBtn = tu_btn("添加子任务", "subtask", self, #selector(sub)); subBtn.accessibilityIdentifier = "edit.subtask"; subBtn.isHidden = task == nil
        detail = tu_stk([ddlBtn, subBtn]); detail.isHidden = quick
        duration.keyboardType = .decimalPad; duration.accessibilityIdentifier = "edit.duration"; duration.accessibilityLabel = "预计分钟"
        if let number = extras["planned_duration"] as? NSNumber { duration.text = String(format: "%.10g", number.doubleValue / 60) }
        timezone.text = extras["timezone_id"] as? String ?? zone.identifier; timezone.accessibilityIdentifier = "edit.timezone"; timezone.accessibilityLabel = "时区"; timezone.autocorrectionType = .no; timezone.autocapitalizationType = .none
        for field in [duration, timezone] { field.font = lb_fnt(.body, nil); field.adjustsFontForContentSizeCategory = true; field.textColor = TaskTheme.ink; field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true; field.addTarget(self, action: #selector(extraChg(_:)), for: .editingChanged) }
        advanced = tu_stk([plan.view, deadline.view, repeatBtn, grade("urgency"), grade("difficulty"), tu_row("预计分钟", duration), tu_row("时区", timezone)]); advanced.isHidden = true
        let extra = tu_btn("更多选项", "down", self, #selector(more)); extra.accessibilityIdentifier = "edit.more"
        let fields: [UIView] = quick ? [titleField, notes, detail, extra, advanced] : [listBtn, titleField, notes, notesBtn, dateBtn, detail, extra, advanced]
        let scroll = tu_form(self, tu_stk(fields), "edit.form")
        let footer: UIStackView
        if quick {
            footer = tu_stk([tu_ibtn("close", "取消", "edit.cancel", self, #selector(cncl)), notesBtn, dateBtn, starBtn, save]); footer.axis = .horizontal; footer.distribution = .fillEqually
        } else {
            let cmpl = tu_btn(task?["status"] as? String == "completed" ? "恢复待办" : "标记为已完成", "check_circle", self, #selector(cmpl)); cmpl.accessibilityIdentifier = "edit.complete"; cmpl.isHidden = task == nil
            footer = tu_stk([cmpl, save]); footer.axis = .horizontal; navigationItem.rightBarButtonItems?.append(UIBarButtonItem(customView: starBtn))
        }
        view.addSubview(footer); tu_wdth(footer, view)
        view.constraints.filter { ($0.firstItem as? UIView) === scroll && $0.firstAttribute == .bottom }.forEach { $0.isActive = false }
        NSLayoutConstraint.activate([footer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -4), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -4)])
        rfrshDtl(); rfrshSv(); if task != nil { children() }
        repeatBtn.isEnabled = extras["parent_id"] is NSNull && detail.arrangedSubviews.last === subBtn
        subBtn.isEnabled = (extras["recurrence"] as! [String]).isEmpty; if !quick && !notes.text.isEmpty { notesBtn.isHidden = true }
    }
    // 使用系统键盘输入快捷标题。
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); if quick && titleField.text.isEmpty { titleField.becomeFirstResponder() } }
    // 保留草稿并刷新子任务。
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); if task != nil && subBtn != nil { children() } }
    // 构建紧急程度与难度菜单。
    private func grade(_ key: String) -> UIButton {
        let label = key == "urgency" ? "紧急程度" : "难易程度", titles = key == "urgency" ? ["未设置", "低", "中", "高"] : ["未评估", "简单", "一般", "困难"]
        let value = (extras[key] as? NSNumber)?.intValue ?? 0; let button = tu_btn(label + "：" + titles[value], "down"); button.accessibilityIdentifier = "edit." + key
        button.menu = UIMenu(children: titles.enumerated().map { index, title in
            let action = tu_act(title, nil, "edit.\(key).\(index)") { [weak self, weak button] in
                self?.extras[key] = index; self?.dirty.insert(key); button?.setTitle(label + "：" + titles[index], for: .normal)
                (button?.menu?.children as? [UIAction])?.forEach { $0.state = $0.title == titles[index] ? .on : .off }
            }; action.state = value == index ? .on : .off; return action
        }); button.showsMenuAsPrimaryAction = true; return button
    }
    // 显示独立日期与星标状态。
    private func rfrshDtl() {
        let starred = (extras["starred"] as? NSNumber)?.boolValue == true; starBtn.setImage(lb_icon(starred ? "star_fill" : "star"), for: .normal); starBtn.accessibilityLabel = starred ? "取消星标" : "添加星标"
        for (value, button) in [(plan!, dateBtn!), (deadline!, ddlBtn!)] {
            var text = value.deadline ? "添加截止期限" : "添加日期/时间"
            if value.enabled.isOn {
                let format = DateFormatter(); format.timeZone = .current; format.dateFormat = value.timed.isOn ? "MM-dd HH:mm" : "yyyy-MM-dd"
                var date = Date(timeIntervalSince1970: value.flds(zone)[value.deadline ? "deadline_at" : "due_at"] as! Double)
                if value.deadline && !value.timed.isOn { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone; date = calendar.date(byAdding: .day, value: -1, to: date)!; format.timeZone = zone }; text = format.string(from: date)
            }
            if quick && !value.deadline { button.setTitle(nil, for: .normal); button.accessibilityLabel = text } else { button.setTitle(text, for: .normal) }
        }
        repeatBtn.setTitle(rptTitle(), for: .normal)
        if let lists = try? store.lsLsts() as? [TaskFields], let list = lists.first(where: { $0["list_id"] as? String == extras["list_id"] as? String }) { listBtn.setTitle(lb_shrt(list["title"] as? String), for: .normal) }
    }
    // 返回短重复标签。
    private func rptTitle() -> String {
        let type = extras["recurrence_type"] as! String, interval = (extras["recurrence_interval"] as! NSNumber).intValue
        if let unit = ["daily":"天", "weekly":"周", "monthly":"月", "yearly":"年"][type], interval > 1 { return "每\(interval)\(unit)" }
        return ["none":"不重复", "daily":"每天", "weekly":"每周", "monthly":"每月", "yearly":"每年", "custom":"完整重复规则"][type] ?? "不重复"
    }
    // 展开全部额外字段。
    @objc private func more() {
        advanced.isHidden.toggle(); detail.isHidden = false
        if quick { let sheet = navigationController?.sheetPresentationController ?? sheetPresentationController; sheet?.animateChanges { sheet?.selectedDetentIdentifier = .large } }
    }
    // 显示备注输入。
    @objc private func nts() { notes.isHidden = false; if !quick { notesBtn.isHidden = true }; notes.becomeFirstResponder() }
    // 记录文本修改并禁用空标题保存。
    func textViewDidChange(_ textView: UITextView) { dirty.insert(textView === titleField ? "title" : "notes"); hint.isHidden = !titleField.text.isEmpty; rfrshSv() }
    // 为新建与编辑统一禁用空白标题保存。
    private func rfrshSv() { save.isEnabled = !saving && !titleField.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    // 记录独立日期修改。
    @objc func dtChg(_ control: UIControl) {
        dirty.insert([plan.enabled, plan.timed, plan.date, plan.time].contains { $0 === control } ? "plan" : "deadline"); plan.rfrsh(); deadline.rfrsh(); rfrshDtl()
    }
    // 保留绝对时刻与仅日期的当地日期。
    @objc private func extraChg(_ field: UITextField) {
        let key = field === timezone ? "timezone_id" : "planned_duration"; dirty.insert(key)
        if field === timezone {
            extras[key] = field.text ?? ""
            guard let next = TimeZone(identifier: field.text ?? ""), next != zone else { return }
            var previous = Calendar(identifier: .gregorian); previous.timeZone = zone; var current = previous; current.timeZone = next
            for value in [plan!, deadline!] {
                var date = value.date.date
                if value.enabled.isOn && !value.timed.isOn { date = current.date(from: previous.dateComponents([.year, .month, .day], from: date))!; dirty.insert(value.deadline ? "deadline" : "plan") }
                else if value.enabled.isOn { date = Date(timeIntervalSince1970: value.flds(zone)[value.deadline ? "deadline_at" : "due_at"] as! Double) }
                value.date.timeZone = next; value.time.timeZone = next; value.date.date = date; value.time.date = date
            }; zone = next; rfrshDtl()
        } else {
            let text = field.text ?? ""; let scanner = Scanner(string: text); let minutes = scanner.scanDouble()
            extras[key] = text.isEmpty ? NSNull() : NSNumber(value: minutes != nil && scanner.isAtEnd ? minutes! * 60 : .nan)
        }
    }
    // 修改草稿星标。
    @objc private func star() { extras["starred"] = !((extras["starred"] as? NSNumber)?.boolValue ?? false); dirty.insert("starred"); rfrshDtl() }
    // 打开系统月历，保留当前时刻。
    @objc private func clndr(_ sender: UIButton) {
        let value = sender === ddlBtn ? deadline! : plan!
        if #available(iOS 16, *) {
            var local = Calendar(identifier: .gregorian); local.timeZone = zone
            let clock = local.dateComponents([.hour, .minute], from: value.time.date), date = local.date(bySettingHour: clock.hour!, minute: clock.minute!, second: 0, of: value.date.date)!
            let action: ((UIViewController) -> Void)? = repeatBtn.isEnabled ? { [weak self] in self?.rptIn($0) } : nil
            let calendar = TaskCalendar(date: date, timed: value.timed.isOn, zone: zone, deadline: value.deadline, repeatName: rptTitle(), action: action) { [weak self] date, timed, clear in
                guard let self = self else { return }; value.enabled.isOn = !clear; value.timed.isOn = timed
                if let date = date { value.date.date = date; value.time.date = date }
                if !value.deadline && clear { self.extras["recurrence_type"] = "none"; self.extras["recurrence_interval"] = 1; self.extras["recurrence"] = [String](); self.dirty.formUnion(["recurrence_type", "recurrence_interval", "recurrence"]) }; self.dtChg(value.enabled)
            }; calendar.preferredContentSize = CGSize(width: 540, height: 600); tu_sheet(self, calendar)
        } else { advanced.isHidden = false; value.enabled.isOn = true; dtChg(value.enabled) }
    }
    // 用当前草稿打开重复设置。
    private func rptIn(_ parent: UIViewController) {
        if !plan.enabled.isOn { plan.enabled.isOn = true; dtChg(plan.enabled) }
        var fields = extras; fields.merge(plan.flds(zone)) { _, new in new }
        let panel = TaskRepeat(fields: fields) { [weak self, weak parent] patch in
            guard let self = self else { return }; self.extras.merge(patch) { _, new in new }; self.dirty.formUnion(patch.keys); self.rfrshDtl()
            if #available(iOS 16, *), let calendar = parent as? TaskCalendar { calendar.rptName(self.rptTitle()) }
        }; tu_sheet(parent, panel)
    }
    // 打开重复编辑。
    @objc private func rpt() { rptIn(self) }
    // 保留清单移动限制。
    @objc private func lsts() {
        do {
            let actions = try (store.lsLsts() as! [TaskFields]).map { list -> UIAction in
                let id = list["list_id"] as! String
                let action = tu_act(lb_shrt(list["title"] as? String), "list", id) { [weak self] in self?.extras["list_id"] = id; self?.dirty.insert("list_id"); self?.rfrshDtl() }
                action.state = id == extras["list_id"] as? String ? .on : .off
                if action.state != .on && (!(extras["recurrence"] as! [String]).isEmpty || !(extras["parent_id"] is NSNull)) { action.attributes = .disabled }; return action
            }; tu_menu(self, "任务清单", actions)
        } catch { tu_err(self, error) }
    }
    // 刷新子任务入口并读取点击时的最新记录。
    private func children() {
        do {
            let all = try store.lsTsks() as! [TaskFields]
            detail.arrangedSubviews.filter { $0.accessibilityIdentifier?.hasPrefix("child.") == true }.forEach { detail.removeArrangedSubview($0); $0.removeFromSuperview() }
            for task in all where (task["deleted"] as! NSNumber).boolValue == false && task["parent_id"] as? String == self.task?["task_id"] as? String {
                let id = task["task_id"] as! String, button = tu_btn(lb_shrt(task["title"] as? String), "subtask"); button.accessibilityLabel = task["title"] as? String; button.accessibilityIdentifier = "child." + id
                button.addAction(UIAction { [weak self] _ in
                    guard let self = self else { return }
                    do { let latest = try self.store.rdTsk(id) as! TaskFields; try tu_live(latest); self.navigationController?.pushViewController(TaskEdit(store: self.store, task: latest, saved: self.saved), animated: true) }
                    catch { self.children(); tu_err(self, error) }
                }, for: .touchUpInside); detail.addArrangedSubview(button)
            }
            repeatBtn.isEnabled = extras["parent_id"] is NSNull && detail.arrangedSubviews.last === subBtn
        } catch { tu_err(self, error) }
    }
    // 新建同清单子任务草稿。
    @objc private func sub() {
        guard let task = task else { return }
        let editor = TaskEdit(store: store, task: nil, draft: ["list_id": extras["list_id"]!, "parent_id": task["task_id"]!], quick: true) { [weak self] in self?.saved?(); self?.children() }
        let nav = UINavigationController(rootViewController: editor); nav.preferredContentSize = editor.preferredContentSize; tu_sheet(self, nav)
    }
    // 展示已完成轮次记录。
    private func hist() {
        do {
            let format = DateFormatter(); format.dateFormat = "MM-dd HH:mm"; format.timeZone = .current
            var actions = try (store.lsOcc((task!["task_id"] as! String)) as! [TaskFields]).filter { $0["action"] as? String == "complete" }.map { occ -> UIAction in
                let title = format.string(from: Date(timeIntervalSince1970: (occ["handled_at"] as! NSNumber).doubleValue)); let item = tu_act(title, "check_circle", occ["occurrence_id"] as! String) {}; item.attributes = .disabled; return item
            }
            if actions.isEmpty { let item = tu_act("暂无完成记录", nil, "history.empty") {}; item.attributes = .disabled; actions = [item] }; tu_menu(self, "完成记录", actions)
        } catch { tu_err(self, error) }
    }
    // 返回时保存修改。
    @objc private func bk() { if dirty.isEmpty { cncl() } else { sv() } }
    // 关闭草稿不写数据库。
    @objc private func cncl() { guard !saving else { return }; if quick { dismiss(animated: true) } else { navigationController?.popViewController(animated: true) } }
    // 完成或恢复当前轮次。
    @objc private func cmpl() { complete = true; series = false; sv() }
    // 提交删除后退出详情。
    private func dl() {
        guard !saving else { return }; saving = true
        DispatchQueue.global(qos: .userInitiated).async {
            var issue: Error?; do { try self.store.delTsk((self.task!["task_id"] as! String)) } catch { issue = error }
            DispatchQueue.main.async { self.saving = false; if let issue = issue { tu_err(self, issue) } else { self.saved?(); self.cncl() } }
        }
    }
    // 提交最小补丁及完成意图，失败保留输入。
    @objc private func sv() {
        guard !saving else { return }
        do { try TaskStore.vldTxt(titleField.text ?? "", notes: notes.text ?? "") } catch { tu_err(self, error); return }
        var fields = task == nil ? draft : [:]
        if task == nil || dirty.contains("title") { fields["title"] = titleField.text ?? "" }; if task == nil || dirty.contains("notes") { fields["notes"] = notes.text ?? "" }
        if task == nil { fields["timezone_id"] = extras["timezone_id"] }
        if task == nil || dirty.contains("plan") { fields.merge(plan.flds(zone)) { _, new in new } }; if task == nil || dirty.contains("deadline") { fields.merge(deadline.flds(zone)) { _, new in new } }
        for key in ["list_id", "parent_id", "starred", "urgency", "difficulty", "planned_duration", "timezone_id", "recurrence_type", "recurrence_interval", "recurrence"] where dirty.contains(key) { fields[key] = extras[key] }
        if fields.isEmpty && !complete { cncl(); return }
        let finishing = complete, allSeries = series; complete = false; series = false; saving = true; save.isEnabled = false; view.isUserInteractionEnabled = false
        navigationItem.leftBarButtonItem?.isEnabled = false; navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }; view.endEditing(true)
        DispatchQueue.global(qos: .userInitiated).async {
            var issue: Error?
            do { try self.store.txn {
                guard let task = self.task else { _ = try self.store.crtTsk(fields); return }
                let id = task["task_id"] as! String; try tu_live(try self.store.rdTsk(id) as! TaskFields)
                if !fields.isEmpty { try self.store.updTsk(id, fields: fields) }; guard finishing else { return }
                if task["status"] as? String == "completed" { try self.store.rstrTsk(id); return }
                let changed = ["due_at", "recurrence", "timezone_id", "deadline_at"].contains { fields[$0] != nil }
                let cycle = changed ? nil : task["next_cycle_at"] as? NSNumber
                if allSeries { try self.store.cmplTsk(id) } else { try self.store.cmplNxt(id, cycle: cycle, generation: cycle == nil ? nil : task["reminder_version"] as? NSNumber) }
            } } catch { issue = error }
            DispatchQueue.main.async {
                self.saving = false; self.rfrshSv(); self.view.isUserInteractionEnabled = true; self.navigationItem.leftBarButtonItem?.isEnabled = true; self.navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true }
                if let issue = issue { tu_err(self, issue) } else { self.saved?(); self.cncl() }
            }
        }
    }
}
