// 独立提醒服务统一持有并释放进程资源。
@objc(TaskReminder) final class TaskReminder: NSObject {
    private let path: String, handler: (NSDictionary?, NSError?) -> Void
    private let cleanup: () -> Void, finish: (Bool) -> Void
    private var store: TaskStore?, scheduler: TaskScheduler?
    private var lock: Int32 = -1, tokens: [Int32] = []
    private var signals: [DispatchSourceSignal] = [], restores: [() -> Void] = [], ended = false
    @objc private(set) var running = false
    // 为采集交接复用服务已有的唯一数据库连接。
    var captureStore: TaskStore? { store }
    // 读取同一生产调度器的最近绝对时刻。
    @objc var nextFireAt: Date? { scheduler?.nextFireAt }
    // 注入已有系统窗口与进程边界，不建立第二套呈现逻辑。
    @objc(initAt:handler:cleanup:finish:) init(path: String, handler: @escaping (NSDictionary?, NSError?) -> Void, cleanup: @escaping () -> Void, finish: @escaping (Bool) -> Void) {
        self.path = path; self.handler = handler; self.cleanup = cleanup; self.finish = finish; super.init()
    }
    // 返回明确服务启动错误。
    private func err(_ error: AutoreleasingUnsafeMutablePointer<NSError?>?, _ code: Int32, _ message: String) -> Bool {
        error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey:message]); return false
    }
    // 注册控制通知，正常关闭先清理再退出。
    private func reg(_ name: String, _ work: @escaping () -> Void) throws {
        var token: Int32 = -1
        let result = name.withCString { notify_register_dispatch($0, &token, .main) { _ in work() } }
        guard result == NOTIFY_STATUS_OK else { throw NSError(domain: "com.iwmei.taskforiwmei.service", code: Int(result), userInfo: [NSLocalizedDescriptionKey:"服务通知注册失败"]) }
        tokens.append(token)
    }
    // 在私有UIKit初始化前建立单一服务与可释放的数据库连接。
    @objc(open:) func opn(_ error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool {
        if lock >= 0 { return true }
        guard !ended, (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue == true else { return err(error, ECANCELED, "提醒服务已关闭") }
        lock = lb_lckhud()
        guard lock >= 0 else {
            let code = errno; if code != EWOULDBLOCK { lb_svstat("服务锁不可用", nil) }
            return err(error, code, "提醒服务锁不可用")
        }
        lb_svstat("启动中", nil)
        var stage = "数据库不可用"
        do {
            store = try TaskStore(at: path)
            try store?.delCap(nil)
            stage = "服务通信失败"
            try reg(LB_STOP_NOTE) { [weak self] in self?.halt() }
            try reg(LB_CFG_NOTE) { [weak self] in if (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue != true { self?.halt(true) } }
            try reg(TS_SB_LAUNCH) { [weak self] in self?.halt(true) }
            for number in [SIGTERM, SIGINT] {
                let previous = signal(number, SIG_IGN); restores.append { _ = signal(number, previous) }
                let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
                source.setEventHandler { [weak self] in self?.halt() }; signals.append(source); source.resume()
            }
            return true
        } catch let issue { lb_svstat(stage, nil); stp(); error?.pointee = issue as NSError; return false }
    }
    // 启动唯一调度核心并在窗口可用后确认就绪。
    @objc(start:) func strt(_ error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool {
        if running { return true }
        guard opn(error), let store else { return false }
        guard (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue == true else { stp(); return err(error, ECANCELED, "提醒服务已关闭") }
        let scheduler = TaskScheduler(store: store, handler: handler)
        scheduler.onPlan = { next, active, error in
            lb_svstat(error == nil ? (active ? "正在提醒" : "正在运行") : "调度读取失败", next.map { NSNumber(value: $0.timeIntervalSince1970) })
        }
        guard scheduler.strt(error) else { lb_svstat("调度启动失败", nil); stp(); return false }
        self.scheduler = scheduler; running = true; notify_post(LB_READY_NOTE); return true
    }
    // 转交当前提醒动作并复用事务后重排。
    @objc(act:until:occID:) func act(_ action: String, until: NSNumber?, occID: String) { scheduler?.act(action, until: until, occID: occID) }
    // 为HUD读取同一服务连接的轻量快照。
    @objc(snapshot:) func snap(_ error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSDictionary? {
        guard let store else { return nil }
        do { return try store.snapshot() as NSDictionary } catch let issue { error?.pointee = issue as NSError; return nil }
    }
    // 转交当前轮次的持久化边栏操作。
    @objc(hold:occID:) func hld(_ mode: String, occID: String) { scheduler?.hld(mode, occID: occID) }
    // 提交边栏主动展开请求。
    @objc(resumeOcc:) func rsm(_ id: String) { scheduler?.rsm(id) }
    // 转交有效图片提交到同一串行调度器。
    @objc(check:method:image:) func chk(_ occID: String, method: String, image: Data) { chk(occID, attachments: [["method": method, "image": image]]) }
    // 提交同一提醒的全部附件。
    @objc(check:attachments:) func chk(_ occID: String, attachments: [TaskFields]) { scheduler?.chk(occID, attachments: attachments) }
    // 显式解除计时、数据库、窗口和锁，重复停止保持幂等。
    @objc(stop) func stp() {
        guard !ended else { return }; ended = true; running = false
        scheduler?.stp(); scheduler = nil
        do { try store?.delCap(nil) } catch { NSLog("采集请求清理失败：%@", error as NSError) }
        notify_post(TS_CAPTURE_NOTE); store = nil
        tokens.forEach { notify_cancel($0) }; tokens.removeAll()
        signals.forEach { $0.cancel() }; signals.removeAll()
        if lock >= 0 { cleanup(); close(lock); lock = -1 }
        restores.forEach { $0() }; restores.removeAll()
    }
    // 配置停用后复核最新启用意图，显式停止不自动恢复。
    private func halt(_ reenable: Bool = false) {
        guard lock >= 0, !ended else { return }; stp()
        finish(reenable && (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue == true)
    }
    // 释放未显式关闭的实例。
    deinit { stp() }
}
