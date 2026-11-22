// 上传已完成记录和原件，所有云端确认成功后才从本地移除原件。
@MainActor final class TaskArchiveSync {
    static let shared = TaskArchiveSync()
    static let changed = Notification.Name("TrollTaskArchiveChanged")
    private var worker: Task<Void, Never>?
    private var pending: (store: TaskStore, force: Bool)?
    private var failures: [String: String] = [:]
    private var retryAt = Date.distantPast

    // 从提醒提交或应用前台启动后台处理。
    nonisolated static func schedule(_ store: TaskStore) {
        Task { @MainActor in shared.run(store) }
    }

    // 合并同一进程的触发，失败后由后续前台、提交或手动操作重试。
    func run(_ store: TaskStore, force: Bool = false) {
        guard force || Date() >= retryAt else { return }
        if worker != nil { pending = (store, force || pending?.force == true); return }
        guard let path = store.path, let config = try? TaskCloudConfig.load(), !config.archiveAccounts.isEmpty else { return }
        worker = Task {
            let issues = await Task.detached(priority: .utility) { await Self.drain(path) }.value
            failures = issues
            retryAt = issues.isEmpty ? .distantPast : Date().addingTimeInterval(30)
            worker = nil
            NotificationCenter.default.post(name: Self.changed, object: nil)
            if let next = pending { pending = nil; run(next.store, force: next.force) }
        }
    }

    // 在工作队列上串行处理同一数据库的前台及提醒进程上传。
    private nonisolated static func drain(_ path: String) async -> [String: String] {
        let lock = open(path + ".archive.lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard lock >= 0 else { return ["*": "无法打开归档同步锁"] }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { return ["*": "归档正在同步"] }
        do {
            let store = try TaskStore(at: path)
            let rows = try store.arcPend() as! [TaskFields]
            var issues: [String: String] = [:]
            var unavailable: [String: String] = [:]
            var clients: [String: TaskCloudClient] = [:]
            var days: [String: String] = [:]
            for entry in rows {
                let id = entry["entry_id"] as! String
                let stamp = entry["completed_at"] as! NSNumber
                let day = (entry["archive_day"] as? String) ?? Self.day(stamp.doubleValue)
                for account in try TaskCloudConfig.load().archiveAccounts {
                    let provider = account.id
                    if let failure = unavailable[provider] { issues[id] = failure; continue }
                    let receipts: [TaskFields]
                    do {
                        let client: TaskCloudClient
                        if let cached = clients[provider] { client = cached }
                        else { client = try await Self.client(provider); clients[provider] = client }
                        let cache = provider + "/" + day
                        let directory: String
                        if let existing = days[cache] { directory = existing }
                        else {
                            let root = try await client.root()
                            directory = try await client.folder(day, parent: root)
                            days[cache] = directory
                        }
                        receipts = try await Self.upload(entry, store: store, client: client, parent: directory)
                    } catch {
                        let failure = error.localizedDescription
                        let response = error as NSError
                        if response.domain == NSURLErrorDomain || [401, 429, 500, 502, 503, 504, 507].contains(response.code) {
                            unavailable[provider] = failure
                        }
                        issues[id] = failure
                        continue
                    }
                    do { try store.arcDone(id, provider: provider, day: day, files: receipts); issues[id] = nil }
                    catch { issues[id] = error.localizedDescription }
                    break
                }
            }
            do { try store.arcTrim() }
            catch { issues["*"] = error.localizedDescription }
            return issues
        } catch { return ["*": error.localizedDescription] }
    }

    // 生成公历两位年月日，已开始的上传继续使用记录中的目录。
    nonisolated static func day(_ timestamp: TimeInterval, zone: TimeZone = .current) -> String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.calendar = Calendar(identifier: .gregorian)
        date.timeZone = zone
        date.dateFormat = "yyMMdd"
        return date.string(from: Date(timeIntervalSince1970: timestamp))
    }

