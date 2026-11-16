// 声振时限独立于任务完成与延后状态。
struct SignalPlan {
    let limit: Double, pulses: Int
    // 未评估沿用中档，不通过难度改变强制规则。
    init(_ urgency: Int) {
        switch urgency { case 1: limit = 5; pulses = 1; case 3: limit = 30; pulses = 6; default: limit = 15; pulses = 3 }
    }
    // 双时钟限制重启后的剩余时长，异常或跨启动时钟直接静音。
    func remaining(_ row: TaskFields, wall: Double, uptime: Double) -> Double {
        guard (row["signal_ack"] as? NSNumber)?.boolValue == false,
              let start = (row["signal_at"] as? NSNumber)?.doubleValue,
              let boot = (row["signal_uptime"] as? NSNumber)?.doubleValue,
              [start, boot, wall, uptime].allSatisfy({ $0.isFinite }), wall >= start, uptime >= boot else { return 0 }
        return max(0, limit - max(wall - start, uptime - boot))
    }
    // 续播仅使用剩余段数，音频服务自身也有有限结束点。
    func playback(_ remaining: Double) -> (offset: Double, loops: Int) {
        let elapsed = max(0, limit - min(limit, remaining))
        return (elapsed.truncatingRemainder(dividingBy: 5), max(0, Int(limit / 5) - Int(elapsed / 5) - 1))
    }
    // 后续震动沿首次声振时刻对齐，恢复不补发已进入的时间段。
    func ticks(_ remaining: Double) -> (first: Double, count: Int) {
        let elapsed = max(0, limit - min(limit, remaining)), slot = Int(elapsed / 5) + 1
        return (Double(slot) * 5 - elapsed, max(0, pulses - slot))
    }
}

// 用方向变化与抬起后短暂稳定过滤桌面震动，不判断任务完成。
struct PickupGate {
    private var baseline: (Double, Double, Double)?, moved: Double?, settled: Double?, last = -Double.infinity
    // 接收重力与去重力加速度，拒绝旧样本和异常数据。
    mutating func sample(_ at: Double, gravity g: (Double, Double, Double), acceleration a: (Double, Double, Double)) -> Bool {
        guard [at, g.0, g.1, g.2, a.0, a.1, a.2].allSatisfy({ $0.isFinite }), at > last else { return false }
        last = at
        guard let base = baseline else { baseline = g; return false }
        let turn = base.0*g.0 + base.1*g.1 + base.2*g.2
        let motion = sqrt(a.0*a.0 + a.1*a.1 + a.2*a.2)
        if turn < 0.9 && motion > 0.15 { moved = at; settled = nil }
        guard let moved, at - moved < 2, g.1 < -0.25, abs(g.2) < 0.9, turn < 0.9, motion < 0.1 else { settled = nil; return false }
        if settled == nil { settled = at }
        return at - settled! >= 0.4
    }
}

