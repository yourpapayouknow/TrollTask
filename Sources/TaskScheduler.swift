// 用单次绝对计时驱动同一存储中的全部待触发轮次。
@objc(TaskScheduler) final class TaskScheduler: NSObject {
    private let store: TaskStore?, handler: (NSDictionary?, NSError?) -> Void
    private let clock: () -> TimeInterval
    private let queue = DispatchQueue(label: "com.iwmei.taskforiwmei.scheduler", qos: .userInitiated)
    private let key = DispatchSpecificKey<UInt8>()
    private var timer: DispatchSourceTimer?, fire: Date?
    private let reminders = ReminderQueue()
    private var active: TaskFields? { reminders.current }
    private var tokens: [Int32] = [], epoch = 0, ticket = 0, faults = 0
    private var running = false, queued = false
    private var observers: [NSObjectProtocol] = []
    private var displayedID: String?
    private var displayed: NSDictionary?

    // 跨线程读取最近尚未触发的绝对时刻。
    @objc var nextFireAt: Date? { qsyn { fire } }
    // 接收现有Objective-C和Swift调用入口。
    @objc(initStore:handler:) convenience init(store: TaskStore?, handler: @escaping (NSDictionary?, NSError?) -> Void) {
        self.init(store: store, clock: { Date().timeIntervalSince1970 }, handler: handler)
    }
    // 隔离验证跳时，生产入口始终读取系统真实时间。
    init(store: TaskStore?, clock: @escaping () -> TimeInterval, handler: @escaping (NSDictionary?, NSError?) -> Void) {
        self.store = store; self.clock = clock; self.handler = handler; super.init(); queue.setSpecific(key: key, value: 1)
    }
    // 在调度队列上读取或修改状态。
    private func qsyn<T>(_ work: () -> T) -> T { DispatchQueue.getSpecific(key: key) == nil ? queue.sync(execute: work) : work() }
    // 解除旧计时并拒绝已经排队的旧回调。
    private func clr() { ticket += 1; timer?.cancel(); timer = nil; fire = nil }
    // 安排一次墙上时钟唤醒，回调后再核对NSDate。
    private func arm(_ date: Date) {
        let stamp = date.timeIntervalSince1970, seconds = floor(stamp)
        let deadline = DispatchWallTime(timespec: timespec(tv_sec: Int(seconds), tv_nsec: Int((stamp-seconds)*1_000_000_000)))
        let source = DispatchSource.makeTimerSource(queue: queue), expected = ticket
        source.setEventHandler { [weak self] in
            guard let self, self.running, self.ticket == expected else { return }; self.rld()
        }
        source.schedule(wallDeadline: deadline, repeating: .never, leeway: .milliseconds(100))
        timer = source; source.resume()
    }
    // 展示前核对持久化轮次和运行代际，拦截已失效结果。
    private func pub(_ alert: TaskFields?, _ error: NSError? = nil) {
        let expected = epoch
        DispatchQueue.main.async { [weak self] in
            guard let self, self.qsyn({ self.epoch == expected && (self.running || alert == nil) }) else { return }
            guard let alert else {
                if self.qsyn({ self.active == nil }) { self.displayedID = nil; self.displayed = nil; self.handler(nil, error) }; return
            }
            guard self.qsyn({ self.active?["occurrence_id"] as? String == alert["occurrence_id"] as? String }), let store = self.store else { return }
            do {
                let snapshot = try store.snapshot() as? TaskFields ?? [:]
                let task = (snapshot["tasks"] as? [TaskFields])?.first { $0["task_id"] as? String == alert["task_id"] as? String }
                let occ = (snapshot["history"] as? [TaskFields])?.first { $0["occurrence_id"] as? String == alert["occurrence_id"] as? String }
                guard let task, let occ, (task["deleted"] as? NSNumber)?.boolValue == false,
                    task["status"] as? String == "needsAction", (task["reminder_version"] as? NSNumber) == (alert["generation"] as? NSNumber),
                    occ["status"] as? String == "presented" else { self.handler(nil, nil); self.rfrsh(); return }
                // 先解除上一窗口，再展示已排队的下一轮。
                let id = alert["occurrence_id"] as? String
                if self.displayedID != nil && self.displayedID != id { self.handler(nil, nil) }
                var fresh = alert; fresh["task"] = task; fresh["occurrence"] = occ
                if error == nil && self.displayed?.isEqual(fresh as NSDictionary) == true { return }
                self.displayedID = id; self.displayed = error == nil ? fresh as NSDictionary : nil
                self.handler(fresh as NSDictionary, error)
            } catch { self.handler(nil, error as NSError); self.rfrsh() }
        }
    }
    // 故障时清除旧提醒并采用独立有界退避恢复。
    private func err(_ error: NSError) {
        reminders.clr(); faults += 1; pub(nil, error)
        arm(Date(timeIntervalSinceNow: min(30, pow(2, Double(min(faults-1, 5))))))
    }
    // 认领全部到期轮次，逐条展示，并只等待最近未来时刻。
    private func rld() {
        guard running, let store else { return }; clr()
        do {
            let now = clock()
            guard let snapshot = try store.plan(at: now) as? TaskFields else {
                throw NSError(domain: "com.iwmei.taskforiwmei.sync", code: Int(SQLITE_ERROR), userInfo: [NSLocalizedDescriptionKey:"调度数据不可用"])
            }
            let alerts = snapshot["alerts"] as? [TaskFields] ?? []
            var revision = (snapshot["revision"] as? NSNumber)?.int64Value ?? 0
            var triggered = Set((snapshot["history"] as? [TaskFields] ?? []).filter { $0["status"] as? String == "presented" }.compactMap { $0["occurrence_id"] as? String })
            var ready = alerts.filter { ($0["occurrence_id"] as? String).map { triggered.contains($0) } == true }
            for alert in alerts where (alert["remind_at"] as? NSNumber)?.doubleValue ?? .infinity <= now {
                if let id = alert["occurrence_id"] as? String, triggered.contains(id) { continue }
                guard let claimed = try store.claim(alert, revision: revision, at: clock()) as? TaskFields else { req(); return }
                if let id = claimed["occurrence_id"] as? String { triggered.insert(id) }
                ready.append(claimed)
                var failure: NSError?
                revision = store.revision(&failure)
                if let failure { throw failure }
            }
            reminders.rcl(ready)
            if let active { pub(active) } else { pub(nil) }
            if let next = alerts.first(where: { alert in
                guard let stamp = alert["remind_at"] as? NSNumber else { return false }
                return stamp.doubleValue > now && (alert["occurrence_id"] as? String).map { !triggered.contains($0) } != false
            }), let stamp = next["remind_at"] as? NSNumber {
                fire = Date(timeIntervalSince1970: stamp.doubleValue); arm(fire!)
            }
            faults = 0
        } catch { err(error as NSError) }
    }
    // 合并同一轮事件中的重复重读请求。
    private func req() {
        guard running, !queued else { return }; queued = true
        queue.async { [weak self] in guard let self else { return }; self.queued = false; self.rld() }
    }
    // 注册系统变化和提交后的Darwin通知，无周期性数据库轮询。
    @objc(start:) func strt(_ error: AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool {
        qsyn {
            if running { return true }
            guard let store else { error?.pointee = NSError(domain: "com.iwmei.taskforiwmei.sync", code: Int(SQLITE_CANTOPEN), userInfo: [NSLocalizedDescriptionKey:"存储未就绪"]); return false }
            let notes: [String] = [store.changeNote, TS_CLOCK_SET, TS_TIME_ZONE, TS_DISPLAY_ON]
            for name in notes {
                var token: Int32 = -1
                let status = name.withCString { notify_register_dispatch($0, &token, queue) { [weak self] _ in self?.req() } }
                guard status == NOTIFY_STATUS_OK else {
                    tokens.forEach { notify_cancel($0) }; tokens.removeAll()
                    error?.pointee = NSError(domain: "com.iwmei.taskforiwmei.sync", code: Int(status), userInfo: [NSLocalizedDescriptionKey:"调度通知注册失败"]); return false
                }
                tokens.append(token)
            }
            running = true; epoch += 1
            var names: [Notification.Name] = [.NSSystemClockDidChange, .NSSystemTimeZoneDidChange]
            #if os(iOS)
            names += [UIApplication.significantTimeChangeNotification, UIApplication.didBecomeActiveNotification,
                UIApplication.willEnterForegroundNotification, UIApplication.protectedDataDidBecomeAvailableNotification]
            #endif
            observers = names.map { name in NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.rfrsh() } }
            req(); return true
        }
    }
    // 外部变化立即打断并重建最近计划。
    @objc(refresh) func rfrsh() { queue.async { [weak self] in self?.req() } }
    // 当前提醒处理提交后立即计算下一条。
    @objc(act:until:occID:) func act(_ action: String, until: NSNumber?, occID: String) {
        queue.async { [weak self] in
            guard let self, self.running, self.active?["occurrence_id"] as? String == occID, let store = self.store else { return }
            do { try store.actOcc(occID, action: action, until: until); self.reminders.nxt(); self.rld() }
            catch { self.pub(self.active, error as NSError) }
        }
    }
    // 持久化收起当前轮次后才撤下全屏并重新调度。
    @objc(hold:occID:) func hld(_ mode: String, occID: String) {
        wrk(occID) { store in _ = try store.hldOcc(occID, mode: mode) }
    }
    // 主动展开持久化边栏后读取同一任务队列。
    @objc(resumeOcc:) func rsm(_ id: String) {
        queue.async { [weak self] in
            guard let self, self.running, let store = self.store else { return }
            do { try store.rsmOcc(id); self.req() }
            catch { self.pub(self.active, error as NSError) }
        }
    }
    // 证据与完成记录提交成功后才撤下当前提醒。
    @objc(check:method:image:) func chk(_ occID: String, method: String, image: Data) {
        chk(occID, attachments: [["method": method, "image": image]])
    }
    // 在唯一数据库内原子提交整组附件。
    @objc(check:attachments:) func chk(_ occID: String, attachments: [TaskFields]) {
        wrk(occID) { store in try store.chkOcc(occID, attachments: attachments) }
    }
    // 只处理仍然显示的同一轮次，失败保留原界面。
    private func wrk(_ id: String, _ work: @escaping (TaskStore) throws -> Void) {
        queue.async { [weak self] in
            guard let self, self.running, self.active?["occurrence_id"] as? String == id, let store = self.store else { return }
            do { try work(store); self.reminders.nxt(); self.rld() }
            catch { self.pub(self.active, error as NSError) }
        }
    }
    // 停止后拒绝旧计时和已排队的展示结果。
    @objc(stop) func stp() {
        qsyn {
            running = false; epoch += 1; queued = false; clr(); reminders.clr()
            tokens.forEach { notify_cancel($0) }; tokens.removeAll()
            observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll(); pub(nil)
        }
    }
    // 释放实例时解除原生系统资源。
    deinit { timer?.cancel(); tokens.forEach { notify_cancel($0) }; observers.forEach { NotificationCenter.default.removeObserver($0) } }
}
