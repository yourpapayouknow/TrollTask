// 查看、复制与清空最近运行日志。
@objc(TaskLogScreen) final class TaskLogScreen: TaskScreen {
    private let text = UITextView()
    // 建立日志正文和复制、清空入口。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "运行日志"
        let back = tu_ibtn("back", "返回设置", "log.back", self, #selector(bck))
        let header = hdr(tu_lbl(title), back, nil)
        let copy = tu_btn("复制", nil, self, #selector(cpy)); copy.accessibilityIdentifier = "log.copy"; tu_fill(copy)
        let clear = tu_btn("清空", nil, self, #selector(clr)); clear.accessibilityIdentifier = "log.clear"; tu_fill(clear)
        let tools = tu_stk([copy, clear]); tools.axis = .horizontal; tools.distribution = .fillEqually; tools.spacing = TaskTheme.gap
        text.isEditable = false; text.isSelectable = true; text.font = lb_fnt(.footnote, nil); text.textColor = TaskTheme.ink
        text.backgroundColor = .clear; text.accessibilityIdentifier = "log.text"; text.textContainerInset = .init(top: 8, left: 0, bottom: 8, right: 0)
        for item in [tools, text] { item.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(item) }
        NSLayoutConstraint.activate([
            tools.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            tools.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), tools.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tools.heightAnchor.constraint(equalToConstant: 44),
            text.topAnchor.constraint(equalTo: tools.bottomAnchor, constant: 8),
            text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            text.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)])
        reload()
    }
    // 读取最新日志，无记录时显示空态。
    private func reload() {
        let lines = TaskLog.lines(); text.text = lines.isEmpty ? "暂无日志" : lines.reversed().joined(separator: "\n")
    }
    // 复制当前日志全文。
    @objc private func cpy() { UIPasteboard.general.string = text.text; TaskHaptics.success() }
    // 确认后清空日志。
    @objc private func clr() {
        guard !TaskLog.lines().isEmpty else { return }
        let alert = UIAlertController(title: "清空运行日志", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in TaskLog.clear(); self?.reload() })
        present(alert, animated: true)
    }
}