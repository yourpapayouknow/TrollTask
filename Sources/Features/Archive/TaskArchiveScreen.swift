// 集中浏览普通待办和常律的历史完成记录。
final class TaskArchiveScreen: TaskScreen, UITableViewDataSource, UITableViewDelegate {
    private let store: TaskStore
    private let table = UITableView(frame: .zero, style: .plain)
    private var rows: [TaskFields] = []
    private var issue: Error?
    private var token: Int32 = -1
    private var observer: NSObjectProtocol?

    // 注入唯一任务存储。
    init(store: TaskStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    // 设置平面归档列表与重试入口。
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "归档"
        let back = tu_ibtn("back", "返回设置", "archive.back", self, #selector(bck))
        let sync = tu_ibtn("repeat", "同步归档", "archive.sync", self, #selector(retry))
        let header = hdr(tu_lbl(title), back, sync)
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 68
        table.accessibilityIdentifier = "archive.table"
        view.addSubview(table)
        tu_wdth(table, view)
        NSLayoutConstraint.activate([table.topAnchor.constraint(equalTo: header.bottomAnchor),
                                     table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)])
        let result = notify_register_dispatch(store.changeNote, &token, .main) { [weak self] _ in self?.read() }
        if result != NOTIFY_STATUS_OK { token = -1 }
        observer = NotificationCenter.default.addObserver(forName: TaskArchiveSync.changed, object: nil, queue: .main) { [weak self] _ in self?.read() }
        read()
    }

    // 列表按同库通知更新，返回时核对恢复后的状态。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        read()
        TaskArchiveSync.shared.run(store)
    }

    // 刷新归档快照。
    private func read() {
        do { rows = try store.arcRows() as! [TaskFields]; issue = nil }
        catch { issue = error }
        table.reloadData()
    }

    // 用户可立即重试待上传记录。
    @objc private func retry() {
        read()
        do {
            guard try !TaskCloudConfig.load().archiveAccounts.isEmpty else { throw TaskCloudHTTP.err("请先设置归档顺序") }
            TaskArchiveSync.shared.run(store, force: true)
        } catch { tu_err(self, error) }
    }

    // 空列表保留状态行。
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(1, rows.count) }

    // 展示记录标题、完成时间和上传状态。
    func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        var content = tu_cell()
        cell.backgroundColor = .clear
        if rows.isEmpty {
            content.text = issue == nil ? "暂无归档" : "重新读取"
            if issue == nil { cell.selectionStyle = .none }
        } else {
            let row = rows[path.row]
            content.text = row["title"] as? String
            let date = Date(timeIntervalSince1970: (row["completed_at"] as! NSNumber).doubleValue)
            content.secondaryText = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
            let routine = row["routine_kind"] as? String != "none"
            content.image = lb_icon(routine ? "repeat" : "check_circle")
            content.imageProperties.tintColor = lb_acnt()
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "archive." + (row["entry_id"] as! String)
        }
        cell.contentConfiguration = content
        return cell
    }

    // 展示不可编辑的归档明细。
    func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        guard !rows.isEmpty else { read(); return }
        navigationController?.pushViewController(TaskArchiveDetail(store: store, row: rows[path.row]), animated: true)
    }

    // 释放同库和上传完成的监听。
    deinit {
        if token >= 0 { notify_cancel(token) }
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

