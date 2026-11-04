// 为有限日期窗口生成常律卡片及五项分隔。
@objc(TaskRoutineView) final class TaskRoutineView:NSObject {
    // 列表和日历共用只读模板投影，按当天起始时刻分组。
    @objc static func sections(_ days:[TaskFields])->[TaskFields] {
        return days.map { day -> TaskFields in
            let startOfDay = (day["day_at"] as! NSNumber).doubleValue
            let entries = (day["entries"] as? [TaskFields] ?? []).filter {
                ($0["cycle_at"] as! NSNumber).doubleValue >= startOfDay
            }
            var rows:[TaskFields]=[]
            for (index, entry) in entries.enumerated() {
                var task=entry["task"] as! TaskFields
                let start=entry["start_at"] as! NSNumber
                if index%5==0 {rows.append(["routine_marker":true,"routine_fire_at":start])}
                task["routine_fire_at"]=start
                task["routine_group_first"]=index%5==0
                rows.append(task)
            }
            return ["day_at":day["day_at"]!,"rows":rows]
        }
    }
}
