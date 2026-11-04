// 从既有任务与轮次派生当天执行清单，不复制常律或任务。
@objc(TaskToday) final class TaskToday:NSObject {
    // 按数据库隔离主动补弹通知，不与其他存储串扰。
    @objc static func note(_ store:TaskStore)->String { store.changeNote+".retry" }
    // 只允许当前版本已到期的原轮次补弹，不创建或完成任务。
    @objc(reminder:task:at:error:) static func alrt(_ store:TaskStore,task:NSDictionary,at:Double)throws->NSDictionary {
        guard at.isFinite,let id=task["task_id"] as? String,let cycle=task["next_cycle_at"] as? NSNumber,ts_num(cycle),let generation=task["reminder_version"] as? NSNumber,ts_num(generation) else{throw TaskAI.err("任务暂未安排提醒")}
        let plan=try store.plan(at:at) as! TaskFields
        guard let alert=(plan["alerts"] as! [TaskFields]).first(where:{$0["task_id"] as? String==id && ($0["cycle_at"] as? NSNumber)==cycle && ($0["generation"] as? NSNumber)==generation}) else{throw TaskAI.err("提醒已处理或变更")}
        guard (alert["remind_at"] as! NSNumber).doubleValue<=at else{throw TaskAI.err("尚未到提醒时间")}
        return alert as NSDictionary
    }
    // 从按时间排序的待办里定位当前区间、下一项或当天最后一项。
    @objc static func focus(_ pending:[TaskFields],at:Double)->Int {
        var active:Int?, next:Int?, last:Int?, activeStart = -Double.infinity, lastStart = -Double.infinity
        for (index, row) in pending.enumerated() {
            guard let start = (row["remind_at"] as? NSNumber)?.doubleValue, start.isFinite else { continue }
            if start >= at && next == nil { next = index }
            if start > lastStart { last = index; lastStart = start }
            if start <= at, start > activeStart, let end = (row["today_end"] as? NSNumber)?.doubleValue, at < end {
                active = index; activeStart = start
            }
        }
        return active ?? next ?? last ?? NSNotFound
    }

