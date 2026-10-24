// 直接验证生产队列的逻辑身份、顺序及重读行为。
@main struct QueueTests {
    private static var checks = 0
    // 输出可定位的失败断言。
    private static func req(_ value: Bool, _ message: String) {
        precondition(value, message); checks += 1
    }
    // 构造原时间与延后时间独立的候选。
    private static func mk(_ task: String, _ at: Double, _ id: String, _ fire: Double = 0) -> TaskFields {
        ["task_id": task, "scheduled_at": at, "occurrence_id": id, "remind_at": fire, "generation": 1]
    }
    // 验证同身份的重复候选和事件均不增加排队名额。
    static func main() {
        let queue = ReminderQueue()
        let a = mk("a", 100, "a1", 900), b = mk("b", 100, "b1", 200), c = mk("c", 101, "c1", 100)
        queue.rcl([c, b, a, a, b]); req(queue.current?["occurrence_id"] as? String == "a1", "按原时间与任务ID排序")
        req(queue.current?["occurrence_at"] as? Double == 100, "原定occurrence_at不取延后时间")
        for _ in 0..<100 {
            queue.rcl([b, c, a, mk("a", 100, "a0"), a])
            req(queue.current?["occurrence_id"] as? String == "a1", "相同身份不同UUID不能替换当前项")
        }
        queue.nxt(); req(queue.current?["occurrence_id"] as? String == "b1", "task_id加原时间只占一个位置")
        queue.rcl([b, c])
        queue.rcl([c, b, a]); req(queue.current?["occurrence_id"] as? String == "b1", "重读不能让更早项抢占当前项")
        queue.nxt(); queue.rcl([c, a]); req(queue.current?["occurrence_id"] as? String == "a1", "当前完成后取其余最早项")
        queue.clr(); queue.rcl([b, c, a]); req(queue.current?["occurrence_id"] as? String == "a1", "异常重建按稳定原时间顺序恢复")
        queue.rcl([b, c]); req(queue.current?["occurrence_id"] as? String == "b1", "已Resolved项从有效快照消失即移出队列")
        queue.clr();queue.rcl([mk("a", 100, "a0"), a, mk("a", 101, "a2"), b])
        req(queue.current?["occurrence_id"] as? String == "a0", "同身份首次选择稳定UUID")
        queue.nxt();req(queue.current?["occurrence_id"] as? String == "b1", "不同任务的相同时刻仍分别排队")
        queue.nxt();req(queue.current?["occurrence_id"] as? String == "a2", "同任务的不同轮次仍分别排队")
        queue.clr();queue.rcl([a, c]);queue.nxt();queue.rcl([b, c])
        req(queue.current?["occurrence_id"] as? String == "b1", "完成后新生成的更早Pending按原时间排队")
        queue.clr();queue.rcl([[:], mk("a", .nan, "bad"), mk("a", .infinity, "bad"), ["task_id":"a","scheduled_at":100]])
        req(queue.current == nil, "无效身份不进入队列")
        print("ReminderQueue: \(checks) checks passed")
    }
}
