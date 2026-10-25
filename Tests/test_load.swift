// 在单一临时数据库中验证千任务写入、计划查询与真实调度响应。
@main struct LoadTests {
    private static var checks = 0
    // 失败保留明确断言名称。
    private static func req(_ valid: Bool, _ text: String) {
        if !valid { print("Load failure: \(text)"); fflush(stdout); exit(1) }; checks += 1
    }
    // 用单调时钟计量，不受模拟系统跳时影响。
    private static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds)/1_000_000 }
    // 主线程继续处理真实呈现和心跳，后台工作有明确截止。
    private static func wt(_ text: String, _ check: () -> Bool) {
        let end = now()+30_000
        while !check() && now()<end { _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
        req(check(), text)
    }
    // 输出固定百分位指标。
    private static func pct(_ values: [Double], _ fraction: Double) -> Double {
        let sorted=values.sorted(); return sorted.isEmpty ? .infinity : sorted[min(sorted.count-1,Int(ceil(Double(sorted.count)*fraction))-1)]
    }
    // 连续真实事务写入，不使用SQL捷径或第二套调度器。
    static func main() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("trolltask-load-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path=folder.appendingPathComponent("tasks.sqlite3").path
        let store=try TaskStore(at:path), reader=try TaskStore(at:path)
        let base=floor(Date().timeIntervalSince1970)+3600, clock=TestClock(base-1)
        var shown: TaskFields?, events=0, updates=0, next: Date?, issue: String?
        let scheduler=TaskScheduler(store:reader,clock:clock.rd) { alert,error in
            shown=alert as? TaskFields; if alert != nil { events += 1 }; if let error { issue=error.localizedDescription }
        }
        scheduler.onPlan = { date,_,error in DispatchQueue.main.async { next=date;updates += 1;if let error { issue=error.localizedDescription } } }
        req(scheduler.strt(nil),"批量写入前启动生产调度器")
        defer { scheduler.stp() }
        var gaps:[Double]=[], last=now()
        let heartbeat=DispatchSource.makeTimerSource(queue:.main)
        heartbeat.schedule(deadline:.now()+0.01,repeating:.milliseconds(10))
        heartbeat.setEventHandler { let tick=now();gaps.append(tick-last);last=tick };heartbeat.resume()
        defer { heartbeat.cancel() }
        var created:[String]?, creationMS=0.0
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let writer=try TaskStore(at:path), start=now();var ids:[String]=[]
                for index in 0..<1000 {
                    let task=try writer.crtTsk(["title":"批量\(index)","due_at":base+Double(index/5),"timezone_id":"UTC"])
                    ids.append(task["task_id"] as! String)
                }
                let elapsed=now()-start; DispatchQueue.main.async { created=ids;creationMS=elapsed }
            } catch { let text=error.localizedDescription;DispatchQueue.main.async { issue=text } }
        }
        wt("连续1000次正常建任务事务完成") { created != nil || issue != nil }
        req(issue==nil,"批量写入没有数据库错误")
        let ids=created!;req(ids.count==1000 && Set(ids).count==1000,"1000条唯一任务完整写入")
        wt("数据库变化后调度器定位正确首个未来时刻") { next?.timeIntervalSince1970==base || issue != nil }
        req(events==0 && issue==nil,"批量写入期间不提前呈现未来待办")
        let expected=ids.enumerated().sorted { a,b in a.offset/5==b.offset/5 ? a.element<b.element : a.offset<b.offset }.map(\.element)
        var samples:[Double]?, consistent=false
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let query=try TaskStore(at:path);var times:[Double]=[], valid=true
                for _ in 0..<30 {
                    let start=now(), plan=try query.plan(at:base-1) as! TaskFields;times.append(now()-start)
                    let alerts=plan["alerts"] as? [TaskFields] ?? []
                    valid = valid && alerts.compactMap { $0["task_id"] as? String }==expected
                }
                let result=valid;DispatchQueue.main.async { samples=times;consistent=result }
            } catch { let text=error.localizedDescription;DispatchQueue.main.async { issue=text } }
        }
        wt("1000任务的30次计划查询完成") { samples != nil || issue != nil }
        heartbeat.cancel()
        req(issue==nil && consistent,"30次查询都返回完整1000项且同刻顺序稳定")
        let times=samples!, p95=pct(times,0.95), maxMS=times.max() ?? .infinity, maxGap=gaps.max() ?? .infinity
        let metrics:TaskFields=["tasks":ids.count,"queries":times.count,"creation_ms":creationMS,
            "plan_p50_ms":pct(times,0.5),"plan_p95_ms":p95,"plan_max_ms":maxMS,
            "main_p95_gap_ms":pct(gaps,0.95),"main_max_gap_ms":maxGap,"heartbeat_samples":gaps.count,
            "plan_budget_p95_ms":200,"plan_budget_max_ms":500,"main_budget_max_gap_ms":250]
        let data=try JSONSerialization.data(withJSONObject:metrics,options:.prettyPrinted)
        try data.write(to:URL(fileURLWithPath:"build/TaskLoadReport.json"))
        print(String(format:"Load metrics: 1000 tasks, create %.1fms, plan p50 %.2fms / p95 %.2fms / max %.2fms, main max gap %.2fms",creationMS,pct(times,0.5),p95,maxMS,maxGap));fflush(stdout)
        req(p95<=200 && maxMS<=500,"千任务计划查询满足p95≤200ms、最大≤500ms预算")
        req(gaps.count>=3 && maxGap<=250,"后台批量写入/查询期间主线程心跳间隔不超过250ms")
        let snapshot=try store.snapshot() as! TaskFields
        req((snapshot["tasks"] as? [TaskFields])?.count==1000 && (snapshot["history"] as? [TaskFields])?.isEmpty==true,"持久化1000任务且未来查询不生成Occurrence")
        clock.set(base+0.1);TS_CLOCK_SET.withCString { _=notify_post($0) }
        wt("千任务中同刻五项正常认领并按稳定次序呈现") { shown?["task_id"] as? String==expected[0] || issue != nil }
        let first=shown?["occurrence_id"] as! String, count=events
        for _ in 0..<100 { store.changeNote.withCString { _=notify_post($0) };scheduler.rfrsh() }
        var settled=false;DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { settled=true }
        wt("千任务通知风暴完成") { settled }
        let history=(try store.snapshot() as! TaskFields)["history"] as? [TaskFields] ?? []
        req(history.count==5 && events==count && shown?["occurrence_id"] as? String==first,"千任务事件风暴不重复认领或呈现")
        for _ in 0..<30 { scheduler.act("complete",until:nil,occID:first) }
        wt("重复完成仅推进到第二项") { shown?["task_id"] as? String==expected[1] }
        scheduler.stp();shown=nil;let before=updates;req(scheduler.strt(nil),"千任务背景下重启调度器")
        wt("重启恢复第二项并跳过已Resolved第一项") { updates>before && shown?["task_id"] as? String==expected[1] }
        for task in expected.prefix(5).dropFirst() {
            req(shown?["task_id"] as? String==task,"千任务中的同刻队列稳定推进")
            let current=shown?["occurrence_id"] as! String;scheduler.act("complete",until:nil,occID:current)
            wt("已完成身份退出当前队首") { shown?["occurrence_id"] as? String != current }
        }
        req(shown==nil && issue==nil,"处理五项后其余995项继续等待，无错误或残留")
        let final=(try store.snapshot() as! TaskFields)["history"] as? [TaskFields] ?? []
        req(final.count==5 && final.allSatisfy { $0["status"] as? String=="resolved" },"五项各完成一次，没有重复历史")
        print("TaskLoad: \(checks) checks passed; 1000 writes, 30 plans, live event storm and restart")
    }
}
