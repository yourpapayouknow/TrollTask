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
    func flds(_ zone: TimeZone, active: Bool? = nil) -> TaskFields {
        let key = deadline ? "deadline_at" : "due_at", kind = deadline ? "deadline_kind" : "schedule_kind"
        guard active ?? enabled.isOn else { return [key: NSNull(), kind: "none"] }
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
    private var extras: TaskFields, dirty: Set<String> = []
    private let zone: TimeZone
    private let quick: Bool
    private var saving = false
    private let titleField = UITextView(), notes = UITextView(), hint = tu_lbl("新建任务"), schedule = tu_lbl(nil)
    private var plan: TaskDate!
    private var save: UIButton!, notesBtn: UIButton!, dateBtn: UIButton!, starBtn: UIButton!, repeatBtn: UIButton!
    private var detail: UIStackView!, formStack: UIStackView!
        private var textHeights: [NSLayoutConstraint] = []
    private var actionRow: UIStackView?
    private weak var formScroll: UIScrollView?
    private var dateFields: TaskWindowFields?
    private weak var editingBeforeDate: UITextView?
        private var dateLine: UIStackView!
    private var routine: Bool { extras["list_id"] as? String == TS_RTN_LST }
    private var newTodo: Bool { quick && task == nil && !routine }
    private let routineEnd = UIDatePicker(), routineEnabled = UISwitch()
    private var endRow: UIStackView!
    private var routineKind: UIButton!, endConfirm: UIButton!
    // 初始化完整详情。
    @objc(initWithStore:task:saved:) convenience init(store: TaskStore, task: TaskFields?, saved: (() -> Void)?) { self.init(store: store, task: task, draft: nil, quick: false, saved: saved) }
    // 保留原始字段与明确的修改集合。
    @objc(initWithStore:task:draft:quick:saved:) init(store: TaskStore, task: TaskFields?, draft: TaskFields?, quick: Bool, saved: (() -> Void)?) {
        self.store = store; self.task = task; self.draft = draft ?? [:]; self.quick = quick; self.saved = saved
        extras = task ?? ["list_id": TS_DFLT_LST, "parent_id": NSNull(), "starred": 0, "urgency": 0, "difficulty": 0, "rush": 0, "density": 1, "recurrence_type": "none", "recurrence_interval": 1, "recurrence": [String]()]
        extras.merge(draft ?? [:]) { _, new in new }
        zone = (extras["timezone_id"] as? String).flatMap { TimeZone(identifier: $0) } ?? TaskTimeZone.current
        super.init(nibName: nil, bundle: nil); if quick { preferredContentSize = CGSize(width: 540, height: 128) }
    }
    // 禁用归档初始化。
    required init?(coder: NSCoder) { fatalError("Use init(store:task:saved:)") }
    // 构建完整详情和可展开的额外字段。
    override func viewDidLoad() {
        super.viewDidLoad(); title = task == nil ? (routine ? "新建常律" : "添加待办") : "任务详情"
        if quick {
            let surface = UIView(frame: view.bounds); surface.backgroundColor = TaskTheme.surface; surface.isUserInteractionEnabled = false
            surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.insertSubview(surface, at: 1)
        }
        if newTodo {
            let dates = TaskWindowFields(zone: zone)
            dates.isHidden = true
            dates.changed = { [weak self] in self?.rfrshDtl(); self?.view.setNeedsLayout(); self?.revealDates() }
            dates.picking = { [weak self] active in
                guard let self else { return }
                if active {
                    self.editingBeforeDate = [self.titleField, self.notes].first { $0.isFirstResponder }
                    self.view.endEditing(true)
                } else {
                    self.editingBeforeDate?.becomeFirstResponder()
                    self.editingBeforeDate = nil
                }
            }
            dateFields = dates
        }
        hint.text = routine ? "新建常律" : "新建任务"
        save = tu_btn(task==nil && !routine ? "下一步":"保存", nil, self, #selector(sv)); save.accessibilityIdentifier = "edit.save"; var saveStyle = save.configuration; saveStyle?.baseForegroundColor = lb_acnt(); save.configuration = saveStyle
        if quick { navigationController?.setNavigationBarHidden(true, animated: false) }
        else {
            navigationItem.title = ""
            let back = tu_ibtn("back", "返回", "edit.back", self, #selector(bk))
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: back)
            let more = tu_ibtn("more", "任务选项", "edit.menu", nil, nil)
            var actions = [tu_act("放弃更改", nil, "edit.cancel") { [weak self] in self?.cncl() }]
            if task != nil {
                let remove = tu_act("删除任务", nil, "edit.delete") { [weak self] in guard let self = self else { return }; tu_cfrm(self, routine ? "删除常律" : "删除任务及子任务") { [weak self] in self?.dl() } }; remove.attributes = .destructive; actions.append(remove)
            }
            more.menu = UIMenu(children: actions); more.showsMenuAsPrimaryAction = true; navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: more)]
        }
        for (field, id, label, style) in [(titleField, "edit.title", "任务标题", UIFont.TextStyle.title2), (notes, "edit.notes", "详细信息", .body)] {
            let fontStyle: UIFont.TextStyle = quick && field === titleField ? .body : quick && field === notes ? .subheadline : style
            field.delegate = self; field.accessibilityIdentifier = id; field.accessibilityLabel = label; field.font = lb_fnt(fontStyle, nil); field.adjustsFontForContentSizeCategory = true; field.textColor = TaskTheme.ink; field.backgroundColor = .clear
            field.textContainerInset = .init(top: 8, left: 8, bottom: 8, right: 8); field.textContainer.lineFragmentPadding = 0; let height = field.heightAnchor.constraint(equalToConstant: field === titleField ? (quick ? 44 : 72) : 120); height.isActive = true; textHeights.append(height)
        }
        titleField.text = task?["title"] as? String ?? draft["title"] as? String ?? ""; notes.text = task?["notes"] as? String ?? draft["notes"] as? String ?? ""; notes.isHidden = notes.text.isEmpty
        if newTodo {
            titleField.accessibilityLabel = "任务总标题"
            titleField.accessibilityHint = "填写整个任务的最终目标"
            notes.accessibilityLabel = "备注"
        }
        if quick { titleField.returnKeyType = .done }
        hint.font = titleField.font; hint.textColor = TaskTheme.muted; hint.isHidden = !titleField.text.isEmpty; hint.translatesAutoresizingMaskIntoConstraints = false; titleField.addSubview(hint)
        NSLayoutConstraint.activate([hint.leadingAnchor.constraint(equalTo: titleField.leadingAnchor, constant: 8), hint.topAnchor.constraint(equalTo: titleField.topAnchor, constant: 8)])
        plan = TaskDate(task ?? draft, deadline: false, zone: zone, target: self)
        notesBtn = tu_btn(quick ? nil : "添加详细信息", quick ? "notes" : nil, self, #selector(nts)); notesBtn.accessibilityLabel = newTodo ? "备注" : "添加详细信息"; notesBtn.accessibilityIdentifier = "edit.details"
        dateBtn = tu_btn(nil, quick ? "time" : nil, self, newTodo ? #selector(openWindow) : #selector(clndr(_:))); dateBtn.accessibilityIdentifier = "edit.date"
        if newTodo { dateBtn.accessibilityLabel = "时间" }
        starBtn = tu_ibtn("star", "添加星标", "edit.star", self, #selector(star))
        repeatBtn = tu_btn(nil, quick ? "repeat" : nil, self, #selector(rpt)); repeatBtn.accessibilityIdentifier = "edit.repeat"
        if !quick { var config = repeatBtn.configuration; config?.baseForegroundColor = TaskTheme.ink; repeatBtn.configuration = config }
        schedule.numberOfLines = 0; schedule.font = lb_fnt(.subheadline, nil); schedule.textColor = TaskTheme.muted; schedule.accessibilityIdentifier = "edit.schedule"
        dateLine = tu_stk(quick && routine ? [schedule] : [dateBtn!]); dateLine.axis = .horizontal; dateLine.accessibilityIdentifier = "edit.dateline"
        detail = tu_stk([])
        for button in [notesBtn!] {
            var config = button.configuration; config?.baseForegroundColor = TaskTheme.muted; config?.imagePadding = 8
            config?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in var value = attributes; value.font = lb_fnt(.body, nil); return value }; button.configuration = config
        }
        for button in [dateBtn!] {
            var config = button.configuration; config?.baseForegroundColor = TaskTheme.ink; config?.imagePadding = 8
            config?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in var value = attributes; value.font = lb_fnt(.body, nil); return value }; button.configuration = config
        }
        if routine {
            routineKind = tu_btn(nil, "calendar"); routineKind.accessibilityIdentifier = "routine.kind"; routineKind.showsMenuAsPrimaryAction = true
            routineKind.menu = UIMenu(children: [("fixed","固定安排"),("work","一般任务时段"),("rest","休息"),("background","可并行安排")].map { key, title in
                let action = tu_act(title, nil, "routine."+key) { [weak self] in self?.extras["routine_kind"] = key; self?.dirty.insert("routine_kind"); self?.rfrshDtl() }
                action.state = extras["routine_kind"] as? String == key ? .on : .off; return action
            })
            routineEnd.datePickerMode = .time; routineEnd.preferredDatePickerStyle = .compact; routineEnd.locale = Locale(identifier: "zh_CN"); routineEnd.timeZone = zone; routineEnd.accessibilityIdentifier = "routine.end"
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone; let minute = (extras["routine_end"] as? NSNumber)?.intValue ?? 510
            routineEnd.date = calendar.date(bySettingHour: minute/60, minute: minute%60, second: 0, of: plan.date.date)!
            routineEnd.addTarget(self, action: #selector(rtnChg(_:)), for: .valueChanged)
            routineEnabled.isOn = (extras["routine_enabled"] as? NSNumber)?.boolValue ?? true; routineEnabled.onTintColor = lb_acnt(); routineEnabled.accessibilityIdentifier = "routine.enabled"; routineEnabled.addTarget(self, action: #selector(rtnChg(_:)), for: .valueChanged)
            endConfirm = tu_btn("确认结束时间", nil, self, #selector(endCnfrm)); endConfirm.accessibilityIdentifier = "routine.end.confirm"
            endRow = tu_row("结束时间", routineEnd)
            var rows: [UIView] = [routineKind!, dateLine!, endRow!, endConfirm!, repeatBtn!]
            if task != nil { rows.append(tu_row("启用常律", routineEnabled)) } else { extras["routine_enabled"] = 1; dirty.insert("routine_enabled") }
            rows.forEach { detail.addArrangedSubview($0) }
        }
        detail.isHidden = quick
        let extra = quick ? tu_btn(nil, "more", self, #selector(more)) : nil
        if let extra { extra.accessibilityIdentifier = "edit.more"; extra.accessibilityLabel = "更多选项" }
        var titleLine: UIView = titleField
        if quick && !newTodo, let extra {
            let row = tu_stk([titleField, extra]); row.axis = .horizontal; row.alignment = .top; titleLine = row
            extra.widthAnchor.constraint(equalToConstant: 44).isActive = true
            extra.menu = UIMenu(children: [tu_act("取消", "close", "edit.cancel") { [weak self] in self?.cncl() }])
        }
        let fields: [UIView] = dateFields.map { [titleLine, notes, $0] } ?? (quick ? [titleLine, notes, dateLine, detail] : routine ? [titleField, notes, notesBtn, detail] : [titleField, notes, notesBtn])
        formStack = tu_stk(fields)
        let scroll = tu_form(self, formStack, "edit.form"); formScroll = scroll
        let footer: UIStackView?
        if quick {
            var config = save.configuration; config?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var value = attributes; let scaled = lb_fnt(.headline, nil)!; value.font = scaled.withSize(min(32, scaled.pointSize)); return value
            }
            if newTodo { config?.titleLineBreakMode = .byTruncatingTail }
            save.configuration = config
            if newTodo {
                save.titleLabel?.numberOfLines = 1
                save.setContentCompressionResistancePriority(.required, for: .horizontal)
            }
            scroll.contentInset.top = 8
            let tools = [notesBtn!, dateBtn!, routine ? repeatBtn! : starBtn!]
            footer = tu_stk(tools + [UIView(), save]); footer?.axis = .horizontal; footer?.distribution = .fill
            for button in tools {
                var style = button.configuration
                style?.contentInsets = .init(top:8, leading:8, bottom:8, trailing:8)
                button.configuration = style
                button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            }
            save.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        } else if task == nil {
            footer = tu_stk([save,UIView()]); footer?.axis = .horizontal; save.setContentHuggingPriority(.defaultHigh,for:.horizontal)
        } else {
            save.isHidden = true; footer = nil
        }
        view.constraints.filter { ($0.firstItem as? UIView) === scroll && $0.firstAttribute == .bottom }.forEach { $0.isActive = false }
        if let footer {
            footer.accessibilityIdentifier = "edit.actions"; actionRow = footer
            view.addSubview(footer); tu_wdth(footer, view)
            NSLayoutConstraint.activate([footer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12)])
        } else {
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12).isActive = true
        }
        rfrshDtl(); rfrshSv(); if !quick && !notes.text.isEmpty { notesBtn.isHidden = true }
    }
    // 为辅助大字保留完整输入行高度。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for (index, field) in [titleField, notes].enumerated() where index < textHeights.count {
            field.layoutManager.ensureLayout(for: field.textContainer)
            let natural = field.layoutManager.usedRect(for: field.textContainer).height + field.textContainerInset.top + field.textContainerInset.bottom
            textHeights[index].constant = max(44, min(320, ceil(natural)))
        }
        if newTodo { fitDraft() } else { rtnSize() }
        if !quick, let row = actionRow {
            let large = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            row.axis = large ? .vertical : .horizontal; row.arrangedSubviews.last?.isHidden = large
        }
    }
    // 使用系统键盘输入快捷标题。
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); if quick && !newTodo && titleField.text.isEmpty { titleField.becomeFirstResponder() } }
    // 在快捷面板完成转场后唤起总标题的键盘。
    func focusDraft() {
        guard newTodo, let window = view.window else { return }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(focusReady), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(focusReady), name: UIWindow.didBecomeKeyNotification, object: window)
        DispatchQueue.main.async { [weak self] in self?.focusReady() }
    }
    // 首次聚焦只执行一次，避免 resign/become 造成键盘闪动。
    @objc private func focusReady() {
        guard UIApplication.shared.applicationState == .active, view.window?.isKeyWindow == true else { return }
        stopFocusWait()
        guard navigationController?.topViewController === self, !isBeingDismissed else { return }
        titleField.becomeFirstResponder()
    }
    private func stopFocusWait() {
        let center = NotificationCenter.default
        center.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        center.removeObserver(self, name: UIWindow.didBecomeKeyNotification, object: nil)
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if newTodo { stopFocusWait() }
    }
    // 保留草稿状态。
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(quick, animated: false) }
    // 显示星标、快捷入口与常律时间。
    private func rfrshDtl() {
        starBtn.isHidden=routine
        let starred = (extras["starred"] as? NSNumber)?.boolValue == true; starBtn.setImage(lb_icon(starred ? "star_fill" : "star"), for: .normal); starBtn.accessibilityLabel = starred ? "取消星标" : "添加星标"
        if newTodo {
            let toggles = [(notesBtn!, !notes.isHidden, TaskTheme.ink),
                           (dateBtn!, dateFields?.isHidden == false, TaskTheme.ink),
                           (starBtn!, starred, TaskTheme.muted)]
            for (button, selected, idleColor) in toggles {
                button.configuration?.baseForegroundColor = selected ? TaskTheme.orangeInk : idleColor
                if selected { button.accessibilityTraits.insert(.selected) }
                else { button.accessibilityTraits.remove(.selected) }
            }
            starBtn.accessibilityValue = starred ? "紧急程度高" : nil
            if let dates = dateFields {
                let calendar = TaskWindow.calendar(zone)
                let format = DateFormatter(); format.timeZone = zone; format.dateFormat = "MM-dd"
                dateBtn.accessibilityValue = format.string(from: dates.start) + (dates.end.map { "至" + format.string(from: TaskWindow.deadline($0, in: calendar)) } ?? "，待选截止日期")
            }
            if notes.isHidden { preferredContentSize.height = 128 }
            return
        }
        if routine {
            let role = extras["routine_kind"] as? String ?? "fixed", names = ["fixed":"固定安排","work":"一般任务时段","rest":"休息","background":"可并行安排"]
            routineKind?.setTitle(names[role], for: .normal)
            endConfirm?.isHidden = extras["routine_end"] is NSNumber
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let start = calendar.dateComponents([.hour,.minute], from: plan.time.date)
            (endRow?.arrangedSubviews.first as? UILabel)?.text = (extras["routine_end"] as? NSNumber).map { $0.intValue <= start.hour! * 60 + start.minute! ? "次日结束" : "结束时间" } ?? "结束待确认"
            (routineKind?.menu?.children as? [UIAction])?.forEach { $0.state = $0.identifier.rawValue == "routine."+role ? .on : .off }
            let format = DateFormatter(); format.timeZone = zone; format.dateFormat = "MM-dd HH:mm"
            let date = Date(timeIntervalSince1970: plan.flds(zone, active: true)["due_at"] as! Double)
            let title = "日期  " + format.string(from: date)
            if quick { dateBtn.setTitle(nil, for: .normal) } else { dateBtn.setTitle(title, for: .normal) }
            dateBtn.accessibilityLabel = title
            if quick, let minute = (extras["routine_end"] as? NSNumber)?.intValue {
                let time = String(format: "%02d:%02d", minute / 60, minute % 60)
                let overnight = (endRow?.arrangedSubviews.first as? UILabel)?.text == "次日结束"
                var start = title
                var fields = extras; fields.merge(plan.flds(zone)) { _, new in new }
                if let stamp = fields["due_at"] as? NSNumber, let values = try? TaskRule.cycles(fields, at: stamp.doubleValue, limit: 1) as? [NSNumber], let first = values.first(where: { $0.doubleValue >= stamp.doubleValue }) { start = format.string(from: Date(timeIntervalSince1970: first.doubleValue)) }
                schedule.text = detail.isHidden ? start + "–" + (overnight ? "次日" : "") + time : "开始：" + start
                schedule.text! += "\n" + rptTitle()
                dateBtn.accessibilityLabel = "开始时间，" + start
            }
        }
        repeatBtn.setTitle(quick && routine ? nil : rptTitle(), for: .normal); repeatBtn.accessibilityLabel = rptTitle()
    }
    // 由实际内容高度撑开常律卡片。
    private func rtnSize() {
        guard quick && routine, let formStack else { return }
        let content = formStack.systemLayoutSizeFitting(CGSize(width: max(44, view.bounds.width - 32), height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let height = ceil(content) + max(44, actionRow?.bounds.height ?? 44) + 44
        if abs(preferredContentSize.height - height) > 1 { preferredContentSize.height = height }
    }
    // 随标题、备注及动态字号调整快捷面板高度。
    private func fitDraft() {
        let size = CGSize(width: max(44, view.bounds.width - 32), height: 0)
        dateFields?.fit(size.width)
        let form = formStack.systemLayoutSizeFitting(size, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let footer = actionRow?.systemLayoutSizeFitting(size, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height ?? 44
        let height = max(128, ceil(form + footer + 44))
        if abs(preferredContentSize.height - height) > 1 {
            preferredContentSize.height = height
            // 让外层弹层在没有键盘事件时也收到尺寸变更。
            navigationController?.preferredContentSize = preferredContentSize
        }
    }
    // 常律结束时刻和启用状态只写入当前编辑草稿。
    @objc private func rtnChg(_ sender: UIControl) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour,.minute], from: routineEnd.date)
        if sender === routineEnd { extras["routine_end"] = parts.hour! * 60 + parts.minute!; dirty.insert("routine_end") }
        if sender === routineEnabled { extras["routine_enabled"] = routineEnabled.isOn ? 1 : 0; dirty.insert("routine_enabled") }; rfrshDtl()
    }
    // 缺失时刻必须由用户明确确认，不能由启用开关代填。
    @objc private func endCnfrm() { rtnChg(routineEnd) }
    // 返回短重复标签。
    private func rptTitle(_ fields: TaskFields? = nil) -> String {
        TaskRoutineCheck.rptTxt(fields ?? extras)
    }
    // 展开或收起常律额外字段。
    @objc private func more() {
        if quick && routine { detail.isHidden.toggle(); rfrshDtl(); return }
        detail.isHidden = false; rfrshDtl()
    }
    // 普通待办再次点备注时收起输入并保留草稿。
    @objc private func nts() {
        if newTodo && !notes.isHidden {
            if notes.isFirstResponder { titleField.becomeFirstResponder() }
            if editingBeforeDate === notes { editingBeforeDate = titleField }
            notes.isHidden = true
        } else {
            notes.isHidden = false
            if !quick { notesBtn.isHidden = true }
            notes.becomeFirstResponder()
        }
        if newTodo { rfrshDtl() }
        view.setNeedsLayout()
    }
    // 标题完成键只收起键盘，中文组词和备注仍按原生输入。
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if quick && textView === titleField && text == "\n" && textView.markedTextRange == nil { textView.resignFirstResponder(); return false }
        return true
    }
    // 记录文本修改并禁用空标题保存。
    func textViewDidChange(_ textView: UITextView) { dirty.insert(textView === titleField ? "title" : "notes"); hint.isHidden = !titleField.text.isEmpty; view.setNeedsLayout(); rfrshSv() }
    // 为新建与编辑统一禁用空白标题保存。
    private func rfrshSv() { save.isEnabled = !saving && !titleField.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    // 记录独立日期修改。
    @objc func dtChg(_ control: UIControl) {
        if routine { plan.enabled.isOn = true; plan.timed.isOn = true }
        // 两个清除日期入口共用规则，日期与重复一起清除。
        if control === plan.enabled && !plan.enabled.isOn {
            extras["recurrence_type"] = "none"; extras["recurrence_interval"] = 1; extras["recurrence"] = [String]()
            dirty.formUnion(["recurrence_type", "recurrence_interval", "recurrence"])
        }
        dirty.insert("plan"); plan.rfrsh(); rfrshDtl()
    }
    // 修改草稿星标。
    @objc private func star() { guard !routine else{return}; extras["starred"] = !((extras["starred"] as? NSNumber)?.boolValue ?? false); dirty.insert("starred"); rfrshDtl() }
    // 日期选择展开后把确认按钮滚到工具栏上方。
    private func revealDates() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let dates = self.dateFields, !dates.isHidden, dates.awaitingConfirm, let scroll = self.formScroll else { return }
            self.view.layoutIfNeeded()
            scroll.scrollRectToVisible(dates.convert(dates.confirmRect, to: scroll).insetBy(dx: 0, dy: -TaskTheme.gap), animated: true)
        }
    }
    // 在标题和备注下方展开或收起日期设置。
    @objc private func openWindow() {
        guard let dates = dateFields else { return }
        dates.isHidden.toggle()
        if dates.isHidden { dates.closePicker() }
        rfrshDtl(); view.setNeedsLayout()
    }
    // 打开系统月历，保留当前时刻。
    @objc private func clndr(_ sender: UIButton) {
        let value = plan!
        if #available(iOS 16, *) {
            var local = Calendar(identifier: .gregorian); local.timeZone = zone
            let clock = local.dateComponents([.hour, .minute], from: value.time.date), date = local.date(bySettingHour: clock.hour!, minute: clock.minute!, second: 0, of: value.date.date)!
            let action: ((UIViewController) -> Void)? = repeatBtn.isEnabled ? { [weak self] in self?.rptIn($0) } : nil
            let calendar = TaskCalendar(date: date, timed: value.timed.isOn, zone: zone, deadline: value.deadline, repeatName: rptTitle(), action: action) { [weak self] date, timed, clear, patch in
                guard let self = self else { return }; value.enabled.isOn = !clear; value.timed.isOn = timed
                if let date = date { value.date.date = date; value.time.date = date }
                self.extras.merge(patch) { _, new in new }; self.dirty.formUnion(patch.keys)
                self.dtChg(value.enabled)
            }; calendar.requiresTime = routine && !value.deadline; calendar.preferredContentSize = CGSize(width: 540, height: value.deadline ? 400 : 508); tu_sheet(self, calendar)
        } else { value.enabled.isOn = true; dtChg(value.enabled) }
    }
    // 用当前草稿打开重复设置。
    private func rptIn(_ parent: UIViewController) {
        var fields = extras; fields.merge(plan.flds(zone, active: true)) { _, new in new }
        if #available(iOS 16, *), let calendar = parent as? TaskCalendar { fields.merge(calendar.rptFlds()) { _, new in new } }
        let panel = TaskRepeat(fields: fields) { [weak self, weak parent] patch in
            guard let self = self else { return }
            if #available(iOS 16, *), let calendar = parent as? TaskCalendar { calendar.rptSet(patch, name: self.rptTitle(patch)); return }
            if patch["recurrence_type"] as? String != "none" && !self.plan.enabled.isOn { self.plan.enabled.isOn = true; self.dtChg(self.plan.enabled) }
            self.extras.merge(patch) { _, new in new }; self.dirty.formUnion(patch.keys); self.rfrshDtl()
        }; panel.allowsNone = !routine; let navigation = UINavigationController(rootViewController: panel); navigation.modalPresentationStyle = .fullScreen; parent.present(navigation, animated: true)
    }
    // 打开重复编辑。
    @objc private func rpt() { rptIn(self) }
    // 返回时保存修改。
    @objc private func bk() { if dirty.isEmpty { cncl() } else { sv() } }
    // 关闭草稿不写数据库。
    @objc private func cncl() { guard !saving else { return }; if quick { dismiss(animated: true) } else { navigationController?.popViewController(animated: true) } }
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
        if task == nil { fields["timezone_id"] = zone.identifier }
        if task == nil || dirty.contains("plan") { fields.merge(plan.flds(zone)) { _, new in new } }
        for key in ["list_id", "parent_id", "starred", "urgency", "difficulty", "rush", "density", "planned_duration", "recurrence_type", "recurrence_interval", "recurrence", "routine_kind", "routine_end", "routine_enabled"] where dirty.contains(key) { fields[key] = extras[key] }
        if newTodo {
            guard let dates = dateFields else { return }
            guard let windowEnd = dates.end else {
                if dates.isHidden { openWindow() }
                dates.selectDeadline()
                return
            }
            let windowStart = dates.start
            if let issue = TaskWindow.issue(windowStart, windowEnd, in: TaskWindow.calendar(zone)) { tu_err(self, TaskAI.err(issue)); return }
            fields["due_at"] = windowStart.timeIntervalSince1970
            fields["deadline_at"] = windowEnd.timeIntervalSince1970
            fields["schedule_kind"] = "date"; fields["deadline_kind"] = "date"; fields["planning_mode"] = "window"
            fields["urgency"] = (extras["starred"] as? NSNumber)?.boolValue == true ? 3 : 0
        }
        if newTodo {
            let page=TaskAdmissionScreen(store:store,fields:fields){[weak self] in guard let self else{return};TaskHaptics.success();self.saved?();self.dismiss(animated:true)}
            view.endEditing(true);navigationController?.pushViewController(page,animated:true);return
        }
        if fields.isEmpty { finish(); return }
        saving = true; save.isEnabled = false; view.isUserInteractionEnabled = false
        if quick { navigationController?.isModalInPresentation = true }
        navigationItem.leftBarButtonItem?.isEnabled = false; navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }; view.endEditing(true)
        DispatchQueue.global(qos: .userInitiated).async {
            var issue: Error?
            do { try self.store.txn {
                guard let task = self.task else { _ = try self.store.crtTsk(fields); return }
                let id = task["task_id"] as! String; try tu_live(try self.store.rdTsk(id) as! TaskFields)
                if !fields.isEmpty { try self.store.updTsk(id, fields: fields) }
            } } catch { issue = error }
            DispatchQueue.main.async {
                self.saving = false; self.rfrshSv(); self.view.isUserInteractionEnabled = true; self.navigationItem.leftBarButtonItem?.isEnabled = true; self.navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = true }
                if self.quick { self.navigationController?.isModalInPresentation = false }
                if let issue = issue { tu_err(self, issue) } else { self.finish() }
            }
        }
    }
    // 保存后关闭编辑页，返回时显示最新快照。
    private func finish() {
        TaskHaptics.success()
        saved?()
        cncl()
    }
}
