// 保留原生UIApplicationDelegate入口并用Swift创建主页。
@objc(LBAppDel) final class TaskApp: UIResponder, UIApplicationDelegate {
    @objc var window: UIWindow?
    private var store: TaskStore?
    private var routineIssue: Error?
    private var seededPath: String?
    private var capture: TaskHUD?, captureID: String?, captureNote: Int32 = -1
    // 启动共享存储和已启用的独立HUD。
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        do { store = try TaskStore.shrd() } catch { NSLog("TaskStore初始化失败：%@", error as NSError) }
        seed()
        let home = TaskHome(store: store) { [weak self] navigation in
            let settings = TaskSettingsScreen(); settings.taskStore = self?.store; settings.storeIssue = { [weak self] in self?.store == nil }
            let panel=UINavigationController(rootViewController:settings);panel.modalPresentationStyle = .fullScreen;navigation.present(panel,animated:true)
        }
        home.onStore = { [weak self, weak home] active in
            self?.store = active; if self?.seed()==true { home?.rfrsh() }; self?.seedIssue(); self?.rstr(); self?.capStart()
            if let active { TaskArchiveSync.schedule(active) }
        }
        let navigation = UINavigationController(rootViewController: home)
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = navigation; window.overrideUserInterfaceStyle = TaskLook.styles[TaskLook.index]; self.window = window; window.makeKeyAndVisible()
        DispatchQueue.main.async { [weak self] in self?.seedIssue() }
        let result = notify_register_dispatch(TS_CAPTURE_NOTE, &captureNote, .main) { [weak self] _ in self?.capStart() }
        if result != NOTIFY_STATUS_OK { captureNote = -1 }
        rstr()
        return true
    }
    // 正式常律进入唯一数据库，幂等标记保留后续用户编辑。
    @discardableResult private func seed() -> Bool {
        guard let store, seededPath != store.path else { return false }
        do {
            guard let url=Bundle.main.url(forResource:"WeeklyRoutine",withExtension:"json"),
                let document=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? NSDictionary else {
                throw NSError(domain:"routine",code:1,userInfo:[NSLocalizedDescriptionKey:"时间表资源缺失"])
            }
            let result = try TaskRoutineImport.formal(store,document:document,anchor:Date(),zone:TimeZone.current.identifier)
            routineIssue=nil; seededPath=store.path; return (result["added"] as? NSNumber)?.intValue ?? 0 > 0
        } catch { routineIssue=error; NSLog("正式常律写入失败：%@",error as NSError); return false }
    }
    // 写入失败明确告知，不把未落库时间表显示为已启用。
    private func seedIssue() {
        guard let issue=routineIssue, let root=window?.rootViewController, root.presentedViewController==nil else { return }
        routineIssue=nil
        let alert=UIAlertController(title:"常律写入失败",message:issue.localizedDescription,preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"知道了",style:.default));root.present(alert,animated:true)
    }
    // 只在正常前台生命周期中开启系统采集。
    func applicationDidBecomeActive(_ application: UIApplication) {
        rstr(); capStart()
        if let store { TaskArchiveSync.schedule(store) }
    }
    // 每次回到App核对真实进程锁，按已有启用意图恢复服务。
    private func rstr() {
        guard store != nil, (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue == true, !lb_svcup() else { return }
        if !lb_spawn() { NSLog("提醒服务恢复失败") }
    }
    // 用户切走或划掉采集App时交回取消，提醒服务继续运行。
    func applicationDidEnterBackground(_ application: UIApplication) { capture?.capAbort() }
    // 按同库请求临时呈现采集页，不创建提醒服务或另一个数据库。
    private func capStart() {
        guard UIApplication.shared.applicationState == .active, let store, let root = window?.rootViewController else { return }
        do {
            if let token = captureID {
                let current = try store.rdCap(token)
                if current["token"] == nil { capDrop(token, store) }
                return
            }
            guard capture == nil, lb_svcup() else { return }
            var host = root
            while let presented = host.presentedViewController { host = presented }
            let request = try store.rdCap(nil)
            guard (request["state"] as? NSNumber)?.intValue == 0, let token = request["token"] as? String else { return }
            guard !host.isBeingPresented, !host.isBeingDismissed, host.transitionCoordinator == nil else {
                DispatchQueue.main.asyncAfter(deadline: .now()+0.3) { [weak self] in self?.capStart() }; return
            }
            let picker = TaskHUD(); capture = picker; captureID = token; picker.modalPresentationStyle = .overFullScreen
            host.present(picker, animated: false) { [weak self, weak picker] in
                guard let self, let picker, self.captureID == token else { return }
                do {
                    guard UIApplication.shared.applicationState == .active else { self.capDrop(token, store); return }
                    try store.ackCap(token)
                } catch { NSLog("前台采集接管失败：%@", error as NSError); self.capDrop(token, store); return }
                picker.capOpen(request as? TaskFields ?? [:]) { [weak self, weak picker] items, issue in
                    guard let self, self.captureID == token else { return }
                    do { let current = try store.rdCap(token); if current["token"] != nil { try store.finCap(token, attachments: items, issue: issue) } }
                    catch {
                        NSLog("前台采集交回失败：%@", error as NSError)
                        do { try store.finCap(token, attachments: [], issue: "图片读取失败") }
                        catch { NSLog("采集取消交回失败：%@", error as NSError); self.capDrop(token, store); return }
                    }
                    self.captureID = nil; self.capture = nil; notify_post(TS_CAPTURE_NOTE)
                    picker?.dismiss(animated: false) { [weak self] in picker?.stp(); self?.capStart() }
                }
                notify_post(TS_CAPTURE_NOTE)
            }
        } catch { NSLog("前台采集启动失败：%@", error as NSError) }
    }
    // 超时或交回失败清理同一采集，允许原HUD恢复后再次选择。
    private func capDrop(_ token: String, _ store: TaskStore) {
        guard captureID == token else { return }
        let picker = capture; captureID = nil; capture = nil; picker?.capAbort()
        do { try store.delCap(token) } catch { NSLog("前台采集清理失败：%@", error as NSError) }
        notify_post(TS_CAPTURE_NOTE)
        if picker?.presentingViewController != nil { picker?.dismiss(animated: false) { [weak self] in picker?.stp(); self?.capStart() } }
        else { picker?.stp() }
    }
    // 注销采集请求通知。
    deinit { if captureNote >= 0 { notify_cancel(captureNote) } }
}
