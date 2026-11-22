// 保留时刻缺失、套装边界和原始引用，不替用户猜时间。
private struct RoutineDraft {
    var title: String, role: String, start: Int?, end: Int?, notes: String, days: Set<Int>, source: String
}

// 读取固定表达式的所有捕获组。
private func tr_match(_ pattern: String, _ text: String) -> [[String]] {
    let expression = try! NSRegularExpression(pattern: pattern)
    return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
        (1..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
    }
}
// 去掉Markdown强调标记，不执行文本内容。
private func tr_text(_ value: String) -> String { value.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
// 将合法时刻转换为当地分钟。
private func tr_clock(_ text: String, near: Int?) -> Int? {
    let values = text.split(separator: "/").compactMap { part -> Int? in
        let pieces = part.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]), (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }; return hour*60+minute
    }
    if values.count == 1 { return values[0] }; if let near { return values.min(by: { abs($0-near) < abs($1-near) }) }; return nil
}
// 识别明确的一般任务时间，不把游戏和休息当作空档。
private func tr_role(_ text: String, parallel: Bool) -> String {
    if ["一般代办","一般待办","按顺序完成任务","继续完成任务","继续手头","一般工作"].contains(where: text.contains) { return "work" }
    if text.contains("休息") || text.contains("什么都不做") { return "rest" }
    return parallel ? "background" : "fixed"
}