    @objc(rows:at:zone:error:) static func rows(_ store:TaskStore,at:Double,zone:String)throws->NSArray {
        try rows(store, snapshot: store.plan(at:at) as! TaskFields, at:at, zone:zone) as NSArray
    }
    // 首页复用同一调度快照，避免为不同清单重复计算。
    static func rows(_ store:TaskStore,snapshot:TaskFields,at:Double,zone:String)throws->[TaskFields] {
        let plan=try store.day(at:at,zone:zone,now:at) as! TaskFields,lo=(plan["day_at"] as! NSNumber).doubleValue,hi=(plan["day_end"] as! NSNumber).doubleValue
        let all = snapshot["tasks"] as! [TaskFields], alerts = snapshot["alerts"] as! [TaskFields]
        let history = snapshot["history"] as! [TaskFields], slots = snapshot["slots"] as! [TaskFields]
        let slotsByTask = Dictionary(grouping: slots) { $0["task_id"] as! String }
        let alertsByTask = Dictionary(grouping: alerts) { $0["task_id"] as! String }
        let recordsByTask = Dictionary(grouping: history) { $0["task_id"] as! String }
        let live = all.filter { ($0["deleted"] as? Bool) == false }
        var rows:[TaskFields]=[],seen=Set<String>()
        for entry in plan["entries"] as! [TaskFields] where entry["kind"] as? String != "work" {
            var task=entry["task"] as! TaskFields
            let id=entry["id"] as! String, cycle=entry["cycle_at"] as! NSNumber
            let slot = slotsByTask[task["task_id"] as! String]?.first {
                ($0["generation"] as? NSNumber)==task["reminder_version"] as? NSNumber && ($0["cycle_at"] as? NSNumber)==cycle
            }
            let start = (slot?["start_at"] as? NSNumber ?? cycle).doubleValue
            let expired = recordsByTask[task["task_id"] as! String]?.contains {
                ($0["generation"] as? NSNumber)==task["reminder_version"] as? NSNumber &&
                ($0["action"] as? String)=="expire" && ($0["cycle_at"] as! NSNumber).doubleValue>=cycle.doubleValue
            } ?? false
            guard start >= lo, start < hi, !expired, seen.insert(id).inserted else { continue }
            task["next_cycle_at"]=entry["cycle_at"];task["remind_at"]=entry["start_at"];task["today_end"]=entry["end_at"];task["today_key"]=id
            if (entry["completed"] as? Bool)==true {task["status"]="completed";task["today_resolved"]=true}
            rows.append(task)
        }
        let placed=Set(rows.map{$0["task_id"] as! String})
        let byID=Dictionary(uniqueKeysWithValues:all.map{($0["task_id"] as! String,$0)})
        for history in history where history["action"] as? String=="complete" && ["completed","resolved"].contains(history["status"] as? String ?? "") {
            guard var task=byID[history["task_id"] as! String],task["routine_kind"] as? String=="none",!(task["recurrence"] as? [String] ?? []).isEmpty,(task["deleted"] as? Bool)==false,(history["generation"] as? NSNumber)==task["reminder_version"] as? NSNumber,let cycle=history["cycle_at"] as? NSNumber,cycle.doubleValue>=lo,cycle.doubleValue<hi else{continue}
            let key=(task["task_id"] as! String)+"/"+String(describing:history["generation"]!)+"/"+String(describing:cycle)
            guard seen.insert(key).inserted else{continue};task["status"]="completed";task["today_resolved"]=true;task["today_key"]=key;task["remind_at"]=cycle;task["completed_at"]=history["handled_at"];rows.append(task)
        }
        let parents=Set(live.filter{$0["status"] as? String != "completed"}.compactMap{$0["parent_id"] as? String})
        for var task in live where task["routine_kind"] as? String == "none" && !placed.contains(task["task_id"] as! String) {
            let id = task["task_id"] as! String
            let today = (lo..<hi)
            let slots = slotsByTask[id] ?? [], history = recordsByTask[id] ?? []
            let start=(task["due_at"] as? NSNumber)?.doubleValue, end=(task["deadline_at"] as? NSNumber)?.doubleValue
            let window = task["planning_mode"] as? String == "window"
            if task["status"] as? String == "completed" {
                let handled = history.last { ($0["action"] as? String)=="complete" }
                let cycle = handled?["cycle_at"] as? NSNumber
                let slot = slots.last { ($0["cycle_at"] as? NSNumber)==cycle }
                let stamp = (slot?["start_at"] as? NSNumber ?? cycle)?.doubleValue ?? start ?? end
                if let stamp, today.contains(stamp), let date=(task["completed_at"] as? NSNumber)?.doubleValue, today.contains(date) {
                    task["today_key"]=id; task["remind_at"]=stamp; rows.append(task)
                }
                continue
            }
            guard !parents.contains(id) else { continue }
            let repeating = !(task["recurrence"] as? [String] ?? []).isEmpty
            let alert = alertsByTask[id]?.first {
                let stamp = (window ? $0["scheduled_at"] : $0["cycle_at"]) as! NSNumber
                return today.contains(stamp.doubleValue)
            }
            let hasOldSlot = slots.contains {
                ($0["generation"] as? NSNumber)==task["reminder_version"] as? NSNumber &&
                ($0["start_at"] as! NSNumber).doubleValue < lo
            }
            let isDiscarded = !repeating && history.contains {
                ($0["generation"] as? NSNumber)==task["reminder_version"] as? NSNumber && ($0["action"] as? String)=="expire"
            }
            let anchor = window ? (end ?? start) : (start ?? end)
            guard !hasOldSlot, !isDiscarded, alert != nil || (!repeating && anchor.map(today.contains)==true) else { continue }
            task["remind_at"]=alert?["remind_at"] ?? NSNull()
            task["next_cycle_at"]=alert?["cycle_at"] ?? NSNull()
            task["today_unplaced"]=true;task["today_key"]=id;rows.append(task)
        }
        return rows.sorted {a,b in
            let left=(a["remind_at"] as? NSNumber)?.doubleValue ?? .greatestFiniteMagnitude,right=(b["remind_at"] as? NSNumber)?.doubleValue ?? .greatestFiniteMagnitude
            return left==right ? (a["today_key"] as! String)<(b["today_key"] as! String):left<right
        }
    }
}
