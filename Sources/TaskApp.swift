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
            let settings = TaskSettings(); settings.storeIssue = { [weak self] in self?.store == nil }
            let panel=UINavigationController(rootViewController:settings);panel.modalPresentationStyle = .fullScreen;navigation.present(panel,animated:true)
        }
        home.onStore = { [weak self, weak home] active in self?.store = active; if self?.seed()==true { home?.rfrsh() }; self?.seedIssue(); self?.rstr(); self?.capStart() }
        let navigation = UINavigationController(rootViewController: home); navigation.overrideUserInterfaceStyle = .unspecified
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = navigation; self.window = window; window.makeKeyAndVisible()
        DispatchQueue.main.async { [weak self] in self?.seedIssue() }
        let result = notify_register_dispatch(TS_CAPTURE_NOTE, &captureNote, .main) { [weak self] _ in self?.capStart() }
        if result != NOTIFY_STATUS_OK { captureNote = -1 }
        rstr()
        return true
    }
    // 正式周表进入唯一数据库，幂等标记保留后续用户编辑。
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
    func applicationDidBecomeActive(_ application: UIApplication) { rstr(); capStart() }
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

// 通过原生Darwin通信控制既有独立HUD。
@objc(LBSetCtl) final class TaskSettings: TaskScreen {
    @objc var storeFailed = false
    @objc var storeIssue: (() -> Bool)?
    private let monitor = UISwitch()
    private var preview: UIButton!, recovery: UIButton!
    private var status: UIButton!, planned: UIButton!, timer: DispatchSourceTimer?, watcher: DispatchSourceProcess?
    private var routinePicker: TaskRtnPicker?
    private var watched: pid_t = 0
    private var pending = false
    private var request = 0
    private var token: Int32 = -1
    private var activation: NSObjectProtocol?
    // 创建服务控制与预览入口。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "设置"
        let heading=tu_lbl(title);heading.font=lb_fnt(.headline,traitCollection)
        let close=tu_ibtn("close","关闭设置","settings.close",self,#selector(bck))
        let header=hdr(heading,nil,close)
        monitor.onTintColor = lb_acnt(); monitor.isOn = (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue == true
        monitor.accessibilityIdentifier = "settings.enabled"; monitor.addTarget(self, action: #selector(monChg), for: .valueChanged)
        status = tu_btn("正在检查","check_circle",self,#selector(rfrsh));status.accessibilityIdentifier="settings.status"
        planned = tu_btn("下一提醒","time",self,#selector(rfrsh));planned.accessibilityIdentifier="settings.next"
        preview = tu_btn("测试全屏提醒","list",self,#selector(tst));preview.accessibilityIdentifier="settings.preview"
        recovery = tu_btn("恢复提醒","repeat",self,#selector(rstr));recovery.accessibilityIdentifier="settings.recovery"
        let assistant=tu_btn("智能助手","subtask",self,#selector(aiCfg));assistant.accessibilityIdentifier="settings.assistant"
        let routineImport=tu_btn("导入常律","file",self,#selector(rtnImp));routineImport.accessibilityIdentifier="settings.routineImport"
        for button in [status!,planned!,preview!,recovery!,assistant,routineImport] {
            var config=button.configuration;config?.imagePadding=8;config?.background.cornerRadius=12;config?.contentInsets=NSDirectionalEdgeInsets(top:8,leading:12,bottom:8,trailing:12)
            config?.titleLineBreakMode = .byWordWrapping;config?.subtitleLineBreakMode = .byWordWrapping
            config?.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer { attributes in var result=attributes;result.font=lb_fnt(.body,nil);return result }
            config?.subtitleTextAttributesTransformer=UIConfigurationTextAttributesTransformer { attributes in var result=attributes;result.font=lb_fnt(.subheadline,nil);result.foregroundColor=TaskTheme.muted;return result }
            button.configuration=config;button.titleLabel?.numberOfLines=0;button.heightAnchor.constraint(greaterThanOrEqualToConstant:56).isActive=true
        }
        let hint="重启后打开App恢复";recovery.accessibilityHint="整机重启后需打开一次App恢复提醒服务"
        recovery.addInteraction(UIToolTipInteraction(defaultToolTip:hint))
        let help=UIAction(title:hint,identifier:UIAction.Identifier("settings.recovery.help")){[weak self] _ in self?.hlp(hint)}
        recovery.menu=UIMenu(children:[help])
        let icon=UIImageView(image:lb_icon("settings"));icon.tintColor=TaskTheme.ink;icon.contentMode = .scaleAspectFit;NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant:24),icon.heightAnchor.constraint(equalToConstant:24)])
        let service=tu_stk([icon,tu_lbl("后台服务"),monitor]);service.axis = .horizontal;service.alignment = .center;service.spacing=8;service.isLayoutMarginsRelativeArrangement=true;service.directionalLayoutMargins=NSDirectionalEdgeInsets(top:8,leading:12,bottom:8,trailing:12);service.accessibilityIdentifier="settings.service";service.heightAnchor.constraint(greaterThanOrEqualToConstant:56).isActive=true
        let divider=UIView();divider.backgroundColor = .separator;divider.heightAnchor.constraint(equalToConstant:1/UIScreen.main.scale).isActive=true
        let fields=tu_stk([service,status,planned,preview,recovery,divider,assistant,routineImport]);fields.spacing=16
        _ = tu_form(self,fields,"settings.content",top:header);fields.setCustomSpacing(TaskTheme.section,after:recovery);fields.setCustomSpacing(TaskTheme.section,after:divider)
        let result = notify_register_dispatch(LB_READY_NOTE, &token, .main) { [weak self] _ in
            guard let self = self, self.pending else { return }; self.pending = false; self.stat("测试全屏提醒"); self.sync(); notify_post(LB_TEST_NOTE)
        }
        if result != NOTIFY_STATUS_OK { token = -1 }; sync()
        activation = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.rfrsh() }
    }
    // 导入入口复用首页模板与事务，不启用HUD服务。
    @objc private func rtnImp() {
        do {
            if routinePicker == nil { routinePicker = TaskRtnPicker(store:try TaskStore.shrd(),host:self) {} }
            routinePicker?.open()
        } catch { tu_err(self,error) }
    }
    // 连接设置保存在App内，密钥进入系统钥匙串。
    @objc private func aiCfg() { navigationController?.pushViewController(TaskAISettings(), animated: true) }
    // 更新唯一功能按钮文字。
    private func stat(_ title: String) { var config = preview.configuration; config?.title = title; preview.configuration = config }
    // 页面可见时才检查共享快照，离开后停止前台诊断。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); rfrsh()
        timer?.cancel(); let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        source.setEventHandler { [weak self] in self?.rfrsh() }; timer = source; source.resume()
    }
    // 离开页面释放检查计时与进程退出观察。
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated); timer?.cancel(); timer = nil; watcher?.cancel(); watcher = nil; watched = 0
    }
    // 显示真实进程状态和服务计算的下一时刻，拒绝遗留正常记录。
    @objc private func rfrsh() {
        monitor.isOn = (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue == true
        preview.isEnabled = monitor.isOn && !pending; recovery.isEnabled = !pending
        let value = (storeIssue?() ?? storeFailed) ? ["state":"数据库不可用"] : lb_rdstat() ?? [:]
        let title = value["state"] as? String ?? "状态不可用"
        var config = status.configuration; config?.title = title;config?.image=lb_icon((value["running"] as? NSNumber)?.boolValue == true ? "check_circle":"round"); status.configuration = config
        var plan = planned.configuration; plan?.subtitle = nil
        if let stamp = value["next_fire_at"] as? NSNumber {
            let format = DateFormatter(); format.locale = Locale(identifier: "zh_CN"); format.dateFormat = "MM-dd HH:mm"
            plan?.title = "下一提醒"; plan?.subtitle = format.string(from: Date(timeIntervalSince1970: stamp.doubleValue))
        } else { plan?.title = (value["running"] as? NSNumber)?.boolValue == true ? "无后续提醒" : "下一提醒未就绪" }
        planned.configuration = plan
        let pid = (value["running"] as? NSNumber)?.boolValue == true ? (value["pid"] as? NSNumber)?.int32Value ?? 0 : 0
        if pid != watched {
            watcher?.cancel(); watcher = nil; watched = pid
            if pid > 0 {
                let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
                source.setEventHandler { [weak self] in self?.rfrsh() }; watcher = source; source.resume()
            }
        }
    }
    // 同步服务和预览请求状态。
    private func sync() { rfrsh() }
    // 保持重启限制可见，并提供现有服务的手动恢复入口。
    @objc private func rstr() {
        guard !pending else { return }
        guard monitor.isOn else {hlp("先开启后台服务");return}
        stat(lb_spawn() ? "测试全屏提醒" : "恢复失败"); sync()
    }
    // 用悬浮对话框显示短说明，不改变服务开关。
    private func hlp(_ text:String) {
        guard presentedViewController == nil else{return}
        let alert=UIAlertController(title:text,message:nil,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"知道了",style:.cancel));present(alert,animated:false)
    }
    // 保存配置并启动或停止HUD。
    @objc private func monChg() {
        pending = false; request += 1
        if !lb_svcfg(["enabled": monitor.isOn]) { monitor.isOn.toggle(); stat("保存失败") }
        else if monitor.isOn {
            if !lb_spawn() { monitor.isOn = false; _ = lb_svcfg(["enabled": false]); stat("启动失败") } else { stat("测试全屏提醒") }
        } else { lb_svstat("服务已关闭", nil); stat("测试全屏提醒") }
        sync()
    }
    // 请求预览并等待HUD就绪。
    @objc private func tst() {
        guard token >= 0 else { stat("通信失败"); return }
        pending = true; request += 1; let current = request; sync()
        guard lb_spawn() else { pending = false; stat("启动失败"); sync(); return }
        notify_post(LB_TEST_NOTE)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, self.pending, current == self.request else { return }
            self.pending = false; self.stat("测试未响应"); self.sync()
        }
    }
    // 注销系统通知。
    deinit { timer?.cancel(); watcher?.cancel(); if let activation { NotificationCenter.default.removeObserver(activation) }; if token >= 0 { notify_cancel(token) } }
}
