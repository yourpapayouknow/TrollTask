// 验证真实数据库身份、补弹和终态去重。
@main struct RecoveryTests {
    private static var checks = 0
    private static var shown: TaskFields?, events = 0, failures = 0
    // 输出明确失败原因。
    private static func req(_ valid: Bool, _ message: String) {
        if !valid { print("Recovery failure: \(message)"); fflush(stdout); exit(1) }; checks += 1
    }
    // 驱动真实主线程回调并限制等待时间。
    private static func wt(_ message: String, _ check: () -> Bool) {
        let end = Date(timeIntervalSinceNow: 2)
        while !check() && end.timeIntervalSinceNow > 0 { _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
        req(check(), message)
    }
    // 接收生产调度器实际发布的结果。
    private static func evt(_ alert: NSDictionary?, _ error: NSError?) {
        shown = alert as? TaskFields; if alert != nil { events += 1 }; if error != nil { failures += 1 }
    }
    // 读取完整持久化记录。
    private static func rows(_ store: TaskStore, _ task: String) throws -> [TaskFields] { try store.lsOcc(task) as? [TaskFields] ?? [] }
    // 建立使用原有存储校验的测试任务。
    private static func mk(_ store: TaskStore, _ at: TimeInterval, _ repeatDaily: Bool = false) throws -> String {
        var fields: TaskFields = ["title":"恢复验收", "due_at":at, "timezone_id":"UTC"]
        if repeatDaily { fields["recurrence_type"] = "daily" }
        return (try store.crtTsk(fields))["task_id"] as! String
    }
    // 按真实事件渠道唤醒，不向系统公共通知名发测试事件。
    private static func post(_ name: String) { name.withCString { _ = notify_post($0) } }
    // 核对前跳补弹、后跳保持、重复事件及Resolved恢复。
    private static func jumps(_ store: TaskStore, _ clock: TestClock, _ base: TimeInterval) throws {
        let ids = try [5.0, 10, 20].map { try mk(store, base + $0) }
        let scheduler = TaskScheduler(store: store, clock: clock.rd, handler: evt)
        req(scheduler.strt(nil), "调度启动")
        wt("未来任务按绝对时间等待") { scheduler.nextFireAt?.timeIntervalSince1970 == base + 5 }
        clock.set(base + 30); post(TS_CLOCK_SET)
        wt("前跳后所有已到期任务立即认领") { ids.allSatisfy { (try? rows(store, $0).count) == 1 } && shown?["task_id"] as? String == ids[0] }
        let original = try rows(store, ids[0])[0], first = original["occurrence_id"] as! String
        let count = events
        clock.set(base - 30)
        for _ in 0..<50 { post(TS_CLOCK_SET); NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil); scheduler.rfrsh() }
        var settled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { settled = true }
        wt("后跳事件全部处理") { settled }
        req(shown?["occurrence_id"] as? String == first && events == count, "后跳与重复事件不得重新呈现同一轮次")
        req((try rows(store, ids[0])[0]["triggered_at"] as? NSNumber) == (original["triggered_at"] as? NSNumber), "后跳不重写原触发时刻")
        clock.set(base + 30)
        let extra = try mk(store, base + 100)
        wt("新任务安排在未来") { scheduler.nextFireAt?.timeIntervalSince1970 == base + 100 }
        clock.set(base + 120); post(TS_TIME_ZONE)
        wt("独立时区事件也执行当前时间补算") { (try? rows(store, extra).count) == 1 }
        req(shown?["occurrence_id"] as? String == first, "新到期提醒不抢占当前项")
        for id in ids + [extra] {
            wt("原定时间顺序处理") { shown?["task_id"] as? String == id }
            let occurrence = shown?["occurrence_id"] as! String
            scheduler.act("complete", until: nil, occID: occurrence)
            wt("单条完成只推进一次") { shown?["occurrence_id"] as? String != occurrence }
        }
        scheduler.stp(); shown = nil
        clock.set(base - 100); req(scheduler.strt(nil), "后跳后重启")
        clock.set(base + 1000); post(TS_DISPLAY_ON)
        var recovered = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { recovered = true }
        wt("Resolved恢复事件已经处理") { recovered }
        for id in ids + [extra] { req(try rows(store, id).count == 1 && rows(store, id)[0]["status"] as? String == "resolved", "已处理轮次不能复活") }
        req(shown == nil, "已Resolved无窗口"); scheduler.stp()
    }
    // 跨过多天后保留既有Pending，不被最近重复周期吞掉。
    private static func pending(_ store: TaskStore, _ clock: TestClock, _ base: TimeInterval) throws {
        clock.set(base + 2); let task = try mk(store, base + 1, true)
        let scheduler = TaskScheduler(store: store, clock: clock.rd, handler: evt)
        req(scheduler.strt(nil), "重复恢复启动"); wt("首轮呈现") { shown?["task_id"] as? String == task }
        scheduler.act("complete", until: nil, occID: shown?["occurrence_id"] as! String)
        wt("下一轮Pending已持久化") { (try? rows(store, task).contains { $0["status"] as? String == "pending" }) == true && shown == nil }
        let next = try rows(store, task).first { $0["status"] as? String == "pending" }!["occurrence_id"] as! String
        scheduler.stp(); clock.set(base + 5 * 86400 + 100); req(scheduler.strt(nil), "跨休眠天数重新启动")
        wt("恢复最早未处理Pending而非丢弃") { shown?["occurrence_id"] as? String == next }
        for day in 1...5 {
            wt("积压重复轮次逐日处理") { (shown?["scheduled_at"] as? NSNumber)?.doubleValue == base + 1 + Double(day) * 86400 }
            scheduler.act("complete", until: nil, occID: shown?["occurrence_id"] as! String)
        }
        wt("积压清空后等待下一未来轮次") { shown == nil }
        req(try rows(store, task).filter { $0["status"] as? String == "resolved" }.count == 6, "六轮各完成一次")
        scheduler.stp(); try store.delTsk(task)
    }
    // Snoozed跨过休眠期限仍用原身份补弹并保留单次额度。
    private static func snoozed(_ store: TaskStore, _ clock: TestClock) throws {
        let now = Date().timeIntervalSince1970, task = try mk(store, now - 1)
        let plan = try store.plan(at: now) as! TaskFields
        let candidate = (plan["alerts"] as! [TaskFields]).first { $0["task_id"] as? String == task }!
        let alert = try store.claim(candidate, revision: (plan["revision"] as! NSNumber).int64Value, at: now) as! TaskFields
        let id = alert["occurrence_id"] as! String, hold = try store.hldOcc(id, mode: "snooze")
        clock.set(now);let scheduler = TaskScheduler(store: store, clock: clock.rd, handler: evt)
        req(scheduler.strt(nil), "延期恢复启动")
        wt("延期未到不能提前呈现") { scheduler.nextFireAt != nil }
        req(shown == nil, "延期仍收起")
        clock.set((hold["hold_until"] as! NSNumber).doubleValue + 1);post(TS_DISPLAY_ON)
        wt("唤醒立即补弹已过期延期") { shown?["occurrence_id"] as? String == id }
        req((try rows(store, task)[0]["defer_count"] as? NSNumber)?.intValue == 1, "休眠恢复不重置延期额度")
        scheduler.act("complete", until: nil, occID: id);wt("延期任务完成") { shown == nil };scheduler.stp()
    }
    // 让原生计时事件重复投递，不能用refresh替代timer覆盖。
    private static func timers(_ store: TaskStore, _ clock: TestClock, _ base: TimeInterval) throws {
        clock.set(base); let first = try mk(store, base-2), second = try mk(store, base-1), future = try mk(store, base+60)
        let scheduler = TaskScheduler(store: store, clock: clock.rd, handler: evt)
        var fired = 0, delivered = 0
        scheduler.onArm = { timer in
            if fired < 30 { timer.schedule(deadline: .now(), repeating: .never) }
            return { fired += 1 }
        }
        scheduler.onPlan = { _, _, _ in
            let count = fired; DispatchQueue.main.async { delivered = count }
        }
        req(scheduler.strt(nil), "原生timer风暴启动")
        wt("三十次真实计时事件完成重算") { delivered >= 30 && shown?["task_id"] as? String == first }
        req(delivered == 30, "直接统计三十次原生timer处理回调")
        let rowsBefore = try rows(store, first), id = rowsBefore[0]["occurrence_id"] as! String, count = events
        req(try rows(store, future).isEmpty, "早到timer必须重新核对真实时刻，不提前认领未来任务")
        req(try rows(store, second).count == 1 && rowsBefore.count == 1, "重复timer只认领每个已到期轮次一次")
        for _ in 0..<50 { post(store.changeNote) }
        var settled = false; DispatchQueue.main.asyncAfter(deadline: .now()+0.15) { settled = true }
        wt("timer后Darwin风暴处理完毕") { settled }
        req(events == count && shown?["occurrence_id"] as? String == id, "timer与Darwin重放均不重复呈现")
        req(try rows(store, first) as NSArray == rowsBefore as NSArray, "重复事件不改写原Occurrence")
        scheduler.stp(); scheduler.onArm = nil
        for task in [first,second,future] { try store.delTsk(task) }
        print("Native timer: 30 actual deliveries, 50 Darwin posts; no early claim or duplicate occurrence")
    }
    // 主线程尚未消费呈现结果时，停止和完成必须取消旧结果。
    private static func delivery(_ store: TaskStore, _ clock: TestClock, _ base: TimeInterval) throws {
        clock.set(base); let task = try mk(store, base-1), before = events
        let scheduler = TaskScheduler(store: store, clock: clock.rd, handler: evt)
        req(scheduler.strt(nil), "排队呈现启动")
        _ = scheduler.nextFireAt // 同步屏障保证调度已结束，主线程尚未消费呈现。
        let id = try rows(store, task)[0]["occurrence_id"] as! String
        scheduler.stp()
        var stopped = false; DispatchQueue.main.async { stopped = true }
        wt("停止后的主线程结果已消费") { stopped }
        req(shown == nil && events == before, "停止必须取消尚未交付的旧提醒")
        req(scheduler.strt(nil), "取消呈现后重新启动")
        wt("恢复原先已认领的轮次") { shown?["occurrence_id"] as? String == id && events == before+1 }
        scheduler.stp(); req(scheduler.strt(nil), "同一实例立即停止重启")
        wt("重新启动必须重新交付相同轮次") { shown?["occurrence_id"] as? String == id && events == before+2 }
        scheduler.stp(); req(scheduler.strt(nil), "完成前重新排队呈现")
        _ = scheduler.nextFireAt
        scheduler.act("complete", until: nil, occID: id)
        _ = scheduler.nextFireAt // 等待完成事务取消旧呈现，仍不运行主线程队列。
        var completed = false; DispatchQueue.main.async { completed = true }
        wt("完成后的主线程结果已消费") { completed }
        req(shown == nil && events == before+2, "完成必须取消尚未交付的提醒，不能闪回旧弹窗")
        req(try rows(store, task).count == 1 && rows(store, task)[0]["status"] as? String == "resolved", "取消呈现仍只完成同一轮次一次")
        scheduler.stp()
    }
    // 仅使用临时数据库与受控时钟。
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trolltask-recover-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try TaskStore(at: folder.appendingPathComponent("tasks.sqlite3").path)
        let base = floor(Date().timeIntervalSince1970) + 3600, clock = TestClock(base)
        try jumps(store, clock, base);try pending(store, clock, base);try snoozed(store, clock);try timers(store, clock, base);try delivery(store, clock, base)
        req(failures == 0, "生产回调无错误")
        print("Recovery: \(checks) checks passed; clock jumps, wake catch-up, persisted Pending/Snoozed and Resolved deduplication")
    }
}
