// 为手动新建常律提供可见的次日早间默认值。
func tr_draft() -> TaskFields {
    let zone = TaskTimeZone.current
    var calendar = Calendar.current
    calendar.timeZone = zone
    let start = calendar.nextDate(after: Date(), matching: DateComponents(hour: 8, minute: 0), matchingPolicy: .nextTime)!
    return ["list_id": TS_RTN_LST, "routine_kind": "fixed", "routine_end": 510, "routine_enabled": 1,
            "due_at": start.timeIntervalSince1970, "schedule_kind": "timed", "recurrence_type": "daily", "recurrence_interval": 1,
            "recurrence": ["RRULE:FREQ=DAILY;INTERVAL=1"], "timezone_id": zone.identifier]
}

// 首页与设置共用模板下载和正式常律导入。
final class TaskRtnPicker:NSObject,UIDocumentPickerDelegate {
    private let store:TaskStore,changed:()->Void
    private weak var host:UIViewController?
    private var importing=false, exporting=false
    private var templateURL: URL?
    private let queue=DispatchQueue(label:"com.iwmei.taskforiwmei.routine.import")
    // 接收同库和当前展示页。
    init(store:TaskStore,host:UIViewController,changed:@escaping ()->Void){self.store=store;self.host=host;self.changed=changed;super.init()}
    // 原生菜单提供模板下载和文件上传两个独立入口。
    func open() {
        guard !importing,let host,host.presentedViewController == nil else { return }
        let menu = UIAlertController(title:"导入常律",message:nil,preferredStyle:.actionSheet); menu.view.tintColor = lb_acnt()
        for (title, export) in [("下载模板",true),("选择文件",false)] {
            menu.addAction(UIAlertAction(title:title,style:.default) { [weak self, weak menu] _ in
                menu?.dismiss(animated:true) { self?.pick(export) }
            })
        }
        menu.addAction(UIAlertAction(title:"取消",style:.cancel))
        menu.popoverPresentationController?.sourceView = host.view
        menu.popoverPresentationController?.sourceRect = CGRect(x:host.view.bounds.midX,y:host.view.bounds.midY,width:0,height:0)
        host.present(menu,animated:true)
    }
    // 使用iOS14起的复制导出和复制导入接口。
    private func pick(_ export: Bool) {
        guard let host,host.presentedViewController == nil else { return }
        do {
            let picker: UIDocumentPickerViewController
            if export {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("routine-"+UUID().uuidString,isDirectory:true)
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                let url = directory.appendingPathComponent("常律模板.md")
                try TaskRoutineImport.template().write(to:url,atomically:true,encoding:.utf8); templateURL = url; exporting = true
                picker = UIDocumentPickerViewController(forExporting:[url],asCopy:true)
            } else { exporting = false; picker = UIDocumentPickerViewController(forOpeningContentTypes:[.data],asCopy:true) }
            picker.delegate = self; picker.allowsMultipleSelection = false; host.present(picker,animated:true)
        } catch { tu_err(host,error) }
    }
    // 释放本次导出的临时模板。
    private func clear() { if let url = templateURL { try? FileManager.default.removeItem(at:url.deletingLastPathComponent()) }; templateURL = nil; exporting = false }
    // 在后台完整验证UTF8模板，整批创建或整批拒绝。
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if exporting { clear(); return }
        guard let url = urls.first, !importing else { return }; importing = true
        if controller.presentingViewController != nil { controller.dismiss(animated: true) { [weak self] in self?.rdImp(url) } }
        else { rdImp(url) }
    }
    // 选择器退出后读取，避免结果弹窗被系统关闭过渡吞掉。
    private func rdImp(_ url: URL) {
        queue.async {
            var result: TaskFields?, failure: Error?
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let info = try url.resourceValues(forKeys: [.fileSizeKey,.isRegularFileKey])
                guard info.isRegularFile == true, (info.fileSize ?? Int.max) <= 1024*1024 else { throw NSError(domain:"routine",code:1,userInfo:[NSLocalizedDescriptionKey:"请选择小于1MB的文本"]) }
                let data = try Data(contentsOf: url)
                guard data.count <= 1024*1024, let text = String(data:data,encoding:.utf8) else { throw NSError(domain:"routine",code:1,userInfo:[NSLocalizedDescriptionKey:"需要UTF8时间表"]) }
                let document = try TaskRoutineImport.load(text, source:url.lastPathComponent, anchor:Date(), zone:TimeZone.current.identifier)
                result = try self.store.importRtns(document as! TaskFields) as? TaskFields
            } catch { failure = error }
            DispatchQueue.main.async {
                self.importing = false
                guard let host=self.host,host.viewIfLoaded?.window != nil else { return }
                if let failure { tu_err(host,failure); return }
                let alert = UIAlertController(title:"已导入常律",message:"新增\((result?["added"] as? NSNumber)?.intValue ?? 0)项",preferredStyle:.alert); alert.view.tintColor = lb_acnt()
                alert.addAction(UIAlertAction(title:"完成",style:.default) { [weak self] _ in self?.changed() }); host.present(alert,animated:true)
            }
        }
    }
    // 系统取消导入不改变任何常律。
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { importing = false; clear() }
}

