// 创建统一数值输入。
private func tp_num(_ text: String, _ id: String) -> UITextField {
    let field = UITextField(); field.text = text; field.accessibilityIdentifier = id; field.keyboardType = .numberPad; field.font = lb_fnt(.body, nil)
    field.adjustsFontForContentSizeCategory = true; field.textAlignment = .right
    NSLayoutConstraint.activate([field.widthAnchor.constraint(greaterThanOrEqualToConstant: 44), field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)]); return field
}

// 为进入下一级的功能行统一提供尾部方向图标。
private func tp_arr(_ button: UIButton) {
    let arrow = UIImageView(image: lb_icon("down")); arrow.transform = CGAffineTransform(rotationAngle: -.pi / 2); arrow.tintColor = TaskTheme.muted; arrow.translatesAutoresizingMaskIntoConstraints = false; button.addSubview(arrow)
    var config = button.configuration; config?.contentInsets.trailing = 48; button.configuration = config
    NSLayoutConstraint.activate([arrow.widthAnchor.constraint(equalToConstant: 24), arrow.heightAnchor.constraint(equalToConstant: 24), arrow.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12), arrow.centerYAnchor.constraint(equalTo: button.centerYAnchor)])
}

// 复用预设和结束条件的平面选择行。
private func tp_opt(_ title: String, _ id: String, _ target: Any, _ action: Selector) -> UIButton {
    let row = tu_btn(title, nil, target, action); row.accessibilityIdentifier = id
    var config = row.configuration; config?.contentInsets = .init(top: 12, leading: 12, bottom: 12, trailing: 48)
    config?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in var value = attributes; value.font = lb_fnt(.body, nil); return value }; row.configuration = config
    let mark = UIImageView(image: lb_icon("check")); mark.tintColor = lb_acnt(); mark.translatesAutoresizingMaskIntoConstraints = false; mark.tag = 1; row.addSubview(mark)
    NSLayoutConstraint.activate([mark.widthAnchor.constraint(equalToConstant: 24), mark.heightAnchor.constraint(equalToConstant: 24), mark.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12), mark.centerYAnchor.constraint(equalTo: row.centerYAnchor)]); return row
}

