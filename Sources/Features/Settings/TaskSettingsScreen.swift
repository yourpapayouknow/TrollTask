// 设置主面板：常用设置、后台服务与其他入口各一张单层卡片。
@objc(LBSetCtl) final class TaskSettingsScreen: TaskScreen {
    @objc var storeFailed = false
    @objc var storeIssue: (() -> Bool)?
    @objc var taskStore: TaskStore?
    private let monitor = UISwitch()
    private var recovery: UIButton!, draftClear: UIButton!
    private var timezone: UIButton!, look: UIButton!
    private var serviceState: UILabel!
    private var timer: DispatchSourceTimer?, watcher: DispatchSourceProcess?
    private var routinePicker: TaskRtnPicker?
    private var watched: pid_t = 0
    private var activation: NSObjectProtocol?
    private var stateText = ""
    private let nextFormat: DateFormatter = {
        let format = DateFormatter(); format.locale = Locale(identifier: "zh_CN"); format.dateFormat = "MM-dd HH:mm"; return format
    }()
    // 创建常用设置、服务控制与其他入口。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "设置"
        let heading=tu_lbl(title);heading.font=lb_fnt(.headline,traitCollection)
        let close=tu_ibtn("close","关闭设置","settings.close",self,#selector(bck))
        let header=hdr(heading,nil,close)
        monitor.onTintColor = lb_acnt(); monitor.isOn = (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue == true
        monitor.accessibilityIdentifier = "settings.enabled"; monitor.accessibilityLabel = "后台服务"; monitor.addTarget(self, action: #selector(monChg), for: .valueChanged)
        recovery = tu_btn("恢复提醒","repeat",self,#selector(rstr));recovery.accessibilityIdentifier="settings.recovery"
        let assistant=tu_btn("助手设置","robot",self,#selector(aiCfg));assistant.accessibilityIdentifier="settings.assistant"
        let routineImport=tu_btn("导入常律","file_import",self,#selector(rtnImp));routineImport.accessibilityIdentifier="settings.routineImport"
        let archive=tu_btn("归档内容","archive",self,#selector(archivePage));archive.accessibilityIdentifier="settings.archive"
        let cloud=tu_btn("归档设置","cloud",self,#selector(cloudPage));cloud.accessibilityIdentifier="settings.cloud"
        timezone=tu_btn("任务时区","time",self,#selector(zonePage));timezone.accessibilityIdentifier="settings.timezone"
        look=tu_btn("外观","palette",nil,nil);look.accessibilityIdentifier="settings.appearance"
        look.showsMenuAsPrimaryAction = true
        draftClear=tu_btn("清除编辑草稿","delete",self,#selector(clrDrft));draftClear.accessibilityIdentifier="settings.draft"
        let log=tu_btn("运行日志","documents",self,#selector(logPage));log.accessibilityIdentifier="settings.log"
        let about=tu_btn("关于","information",self,#selector(aboutPage));about.accessibilityIdentifier="settings.about"
        for button in [recovery!,assistant,routineImport,archive,cloud,timezone!,look!,draftClear!,log,about] {
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
        let serviceTitle=tu_lbl("后台服务");serviceTitle.font=lb_fnt(.body,nil)
        serviceState=tu_lbl(nil);serviceState.font=lb_fnt(.subheadline,nil);serviceState.textColor=TaskTheme.muted;serviceState.numberOfLines=0;serviceState.adjustsFontForContentSizeCategory=true;serviceState.accessibilityIdentifier="settings.serviceState"
        let labels=tu_stk([serviceTitle,serviceState]);labels.axis = .vertical;labels.spacing=4;labels.alignment = .leading;labels.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let service=tu_stk([icon,labels,monitor]);service.axis = .horizontal;service.alignment = .center;service.spacing=8;service.isLayoutMarginsRelativeArrangement=true;service.directionalLayoutMargins=NSDirectionalEdgeInsets(top:12,leading:16,bottom:12,trailing:16);service.accessibilityIdentifier="settings.service";service.heightAnchor.constraint(greaterThanOrEqualToConstant:56).isActive=true
        let mainGroup = tu_card([timezone,look,archive,cloud,assistant,routineImport])
        let serviceGroup = tu_card([service,recovery])
        let otherGroup = tu_card([draftClear,log,about])
        let fields=tu_stk([mainGroup,serviceGroup,otherGroup]);fields.spacing=TaskTheme.section
        _ = tu_form(self,fields,"settings.content",top:header)
        rfrsh()
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
        lookMenu(); lookCfg(); rfrshDraft()
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
    // 查看最近运行日志与错误。
    @objc private func logPage() { navigationController?.pushViewController(TaskLogScreen(), animated: true) }
    // 查看版本、作者与开源说明。
    @objc private func aboutPage() { navigationController?.pushViewController(TaskAboutScreen(), animated: true) }
    // 确认后清除未完成的创建草稿。
    @objc private func clrDrft() {
        guard draftClear.isEnabled else { return }
        let alert=UIAlertController(title:"清除未完成的编辑草稿",message:nil,preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"取消",style:.cancel))
        alert.addAction(UIAlertAction(title:"清除",style:.destructive){[weak self] _ in
            guard let self else { return }
            do { try (self.taskStore ?? TaskStore.shrd()).clearDraft(); TaskLog.write("已清除编辑草稿") } catch { tu_err(self,error) }
            self.rfrshDraft()
        })
        present(alert,animated:true)
    }
    // 只在存在草稿时允许清除。
    private func rfrshDraft() {
        var has = false
        if let store = taskStore ?? (try? TaskStore.shrd()), let value = try? store.draft() { has = !value.isEmpty }
        var config = draftClear.configuration; config?.subtitle = has ? "存在未完成草稿" : "无未完成草稿"; draftClear.configuration = config
        draftClear.isEnabled = has
    }
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
    // 在服务行副标题显示真实进程状态和下一时刻。
    @objc private func rfrsh() {
        let enabled = (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue == true
        if monitor.isOn != enabled { monitor.isOn = enabled }
        recovery.isEnabled = true
        var text = "状态不可用"
        if storeIssue?() ?? storeFailed { text = "数据库不可用" }
        else {
            let value = lb_rdstat() ?? [:]
            text = value["state"] as? String ?? "状态不可用"
            if (value["running"] as? NSNumber)?.boolValue == true {
                if let stamp = value["next_fire_at"] as? NSNumber { text += " · 下一提醒 " + nextFormat.string(from: Date(timeIntervalSince1970: stamp.doubleValue)) }
                else { text += " · 无后续提醒" }
            }
        }
        if text != stateText { stateText = text; serviceState.text = text }
        let pid = (lb_rdstat()?["running"] as? NSNumber)?.boolValue == true ? (lb_rdstat()?["pid"] as? NSNumber)?.int32Value ?? 0 : 0
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
        if !lb_svcfg(["enabled": monitor.isOn]) { monitor.isOn.toggle(); lb_svstat("保存失败", nil); TaskLog.write("后台服务配置保存失败") }
        else if monitor.isOn {
            if !lb_spawn() { monitor.isOn = false; _ = lb_svcfg(["enabled": false]); lb_svstat("启动失败", nil); TaskLog.write("后台服务启动失败") }
        } else { lb_svstat("服务已关闭", nil); TaskLog.write("后台服务已关闭") }
        rfrsh()
    }
    // 注销系统通知。
    deinit { timer?.cancel(); watcher?.cancel(); if let activation { NotificationCenter.default.removeObserver(activation) } }
}