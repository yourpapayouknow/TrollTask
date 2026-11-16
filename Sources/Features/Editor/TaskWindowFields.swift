// 在普通待办草稿内编辑起始日期和截止日期。
final class TaskWindowFields: UIStackView {
    private let calendar: Calendar
    private let formatter = DateFormatter()
    private let startButton = tu_btn(nil), deadlineButton = tu_btn("选择日期")
    private let picker = UIDatePicker(), confirm = tu_btn("选定日期"), status = tu_lbl(nil)
    private var rows: [UIStackView] = []
    private var editing: Bool?
    private(set) var start: Date
    private(set) var end: Date?
    var changed: (() -> Void)?
    var picking: ((Bool) -> Void)?

    init(zone: TimeZone) {
        calendar = TaskWindow.calendar(zone)
        start = TaskWindow.start(Date(), in: calendar)
        super.init(frame: .zero)
        axis = .vertical
        spacing = TaskTheme.gap
        accessibilityIdentifier = "window.form"
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy年M月d日"
        picker.preferredDatePickerStyle = .inline
        picker.datePickerMode = .date
        picker.locale = formatter.locale
        picker.calendar = calendar
        picker.timeZone = zone
        picker.maximumContentSizeCategory = .extraExtraExtraLarge
        picker.accessibilityIdentifier = "window.picker"
        picker.addTarget(self, action: #selector(refresh), for: .valueChanged)
        startButton.accessibilityIdentifier = "window.start"
        deadlineButton.accessibilityIdentifier = "window.choose"
        startButton.addTarget(self, action: #selector(pickStart), for: .touchUpInside)
        deadlineButton.addTarget(self, action: #selector(pickEnd), for: .touchUpInside)
        for button in [startButton, deadlineButton] { button.contentHorizontalAlignment = .trailing }
        confirm.accessibilityIdentifier = "window.done"
        confirm.addTarget(self, action: #selector(selectDate), for: .touchUpInside)
        status.accessibilityIdentifier = "window.error"
        status.textColor = TaskTheme.danger
        rows = [tu_row("起始日期", startButton), tu_row("截止日期", deadlineButton)]
        (rows + [picker, confirm, status]).forEach(addArrangedSubview)
        refresh()
    }

    required init(coder: NSCoder) { fatalError("Use init(zone:)") }

    // 两行同时换行，并保持日期和标签可读。
    func fit(_ width: CGFloat) {
        let font = lb_fnt(.headline, nil)!
        let buttonFont = font.withSize(min(32, font.pointSize))
        let widest = rows.map { row -> CGFloat in
            guard let label = row.arrangedSubviews.first as? UILabel, let button = row.arrangedSubviews.last as? UIButton,
                  let config = button.configuration, let title = config.title else { return 0 }
            let size = (title as NSString).size(withAttributes: [.font: buttonFont]).width
            return label.intrinsicContentSize.width + row.spacing + size + config.contentInsets.leading + config.contentInsets.trailing
        }.max() ?? 0
        let vertical = widest > width
        for row in rows {
            row.axis = vertical ? .vertical : .horizontal
            row.alignment = vertical ? .leading : .center
        }
    }

    // 打开原地日历，不将浏览中的日期写入草稿。
    @objc private func pickStart() { pick(false) }
    @objc private func pickEnd() { pick(true) }
    func selectDeadline() { if editing != true { pick(true) } }
    private func pick(_ deadline: Bool) {
        if editing == deadline { closePicker(); return }
        if editing == nil { picking?(true) }
        editing = deadline
        picker.date = deadline ? end.map { TaskWindow.deadline($0, in: calendar) } ?? start : start
        refresh()
    }

    func closePicker() {
        guard editing != nil else { return }
        editing = nil
        refresh()
        picking?(false)
    }

    private func issue(_ deadline: Bool) -> String? {
        let first = deadline ? start : calendar.startOfDay(for: picker.date)
        guard let last = deadline ? TaskWindow.end(picker.date, in: calendar) : end else { return nil }
        return TaskWindow.issue(first, last, in: calendar)
    }

    @objc private func refresh() {
        startButton.configuration?.title = formatter.string(from: start)
        deadlineButton.configuration?.title = end.map { formatter.string(from: TaskWindow.deadline($0, in: calendar)) } ?? "选择日期"
        for (button, selected) in [(startButton, editing == false), (deadlineButton, editing == true)] {
            button.configuration?.baseForegroundColor = selected ? lb_acnt() : TaskTheme.ink
            if selected { button.accessibilityTraits.insert(.selected) }
            else { button.accessibilityTraits.remove(.selected) }
        }
        picker.isHidden = editing == nil
        confirm.isHidden = editing == nil
        let error = editing.flatMap(issue)
        status.text = error
        status.isHidden = error == nil
        confirm.isEnabled = error == nil
        changed?()
    }

    @objc private func selectDate() {
        guard let editing, issue(editing) == nil else { return }
        if editing { end = TaskWindow.end(picker.date, in: calendar) }
        else { start = calendar.startOfDay(for: picker.date) }
        closePicker()
    }
}
