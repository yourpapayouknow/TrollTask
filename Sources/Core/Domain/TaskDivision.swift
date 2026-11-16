// 在原任务树上原子应用可编辑拆分，不创建第二套任务模型。
@objc(TaskDivision) final class TaskDivision: NSObject {
    // 提取与本次编辑有关的稳定版本。
    private static func sig(_ rows: [TaskFields]) -> [TaskFields] {
        rows.sorted { ($0["task_id"] as! String) < ($1["task_id"] as! String) }
    }
    // 返回可比较的父任务与直接子任务快照。
    @objc(draft:task:error:) static func drft(_ store: TaskStore, task: String) throws -> NSDictionary {
        let snapshot = try store.snapshot() as! TaskFields, all = snapshot["tasks"] as! [TaskFields]
        guard let parent = all.first(where: { $0["task_id"] as? String == task }), (parent["deleted"] as? NSNumber)?.boolValue == false,
              parent["status"] as? String == "needsAction", parent["routine_kind"] as? String == "none", (parent["recurrence"] as! [String]).isEmpty else { throw TaskAI.err("此任务暂不能拆分") }
        let children = all.filter { $0["parent_id"] as? String == task && ($0["deleted"] as? NSNumber)?.boolValue == false }.sorted {
            let a = ($0["position"] as! NSNumber).doubleValue, b = ($1["position"] as! NSNumber).doubleValue
            return a == b ? ($0["created_at"] as! NSNumber).doubleValue < ($1["created_at"] as! NSNumber).doubleValue : a < b
        }
        var family=Set([task]),changed=true
        while changed { let count=family.count;for row in all where (row["parent_id"] as? String).map({family.contains($0)}) == true {family.insert(row["task_id"] as! String)};changed=count != family.count }
        return ["task":parent,"children":children,"signature":sig(all.filter{family.contains($0["task_id"] as! String)}),"family_ids":family.sorted()]
    }
    // 校验全部草稿后一次保存，过时或重复确认均不能创建重复子任务。
    @objc(apply:task:parts:expected:error:) static func aply(_ store: TaskStore, task: String, parts: NSArray, expected: NSDictionary) throws -> NSDictionary {
        var output: TaskFields?
        try store.wrTxn { pointer in
            do {
                let current = try drft(store,task:task) as! TaskFields
                guard let expectedSig = expected["signature"] as? [TaskFields], NSDictionary(dictionary:["rows":expectedSig]).isEqual(to:["rows":current["signature"]!]) else { throw TaskAI.err("任务已变更，请重载") }
                guard let rows = parts as? [TaskFields], (1...64).contains(rows.count) else { throw TaskAI.err("请添加有效步骤") }
                let parent = current["task"] as! TaskFields, children = current["children"] as! [TaskFields], byID = Dictionary(uniqueKeysWithValues:children.map { ($0["task_id"] as! String,$0) })
                let snapshot = try store.snapshot() as! TaskFields
                // 父任务及其后代存在未处理提醒时保持当前窗口与附件。
                let family=Set(current["family_ids"] as! [String])
                if (snapshot["history"] as! [TaskFields]).contains(where: { family.contains($0["task_id"] as! String) && ["presented","snoozed"].contains($0["status"] as! String) }) { throw TaskAI.err("请先处理当前提醒") }
                var ids = Set<String>(), total = 0.0
                for row in rows {
                    guard Set(row.keys).isSubset(of:["task_id","title","notes","planned_duration"]), let id = row["task_id"] as? String, UUID(uuidString:id) != nil, id == id.lowercased(), ids.insert(id).inserted,
                          let title = row["title"] as? String, let notes = row["notes"] as? String else { throw TaskAI.err("步骤内容无效") }
                    try TaskStore.vldTxt(title,notes:notes)
                    if let old=byID[id],old["status"] as? String == "completed" {
                        guard title==old["title"] as? String,notes==old["notes"] as? String,(row["planned_duration"] as? NSObject)?.isEqual(old["planned_duration"]) == true else{throw TaskAI.err("完成步骤不可改写")}
                        total += (old["planned_duration"] as? NSNumber)?.doubleValue ?? 0;continue
                    }
                    guard let duration=row["planned_duration"] as? NSNumber,ts_num(duration),duration.doubleValue>0,duration.doubleValue<=31536000 else{throw TaskAI.err("步骤内容无效")};total += duration.doubleValue
                }
                for child in children where !ids.contains(child["task_id"] as! String) {
                    guard child["status"] as? String != "completed" else { throw TaskAI.err("完成步骤不能移除") }
                    try store.delTsk((child["task_id"] as! String))
                }
                for (position,row) in rows.enumerated() {
                    let id = row["task_id"] as! String
                    if let old = byID[id] {
                        if old["status"] as? String != "completed" { try store.updTsk(id,fields:["title":row["title"]!,"notes":row["notes"]!,"planned_duration":row["planned_duration"]!,"position":position]) }
                    } else {
                        var fields = row; fields.removeValue(forKey:"task_id"); fields["parent_id"] = task; fields["position"] = position
                        for key in ["list_id","timezone_id","urgency","difficulty","deadline_at","deadline_kind"] { fields[key] = parent[key] }
                        _ = try store.crtTsk(fields,uuid:id)
                    }
                }
                try store.updTsk(task,fields:["planned_duration":total]); output = ["task_id":task,"children":ids.sorted(),"planned_duration":total]; return true
            } catch { pointer?.pointee = error as NSError; return false }
        }
        guard let output else { throw TaskAI.err("拆分未保存") }; return output as NSDictionary
    }
}
