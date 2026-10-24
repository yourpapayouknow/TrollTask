// 在调度器串行队列内维护唯一、稳定且不抢占的提醒队列。
final class ReminderQueue {
    // 原定提醒时间构成身份，延后时间不参与去重。
    private struct Identity: Hashable {
        let task: String
        let occurrence: Double
    }
    private var items: [TaskFields] = []
    private var pinned = false
    var current: TaskFields? { items.first }

    // 从唯一数据库的有效Presented记录恢复并更新队列。
    func rcl(_ candidates: [TaskFields]) {
        let previous = pinned ? current : nil
        var seen = Set<Identity>()
        items = candidates.sorted { a, b in
            let first = (a["scheduled_at"] as? NSNumber)?.doubleValue ?? .infinity
            let second = (b["scheduled_at"] as? NSNumber)?.doubleValue ?? .infinity
            if first != second { return first < second }
            let taskA = a["task_id"] as? String ?? "", taskB = b["task_id"] as? String ?? ""
            if taskA != taskB { return taskA < taskB }
            let old = previous?["occurrence_id"] as? String
            let oldA = old != nil && a["occurrence_id"] as? String == old
            let oldB = old != nil && b["occurrence_id"] as? String == old
            if oldA != oldB { return oldA }
            return (a["occurrence_id"] as? String ?? "") < (b["occurrence_id"] as? String ?? "")
        }.compactMap { candidate in
            guard let task = candidate["task_id"] as? String, let stamp = candidate["scheduled_at"] as? NSNumber,
                stamp.doubleValue.isFinite, candidate["occurrence_id"] is String,
                seen.insert(Identity(task: task, occurrence: stamp.doubleValue)).inserted else { return nil }
            var item = candidate; item["occurrence_at"] = stamp; return item
        }
        // 当前项仍然有效时保留它，后到的任务不能抢占提交或附件采集。
        if let previous, let index = items.firstIndex(where: {
            $0["occurrence_id"] as? String == previous["occurrence_id"] as? String
                && ($0["generation"] as? NSNumber) == (previous["generation"] as? NSNumber)
        }) { items.insert(items.remove(at: index), at: 0) }
        pinned = true
    }
    // 当前事务成功后移出队首。
    func nxt() { if !items.isEmpty { items.removeFirst() }; pinned = false }
    // 停止或读取失败后丢弃内存状态，后续从同库恢复。
    func clr() { items.removeAll(); pinned = false }
}