// 保存完整重复属性并只修改用户改变的规则参数。
@objc(TaskRepeat) final class TaskRepeat: TaskScreen, UIPickerViewDataSource, UIPickerViewDelegate {
    var allowsNone = true
    private let original: TaskFields, reply: ((TaskFields) -> Void)?
    private var type: String, end = "none", days: Set<String> = [], dirty: Set<String> = []
    private var interval: UITextField!, count: UITextField!
    private let until = UIDatePicker(), raw = UITextView()
    private let typeRows = UIStackView(), picker = UIPickerView(), summary = tu_lbl(nil)
    private var customMode = false, presetKeys: [String] = [], pickerLimit = 1000
    private let units = ["天", "周", "个月", "年"], freqs = ["daily", "weekly", "monthly", "yearly"]
    private var endBtn: UIButton!, daysBtn: UIButton!, basic: UIStackView!
    // 接收完整草稿。
    @objc(initWithFields:reply:) init(fields: TaskFields, reply: ((TaskFields) -> Void)?) {
        original = fields; self.reply = reply; type = fields["recurrence_type"] as? String ?? "none"; super.init(nibName: nil, bundle: nil)
    }
    // 禁用归档初始化。
    required init?(coder: NSCoder) { fatalError("Use init(fields:reply:)") }
    // 解析第一条规则中的有限键值，保留其余属性。
    private func parts(_ line: String?) -> [String: String] {
        var result: [String: String] = [:]
        for pair in (line.map { String($0.dropFirst(6)) } ?? "").split(separator: ";") {
            let items = pair.split(separator: "=", omittingEmptySubsequences: false); if items.count == 2 { result[String(items[0])] = String(items[1]) }
        }; return result
    }
    // 创建原生重复和结束条件控件。
    override func viewDidLoad() {
        super.viewDidLoad(); title = customMode ? "自定义" : "重复"
        let lines = original["recurrence"] as? [String] ?? [], values = parts(lines.first { $0.hasPrefix("RRULE:") })
        days = Set((values["BYDAY"] ?? "").split(separator: ",").map(String.init))
        interval = tp_num(values["INTERVAL"] ?? (original["recurrence_interval"] as? NSNumber)?.stringValue ?? "1", "repeat.interval"); count = tp_num(values["COUNT"] ?? "10", "repeat.count")
        until.datePickerMode = .date; until.preferredDatePickerStyle = .compact; until.timeZone = TimeZone(identifier: original["timezone_id"] as? String ?? "") ?? .current; until.locale = Locale(identifier: "zh_CN"); until.accessibilityIdentifier = "repeat.until"
        if let start = original["due_at"] as? NSNumber { until.date = Date(timeIntervalSince1970: max(start.doubleValue, Date().timeIntervalSince1970)) }
        if values["COUNT"] != nil { end = "count" }
        if let stamp = values["UNTIL"] {
            end = "until"; let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = stamp.count == 8 ? "yyyyMMdd" : "yyyyMMdd'T'HHmmss'Z'"; until.date = format.date(from: stamp) ?? Date()
        }
        endBtn = tu_btn(nil, "repeat"); endBtn.accessibilityIdentifier = "repeat.end"; tp_arr(endBtn); daysBtn = tu_btn("指定星期", "calendar"); daysBtn.accessibilityIdentifier = "repeat.days"
        raw.text = lines.joined(separator: "\n"); raw.font = lb_fnt(.body, nil); raw.adjustsFontForContentSizeCategory = true; raw.textColor = TaskTheme.ink; raw.backgroundColor = .clear
        raw.accessibilityIdentifier = "repeat.rules"; raw.accessibilityLabel = "完整重复规则"; raw.textContainerInset = .init(top: 4, left: 4, bottom: 4, right: 4); raw.heightAnchor.constraint(equalToConstant: 180).isActive = true
        let done = tu_btn("完成", nil, self, #selector(sv)); done.accessibilityIdentifier = "repeat.done"
        let cancel = tu_btn("取消", nil, self, #selector(cncl)); cancel.accessibilityIdentifier = "repeat.cancel"
        for button in [cancel, done] { var config = button.configuration; config?.baseForegroundColor = lb_acnt(); button.configuration = config }
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: cancel); navigationItem.rightBarButtonItem = UIBarButtonItem(customView: done)
        if customMode {
            if type == "none" { type = "daily"; dirty.insert("type") }
            if type == "custom" { type = freqs.contains(values["FREQ"]?.lowercased() ?? "") ? values["FREQ"]!.lowercased() : "daily" }
            navigationItem.leftBarButtonItem = nil
            picker.accessibilityIdentifier = "repeat.picker"; picker.dataSource = self; picker.delegate = self
            pickerLimit = max(1000, Int(interval.text ?? "1") ?? 1)
            picker.selectRow(max(0, (Int(interval.text ?? "1") ?? 1) - 1), inComponent: 0, animated: false)
            picker.selectRow(freqs.firstIndex(of: type) ?? 0, inComponent: 1, animated: false)
            picker.heightAnchor.constraint(equalToConstant: 216).isActive = true
            let icon = UIImageView(image: lb_icon("repeat")); icon.tintColor = TaskTheme.muted; icon.widthAnchor.constraint(equalToConstant: 24).isActive = true; summary.accessibilityIdentifier = "repeat.summary"
            let summaryRow = tu_stk([icon, summary]); summaryRow.axis = .horizontal; summaryRow.alignment = .center; summaryRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            let rules = tu_btn("完整重复规则", "more", self, #selector(rules)); rules.accessibilityIdentifier = "repeat.raw"
            basic = tu_stk([summaryRow, picker, daysBtn, endBtn, rules])
            tu_form(self, basic, "repeat.form"); menus()
        } else {
            navigationItem.rightBarButtonItem = nil
            var closeStyle = cancel.configuration; closeStyle?.title = ""; closeStyle?.image = lb_icon("close"); cancel.configuration = closeStyle; cancel.accessibilityLabel = "取消"
            var local = Calendar(identifier: .gregorian); local.timeZone = until.timeZone ?? .current
            let anchor = (original["due_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date()
            let weekday = local.component(.weekday, from: anchor), day = local.component(.day, from: anchor)
            let week = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"][weekday - 1]
            let ordinal = ["第一个", "第二个", "第三个", "第四个", "第五个"][(day - 1) / 7]
            presetKeys = ["none", "daily", "weekly", "ordinal", "monthly", "yearly", "workdays", "custom"]
            let titles = ["不重复", "每天", "每1周的" + week, "每1个月的" + ordinal + week, "每1个月的\(day)号", "每年", "每个工作日", "自定义…"]
            let choices = zip(presetKeys,titles).filter { allowsNone || $0.0 != "none" }; presetKeys = choices.map { $0.0 }
            typeRows.axis = .vertical; typeRows.spacing = 8
            for (key, name) in choices {
                let row = tp_opt(name, "repeat.type." + key, self, #selector(tpSel(_:)))
                typeRows.addArrangedSubview(row)
            }
            tu_form(self, typeRows, "repeat.form"); menus()
        }
    }
    // 预设即选即返回，自定义进入独立页面。
    @objc private func tpSel(_ sender: UIButton) {
        let key = String(sender.accessibilityIdentifier!.dropFirst(12))
        if key == "custom" {
            let editor = TaskRepeat(fields: original, reply: reply); editor.customMode = true; editor.allowsNone = allowsNone
            navigationItem.backButtonTitle = "重复"; navigationController?.pushViewController(editor, animated: true); return
        }
        type = key; interval.text = "1"; dirty.formUnion(["type", "interval", "days"])
        var local = Calendar(identifier: .gregorian); local.timeZone = until.timeZone ?? .current
        let anchor = (original["due_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date()
        let day = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"][local.component(.weekday, from: anchor) - 1]
        days = key == "weekly" ? [day] : []
        if key == "ordinal" || key == "workdays" {
            var lines = original["recurrence"] as? [String] ?? [], values = parts(lines.first { $0.hasPrefix("RRULE:") })
            values = values.filter { !$0.key.hasPrefix("BY") }; values["INTERVAL"] = "1"
            values["FREQ"] = key == "ordinal" ? "MONTHLY" : "WEEKLY"
            values["BYDAY"] = key == "ordinal" ? "\((local.component(.day, from: anchor) - 1) / 7 + 1)" + day : "MO,TU,WE,TH,FR"
            let line = "RRULE:" + values.keys.sorted().map { $0 + "=" + values[$0]! }.joined(separator: ";")
            if let index = lines.firstIndex(where: { $0.hasPrefix("RRULE:") }) { lines[index] = line } else { lines.insert(line, at: 0) }
            raw.text = lines.joined(separator: "\n"); type = "custom"; dirty.insert("raw")
        }
        sv()
    }
    // 返回原生间隔和单位两列。
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }
    // 保留原有大间隔值。
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { component == 0 ? pickerLimit : freqs.count }
    // 原生滚轮行高随动态字号增大，避免文字相互覆盖。
    func pickerView(_ pickerView:UIPickerView,rowHeightForComponent component:Int)->CGFloat {max(44,lb_fnt(.body,traitCollection).lineHeight+8)}
    // 使用中文单位和统一字体。
    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let label = view as? UILabel ?? tu_lbl(nil); label.textAlignment = .center; label.text = component == 0 ? String(row + 1) : units[row]; return label
    }
    // 只更新当前自定义草稿。
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if component == 0 { interval.text = String(row + 1); dirty.insert("interval") }
        else { type = freqs[row]; dirty.insert("type") }; menus()
    }
    // 结束条件作为独立页面编辑，返回不保存。
    @objc private func endPage() {
        let page = TaskRepEnd(key: end, date: until.date, count: count.text ?? "10", zone: until.timeZone ?? .current) { [weak self] key, date, number in
            self?.end = key; self?.until.date = date; self?.count.text = number; self?.dirty.insert("end"); self?.menus()
        }; navigationItem.backButtonTitle = "自定义"; navigationController?.pushViewController(page, animated: true)
    }
    // 保留完整规则编辑入口及既有校验器。
    @objc private func rules() {
        let page = TaskRaw(text: raw.text) { [weak self] text in
            guard let self else { return }; self.raw.text = text; self.type = "custom"; self.dirty.insert("raw"); self.sv()
        }; navigationItem.backButtonTitle = "自定义"; navigationController?.pushViewController(page, animated: true)
    }
    // 构建带选中状态的重复、结束及星期菜单。
    private func menus() {
        let ends = ["none", "until", "count"], endTitles = ["无限重复", "特定日期", "限定次数"]
        endBtn.setTitle(end == "count" ? "\(count.text ?? "10")次后" : endTitles[ends.firstIndex(of: end)!], for: .normal)
        endBtn.menu = nil; endBtn.showsMenuAsPrimaryAction = false; endBtn.removeTarget(self, action: #selector(endPage), for: .touchUpInside); endBtn.addTarget(self, action: #selector(endPage), for: .touchUpInside)
        daysBtn.menu = UIMenu(children: zip(["MO", "TU", "WE", "TH", "FR", "SA", "SU"], ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]).map { day, title in
            let action = tu_act(title, nil, "repeat.day." + day) { [weak self] in guard let self = self else { return }; if self.days.contains(day) { self.days.remove(day) } else { self.days.insert(day) }; self.dirty.insert("days"); self.menus() }; action.state = days.contains(day) ? .on : .off; return action
        }); daysBtn.showsMenuAsPrimaryAction = true
        let values = parts((original["recurrence"] as? [String])?.first { $0.hasPrefix("RRULE:") })
        var selected = type
        if (Int(values["INTERVAL"] ?? "1") ?? 1) != 1 || values["COUNT"] != nil || values["UNTIL"] != nil { selected = "custom" }
        else if values["FREQ"] == "WEEKLY", Set((values["BYDAY"] ?? "").split(separator: ",")) == Set(["MO", "TU", "WE", "TH", "FR"]) { selected = "workdays" }
        else if values["FREQ"] == "MONTHLY", values["BYDAY"]?.first?.isNumber == true { selected = "ordinal" }
        for (index, row) in typeRows.arrangedSubviews.enumerated() { row.viewWithTag(1)?.isHidden = presetKeys[index] != selected; row.accessibilityValue = presetKeys[index] == selected ? "已选中" : "未选中" }
        if customMode { daysBtn.isHidden = type != "weekly"; summary.text = "每\(interval.text ?? "1")\(units[freqs.firstIndex(of: type) ?? 0])" }
    }
    // 取消面板不修改草稿。
    @objc private func cncl() { dismiss(animated: true) }
    // 生成保留例外属性的重复补丁并调用共享校验器。
    @objc private func sv() {
        guard !dirty.isEmpty else { cncl(); return }
        let intervalValue = Int64(interval.text ?? "") ?? 0, countValue = Int64(count.text ?? "") ?? 0
        let nonDigits = CharacterSet.decimalDigits.inverted
        if type != "none" && type != "custom" && (intervalValue < 1 || interval.text!.rangeOfCharacter(from: nonDigits) != nil || (end == "count" && (countValue < 1 || count.text!.rangeOfCharacter(from: nonDigits) != nil))) { tu_err(self, NSError(domain: "repeat", code: 1, userInfo: ["kind":"invalid_fields"])); return }
        var lines = original["recurrence"] as? [String] ?? [], value = intervalValue
        if type == "none" { lines = []; value = 1 }
        else if type == "custom" { lines = raw.text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        else {
            let index = lines.firstIndex { $0.hasPrefix("RRULE:") }; var values = parts(index.map { lines[$0] })
            if index == nil || dirty.contains("type") {
                if values["FREQ"] != type.uppercased() || !customMode { values = values.filter { !$0.key.hasPrefix("BY") }; if type == "weekly" && !days.isEmpty { values["BYDAY"] = days.sorted().joined(separator: ",") } }; values["FREQ"] = type.uppercased()
            }
            if index == nil || dirty.contains("interval") { values["INTERVAL"] = String(value) }
            if dirty.contains("days") { values["BYDAY"] = days.isEmpty ? nil : days.sorted().joined(separator: ",") }
            if dirty.contains("end") {
                values["UNTIL"] = nil; values["COUNT"] = nil
                if end == "count" { values["COUNT"] = String(countValue) }
                if end == "until" {
                    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = until.timeZone ?? .current
                    let date = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: until.date))!.addingTimeInterval(-1)
                    let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; values["UNTIL"] = format.string(from: date)
                }
            }
            let line = "RRULE:" + values.keys.sorted().map { $0 + "=" + values[$0]! }.joined(separator: ";")
            if let index = index { lines[index] = line } else { lines.insert(line, at: 0) }
        }
        let patch: TaskFields = ["recurrence_type": type, "recurrence_interval": max(value, 1), "recurrence": lines]
        var task = original; task.merge(patch) { _, new in new }
        do { try TaskRule.vld(task); dismiss(animated: true) { self.reply?(patch) } } catch { tu_err(navigationController?.topViewController ?? self, error) }
    }
}

// 独立结束条件草稿，点击返回不影响上一级。
private final class TaskRepEnd: TaskScreen {
    private var key: String
    private let date = UIDatePicker(), count: UITextField, reply: (String, Date, String) -> Void
    private var rows: [UIButton] = [], countRow: UIStackView!
    private let countSlot = UIView()
    // 接收自定义页当前结束条件。
    init(key: String, date: Date, count: String, zone: TimeZone, reply: @escaping (String, Date, String) -> Void) {
        self.key = key; self.count = tp_num(count, "repeat.count"); self.reply = reply
        super.init(nibName: nil, bundle: nil); self.date.date = date; self.date.timeZone = zone
    }
    // 禁用归档初始化。
    required init?(coder: NSCoder) { fatalError("Use init(key:date:count:zone:reply:)") }
    // 使用三行选项、内联月历及次数数字键盘。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "结束时间："
        date.datePickerMode = .date; date.preferredDatePickerStyle = .inline; date.locale = Locale(identifier: "zh_CN"); date.accessibilityIdentifier = "repeat.until"
        for (index, name) in ["无限重复", "特定日期", "限定次数"].enumerated() {
            let row = tp_opt(name, "repeat.end." + ["none", "until", "count"][index], self, #selector(sel(_:))); rows.append(row)
            if index == 0 { let icon = UIImageView(image: lb_icon("repeat")); icon.tintColor = TaskTheme.muted; icon.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(icon); NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: row.leadingAnchor), icon.centerYAnchor.constraint(equalTo: row.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24)]) }
        }
        let done = tu_btn("完成", nil, self, #selector(sv)); done.accessibilityIdentifier = "repeat.end.done"; var style = done.configuration; style?.baseForegroundColor = lb_acnt(); done.configuration = style; navigationItem.rightBarButtonItem = UIBarButtonItem(customView: done)
        count.textAlignment = .left; count.accessibilityLabel = "重复次数"; countRow = tu_stk([count, tu_lbl("次后"), UIView()]); countRow.axis = .horizontal; countRow.alignment = .center; countRow.spacing = 8; countRow.translatesAutoresizingMaskIntoConstraints = false; countSlot.addSubview(countRow)
        let mark = UIImageView(image: lb_icon("check")); mark.tintColor = lb_acnt(); mark.translatesAutoresizingMaskIntoConstraints = false; countSlot.addSubview(mark)
        NSLayoutConstraint.activate([countRow.leadingAnchor.constraint(equalTo: countSlot.leadingAnchor, constant: 12), countRow.trailingAnchor.constraint(equalTo: countSlot.trailingAnchor, constant: -48), countRow.topAnchor.constraint(equalTo: countSlot.topAnchor), countRow.bottomAnchor.constraint(equalTo: countSlot.bottomAnchor), countSlot.heightAnchor.constraint(greaterThanOrEqualToConstant: 48), mark.widthAnchor.constraint(equalToConstant: 24), mark.heightAnchor.constraint(equalToConstant: 24), mark.trailingAnchor.constraint(equalTo: countSlot.trailingAnchor, constant: -12), mark.centerYAnchor.constraint(equalTo: countSlot.centerYAnchor)])
        date.addTarget(self, action: #selector(dtChg), for: .valueChanged)
        tu_form(self, tu_stk([rows[0], rows[1], date, rows[2], countSlot]), "repeat.end.form"); refresh()
    }
    // 更新本页选中状态。
    @objc private func sel(_ sender: UIButton) { key = String(sender.accessibilityIdentifier!.dropFirst(11)); refresh(); if key == "count" { count.becomeFirstResponder() } else { view.endEditing(true) } }
    // 显示当前条件对应的系统控件。
    private func refresh() {
        date.isHidden = key != "until"; rows[2].isHidden = key == "count"; countSlot.isHidden = key != "count"
        let format = DateFormatter(); format.locale = Locale(identifier: "zh_CN"); format.timeZone = date.timeZone; format.dateFormat = "M月d日 E"
        rows[1].setTitle(key == "until" ? format.string(from: date.date) : "特定日期", for: .normal)
        for row in rows { let selected = row.accessibilityIdentifier == "repeat.end." + key; row.accessibilityValue = selected ? "已选中" : "未选中"; row.viewWithTag(1)?.isHidden = !selected }
    }
    // 只刷新本页日期摘要。
    @objc private func dtChg() { refresh() }
    // 校验次数后交回自定义草稿。
    @objc private func sv() {
        if key == "count" && ((Int64(count.text ?? "") ?? 0) < 1 || count.text!.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil) { tu_err(self, NSError(domain: "repeat", code: 1, userInfo: ["kind":"invalid_fields"])); return }
        reply(key, date.date, count.text ?? "10"); navigationController?.popViewController(animated: true)
    }
}

// 保留完整iCalendar规则的原生文本编辑页。
private final class TaskRaw: TaskScreen {
    private let text: String, save: (String) -> Void
    private let field = UITextView()
    // 接收完整规则而不提前写入草稿。
    init(text: String, save: @escaping (String) -> Void) { self.text = text; self.save = save; super.init(nibName: nil, bundle: nil) }
    // 禁用归档初始化。
    required init?(coder: NSCoder) { fatalError("Use init(text:save:)") }
    // 创建完整规则输入和完成入口。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "完整重复规则"; field.text = text; field.accessibilityIdentifier = "repeat.rules"; field.font = lb_fnt(.body, nil); field.adjustsFontForContentSizeCategory = true; field.textColor = TaskTheme.ink;
        tu_fld(field);field.isScrollEnabled = false; field.heightAnchor.constraint(greaterThanOrEqualToConstant: 216).isActive = true
        let done = tu_btn("完成", nil, self, #selector(sv)); done.accessibilityIdentifier = "repeat.raw.done"; var style = done.configuration; style?.baseForegroundColor = lb_acnt(); done.configuration = style; navigationItem.rightBarButtonItem = UIBarButtonItem(customView: done)
        tu_form(self, tu_stk([field]), "repeat.raw.form")
    }
    // 交给既有重复校验和保存入口。
    @objc private func sv() { save(field.text) }
}

// 使用iOS16原生月历及系统时间输入。
@available(iOS 16, *) @objc(TaskCalendar) final class TaskCalendar: TaskScreen, UICalendarSelectionSingleDateDelegate {
    var requiresTime = false
    private var date: Date, repeatName: String?
    private let zone: TimeZone, deadline: Bool
    private var timed: Bool, clockMode = false
    private let action: ((UIViewController) -> Void)?, reply: ((Date?, Bool, Bool, TaskFields) -> Void)?
    private var repeatFields: TaskFields = [:]
    private let calendar = UICalendarView(), time = UIDatePicker()
    private var dayBtn: UIButton!, timeBtn: UIButton!, remove: UIButton!, clockRow: UIStackView!
    private var repeatBtn: UIButton!
    // 接收草稿日期和回调。
    @objc(initWithDate:timed:zone:deadline:repeat:action:reply:) init(date: Date, timed: Bool, zone: TimeZone, deadline: Bool, repeatName: String?, action: ((UIViewController) -> Void)?, reply: ((Date?, Bool, Bool, TaskFields) -> Void)?) {
        self.date = date; self.timed = timed; self.zone = zone; self.deadline = deadline; self.repeatName = repeatName; self.action = action; self.reply = reply; super.init(nibName: nil, bundle: nil)
    }
    // 禁用归档初始化。
    required init?(coder: NSCoder) { fatalError("Use init(date:timed:zone:deadline:repeatName:action:reply:)") }
    // 创建原生月历、时间和独立截止控件。
    override func viewDidLoad() {
        super.viewDidLoad(); var local = Calendar(identifier: .gregorian); local.timeZone = zone
        if requiresTime { timed = true }
        calendar.tintColor = TaskTheme.cyanInk; calendar.accessibilityIdentifier = "calendar.month"; calendar.calendar = local; calendar.timeZone = zone; calendar.locale = Locale(identifier: "zh_CN")
        let selection = UICalendarSelectionSingleDate(delegate: self); calendar.selectionBehavior = selection
        let parts = local.dateComponents([.year, .month, .day], from: date); selection.setSelected(parts, animated: false); calendar.setVisibleDateComponents(parts, animated: false)
        time.datePickerMode = .time; time.preferredDatePickerStyle = .wheels; time.timeZone = zone; time.locale = calendar.locale; time.date = date; time.accessibilityIdentifier = "calendar.time"
        time.addTarget(self, action: #selector(clkChg), for: .valueChanged)
        dayBtn = tu_btn(nil, "calendar", self, #selector(month)); dayBtn.accessibilityIdentifier = "calendar.day"
        timeBtn = tu_btn(nil, "time", self, #selector(tgl)); timeBtn.accessibilityIdentifier = "calendar.timed"
        remove = tu_ibtn("close", "移除时间", "calendar.removeTime", self, #selector(rmTime)); remove.widthAnchor.constraint(equalToConstant: 44).isActive = true
        clockRow = tu_stk([timeBtn, remove]); clockRow.axis = .horizontal; clockRow.accessibilityIdentifier = "calendar.clockRow"
        let done = tu_btn("完成", nil, self, #selector(sv)); done.accessibilityIdentifier = "calendar.done"; var config = done.configuration; config?.baseForegroundColor = lb_acnt(); done.configuration = config
        repeatBtn = tu_btn(repeatName ?? "不重复", "repeat", self, #selector(rpt)); repeatBtn.isHidden = deadline || requiresTime; repeatBtn.isEnabled = action != nil; repeatBtn.accessibilityIdentifier = "calendar.repeat"; var repeatStyle = repeatBtn.configuration; repeatStyle?.contentInsets.trailing = 44; repeatBtn.configuration = repeatStyle
        let label=tu_lbl(deadline ? "选择截止日期":requiresTime ? "开始时间":"日期和时间"),header=hdr(label,nil,done)
        tp_arr(repeatBtn)
        tu_form(self, tu_stk([dayBtn, calendar, clockRow, time, repeatBtn]), "calendar.form",top:header); mode()
    }
    // 使用语义文字识别星期标签，补足原生月历的文字对比度。
    override func viewDidLayoutSubviews(){
        super.viewDidLayoutSubviews();calendar.layoutIfNeeded();let format=DateFormatter();format.locale=calendar.locale;let weekdays=Set(format.shortStandaloneWeekdaySymbols ?? []);var views=calendar.subviews
        while let view=views.popLast(){if let label=view as? UILabel,weekdays.contains(label.text ?? ""){label.textColor=TaskTheme.muted};views.append(contentsOf:view.subviews)}
    }
    // 更新草稿重复标签。
    @objc func rptName(_ name: String) { repeatName = name; repeatBtn?.setTitle(name, for: .normal) }
    // 重复面板读取月历当前选择，尚不修改外层草稿。
    func rptFlds() -> TaskFields {
        var fields: TaskFields = ["due_at":dt().timeIntervalSince1970, "schedule_kind":timed ? "timed" : "date"]
        fields.merge(repeatFields) { _, new in new }; return fields
    }
    // 将重复补丁暂存到月历，只有完成月历才交回。
    func rptSet(_ patch: TaskFields, name: String) { repeatFields = patch; rptName(name) }
    // 在同一面板切换系统时刻滚轮。
    @objc private func tgl() { timed = true; clockMode = true; mode() }
    // 返回同一草稿的完整月历。
    @objc private func month() { clockMode = false; mode() }
    // 移除时刻并保留日期和重复草稿。
    @objc private func rmTime() { timed = false; clockMode = false; mode() }
    // 同步时间摘要。
    @objc private func clkChg() { mode() }
    // 保持原版日期与时间两个互斥面板。
    private func mode() {
        calendar.isHidden = clockMode; dayBtn.isHidden = !clockMode; time.isHidden = !clockMode || deadline; clockRow.isHidden = deadline; remove.isHidden = !timed || requiresTime
        let format = DateFormatter(); format.locale = Locale(identifier: "zh_CN"); format.timeZone = zone; format.dateFormat = "M月d日 EEEE"
        dayBtn.setTitle(format.string(from: date), for: .normal)
        format.dateFormat = "HH:mm"; timeBtn.setTitle(timed ? format.string(from: time.date) : "设置时间", for: .normal)
        timeBtn.accessibilityValue = timed ? "已设置" : "未设置"
    }
    // 接收系统月历的当地日期。
    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate components: DateComponents?) { if let components = components, let date = calendar.calendar.date(from: components) { self.date = date; mode() } }
    // 保持有效日期。
    func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate components: DateComponents?) -> Bool { components != nil }
    // 返回日期与当前时刻的绝对时间。
    private func dt() -> Date {
        let local = calendar.calendar, clock = local.dateComponents([.hour, .minute], from: time.date), day = local.startOfDay(for: date)
        return timed ? local.date(bySettingHour: clock.hour!, minute: clock.minute!, second: 0, of: day)! : day
    }
    // 在月历内编辑重复，不提前提交外层草稿。
    @objc private func rpt() { action?(self) }
    // 返回选择，不直接写数据库。
    @objc private func sv() { let date = dt(); dismiss(animated: true) { self.reply?(date, self.timed, false, self.repeatFields) } }
}