// 按单个附件读取并交给原生QuickLook，不一次解码整组图片。
final class TaskProofScreen: TaskScreen, UITableViewDataSource, UITableViewDelegate, QLPreviewControllerDataSource {
    private let store: TaskStore, occurrence: String
    private let table = UITableView(frame: .zero, style: .plain)
    private var items: [TaskFields] = [], preview: URL?, directory: URL?, loading = false, failure: Error?
    // 接收同库的完成轮次身份。
    init(store: TaskStore, occurrence: String) { self.store = store; self.occurrence = occurrence; super.init(nibName: nil, bundle: nil) }
    // 禁用归档初始化。
    required init?(coder: NSCoder) { fatalError("Use init(store:occurrence:)") }
    // 元数据列表保持可退出空态。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "打卡附件"; table.dataSource = self; table.delegate = self; table.backgroundColor = .clear; table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 64; table.accessibilityIdentifier = "proof.table"
        view.addSubview(table); tu_wdth(table, view); NSLayoutConstraint.activate([table.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)])
        read()
    }
    // 读取失败保留原页重试入口。
    private func read() {
        do { items = try store.lsChk(occurrence, images: false) as! [TaskFields]; failure = nil } catch { failure = error }
        table.reloadData()
    }
    // 返回独立附件数量。
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { max(1,items.count) }
    // 文件名仅在归档页呈现，HUD仍保持纯图标。
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil); cell.backgroundColor = .clear
        var content = tu_cell(); content.textProperties.font = lb_fnt(.body, traitCollection); content.textProperties.color = TaskTheme.ink; content.textProperties.numberOfLines = 0; content.secondaryTextProperties.color = TaskTheme.muted
        if items.isEmpty { content.text = failure == nil ? "无附件" : "重新读取"; cell.selectionStyle = failure == nil ? .none : .default }
        else { let item = items[indexPath.row]; content.text = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "图片\(indexPath.row+1)"; content.image = lb_icon(item["method"] as? String == "file" ? "folder" : "pic"); content.secondaryText = ByteCountFormatter.string(fromByteCount: (item["image_bytes"] as! NSNumber).int64Value, countStyle: .file); cell.accessoryType = .disclosureIndicator }
        cell.accessibilityIdentifier = "proof.item.\(indexPath.row)"; content.imageProperties.tintColor = lb_acnt(); cell.contentConfiguration = content; return cell
    }
    // 只导出用户点击的附件，文件名不能逃出临时目录。
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let failure { tu_err(self, failure); read(); return }
        guard !items.isEmpty, !loading else { return }; loading = true
        let index = indexPath.row
        Task { [self] in
            var result: URL?, folder: URL?, failure: Error?
            do {
                let item = try self.store.rdPrf(self.occurrence, position: index) as! TaskFields
                let data = try await TaskArchiveSync.fetch(item)
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true); folder = directory
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                var suffix = (item["content_type"] as? String).flatMap { (UTType($0) ?? UTType(mimeType: $0))?.preferredFilenameExtension }
                if suffix == nil, item["method"] as? String != "file", let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) { suffix = UTType(type as String)?.preferredFilenameExtension }
                let fallback = "附件" + (suffix.map { "." + $0 } ?? "")
                let raw = (item["name"] as? String) ?? fallback, name = URL(fileURLWithPath: raw).lastPathComponent
                let url = directory.appendingPathComponent(name == "." || name == ".." || name.isEmpty ? fallback : name)
                try data.write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path); result = url
            } catch { failure = error }
            self.loading = false
            guard self.navigationController?.topViewController === self else {
                if let folder { try? FileManager.default.removeItem(at: folder) }
                return
            }
            if let failure { if let folder { try? FileManager.default.removeItem(at: folder) }; tu_err(self,failure); return }
            if let previous = self.directory { try? FileManager.default.removeItem(at: previous) }; self.directory = folder; self.preview = result
            let controller = QLPreviewController(); controller.dataSource = self; self.navigationController?.pushViewController(controller, animated: true)
        }
    }
    // 一次只向原生预览提供一个文件。
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { preview == nil ? 0 : 1 }
    // 返回已限制路径的临时文件。
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { preview! as NSURL }
    // 离开附件页后清理预览副本，数据库原件不删除。
    deinit { if let directory { try? FileManager.default.removeItem(at: directory) } }
}
