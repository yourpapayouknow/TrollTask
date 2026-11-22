// 将创建评估与提醒轮次分开，所有正式保存共用原子门禁。
@objc(TaskIntake) final class TaskIntake:NSObject {
    static let keys:Set<String>=["title","notes","due_at","timezone_id","recurrence_type","recurrence_interval","list_id","parent_id","position","starred","schedule_kind","planned_duration","deadline_at","deadline_kind","recurrence","urgency","difficulty","rush","density","planning_mode"]
    // 拆分步骤只保留存储层接受的四个键。
    static let partKeys:Set<String>=["task_id","title","notes","planned_duration"]
    // 对评估有关的任务字段和全部后代签名。
    static func sig(_ store:TaskStore,_ id:String,strict:Bool=false)throws->[TaskFields] {
        let all=try store.lsTsks() as! [TaskFields];var family=Set([id]),changed=true
        while changed {let count=family.count;for row in all where (row["parent_id"] as? String).map({family.contains($0)})==true {family.insert(row["task_id"] as! String)};changed=count != family.count}
        return all.filter{family.contains($0["task_id"] as! String)}.sorted{($0["task_id"] as! String)<($1["task_id"] as! String)}.map{row in var fields=strict ? row:row.filter{keys.contains($0.key) && !["position","starred","list_id"].contains($0.key)};for key in ["task_id","status","deleted"]{fields[key]=row[key]};return fields}
    }
    // 提取可编辑上下文；没有开始或结束时由表单补齐，不猜测工时。
    @objc(context:fields:parts:at:error:) static func ctx(_ store:TaskStore,fields:NSDictionary,parts:NSArray,at:Double)throws->NSDictionary {
        guard at.isFinite,let input=fields as? TaskFields,let rows=parts as? [TaskFields] else{throw TaskAI.err("评估输入无效")}
        let id=input["task_id"] as? String,old:TaskFields?=try id.map{try store.rdTsk($0) as! TaskFields}
        if let id,let baseline=input["_baseline"] as? [TaskFields],!NSDictionary(dictionary:["rows":baseline]).isEqual(to:["rows":try sig(store,id,strict:true)]){throw TaskAI.err("任务已变更，请重载")}
        var task=old?.filter{keys.contains($0.key)} ?? ["title":"","notes":"","timezone_id":TimeZone.current.identifier,"list_id":TS_DFLT_LST,"recurrence":[],"difficulty":0,"urgency":0,"rush":0,"density":1]
        task.merge(input.filter{keys.contains($0.key)}){_,new in new}
        if old == nil { task["density"] = 1 }
        if (task["rush"] as? NSNumber)?.boolValue == true { task["urgency"] = 3 }
        try TaskStore.vldTxt(task["title"] as? String ?? "",notes:task["notes"] as? String ?? "")
        if let old,old["status"] as? String != "needsAction" || (old["deleted"] as? NSNumber)?.boolValue==true{throw TaskAI.err("任务已处理或删除")}
        guard let start=task["due_at"] as? NSNumber,ts_num(start),let end=task["deadline_at"] as? NSNumber,ts_num(end),end.doubleValue>start.doubleValue,end.doubleValue>at,
              let zone=task["timezone_id"] as? String,TimeZone(identifier:zone) != nil else{throw TaskAI.err("请设置开始和结束")}
        if TaskWindow.dayOnly(task), let timezone = TimeZone(identifier: zone) {
            let calendar = TaskWindow.calendar(timezone)
            let first = Date(timeIntervalSince1970: start.doubleValue)
            let last = Date(timeIntervalSince1970: end.doubleValue)
            guard first == calendar.startOfDay(for: first), last == calendar.startOfDay(for: last) else { throw TaskAI.err("请选择整天") }
            if let issue = TaskWindow.issue(first, last, in: calendar) { throw TaskAI.err(issue) }
            if old == nil, (task["starred"] as? NSNumber)?.boolValue == true { task["urgency"] = 3 }
        }
        let snapshot=try store.snapshot() as! TaskFields
        if let id,(snapshot["history"] as! [TaskFields]).contains(where:{$0["task_id"] as? String==id && ["presented","snoozed"].contains($0["status"] as? String ?? "")}){throw TaskAI.err("请先处理当前提醒")}
        let doneIDs=Set((snapshot["tasks"] as! [TaskFields]).filter{$0["status"] as? String=="completed"}.map{$0["task_id"] as! String})
        let retained=rows.filter{doneIDs.contains($0["task_id"] as? String ?? "")}
        let doneEffort=retained.reduce(0.0){$0+(($1["planned_duration"] as? NSNumber)?.doubleValue ?? 0)}
        let room=try store.room(start:start.doubleValue,end:end.doubleValue,zone:zone,excluding:id.map{[$0]} ?? [],now:at) as! TaskFields
        let horizon=Calendar(identifier:.gregorian).date(byAdding:.day,value:14,to:Date(timeIntervalSince1970:end.doubleValue))!.timeIntervalSince1970
        let future=(end.doubleValue-start.doubleValue < 380*86400) ? try store.room(start:start.doubleValue,end:horizon,zone:zone,excluding:id.map{[$0]} ?? [],now:at) as! TaskFields:room
        var result:TaskFields=["completed_ids":retained.compactMap{$0["task_id"] as? String},"completed_effort":doneEffort,"future_gaps":future["gaps"]!,"task_id":id ?? UUID().uuidString.lowercased(),"existing":id != nil,"fields":task,"parts":rows,"room":room,"revision":snapshot["revision"]!,"at":at]
        if !rows.isEmpty {result["dry"]=try store.evaluate(fields:task,parts:rows,now:at)}
        return result as NSDictionary
    }
    // 以真实空档计算可达到的结束时刻，不把日期窗口当作全程工作。
    static func finish(_ gaps:[TaskFields],_ seconds:Double)->Double? {
        var left=seconds;for gap in gaps {let lo=(gap["start_at"] as! NSNumber).doubleValue,hi=(gap["end_at"] as! NSNumber).doubleValue;if left<=hi-lo{return lo+left};left-=hi-lo};return nil
    }
    // 按依赖顺序逐步放入空档，容量总和足够也可能无法排下。
    static func fit(_ gaps:[TaskFields],_ durations:[Double])->Double? {
        var index=0,used=0.0,last:Double?
        for duration in durations {var placed=false
            while index<gaps.count {let start=(gaps[index]["start_at"] as! NSNumber).doubleValue+used,end=(gaps[index]["end_at"] as! NSNumber).doubleValue
                if start+duration<=end {used+=duration;last=start+duration;placed=true;break};index+=1;used=0
            };if !placed{return nil}
        };return last
    }
    // 验证AI工时区间与步骤，独立于界面和HTTP。
    static func range(_ estimate:TaskFields)throws->(Double,Double,Double) {
        var values:[Double]=[]
        for key in ["minimum_minutes","recommended_minutes","maximum_minutes"] {guard let number=estimate[key] as? NSNumber,ts_num(number),number.doubleValue==Double(number.intValue),(1...525600).contains(number.intValue) else{throw TaskAI.err("AI估时区间无效")};values.append(number.doubleValue*60)}
        guard values[0]<=values[1],values[1]<=values[2] else{throw TaskAI.err("AI估时区间无效")};return(values[0],values[1],values[2])
    }
    // 计算确定性门禁：离线额度、范围匹配、拆分和显式DDL确认。
    @objc(verdict:estimate:effort:ddl:error:) static func vld(_ context:NSDictionary,estimate:NSDictionary,effort:Double,ddl:Bool)throws->NSDictionary {
        let context=context as! TaskFields,estimate=estimate as! TaskFields,fields=context["fields"] as! TaskFields,room=context["room"] as! TaskFields,parts=context["parts"] as! [TaskFields]
        guard effort.isFinite,effort>0,effort<=31536000 else{throw TaskAI.err("请填写预计分钟")}
        var state="ready",reason="可以创建",minEff=effort,recommended=effort,upper=effort
        let offline=(estimate["offline"] as? Bool)==true,capacity=(room["capacity"] as! NSNumber).doubleValue,maxSpan=(room["max_span"] as! NSNumber).doubleValue
        let start=(fields["due_at"] as! NSNumber).doubleValue,end=(fields["deadline_at"] as! NSNumber).doubleValue
        if offline {
            var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:fields["timezone_id"] as! String)!
            let limit=calendar.date(byAdding:.day,value:3,to:Date(timeIntervalSince1970:start))!.timeIntervalSince1970
            if end>=limit {state="blocked";reason="离线窗口须不足三天"} else {state="offline";reason="待联网补评估"}
        } else {(minEff,recommended,upper)=try range(estimate)}
        var sum=0.0,longest=0.0,ids=Set<String>()
        let completed=Set(context["completed_ids"] as? [String] ?? [])
        for part in parts {
            if completed.contains(part["task_id"] as? String ?? ""){continue}
            guard let title=part["title"] as? String,let seconds=part["planned_duration"] as? NSNumber,ts_num(seconds),seconds.doubleValue>0,let id=part["task_id"] as? String,UUID(uuidString:id) != nil,ids.insert(id).inserted else{throw TaskAI.err("请完善子任务估时")}
            try TaskStore.vldTxt(title,notes:part["notes"] as? String ?? "");sum+=seconds.doubleValue;longest=max(longest,seconds.doubleValue)
        }
        if !parts.isEmpty && abs(sum-effort)>0.5 {state="split";reason="子任务用时不符"}
        if (room["conflicts"] as? Bool)==true {state="adjust";reason="请先调整常律冲突"}
        else if capacity<minEff || effort>capacity {state="adjust";reason="窗口内工时不足"}
        else if !offline && effort>upper {state="adjust";reason="投入超过合理上限"}
        else if !offline && effort<minEff {state=parts.isEmpty ? "split":"adjust";reason=parts.isEmpty ? "请先拆分复杂任务":"投入低于最低需求"}
        else if (parts.isEmpty ? effort:longest)>maxSpan {state="split";reason="请按空档拆分任务"}
        else if !offline && effort<recommended {state=ddl ? "ready":"ddl";reason=ddl ? "已确认赶DDL":"需确认赶DDL"}
        if !parts.isEmpty && abs(sum-effort)>0.5 {state="split";reason="子任务用时不符"}
        if offline {var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:fields["timezone_id"] as! String)!;if end>=calendar.date(byAdding:.day,value:3,to:Date(timeIntervalSince1970:start))!.timeIntervalSince1970 {state="blocked";reason="离线窗口须不足三天"}}
        let durations=parts.filter{!completed.contains($0["task_id"] as? String ?? "")}.compactMap{($0["planned_duration"] as? NSNumber)?.doubleValue}
        if !durations.isEmpty,fit(room["gaps"] as! [TaskFields],durations)==nil {state="adjust";reason="子任务顺序排不下"}
        if let dry=context["dry"] as? TaskFields,(dry["feasible"] as? Bool) != true {
            state = parts.isEmpty ? "split" : "adjust"
            reason = dry["reason"] as? String ?? "截止前排不下"
        }
        let target=recommended
        var result:TaskFields=["state":state,"reason":reason,"minimum":minEff,"recommended":recommended,"maximum":upper,"capacity":capacity,"max_span":maxSpan,"offline":offline,"ddl":ddl]
        let future=(context["future_gaps"] as? [TaskFields]) ?? room["gaps"] as! [TaskFields]
        if let end=durations.isEmpty ? finish(future,target):fit(future,durations){result["suggested_end"]=end}
        return result as NSDictionary
    }
    // 事务核对既有修订、重新计算时间，再一次性保存父子任务与评估。
    @objc(commit:context:estimate:effort:ddl:at:error:) static func cmt(_ store:TaskStore,context:NSDictionary,estimate:NSDictionary,effort:Double,ddl:Bool,at:Double)throws->NSDictionary {
        let ctx=context as! TaskFields,id=ctx["task_id"] as! String;var output:TaskFields?
        try store.wrTxn {pointer in do {
            var issue:NSError?;let revision=store.revision(&issue);if let issue{throw issue};guard revision==(ctx["revision"] as! NSNumber).int64Value else{throw TaskAI.err("安排已变化，请重评")}
            var fields=ctx["fields"] as! TaskFields;let parts=ctx["parts"] as! [TaskFields]
            if (fields["difficulty"] as? NSNumber)?.intValue ?? 0 == 0, let difficulty = estimate["difficulty"] as? NSNumber { fields["difficulty"] = difficulty }
            if ddl || (fields["rush"] as? NSNumber)?.boolValue == true { fields["urgency"] = 3 }
            let existing=ctx["existing"] as! Bool
            var input=fields;if existing{input["task_id"]=id}
            let fresh=try self.ctx(store,fields:input as NSDictionary,parts:parts as NSArray,at:at)
            let verdict=try vld(fresh,estimate:estimate,effort:effort,ddl:ddl) as! TaskFields
            guard ["ready","offline"].contains(verdict["state"] as! String) else{throw TaskAI.err(verdict["reason"] as! String)}
            let dry = parts.isEmpty ? try store.evaluateTask(fields:fields,effort:effort,now:at) : try store.evaluate(fields:fields,parts:parts,now:at)
            guard (dry["feasible"] as? Bool) == true else{throw TaskAI.err(dry["reason"] as? String ?? "截止前排不下")}
            if ddl {guard (estimate["ddl_verified"] as? Bool)==true,!parts.isEmpty else{throw TaskAI.err("请先取得DDL拆分")}}
            fields["planned_duration"]=effort+((ctx["completed_effort"] as? NSNumber)?.doubleValue ?? 0)
            if (fields["recurrence"] as? [String] ?? []).isEmpty {
                if !TaskWindow.dayOnly(fields) { fields["schedule_kind"] = "timed"; fields["deadline_kind"] = "timed" }
                fields["planning_mode"] = "window"
            }
            if existing {try store.updTsk(id,fields:fields)} else {_ = try store.crtTsk(fields,uuid:id)}
            if !parts.isEmpty {let expected=try TaskDivision.drft(store,task:id);_ = try TaskDivision.aply(store,task:id,parts:parts as NSArray,expected:expected)}
            if var parent=fields["parent_id"] as? String {
                while true {let rows=try store.lsTsks() as! [TaskFields],children=rows.filter{$0["parent_id"] as? String==parent && ($0["deleted"] as? Bool)==false};let total=children.reduce(0.0){$0+(($1["planned_duration"] as? NSNumber)?.doubleValue ?? 0)};if total>0{try store.updTsk(parent,fields:["planned_duration":total])};let ancestor=try store.rdTsk(parent) as! TaskFields;if let next=ancestor["parent_id"] as? String{parent=next}else{break}}
            }
            var record=estimate as! TaskFields;record["state"]=verdict["state"];record["ddl"]=ddl;record["evaluated_at"]=at;record["signature"]=try sig(store,id)
            try store.storeReview(id,data:record);output=try store.rdTsk(id) as? TaskFields;return true
        } catch{pointer?.pointee=error as NSError;return false}}
        return output! as NSDictionary
    }
    // 把既有任务或修改后的评估明确标成待补评估。
    @objc(review:task:error:) static func review(_ store:TaskStore,task:String)throws->NSDictionary {
        var review=try store.review(task) as! TaskFields
        if let signature=review["signature"] as? [TaskFields],NSDictionary(dictionary:["rows":signature]).isEqual(to:["rows":try sig(store,task)]) {return review as NSDictionary}
        review["state"]="stale";return review as NSDictionary
    }
}