// 迁移测试专用解析器；严格模板入口使用 load。
@objc(TaskRoutineImport) final class TaskRoutineImport: NSObject {
    // 展开周模板、显式异步及有时刻的套装，原文完整随结果返回。
    @objc(parse:source:anchor:zone:error:) static func parse(_ text: String, source: String, anchor: Date, zone: String) throws -> NSDictionary {
        guard text.utf8.count <= 1024*1024, !source.isEmpty, source.count <= 255, TimeZone(identifier: zone) != nil else {
            throw NSError(domain: "routine", code: 1, userInfo: [NSLocalizedDescriptionKey:"时间表格式无效"])
        }
        let dayNames = ["一","二","三","四","五","六","日"]
        var bundles: [String:[String]] = [:], weeks: [Int:[String]] = [:], bundle: String?, week: Int?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if bundle != nil { bundle = nil } else { let name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces); if !name.isEmpty { bundle = name; bundles[name] = [] } }
                continue
            }
            if let name = bundle { bundles[name, default: []].append(line); continue }
            if let match = tr_match("^##\\s*周([一二三四五六日天])$",line).first, let index = dayNames.firstIndex(of: match[0] == "天" ? "日" : match[0]) { week = index+1; continue }
            if let week { weeks[week, default: []].append(line) }
        }
        var drafts: [RoutineDraft] = [], warnings: [String] = []
        // 继承只有星期引用的套装；循环或缺失引用明确保留问题。
        func lines(_ day: Int, seen: Set<Int> = []) -> [String] {
            guard !seen.contains(day) else { warnings.append("周\(dayNames[day-1])模板循环引用"); return [] }
            let own = weeks[day] ?? []; var result: [String] = []
            for line in own {
                let references = tr_match("\\*\\*([^*]+)\\*\\*",line)
                if line.contains("~次日"), let name = references.first?.first, let body = bundles[name],
                    let ref = body.compactMap({ tr_match(".*##\\s*周([一二三四五六日])",$0).first?.first }).first, let index = dayNames.firstIndex(of: ref) {
                    result += lines(index+1,seen:seen.union([day])); continue
                }
                result.append(line)
            }
            return result
        }
        // 保存一个有界步骤或待确认步骤。
        func append(_ title: String, start: Int?, end: Int?, day: Int, context: String, origin: String, parallel: Bool) {
            let clean = tr_text(title); guard !clean.isEmpty else { return }
            var notes = "原文："+origin+"\n来源："+context+"\n打卡：拍照或截图"
            if start == nil || end == nil { notes += "\n时间待确认，不自动启用"; warnings.append("周\(dayNames[day-1])："+clean+"时间待确认") }
            if origin.contains("非节假日") { notes += "\n交易日/节假日需确认，可用重复例外日期调整" }
            drafts.append(RoutineDraft(title: clean,role: tr_role(clean,parallel:parallel),start:start,end:end,notes:notes,days:[day],source:source+":\(day):\(drafts.count)"))
        }
        // 展开单行时间或套装，有明确时刻才使用该时刻。
        func expand(_ line: String, day: Int, context: String, near: Int? = nil, depth: Int = 0) {
            guard depth < 4 else { warnings.append("套装嵌套过深："+context); return }
            guard let range = tr_match("^\\s*(?:[0-9]+\\.|-)\\s*(.+?)\\s*[~～]\\s*(\\S+)\\s+(.+)$",line).first else { return }
            let start = tr_clock(range[0],near:near), end = tr_clock(range[1],near:start), content = range[2]
            let parallel = tr_match("异步[0-9]+\\{([^}]+)\\}",content)
            if parallel.count > 1 {
                for part in parallel { append(part[0],start:start,end:end,day:day,context:context,origin:line,parallel:true) }; return
            }
            if let name = tr_match("\\*\\*([^*]+)\\*\\*",content).first?.first, let body = bundles[name] {
                let timed = body.filter { !tr_match("^\\s*-\\s*.+?[~～]\\S+\\s+.+$",$0).isEmpty }
                if !timed.isEmpty {
                    for step in timed { expand(step,day:day,context:context+" / "+name,near:start,depth:depth+1) }
                    let first = timed.first.flatMap { tr_match("^-\\s*(.+?)[~～]",$0).first?.first }.flatMap { tr_clock($0,near:start) }
                    if let start, let first, start != first { warnings.append(context+"套装起始与明细不一致") }
                    return
                }
                append(content,start:start,end:end,day:day,context:context,origin:line+"\n"+body.joined(separator:"\n"),parallel:false); return
            }
            append(content,start:start,end:end,day:day,context:context,origin:line,parallel:false)
        }
        for day in 1...7 {
            let own = weeks[day] ?? [], inherited = lines(day)
            let removeMarket = own.contains { $0.contains("所有关于看盘") }
            for line in inherited {
                let count = drafts.count; expand(line,day:day,context:"周"+dayNames[day-1])
                if removeMarket {
                    for index in count..<drafts.count where ["盯盘","看盘","尾盘","基金","竞猜","昨日选股"].contains(where:drafts[index].title.contains) {
                        drafts[index].title = "一般任务时段"
                        drafts[index].role = "work"; drafts[index].notes += "\n按周六原文改为一般工作"
                    }
                }
            }
        }
        let tasks = fields(drafts, anchor:anchor, zone:zone, enabled:false)
        guard !tasks.isEmpty else { throw NSError(domain:"routine",code:1,userInfo:[NSLocalizedDescriptionKey:"未找到按周时间表"]) }
        return ["source":source,"text":text,"tasks":tasks,"warnings":warnings] as NSDictionary
    }
    // 共用按周合并与当地时刻生成，保留标题原文和明确类型。
    private static func fields(_ rows: [RoutineDraft], anchor: Date, zone: String, enabled: Bool) -> [TaskFields] {
        // 同一时间同一内容合并为每周多日，不创建七份相同模板。
        var merged: [RoutineDraft] = [], indexes: [String:Int] = [:]
        for row in rows {
            let key = row.title+"|\(row.start ?? -1)|\(row.end ?? -1)|"+row.role
            if let index = indexes[key] { merged[index].days.formUnion(row.days); if !merged[index].notes.contains(row.notes) { merged[index].notes += "\n"+row.notes } }
            else { indexes[key] = merged.count; merged.append(row) }
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier:zone)!
        let today = calendar.startOfDay(for: anchor), offset = (calendar.component(.weekday,from:today)+5)%7
        let monday = calendar.date(byAdding:.day,value:-offset,to:today)!, codes = ["MO","TU","WE","TH","FR","SA","SU"]
        var tasks: [TaskFields] = []
        for (index,row) in merged.enumerated() {
            let days = row.days.sorted(), label = days.map { "周"+["一","二","三","四","五","六","日"][$0-1] }.joined(separator:"、")
            var fields: TaskFields = ["title":row.title,"notes":row.notes+"\n重复日："+label,"list_id":TS_RTN_LST,"routine_kind":row.role,
                "routine_end":row.end.map { NSNumber(value:$0) as Any } ?? NSNull(),"routine_enabled":enabled ? 1 : 0,"routine_source":"md:"+row.source,"timezone_id":zone,"position":index]
            if let start = row.start {
                let base = calendar.date(byAdding:.day,value:days[0]-1,to:monday)!
                fields["due_at"] = calendar.date(bySettingHour:start/60,minute:start%60,second:0,of:base)!.timeIntervalSince1970; fields["schedule_kind"] = "timed"
                fields["recurrence_type"] = "custom"; fields["recurrence"] = ["RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY="+days.map { codes[$0-1] }.joined(separator:",")]
            }
            tasks.append(fields)
        }
        return tasks
    }
    // 导出可直接编辑的标准Markdown模板。
    @objc static func template() -> String {
        let days = ["一", "二", "三", "四", "五", "六", "日"]
        return "# TrollTask常律模板v1\n# 每行：- 开始~结束 [固定=固定安排/工作=一般任务时段/休息=休息/并行=可并行安排] 标题\n# 使用24小时制；结束早于开始表示次日；起止不得相同。\n# 每周重复；不同行不可重叠；工作占位会自动避让；并行内容写在同一行。\n# 删除示例后填写，不用的日期可留空。\n\n" + days.map { "## 周" + $0 + "\n- 08:00~08:30 [固定] 早餐\n" }.joined(separator: "\n")
    }
    // 严格逐行校验模板，任一错误行整批拒绝。
    @objc(load:source:anchor:zone:error:) static func load(_ text: String, source: String, anchor: Date, zone: String) throws -> NSDictionary {
        let rows = text.components(separatedBy: .newlines), days = ["一", "二", "三", "四", "五", "六", "日"]
        let roles = ["固定":"fixed", "工作":"work", "休息":"rest", "并行":"background"]
        guard rows.first == "# TrollTask常律模板v1", text.utf8.count <= 1024*1024 else { throw NSError(domain:"routine",code:1,userInfo:[NSLocalizedDescriptionKey:"请使用常律模板"]) }
        var day: String?, seen = Set<String>(), headings = Set<String>(), entries: [RoutineDraft] = [], count = 0
        for (index, raw) in rows.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("## 周"), days.contains(String(line.dropFirst(4))) {
                let next = String(line.dropFirst(4))
                guard headings.insert(next).inserted else { throw NSError(domain:"routine",code:1,userInfo:[NSLocalizedDescriptionKey:"重复的星期标题"]) }
                day = next; continue
            }
            if line.hasPrefix("# ") { continue }
            let match = tr_match(#"^- ([0-9]{2}:[0-9]{2})~([0-9]{2}:[0-9]{2}) \[([^]]+)\] (.+)$"#, line).first
            guard let day, let match, let start = tr_clock(match[0], near:nil), let end = tr_clock(match[1], near:nil), start != end,
                  let role = roles[match[2]], !match[3].trimmingCharacters(in:.whitespaces).isEmpty else {
                throw NSError(domain:"routine",code:1,userInfo:[NSLocalizedDescriptionKey:"第\(index+1)行格式有误"])
            }
            let title = match[3].trimmingCharacters(in:.whitespaces)
            try TaskStore.vldTxt(title, notes: "")
            let identity = day + "|" + line
            guard seen.insert(identity).inserted, count < 1000 else { throw NSError(domain:"routine",code:1,userInfo:[NSLocalizedDescriptionKey:"存在重复或过多行"]) }
            entries.append(RoutineDraft(title:title, role:role, start:start, end:end, notes:"来源："+source, days:[days.firstIndex(of:day)!+1], source:source+":\(count)")); count += 1
        }
        guard count > 0 else { throw NSError(domain:"routine",code:1,userInfo:[NSLocalizedDescriptionKey:"模板没有常律内容"]) }
        guard !source.isEmpty, source.count <= 255, TimeZone(identifier:zone) != nil, anchor.timeIntervalSince1970.isFinite else { throw NSError(domain:"routine",code:1,userInfo:[NSLocalizedDescriptionKey:"时间表格式无效"]) }
        let tasks = fields(entries, anchor:anchor, zone:zone, enabled:true)
        return ["source":source, "text":text, "replaces":"md:"+source+":", "tasks":tasks] as NSDictionary
    }

    // 验证整周并启用正式常律，跨夜按当地日历计算。
    @objc(formal:document:anchor:zone:error:) static func formal(_ store: TaskStore, document: NSDictionary, anchor: Date, zone: String) throws -> NSDictionary {
        let issue = NSError(domain:"routine",code:1,userInfo:[NSLocalizedDescriptionKey:"正式时间表无效"])
        guard let source = document["source"] as? String, !source.isEmpty, source.count <= 255,
            let text = document["text"] as? String, text.utf8.count <= 1024*1024,
            let replaces = document["replaces"] as? String, !replaces.isEmpty,
            let entries = document["entries"] as? [TaskFields], !entries.isEmpty, entries.count <= 1000,
            let tz = TimeZone(identifier:zone), anchor.timeIntervalSince1970.isFinite else { throw issue }
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = tz
        let today = calendar.startOfDay(for:anchor), codes = ["MO","TU","WE","TH","FR","SA","SU"]
        var tasks:[TaskFields] = [], keys = Set<String>()
        for (index,entry) in entries.enumerated() {
            guard let key=entry["key"] as? String, !key.isEmpty, keys.insert(key).inserted,
                let title=entry["title"] as? String, let notes=entry["notes"] as? String,
                let role=entry["role"] as? String, ["fixed","work","rest","background"].contains(role),
                let start=entry["start"] as? Int, let end=entry["end"] as? Int,
                (0..<1440).contains(start), (0..<1440).contains(end), start != end,
                let days=entry["days"] as? [Int], !days.isEmpty, Set(days).count==days.count,
                days.allSatisfy({(1...7).contains($0)}) else { throw issue }
            try TaskStore.vldTxt(title,notes:notes)
            var first:Date?
            for offset in 0...7 {
                let date=calendar.date(byAdding:.day,value:offset,to:today)!
                guard days.contains((calendar.component(.weekday,from:date)+5)%7+1),
                    let date=calendar.date(bySettingHour:start/60,minute:start%60,second:0,of:date), date>=anchor else { continue }
                first=date; break
            }
            guard let first else { throw issue }
            tasks.append(["title":title,"notes":notes+"\n每步拍照或截图打卡。\n来源："+source,"list_id":TS_RTN_LST,
                "routine_kind":role,"routine_end":end,"routine_enabled":1,"routine_source":"formal:"+source+":"+key,
                "timezone_id":zone,"position":index,"due_at":first.timeIntervalSince1970,"schedule_kind":"timed",
                "recurrence_type":"custom","recurrence":["RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY="+days.sorted().map{codes[$0-1]}.joined(separator:",")]])
        }
        guard Set(entries.flatMap{ $0["days"] as? [Int] ?? [] }).count==7 else { throw issue }
        return try store.importRtns(["source":source,"text":text,"replaces":replaces,"tasks":tasks]) as NSDictionary
    }

}
