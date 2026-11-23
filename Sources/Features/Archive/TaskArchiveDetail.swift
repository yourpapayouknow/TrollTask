// 保留完成时内容并复用原附件查看页。
final class TaskArchiveDetail: TaskScreen {
    private let store: TaskStore
    private let row: TaskFields
    private let state = tu_lbl(nil)
    private var observer: NSObjectProtocol?

    // 绑定本次完成记录。
    init(store: TaskStore, row: TaskFields) { self.store = store; self.row = row; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(store:row:)") }

    // 使用同一组表单、按钮与系统返回。
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "完成记录"
        let name = tu_lbl(row["title"] as? String)
        name.font = lb_fnt(.title1, traitCollection)
        let date = Date(timeIntervalSince1970: (row["completed_at"] as! NSNumber).doubleValue)
        let completed = tu_lbl(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short))
        completed.textColor = TaskTheme.muted
        state.textColor = TaskTheme.muted
        state.accessibilityIdentifier = "archive.upload"
        var fields = [name, completed, state] as [UIView]
        if let notes = row["notes"] as? String, !notes.isEmpty { fields.append(tu_lbl(notes)) }
        if row["occurrence_id"] is String {
            let proof = tu_btn("打卡附件", "folder", self, #selector(openProof))
            proof.accessibilityIdentifier = "archive.proof"
            fields.append(proof)
        }
        if (row["can_restore"] as? NSNumber)?.boolValue == true {
            let restore = tu_btn("恢复待办", "repeat", self, #selector(restoreTask))
            restore.accessibilityIdentifier = "archive.restore"
            fields.append(restore)
        }
        _ = tu_form(self, tu_stk(fields), "archive.detail")
        observer = NotificationCenter.default.addObserver(forName: TaskArchiveSync.changed, object: nil, queue: .main) { [weak self] _ in self?.status() }
        status()
    }

    // 显示云端状态并提供失败原因。
    private func status() {
        let rows = (try? store.arcRows()) as? [TaskFields]
        let latest = rows?.first { $0["entry_id"] as? String == row["entry_id"] as? String } ?? row
        let uploaded = (latest["uploaded"] as? NSNumber)?.boolValue == true
        let failure = TaskArchiveSync.shared.issue(latest["entry_id"] as? String)
        state.text = uploaded ? "已上传" : (failure == nil ? "待上传" : "上传失败")
        state.accessibilityHint = uploaded ? nil : failure
    }

    // 从历史轮次打开附件，避免加载整批原件。
    @objc private func openProof() {
        guard let id = row["occurrence_id"] as? String else { return }
        navigationController?.pushViewController(TaskProofScreen(store: store, occurrence: id), animated: true)
    }

    // 恢复指定普通待办，完成记录仍可追溯。
    @objc private func restoreTask() {
        do { try store.rstrArc(row["entry_id"] as? String); bck() }
        catch { tu_err(self, error) }
    }

    // 解除云端状态监听。
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