// 普通待办使用包含截止日期在内的整日窗口。
enum TaskWindow {
    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static func start(_ now: Date, in calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: now)
        return calendar.component(.hour, from: now) < 8 ? day : end(day, in: calendar)
    }

    static func end(_ deadline: Date, in calendar: Calendar) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: deadline)!)
    }

    static func deadline(_ end: Date, in calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -1, to: end)!
    }

    static func dayOnly(_ task: TaskFields) -> Bool {
        task["planning_mode"] as? String == "window"
            && task["schedule_kind"] as? String == "date" && task["deadline_kind"] as? String == "date"
    }

    static func issue(_ start: Date, _ end: Date, in calendar: Calendar) -> String? {
        if end <= start { return "截止日期早于起始日期" }
        if calendar.date(byAdding: .day, value: 30, to: start).map({ end > calendar.startOfDay(for: $0) }) != false { return "任务最多30天" }
        return nil
    }

    // 未完成且未手动加星的总任务使用时间过半指示。
    static func halfway(_ task: TaskFields) -> Double? {
        guard dayOnly(task), task["status"] as? String == "needsAction", task["parent_id"] is NSNull,
              (task["starred"] as? NSNumber)?.boolValue != true,
              let start = (task["due_at"] as? NSNumber)?.doubleValue,
              let end = (task["deadline_at"] as? NSNumber)?.doubleValue, end > start else { return nil }
        return start + (end - start) / 2
    }
}
