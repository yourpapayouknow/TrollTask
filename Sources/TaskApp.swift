#if !LB_UI_TEST
// 保留原生UIApplicationDelegate入口并用Swift创建主页。
@objc(LBAppDel) final class TaskApp: UIResponder, UIApplicationDelegate {
    @objc var window: UIWindow?
    private var store: TaskStore?
    // 启动共享存储和已启用的独立HUD。
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        do { store = try TaskStore.shrd() } catch { NSLog("TaskStore初始化失败：%@", error as NSError) }
        let home = TaskHome(store: store) { $0.pushViewController(TaskSettings(), animated: true) }
        let navigation = UINavigationController(rootViewController: home); navigation.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: UIScreen.main.bounds); window.rootViewController = navigation; self.window = window; window.makeKeyAndVisible()
        if store != nil, (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue == true { _ = lb_spawn() }
        return true
    }
}
#endif

// 通过原生Darwin通信控制既有独立HUD。
@objc(LBSetCtl) final class TaskSettings: TaskScreen {
    private let monitor = UISwitch()
    private var preview: UIButton!
    private var pending = false
    private var request = 0
    private var token: Int32 = -1
    // 创建服务控制与预览入口。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "TrollTask"
        monitor.onTintColor = lb_acnt(); monitor.isOn = (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue == true
        monitor.accessibilityIdentifier = "settings.enabled"; monitor.addTarget(self, action: #selector(monChg), for: .valueChanged)
        preview = lb_mkbtn("预览浮层", self, #selector(tst)); preview.accessibilityIdentifier = "settings.preview"
        let fields = tu_stk([tu_row("后台服务", monitor), preview]); view.addSubview(fields); tu_wdth(fields, view)
        fields.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4).isActive = true
        let result = notify_register_dispatch(LB_READY_NOTE, &token, .main) { [weak self] _ in
            guard let self = self, self.pending else { return }; self.pending = false; self.stat("预览浮层"); self.sync(); notify_post(LB_TEST_NOTE)
        }
        if result != NOTIFY_STATUS_OK { token = -1 }; sync()
    }
    // 更新唯一功能按钮文字。
    private func stat(_ title: String) { var config = preview.configuration; config?.title = title; preview.configuration = config }
    // 同步服务和预览请求状态。
    private func sync() { preview.isEnabled = monitor.isOn && !pending }
    // 保存配置并启动或停止HUD。
    @objc private func monChg() {
        pending = false; request += 1
        if !lb_svcfg(["enabled": monitor.isOn]) { monitor.isOn.toggle(); stat("保存失败") }
        else if monitor.isOn {
            if !lb_spawn() { monitor.isOn = false; _ = lb_svcfg(["enabled": false]); stat("启动失败") } else { stat("预览浮层") }
        } else { stat("预览浮层") }
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
            self.pending = false; self.stat("预览未响应"); self.sync()
        }
    }
    // 注销系统通知。
    deinit { if token >= 0 { notify_cancel(token) } }
}
