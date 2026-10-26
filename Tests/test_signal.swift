// 验证字段联动与声振限制的生产纯逻辑。
@main struct SignalTests {
    private static var checks = 0
    // 报告可定位的规则断言。
    private static func req(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
    // 生成可比较的任务字段。
    private static func task(_ id: String, _ urgency: Int, _ difficulty: Int, _ seconds: Double?) -> TaskFields {
        var row: TaskFields = ["task_id":id, "created_at":100, "urgency":urgency, "difficulty":difficulty]
        if let seconds { row["planned_duration"] = seconds }; return row
    }
    // 验证时限、时钟、排序、摘要及抬起过滤。
    static func main() {
        let row: TaskFields = ["signal_at":1000, "signal_uptime":100, "signal_ack":false]
        for level in 0...3 {
            let plan = SignalPlan(level), expected: Double = level == 1 ? 5 : (level == 3 ? 30 : 15)
            req(plan.limit == expected && plan.pulses == Int(expected / 5), "有限档位")
            req(plan.remaining(row, wall:1000, uptime:100) == expected, "首次呈现预算")
            req(plan.remaining(row, wall:1002, uptime:103) == max(0,expected-3), "双时钟取较大消耗")
            req(plan.remaining(row, wall:1100, uptime:101) == 0, "向前跳时不能延长")
            req(plan.remaining(row, wall:999, uptime:101) == 0, "向后跳时保守静音")
            req(plan.remaining(row, wall:1001, uptime:1) == 0, "跨整机启动静音")
            req(plan.remaining(row, wall:.nan, uptime:101) == 0, "异常时间拒绝")
            var ack = row; ack["signal_ack"] = true
            req(plan.remaining(ack, wall:1001, uptime:101) == 0, "静音不能重播")
            for step in 1...100 {
                let remaining = expected * Double(step) / 100, playback = plan.playback(remaining)
                req(playback.loops >= 0 && abs(5 * Double(playback.loops + 1) - playback.offset - remaining) < 0.00001, "有限音频自身按剩余预算结束")
                let ticks = plan.ticks(remaining), elapsed = expected - remaining
                req(ticks.count >= 0 && ticks.count < plan.pulses && ticks.first > 0 && ticks.first <= 5, "恢复后只调度尚未开始的震动段")
                if ticks.count > 0 { req(abs((elapsed + ticks.first).truncatingRemainder(dividingBy: 5)) < 0.00001, "后续震动保持原五秒刻度") }
            }
        }
        req(SignalPlan(1).ticks(4.8).count==0 && SignalPlan(3).ticks(29.8).count==5, "恢复不重放首振且不增加总名额")
        let tasks = [task("b",3,1,600), task("c",1,3,60), task("a",3,1,600), task("d",0,0,nil)]
        // 读取排序后的稳定任务身份。
        func ids(_ mode: String) -> [String] { TaskTraits.order(tasks, by:mode).map { $0["task_id"] as! String } }
        req(ids("date") == ["b","c","a","d"], "日期排序保持存储计划")
        req(ids("urgency") == ["a","b","c","d"], "紧急优先且未设置后")
        req(ids("difficulty") == ["c","a","b","d"], "困难优先且稳定同值")
        req(ids("effort") == ["c","a","b","d"], "短任务优先且未设置后")
        req(TaskTraits.labels(task("x",3,3,1500)) == ["紧急：高","难度：困难","预计25分钟"], "摘要展示实际字段")
        req(TaskTraits.labels(task("x",0,0,nil)).isEmpty, "未设置不堆砌占位")
        req(TaskTraits.labels(task("x",0,0,90000)) == ["预计25小时"], "长投入不截断成一天")
        req(TaskTraits.labels(task("x",0,0,.infinity)).isEmpty, "异常投入不格式化")
        req(TaskTraits.labels(task("x",0,0,Double.greatestFiniteMagnitude)).count == 1, "极大投入不溢出整数")
        var desk = PickupGate()
        for step in 0..<300 {
            req(!desk.sample(Double(step)/10, gravity:(0,0,-1), acceleration:(0.4,0,0)), "桌面震动不静音")
        }
        var pickup = PickupGate()
        req(!pickup.sample(1, gravity:(0,0,-1), acceleration:(0,0,0)), "建立初始方向")
        req(!pickup.sample(1.1, gravity:(0,-0.8,-0.6), acceleration:(0.3,0,0)), "抬起仍等待稳定")
        req(!pickup.sample(1.2, gravity:(0,-0.8,-0.6), acceleration:(0,0,0)), "不能单样本静音")
        req(!pickup.sample(1.3, gravity:(0,-0.8,-0.6), acceleration:(0,0,0)), "稳定不足时长")
        req(pickup.sample(1.7, gravity:(0,-0.8,-0.6), acceleration:(0,0,0)), "抬起并稳定后静音")
        req(!pickup.sample(1.6, gravity:(0,-0.8,-0.6), acceleration:(0,0,0)), "旧样本拒绝")
        req(!pickup.sample(.nan, gravity:(0,-0.8,-0.6), acceleration:(0,0,0)), "无效样本拒绝")
        print("Signal/Traits: \(checks) checks passed")
    }
}
