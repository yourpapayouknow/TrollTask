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

