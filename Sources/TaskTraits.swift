// 将任务评估用于清单排序与提醒信息，不改变提醒队列。
enum TaskTraits {
    // 缺失评估置后，同值保持创建时间与身份的稳定次序。
    static func order(_ tasks: [TaskFields], by mode: String) -> [TaskFields] {
        let key = ["manual":"position", "star":"starred_at", "urgency":"urgency", "difficulty":"difficulty", "effort":"planned_duration"][mode]
        guard let key else { return tasks }
        let descending = ["star", "urgency", "difficulty"].contains(mode)
        // 过滤未设置的评估与异常数值。
        func number(_ task: TaskFields) -> Double? {
            guard let value = (task[key] as? NSNumber)?.doubleValue, value.isFinite,
                  !["urgency", "difficulty", "effort"].contains(mode) || value > 0 else { return nil }
            return value
        }
        return tasks.sorted { a, b in
            let av = number(a), bv = number(b)
            if let av, let bv, av != bv { return descending ? av > bv : av < bv }
            if av == nil && bv != nil { return false }; if av != nil && bv == nil { return true }
            let ac = (a["created_at"] as? NSNumber)?.doubleValue ?? 0, bc = (b["created_at"] as? NSNumber)?.doubleValue ?? 0
            if ac != bc { return ac < bc }
            return (a["task_id"] as? String ?? "") < (b["task_id"] as? String ?? "")
        }
    }
    // 仅展示实际设置的字段，长时间采用简短数量级。
    static func labels(_ task: TaskFields) -> [String] {
        var result: [String] = []
        for (key, prefix, names) in [("urgency", "紧急：", ["低", "中", "高"]), ("difficulty", "难度：", ["简单", "一般", "困难"])] {
            if let grade = (task[key] as? NSNumber)?.intValue, (1...3).contains(grade) { result.append(prefix + names[grade - 1]) }
        }
        if let seconds = (task["planned_duration"] as? NSNumber)?.doubleValue, seconds.isFinite, seconds > 0 {
            let hours = seconds / 3600
            result.append("预计" + (hours >= 1 ? String(format: "%.3g小时", hours) : String(format: "%.0f分钟", max(1, ceil(seconds / 60)))))
        }
        return result
    }
}
