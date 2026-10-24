// 创建统一数值输入。
private func tp_num(_ text: String, _ id: String) -> UITextField {
    let field = UITextField(); field.text = text; field.accessibilityIdentifier = id; field.keyboardType = .numberPad; field.font = lb_fnt(.body, nil)
    field.adjustsFontForContentSizeCategory = true; field.textAlignment = .right
    NSLayoutConstraint.activate([field.widthAnchor.constraint(greaterThanOrEqualToConstant: 44), field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)]); return field
}

// 保存完整重复属性并只修改用户改变的规则参数。
@objc(TaskRepeat) final class TaskRepeat: TaskScreen, UITextViewDelegate {
    private let original: TaskFields, reply: ((TaskFields) -> Void)?
    private var type: String, end = "none", days: Set<String> = [], dirty: Set<String> = []
    private var interval: UITextField!, count: UITextField!
    private let until = UIDatePicker(), raw = UITextView()
    private var typeBtn: UIButton!, endBtn: UIButton!, daysBtn: UIButton!, basic: UIStackView!, untilRow: UIStackView!, countRow: UIStackView!
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
        super.viewDidLoad()
        let lines = original["recurrence"] as? [String] ?? [], values = parts(lines.first { $0.hasPrefix("RRULE:") })
        days = Set((values["BYDAY"] ?? "").split(separator: ",").map(String.init))
        interval = tp_num(values["INTERVAL"] ?? (original["recurrence_interval"] as? NSNumber)?.stringValue ?? "1", "repeat.interval"); count = tp_num(values["COUNT"] ?? "10", "repeat.count")
        until.datePickerMode = .date; until.preferredDatePickerStyle = .compact; until.timeZone = TimeZone(identifier: original["timezone_id"] as? String ?? "") ?? .current; until.locale = Locale(identifier: "zh_CN"); until.accessibilityIdentifier = "repeat.until"
        if values["COUNT"] != nil { end = "count" }
        if let stamp = values["UNTIL"] {
            end = "until"; let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = stamp.count == 8 ? "yyyyMMdd" : "yyyyMMdd'T'HHmmss'Z'"; until.date = format.date(from: stamp) ?? Date()
        }
        for control in [interval!, count!, until] { control.addTarget(self, action: #selector(chg(_:)), for: control is UITextField ? .editingChanged : .valueChanged) }
        typeBtn = tu_btn(nil, "repeat"); typeBtn.accessibilityIdentifier = "repeat.type"; endBtn = tu_btn(nil, "down"); endBtn.accessibilityIdentifier = "repeat.end"; daysBtn = tu_btn("指定星期", "calendar"); daysBtn.accessibilityIdentifier = "repeat.days"
        raw.delegate = self; raw.text = lines.joined(separator: "\n"); raw.font = lb_fnt(.body, nil); raw.adjustsFontForContentSizeCategory = true; raw.textColor = TaskTheme.ink; raw.backgroundColor = .clear
        raw.accessibilityIdentifier = "repeat.rules"; raw.accessibilityLabel = "完整重复规则"; raw.textContainerInset = .init(top: 4, left: 4, bottom: 4, right: 4); raw.heightAnchor.constraint(equalToConstant: 180).isActive = true
        let done = tu_btn("完成", nil, self, #selector(sv)); done.accessibilityIdentifier = "repeat.done"
        untilRow = tu_row("结束日期", until); countRow = tu_row("结束次数", count)
        basic = tu_stk([tu_row("重复间隔", interval), daysBtn, endBtn, untilRow, countRow])
        tu_form(self, tu_stk([typeBtn, basic, raw, done, tu_btn("取消", nil, self, #selector(cncl))]), "repeat.form"); menus()
    }
    // 构建带选中状态的重复、结束及星期菜单。
    private func menus() {
        let types = ["none", "daily", "weekly", "monthly", "yearly", "custom"], titles = ["不重复", "每天", "每周", "每月", "每年", "完整规则"]
        typeBtn.setTitle(titles[types.firstIndex(of: type) ?? 0], for: .normal)
        typeBtn.menu = UIMenu(children: zip(types, titles).map { key, title in
            let action = tu_act(title, nil, "repeat.type." + key) { [weak self] in self?.type = key; self?.dirty.insert("type"); self?.menus() }; action.state = type == key ? .on : .off; return action
        }); typeBtn.showsMenuAsPrimaryAction = true
        let ends = ["none", "until", "count"], endTitles = ["永不结束", "指定日期", "指定次数"]
        endBtn.setTitle(endTitles[ends.firstIndex(of: end)!], for: .normal)
        endBtn.menu = UIMenu(children: zip(ends, endTitles).map { key, title in
            let action = tu_act(title, nil, "repeat.end." + key) { [weak self] in self?.end = key; self?.dirty.insert("end"); self?.menus() }; action.state = end == key ? .on : .off; return action
        }); endBtn.showsMenuAsPrimaryAction = true
        daysBtn.menu = UIMenu(children: zip(["MO", "TU", "WE", "TH", "FR", "SA", "SU"], ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]).map { day, title in
            let action = tu_act(title, nil, "repeat.day." + day) { [weak self] in guard let self = self else { return }; if self.days.contains(day) { self.days.remove(day) } else { self.days.insert(day) }; self.dirty.insert("days"); self.menus() }; action.state = days.contains(day) ? .on : .off; return action
        }); daysBtn.showsMenuAsPrimaryAction = true
        raw.isHidden = type != "custom"; basic.isHidden = type == "custom" || type == "none"; daysBtn.isHidden = type != "weekly"; untilRow.isHidden = end != "until"; countRow.isHidden = end != "count"
    }
    // 记录数值或结束条件修改。
    @objc private func chg(_ control: UIControl) { dirty.insert(control === interval ? "interval" : "end") }
    // 记录完整规则编辑。
    func textViewDidChange(_ textView: UITextView) { dirty.insert("raw") }
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
                if values["FREQ"] != type.uppercased() { values = values.filter { !$0.key.hasPrefix("BY") }; if type == "weekly" && !days.isEmpty { values["BYDAY"] = days.sorted().joined(separator: ",") } }; values["FREQ"] = type.uppercased()
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
        do { try TaskRule.vld(task); dismiss(animated: true) { self.reply?(patch) } } catch { tu_err(self, error) }
    }
}

// 使用iOS16原生月历及系统时间输入。
@available(iOS 16, *) @objc(TaskCalendar) final class TaskCalendar: TaskScreen, UICalendarSelectionSingleDateDelegate {
    private var date: Date, repeatName: String?
    private let zone: TimeZone, timed: Bool, deadline: Bool
    private let action: ((UIViewController) -> Void)?, reply: ((Date?, Bool, Bool) -> Void)?
    private let calendar = UICalendarView(), time = UIDatePicker(), toggle = UISwitch()
    private var repeatBtn: UIButton!
    // 接收草稿日期和回调。
    @objc(initWithDate:timed:zone:deadline:repeat:action:reply:) init(date: Date, timed: Bool, zone: TimeZone, deadline: Bool, repeatName: String?, action: ((UIViewController) -> Void)?, reply: ((Date?, Bool, Bool) -> Void)?) {
        self.date = date; self.timed = timed; self.zone = zone; self.deadline = deadline; self.repeatName = repeatName; self.action = action; self.reply = reply; super.init(nibName: nil, bundle: nil)
    }
    // 禁用归档初始化。
    required init?(coder: NSCoder) { fatalError("Use init(date:timed:zone:deadline:repeatName:action:reply:)") }
    // 创建原生月历、时间和独立截止控件。
    override func viewDidLoad() {
        super.viewDidLoad(); var local = Calendar(identifier: .gregorian); local.timeZone = zone
        calendar.accessibilityIdentifier = "calendar.month"; calendar.calendar = local; calendar.timeZone = zone; calendar.locale = Locale(identifier: "zh_CN")
        let selection = UICalendarSelectionSingleDate(delegate: self); calendar.selectionBehavior = selection
        let parts = local.dateComponents([.year, .month, .day], from: date); selection.setSelected(parts, animated: false); calendar.setVisibleDateComponents(parts, animated: false)
        time.datePickerMode = .time; time.preferredDatePickerStyle = .compact; time.timeZone = zone; time.locale = calendar.locale; time.date = date; time.accessibilityIdentifier = "calendar.time"
        toggle.isOn = timed; toggle.onTintColor = lb_acnt(); toggle.accessibilityIdentifier = "calendar.timed"; toggle.addTarget(self, action: #selector(tgl), for: .valueChanged); time.isHidden = !timed
        let done = tu_btn("完成", nil, self, #selector(sv)); done.accessibilityIdentifier = "calendar.done"
        let clear = tu_btn(deadline ? "清除截止" : "清除日期及重复", "close", self, #selector(clr)); clear.accessibilityIdentifier = "calendar.clear"
        repeatBtn = tu_btn(repeatName ?? "不重复", "repeat", self, #selector(rpt)); repeatBtn.isHidden = deadline; repeatBtn.isEnabled = action != nil; repeatBtn.accessibilityIdentifier = "calendar.repeat"
        tu_form(self, tu_stk([tu_row(deadline ? "截止日期" : "日期和时间", done), calendar, tu_row("设置时间", toggle), time, repeatBtn, clear]), "calendar.form")
    }
    // 更新草稿重复标签。
    @objc func rptName(_ name: String) { repeatName = name; repeatBtn?.setTitle(name, for: .normal) }
    // 切换系统时刻控件。
    @objc private func tgl() { time.isHidden = !toggle.isOn }
    // 接收系统月历的当地日期。
    func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate components: DateComponents?) { if let components = components, let date = calendar.calendar.date(from: components) { self.date = date } }
    // 保持有效日期。
    func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate components: DateComponents?) -> Bool { components != nil }
    // 返回日期与当前时刻的绝对时间。
    private func dt() -> Date {
        let local = calendar.calendar, clock = local.dateComponents([.hour, .minute], from: time.date), day = local.startOfDay(for: date)
        return toggle.isOn ? local.date(bySettingHour: clock.hour!, minute: clock.minute!, second: 0, of: day)! : day
    }
    // 从月历进入重复面板前保存草稿选择。
    @objc private func rpt() { reply?(dt(), toggle.isOn, false); action?(self) }
    // 返回选择，不直接写数据库。
    @objc private func sv() { let date = dt(); dismiss(animated: true) { self.reply?(date, self.toggle.isOn, false) } }
    // 明确清除草稿日期。
    @objc private func clr() { dismiss(animated: true) { self.reply?(nil, false, true) } }
}
