// 将任务评估用于清单排序与提醒信息，不改变提醒队列。
enum TaskTraits {
    // 缺失评估置后，同值保持创建时间与身份的稳定次序。
    static func order(_ tasks: [TaskFields], by mode: String) -> [TaskFields] {
        if mode == "name" {
            return tasks.sorted { a, b in
                let order = (a["title"] as? String ?? "").localizedStandardCompare(b["title"] as? String ?? "")
                if order != .orderedSame { return order == .orderedAscending }
                let ac = (a["created_at"] as? NSNumber)?.doubleValue ?? 0, bc = (b["created_at"] as? NSNumber)?.doubleValue ?? 0
                if ac != bc { return ac < bc }
                return (a["task_id"] as? String ?? "") < (b["task_id"] as? String ?? "")
            }
        }
        let key = ["urgency":"urgency", "difficulty":"difficulty"][mode]
        guard let key else { return tasks }
        let descending = ["urgency", "difficulty"].contains(mode)
        // 过滤未设置的评估与异常数值。
        func number(_ task: TaskFields) -> Double? {
            if mode == "urgency", (task["rush"] as? NSNumber)?.boolValue == true { return 4 }
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
    // 父任务在前，子任务紧随其父级并保留原先后。
    static func group(_ tasks: [TaskFields]) -> [TaskFields] {
        let ids = Set(tasks.compactMap { $0["task_id"] as? String })
        var children: [String: [TaskFields]] = [:], roots: [TaskFields] = []
        for task in tasks {
            if let parent = task["parent_id"] as? String, ids.contains(parent) { children[parent, default: []].append(task) }
            else { roots.append(task) }
        }
        var result: [TaskFields] = [], seen = Set<String>()
        func emit(_ task: TaskFields) {
            guard let id = task["task_id"] as? String, seen.insert(id).inserted else { return }
            result.append(task)
            for child in children[id] ?? [] { emit(child) }
        }
        for task in roots { emit(task) }
        for task in tasks { emit(task) }
        return result
    }
    // 供AI和本地门禁共用的固定密度策略。
    static func policy(_ task: TaskFields, maxStep: Int) -> TaskFields {
        let rush = (task["rush"] as? NSNumber)?.boolValue == true
        let urgency = (task["urgency"] as? NSNumber)?.intValue ?? 0
        let difficulty = (task["difficulty"] as? NSNumber)?.intValue ?? 0
        let share = rush ? 1.0 : urgency <= 1 ? 1.0 / 3.0 : urgency == 2 ? 2.0 / 3.0 : 1.0
        let reserve = rush ? 0 : urgency >= 3 ? 60 : 0
        let count = rush ? 64 : difficulty == 3 ? 1 : difficulty == 1 ? 3 : 2
        return ["daily_share": share, "reserve_minutes": reserve, "max_steps_per_day": count,
                "fill_all": rush, "max_step_minutes": max(1, maxStep)]
    }
    // 仅展示实际设置的字段，长时间采用简短数量级。
    static func labels(_ task: TaskFields) -> [String] {
        var result: [String] = []
        if (task["rush"] as? NSNumber)?.boolValue == true { result.append("紧急：赶DDL") }
        else if let grade = (task["urgency"] as? NSNumber)?.intValue, (1...3).contains(grade) { result.append("紧急：" + ["低", "中", "高"][grade - 1]) }
        if let grade = (task["difficulty"] as? NSNumber)?.intValue, (1...3).contains(grade) { result.append("难度：" + ["简单", "一般", "困难"][grade - 1]) }
        if let seconds = (task["planned_duration"] as? NSNumber)?.doubleValue, seconds.isFinite, seconds > 0 {
            let hours = seconds / 3600
            result.append("预计" + (hours >= 1 ? String(format: "%.3g小时", hours) : String(format: "%.0f分钟", max(1, ceil(seconds / 60)))))
        }
        return result
    }
}
