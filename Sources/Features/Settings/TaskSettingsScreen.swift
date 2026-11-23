// 设置主面板：常用设置与后台服务诊断各一张单层卡片。
@objc(LBSetCtl) final class TaskSettingsScreen: TaskScreen {
    @objc var storeFailed = false
    @objc var storeIssue: (() -> Bool)?
    @objc var taskStore: TaskStore?
    private let monitor = UISwitch()
    private var preview: UIButton!, recovery: UIButton!
    private var timezone: UIButton!
    private var look: UIButton!
    private var status: UIButton!, planned: UIButton!, timer: DispatchSourceTimer?, watcher: DispatchSourceProcess?
    private var routinePicker: TaskRtnPicker?
    private var watched: pid_t = 0
    private var pending = false
    private var request = 0
    private var token: Int32 = -1
    private var activation: NSObjectProtocol?
    // 缓存已显示的诊断值，未变化时不重写配置。
    private var statusText = "", statusIcon = ""
    private var nextTitle = "", nextSubtitle: String?
    private let nextFormat: DateFormatter = {
        let format = DateFormatter(); format.locale = Locale(identifier: "zh_CN"); format.dateFormat = "MM-dd HH:mm"; return format
    }()
    // 创建服务控制与预览入口。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "设置"
        let heading=tu_lbl(title);heading.font=lb_fnt(.headline,traitCollection)
        let close=tu_ibtn("close","关闭设置","settings.close",self,#selector(bck))
        let header=hdr(heading,nil,close)
        monitor.onTintColor = lb_acnt(); monitor.isOn = (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue == true
        monitor.accessibilityIdentifier = "settings.enabled"; monitor.accessibilityLabel = "后台服务"; monitor.addTarget(self, action: #selector(monChg), for: .valueChanged)
        status = tu_btn("正在检查","round",self,#selector(rfrsh));status.accessibilityIdentifier="settings.status";status.accessibilityHint="点按刷新"
        planned = tu_btn("下一提醒","calendar",self,#selector(rfrsh));planned.accessibilityIdentifier="settings.next";planned.accessibilityHint="点按刷新"
        preview = tu_btn("测试全屏提醒","list",self,#selector(tst));preview.accessibilityIdentifier="settings.preview"
        recovery = tu_btn("恢复提醒","repeat",self,#selector(rstr));recovery.accessibilityIdentifier="settings.recovery"
        let assistant=tu_btn("助手设置","subtask",self,#selector(aiCfg));assistant.accessibilityIdentifier="settings.assistant"
        let routineImport=tu_btn("导入常律","folder",self,#selector(rtnImp));routineImport.accessibilityIdentifier="settings.routineImport"
        let archive=tu_btn("归档","check",self,#selector(archivePage));archive.accessibilityIdentifier="settings.archive"
        let cloud=tu_btn("云端存储","upload",self,#selector(cloudPage));cloud.accessibilityIdentifier="settings.cloud"
        timezone=tu_btn("任务时区","time",self,#selector(zonePage));timezone.accessibilityIdentifier="settings.timezone"
        look=tu_btn("外观","pic",nil,nil);look.accessibilityIdentifier="settings.appearance"
        look.showsMenuAsPrimaryAction = true
        for button in [status!,planned!,preview!,recovery!,assistant,routineImport,archive,cloud,timezone!,look!] {
            var config=button.configuration;config?.imagePadding=8;config?.background.cornerRadius=12;config?.contentInsets=NSDirectionalEdgeInsets(top:12,leading:16,bottom:12,trailing:16)
            config?.titleLineBreakMode = .byWordWrapping;config?.subtitleLineBreakMode = .byWordWrapping
            config?.imagePlacement = .leading
            config?.titleAlignment = .leading
            config?.baseForegroundColor=TaskTheme.ink
            config?.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer { attributes in var result=attributes;result.font=lb_fnt(.body,nil);return result }
            config?.subtitleTextAttributesTransformer=UIConfigurationTextAttributesTransformer { [weak button] attributes in var result=attributes;result.font=lb_fnt(.subheadline,button?.traitCollection);result.foregroundColor=TaskTheme.muted;return result }
            button.configuration=config;button.titleLabel?.numberOfLines=0;button.heightAnchor.constraint(greaterThanOrEqualToConstant:56).isActive=true
        }
        let hint="重启后打开App恢复";recovery.accessibilityHint="整机重启后需打开一次App恢复提醒服务"
        let help=UIAction(title:hint,identifier:UIAction.Identifier("settings.recovery.help")){[weak self] _ in self?.hlp(hint)}
        recovery.menu=UIMenu(children:[help])
        let icon=UIImageView(image:lb_icon("settings"));icon.tintColor=TaskTheme.ink;icon.contentMode = .scaleAspectFit;NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant:24),icon.heightAnchor.constraint(equalToConstant:24)])
        let service=tu_stk([icon,tu_lbl("后台服务"),monitor]);service.axis = .horizontal;service.alignment = .center;service.spacing=8;service.isLayoutMarginsRelativeArrangement=true;service.directionalLayoutMargins=NSDirectionalEdgeInsets(top:12,leading:16,bottom:12,trailing:16);service.accessibilityIdentifier="settings.service";service.heightAnchor.constraint(greaterThanOrEqualToConstant:56).isActive=true
        let mainGroup = tu_card([timezone,look,archive,cloud,assistant,routineImport])
        let serviceGroup = tu_card([service,status,planned,preview,recovery])
        let fields=tu_stk([mainGroup,serviceGroup]);fields.spacing=TaskTheme.section
        _ = tu_form(self,fields,"settings.content",top:header)
        let result = notify_register_dispatch(LB_READY_NOTE, &token, .main) { [weak self] _ in
            guard let self = self, self.pending else { return }; self.pending = false; self.stat("测试全屏提醒"); self.rfrsh(); notify_post(LB_TEST_NOTE)
        }
        if result != NOTIFY_STATUS_OK { token = -1 }; rfrsh()
        activation = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.rfrsh() }
    }
    // 打开新任务的默认时区选择。
    @objc private func zonePage() { navigationController?.pushViewController(TaskTimeZoneScreen(), animated: true) }
    // 构建外观三项菜单并标记当前选择。
    private func lookMenu() {
        look.menu = UIMenu(children: TaskLook.names.enumerated().map { index, name in
            let action = tu_act(name, nil, "settings.appearance.\(index)") { [weak self] in TaskLook.pick(index); self?.lookCfg() }
            return action
        })
    }
    // 锁定标题，副标题与勾选只显示一次当前选择。
    private func lookCfg() {
        let name = TaskLook.names[TaskLook.index]
        if var config = look.configuration {
            config.title = "外观"
            config.subtitle = TaskLook.index == 0 ? "系统" : name
            look.configuration = config
        }
        look.accessibilityValue = name
        (look.menu?.children as? [UIAction])?.forEach { $0.state = $0.title == name ? .on : .off }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        timezone.configuration?.subtitle = TaskTimeZone.fixed.map(TaskTimeZone.city) ?? "跟随系统"
        lookMenu(); lookCfg()
    }
    // 导入入口复用首页模板与事务，不启用HUD服务。
    @objc private func rtnImp() {
        do {
            if routinePicker == nil { routinePicker = TaskRtnPicker(store:try TaskStore.shrd(),host:self) {} }
            routinePicker?.open()
        } catch { tu_err(self,error) }
    }
    // 连接设置保存在App内，密钥进入系统钥匙串。
    @objc private func aiCfg() { navigationController?.pushViewController(TaskAISettingsScreen(), animated: true) }
    // 查看常律和普通待办的归档记录。
    @objc private func archivePage() {
        do { navigationController?.pushViewController(TaskArchiveScreen(store: try taskStore ?? TaskStore.shrd()), animated: true) }
        catch { tu_err(self, error) }
    }
    // 管理当前归档位置和已验证的连接。
    @objc private func cloudPage() {
        do { navigationController?.pushViewController(TaskCloudScreen(store: try taskStore ?? TaskStore.shrd()), animated: true) }
        catch { tu_err(self, error) }
    }
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
        let enabled = (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue == true
        if monitor.isOn != enabled { monitor.isOn = enabled }
        preview.isEnabled = enabled && !pending; recovery.isEnabled = !pending
        let value = (storeIssue?() ?? storeFailed) ? ["state":"数据库不可用"] : lb_rdstat() ?? [:]
        let title = value["state"] as? String ?? "状态不可用"
        let icon = (value["running"] as? NSNumber)?.boolValue == true ? "check_circle" : "round"
        if title != statusText || icon != statusIcon {
            statusText = title; statusIcon = icon
            var config = status.configuration; config?.title = title; config?.image = lb_icon(icon); status.configuration = config
        }
        var planTitle = "下一提醒"; var planSubtitle: String?
        if let stamp = value["next_fire_at"] as? NSNumber {
            planSubtitle = nextFormat.string(from: Date(timeIntervalSince1970: stamp.doubleValue))
        } else { planTitle = (value["running"] as? NSNumber)?.boolValue == true ? "无后续提醒" : "下一提醒未就绪" }
        if planTitle != nextTitle || planSubtitle != nextSubtitle {
            nextTitle = planTitle; nextSubtitle = planSubtitle
            var plan = planned.configuration; plan?.title = planTitle; plan?.subtitle = planSubtitle; planned.configuration = plan
        }
        let pid = (value["running"] as? NSNumber)?.boolValue == true ? (value["pid"] as? NSNumber)?.int32Value ?? 0 : 0
        if pid != watched {
            watcher?.cancel(); watcher = nil; watched = pid
            if pid > 0 {
                let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
                source.setEventHandler { [weak self] in self?.rfrsh() }; watcher = source; source.resume()
            }
        }
    }
    // 保持重启限制可见，并提供现有服务的手动恢复入口。
    @objc private func rstr() {
        guard !pending else { return }
        guard monitor.isOn else {hlp("先开启后台服务");return}
        if !lb_spawn() { tu_err(self, NSError(domain:"com.iwmei.taskforiwmei.ui",code:1,userInfo:[NSLocalizedDescriptionKey:"恢复失败"])) }
        rfrsh()
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
        rfrsh()
    }
    // 请求预览并等待HUD就绪。
    @objc private func tst() {
        guard token >= 0 else { stat("通信失败"); return }
        pending = true; request += 1; let current = request; rfrsh()
        guard lb_spawn() else { pending = false; stat("启动失败"); rfrsh(); return }
        notify_post(LB_TEST_NOTE)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, self.pending, current == self.request else { return }
            self.pending = false; self.stat("测试未响应"); self.rfrsh()
        }
    }
    // 注销系统通知。
    deinit { timer?.cancel(); watcher?.cancel(); if let activation { NotificationCenter.default.removeObserver(activation) }; if token >= 0 { notify_cancel(token) } }
}