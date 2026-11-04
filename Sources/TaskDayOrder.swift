// AI只排序可移动任务，实际时间由原排程器约束。
@objc(TaskDayOrder) final class TaskDayOrder:NSObject {
    // 读取不可变的一日候选与修订，保留子任务内部执行顺序。
    @objc(context:at:error:) static func ctx(_ store:TaskStore,at:Double)throws->NSDictionary {
        let snapshot=try store.snapshot() as! TaskFields
        guard !(snapshot["history"] as! [TaskFields]).contains(where:{["presented","snoozed"].contains($0["status"] as? String ?? "")}) else{throw TaskAI.err("请先处理当前提醒")}
        let hi=Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:Date(timeIntervalSince1970:at)))!.timeIntervalSince1970
        let tasks=(snapshot["tasks"] as! [TaskFields]).filter {row in
            row["status"] as? String=="needsAction" && (row["deleted"] as? Bool)==false && row["routine_kind"] as? String=="none" && row["parent_id"] is NSNull && (row["planning_mode"] as? String=="window" || row["schedule_kind"] as? String != "timed") && ((row["due_at"] as? NSNumber)?.doubleValue ?? at)<hi
        }.sorted{($0["task_id"] as! String)<($1["task_id"] as! String)}.map {row in row.filter{["task_id","title","notes","planned_duration","deadline_at","urgency","difficulty"].contains($0.key)}}
        guard !tasks.isEmpty else{throw TaskAI.err("暂无可安排任务")}
        return ["mode":"order","tasks":tasks,"revision":snapshot["revision"]!,"difficulty":3,"at":at]
    }
    // 修订或候选变化则拒绝旧排序，整批顺序只生效一次。
    @objc(apply:context:result:at:error:) static func aply(_ store:TaskStore,context:NSDictionary,result:NSDictionary,at:Double)throws->NSDictionary {
        try store.wrTxn {pointer in do {
            let current=try ctx(store,at:at) as! TaskFields
            guard let revision=context["revision"] as? NSNumber,revision==current["revision"] as? NSNumber,let order=result["order"] as? [String],let tasks=current["tasks"] as? [TaskFields],Set(order)==Set(tasks.map{$0["task_id"] as! String}),Set(order).count==order.count else{throw TaskAI.err("安排已变化，请重评")}
            let before=try store.day(at:at,zone:TimeZone.current.identifier,now:at) as! TaskFields
            let scheduled=Set((before["entries"] as! [TaskFields]).filter{$0["kind"] as? String=="task"}.map{$0["task_id"] as! String})
            for(index,id) in order.enumerated(){try store.updTsk(id,fields:["position":index])}
            let after=try store.day(at:at,zone:TimeZone.current.identifier,now:at) as! TaskFields
            if (after["unplaced"] as! [TaskFields]).contains(where:{scheduled.contains(($0["task"] as! TaskFields)["task_id"] as! String)}){throw TaskAI.err("排序会挤占原有任务")}
            try store.arrange(at:at,zone:TimeZone.current.identifier);return true
        }catch{pointer?.pointee=error as NSError;return false}}
        return ["applied":true]
    }
}