#if os(iOS)
// 原生声振只在当前全屏呈现期间运行，私有串行队列承担硬截止。
final class TaskSignal {
    private let queue = DispatchQueue(label: "com.iwmei.taskforiwmei.signal")
    private var player: AVAudioPlayer?, motion: CMMotionManager?, beat: DispatchSourceTimer?, deadline: DispatchSourceTimer?
    private var key: String?, store: TaskStore?, occurrence: String?, trigger: NSNumber?, active = false, audio = false
    private var gate = PickupGate(), observer: NSObjectProtocol?, generation = 0
#if LB_UI_TEST
    private var audioProbe = false, pulseCount = 0, starts = 0
    private var reason = "", audioInfo: TaskFields = [:]
    // 只在隔离模拟器测试启用原生播放器，输出音量固定为零。
    func probeAudio(_ enabled: Bool) { queue.sync { audioProbe = enabled } }
    // 读取同一生产实例的资源和调度状态。
    func probe() -> TaskFields {
        queue.sync { ["active":active,"generation":generation,"pulses":pulseCount,"starts":starts,"reason":reason,
                      "playing":player?.isPlaying ?? false,"audio":audio,"beat":beat != nil,"deadline":deadline != nil,"audioInfo":audioInfo] }
    }
    // 模拟器样本进入与Core Motion共用的回调入口。
    func probeSample(_ fields: TaskFields) {
        guard let time = fields["time"] as? Double, let gravity = fields["gravity"] as? [Double], let acceleration = fields["acceleration"] as? [Double],
              let run = fields["generation"] as? Int, gravity.count == 3, acceleration.count == 3 else { return }
        queue.async { [weak self] in self?.sample(time, gravity: (gravity[0],gravity[1],gravity[2]), acceleration: (acceleration[0],acceleration[1],acceleration[2]), run: run) }
    }
#endif
    // 保存当前呈现的首次声振时刻，重复事件不重新播放。
    func present(_ alert: TaskFields, store: TaskStore?) {
        guard let store, let id = alert["occurrence_id"] as? String, let row = alert["occurrence"] as? TaskFields,
              let trigger = row["triggered_at"] as? NSNumber else { return }
        let task = alert["task"] as? TaskFields ?? [:]
        queue.async { [weak self] in
            guard let self else { return }; let key = id + ":" + trigger.stringValue
            guard self.key != key else { return }; self.clear(); self.key = key; self.store = store; self.occurrence = id; self.trigger = trigger
            do {
                guard let state = try store.sigOcc(id, trigger: trigger, ack: false) as? TaskFields else { return }
                let plan = SignalPlan((task["urgency"] as? NSNumber)?.intValue ?? 0)
                let left = plan.remaining(state, wall: Date().timeIntervalSince1970, uptime: ProcessInfo.processInfo.systemUptime)
                guard left > 0 else { return }; self.play(plan, remaining: left, fresh: (state["signal_new"] as? NSNumber)?.boolValue == true)
            } catch { NSLog("声振状态不可用：%@", error as NSError) }
        }
    }
    // 预览使用纯内存时限，不向正常任务库写入。
    func preview() { queue.async { [weak self] in self?.clear(); self?.key = "preview"; self?.play(SignalPlan(0), remaining: 15, fresh: true) } }
    // 操作与抬起只静音，写入同一轮呈现的确认标记。
    func quiet() { queue.async { [weak self] in self?.ack("interaction") } }
    // 隐藏与服务退出释放资源，不把未处理任务标为完成。
    func stop() { queue.async { [weak self] in self?.clear(); self?.key = nil } }
    // 在原生音频中使用有限循环，主线程阻塞也不会无限播放。
    private func play(_ plan: SignalPlan, remaining: Double, fresh: Bool) {
        active = true; gate = PickupGate(); let run = generation, began = ProcessInfo.processInfo.systemUptime
#if LB_UI_TEST
        pulseCount = 0; starts += 1; reason = ""; audioInfo = [:]
#endif
        let end = DispatchSource.makeTimerSource(queue: queue); deadline = end
        end.schedule(deadline: .now() + remaining); end.setEventHandler { [weak self] in
            guard let self, self.generation == run else { return }; self.ack("timeout")
        }; end.resume()
#if !LB_UI_TEST
        ring(plan, remaining: remaining)
#else
        if audioProbe { ring(plan, remaining: remaining) }
#endif
        let left = max(0, remaining - (ProcessInfo.processInfo.systemUptime - began))
        guard left > 0 else { ack("timeout"); return }
        if fresh { pulse() }
        let ticks = plan.ticks(left)
        if ticks.count > 0 {
            var pulses = ticks.count
            let timer = DispatchSource.makeTimerSource(queue: queue); beat = timer
            timer.schedule(deadline: .now() + ticks.first, repeating: 5)
            timer.setEventHandler { [weak self] in
                guard let self, self.active, self.generation == run, pulses > 0 else { return }; pulses -= 1; self.pulse()
                if pulses == 0 { self.beat?.cancel(); self.beat = nil }
            }; timer.resume()
        }
#if !LB_UI_TEST
        let motion = CMMotionManager(); self.motion = motion
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.1
            let updates = OperationQueue(); updates.maxConcurrentOperationCount = 1; updates.underlyingQueue = queue
            var received = false
            motion.startDeviceMotionUpdates(to: updates) { [weak self] data, error in
                guard let self, self.active, self.generation == run else { return }
                guard let data, error == nil else { NSLog("抬起检测不可用：%@", String(describing: error)); self.motion?.stopDeviceMotionUpdates(); self.motion = nil; return }
                if !received { received = true; NSLog("ReminderSignal motion ready") }
                let g = data.gravity, a = data.userAcceleration
                self.sample(data.timestamp, gravity: (g.x,g.y,g.z), acceleration: (a.x,a.y,a.z), run: run)
            }
        }
#endif
        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in guard let self, self.generation == run else { return }; self.ack("interruption") }
        }
        NSLog("ReminderSignal started %.2fs", remaining)
    }
    // 调度与马达输出分开，模拟器仅记录同一触发点的次数。
    private func pulse() {
#if LB_UI_TEST
        pulseCount += 1
#else
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
#endif
    }
    // 丢弃退役呈现的样本，当前抬起仅确认声振。
    private func sample(_ time: Double, gravity: (Double,Double,Double), acceleration: (Double,Double,Double), run: Int) {
        guard active, generation == run else { return }
        if gate.sample(time, gravity: gravity, acceleration: acceleration) { ack("pickup") }
    }
    // 播放失败立即释放音频占用，震动与截止仍可独立运行。
    private func ring(_ plan: SignalPlan, remaining: Double) {
        do {
            guard let url = Bundle.main.url(forResource: "Reminder", withExtension: "wav") else { throw NSError(domain: "ReminderSignal", code: 1) }
            let session = AVAudioSession.sharedInstance(); try session.setCategory(.playback, options: [.duckOthers]); try session.setActive(true); audio = true
            let player = try AVAudioPlayer(contentsOf: url), playback = plan.playback(remaining)
            player.numberOfLoops = playback.loops; player.currentTime = playback.offset; player.volume = 0.6; self.player = player
#if LB_UI_TEST
            player.volume = 0
#endif
            guard player.play() else { throw NSError(domain: "ReminderSignal", code: 2) }
#if LB_UI_TEST
            audioInfo = ["duration":player.duration,"loops":player.numberOfLoops,"offset":player.currentTime,"volume":player.volume]
#endif
        } catch { endAudio(); NSLog("铃声不可用：%@", error as NSError) }
    }
    // 先停声音再释放系统会话，失败路径与正常退出共用。
    private func endAudio() {
        player?.stop(); player = nil
        if audio { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); audio = false }
    }
    // 本地先停声振，持久化失败也不恢复响铃。
    private func ack(_ reason: String) {
        guard active else { return }
#if LB_UI_TEST
        self.reason = reason
#endif
        NSLog("ReminderSignal quiet %@", reason)
        let store = store, id = occurrence, trigger = trigger; clear()
        if let store, let id, let trigger {
            do { _ = try store.sigOcc(id, trigger: trigger, ack: true) } catch { NSLog("声振静音保存失败：%@", error as NSError) }
        }
    }
    // 释放所有计时器、传感器、声音和音频占用。
    private func clear() {
        generation += 1; active = false; deadline?.cancel(); deadline = nil; beat?.cancel(); beat = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
        endAudio(); motion?.stopDeviceMotionUpdates(); motion = nil
        store = nil; occurrence = nil; trigger = nil
    }
    // 实例销毁不能留下独立音频或传感器回调。
    deinit { clear() }
}
#endif