    // 逐个核对文件读回结果，再写入完成记录。
    private nonisolated static func upload(_ entry: TaskFields, store: TaskStore, client: TaskCloudClient,
                                          parent: String) async throws -> [TaskFields] {
        let folder = try await client.folder(entry["entry_id"] as! String, parent: parent)
        var receipts: [TaskFields] = []
        var attachments: [TaskFields] = []
        if let occurrence = entry["occurrence_id"] as? String {
            let items = try store.lsChk(occurrence, images: false) as! [TaskFields]
            for item in items {
                let index = (item["position"] as! NSNumber).intValue
                let file = try store.rdPrf(occurrence, position: index) as! TaskFields
                guard let data = file["image"] as? Data else { throw TaskCloudHTTP.err("本地附件不可读") }
                let type = (item["content_type"] as? String).flatMap { UTType($0) ?? UTType(mimeType: $0) }
                let ext = type?.preferredFilenameExtension ?? (item["method"] as? String == "file" ? "bin" : "jpg")
                let suffix = String(ext.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.prefix(12))
                let name = "附件\(index + 1)." + (suffix.isEmpty ? "bin" : suffix)
                let checksum = TaskCloudHTTP.digest(data)
                var manifest = item
                if data.isEmpty && client.account.kind == .baidu {
                    // 百度网盘无法创建零字节文件，由已验证的记录保存空附件。
                    receipts.append(["position": index, "remote_key": "empty", "sha256": checksum])
                    manifest["file"] = NSNull()
                } else {
                    let remote = try await client.put(data, name: name, parent: folder)
                    guard try await client.get(remote) == data else { throw TaskCloudHTTP.err("云端附件校验失败") }
                    receipts.append(["position": index, "remote_key": remote, "sha256": checksum])
                    manifest["file"] = name
                }
                manifest["sha256"] = checksum
                attachments.append(manifest)
            }
        }
        let keys = ["entry_id", "task_id", "occurrence_id", "title", "notes", "routine_kind", "completed_at", "scheduled_at"]
        var manifest = entry.filter { keys.contains($0.key) }
        manifest["attachments"] = attachments
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
        let record = try await client.put(data, name: "record.json", parent: folder)
        guard try await client.get(record) == data else { throw TaskCloudHTTP.err("云端归档校验失败") }
        return receipts
    }

    // 读取已保存账号，在需要时换取新访问令牌。
    nonisolated static func client(_ id: String) async throws -> TaskCloudClient {
        let config = try TaskCloudConfig.load()
        guard let account = config.accounts.first(where: { $0.id == id }) else { throw TaskCloudHTTP.err("归档账户不可用") }
        guard !account.kind.isDAV else { return TaskCloudClient(account: account) }
        let fresh = try await TaskCloudOAuth(account.kind).refresh(account)
        if fresh.access != account.access {
            return try await MainActor.run {
                var latest = try TaskCloudConfig.load()
                guard let index = latest.accounts.firstIndex(where: { $0.id == id }) else { throw TaskCloudHTTP.err("归档账户不可用") }
                if latest.accounts[index].access == account.access {
                    latest.accounts[index].access = fresh.access
                    latest.accounts[index].expires = fresh.expires
                    latest.accounts[index].secret = fresh.secret
                    try latest.save()
                }
                return TaskCloudClient(account: latest.accounts[index])
            }
        }
        return TaskCloudClient(account: fresh)
    }

    // 按保存原件的账号读取，校验后交给系统预览。
    nonisolated static func fetch(_ item: TaskFields) async throws -> Data {
        if let local = item["image"] as? Data { return local }
        guard let provider = item["provider_id"] as? String, let key = item["remote_key"] as? String,
              let checksum = item["sha256"] as? String else { throw TaskCloudHTTP.err("附件内容不可用") }
        let data: Data
        if key == "empty" && (item["image_bytes"] as? NSNumber)?.intValue == 0 { data = Data() }
        else { data = try await client(provider).get(key) }
        guard TaskCloudHTTP.digest(data) == checksum else { throw TaskCloudHTTP.err("云端附件校验失败") }
        return data
    }

    // 提供指定连接的简短同步状态。
    func issue(_ id: String?) -> String? { id.flatMap { failures[$0] } ?? failures["*"] }
}

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

// 保留完成时内容并复用原附件查看页。
private final class TaskArchiveDetail: TaskScreen {
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
