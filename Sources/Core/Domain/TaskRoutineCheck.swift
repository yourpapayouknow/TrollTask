// 复用原生重复展开，完整验证常律之间的真实时段。
@objc(TaskRoutineCheck) final class TaskRoutineCheck: NSObject {
    private struct Pattern {
        let task: TaskFields, calendar: Calendar, period: Int?, step: Int
    }
    private struct Span {
        let start: Double, end: Double
    }
    // 返回用户可直接修正的校验错误。
    private static func fail(_ text: String) -> NSError { NSError(domain: "routine", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    // 计算有界的完整公倍周期。
    private static func period(_ a: Int, _ b: Int) throws -> Int {
        var x = a, y = b
        while y != 0 { let next = x % y; x = y; y = next }
        guard a / x <= 36600 / b else { throw fail("请设置重复结束") }
        return a / x * b
    }
    // 简单日周规则按完整周期检查，其他规则必须有结束范围。
    private static func pattern(_ task: TaskFields, at: Double) throws -> Pattern {
        let lines = task["recurrence"] as? [String] ?? []
        guard let zone = TimeZone(identifier: task["timezone_id"] as? String ?? ""),
              task["due_at"] is NSNumber, task["routine_end"] is NSNumber, !lines.isEmpty else { throw fail("常律时段不完整") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var simple = zone.nextDaylightSavingTimeTransition(after: Date(timeIntervalSince1970: at - 172800)) == nil
        var finite = true, cycle = 7, step = Int.max, rules = 0
        let allowed: Set<String> = ["FREQ", "INTERVAL", "BYDAY", "WKST", "COUNT", "UNTIL"]
        for raw in lines {
            let line = raw.uppercased()
            guard line.hasPrefix("RRULE:") else { simple = false; continue }
            rules += 1
            let pairs = line.dropFirst(6).split(separator: ";").map { $0.split(separator: "=", maxSplits: 1) }
            let fields = Dictionary(pairs.filter { $0.count == 2 }.map { (String($0[0]), String($0[1])) }, uniquingKeysWith: { _, new in new })
            finite = finite && (fields["COUNT"] != nil || fields["UNTIL"] != nil)
            if let count = fields["COUNT"].flatMap(Int.init), count > 20000 { throw fail("重复范围过长") }
            let interval = Int(fields["INTERVAL"] ?? "1") ?? 0
            let days = (fields["BYDAY"] ?? "").split(separator: ",").map(String.init)
            let basic = allowed.isSuperset(of: fields.keys) && days.allSatisfy { ["MO", "TU", "WE", "TH", "FR", "SA", "SU"].contains($0) }
            if basic && interval > 0 && interval <= 36600 && ["DAILY", "WEEKLY"].contains(fields["FREQ"] ?? "") {
                let count = interval * (fields["FREQ"] == "WEEKLY" ? 7 : 1)
                if count <= 36600 { if let complete = try? period(cycle, count) { cycle = complete } else { simple = false }
                    step = min(step, fields["FREQ"] == "DAILY" ? interval : 1) }
                else { simple = false }
            } else { simple = false }
        }
        if rules == 0 { simple = false }
        guard simple || finite else { throw fail("请设置重复结束") }
        return Pattern(task: task, calendar: calendar, period: simple ? cycle : nil, step: max(1, step == Int.max ? 1 : step))
    }
    // 沿用当地日历的跨夜结束语义。
    private static func span(_ value: Double, _ pattern: Pattern) -> Span {
        let minute = (pattern.task["routine_end"] as! NSNumber).intValue, start = Date(timeIntervalSince1970: value)
        var end = pattern.calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: start)!
        if end <= start { end = pattern.calendar.date(byAdding: .day, value: 1, to: end)! }
        return Span(start: value, end: end.timeIntervalSince1970)
    }
    // 有限规则一次有界展开，超出能力时阻止保存，不按短窗口放行。
    private static func spans(_ pattern: Pattern, from: Double, until: Double?, at: Double) throws -> [Span] {
        let limit = until.map { min(20001, max(8, Int(ceil(($0 - from) / 86400 / Double(pattern.step))) + 8)) } ?? 20001
        let values = try TaskRule.cycles(pattern.task, at: from, limit: UInt(limit)) as! [NSNumber]
        let future = values.filter { $0.doubleValue >= from }
        if future.count >= 20001 && (until == nil || future.last!.doubleValue < until!) { throw fail("重复范围过长") }
        return values.map { span($0.doubleValue, pattern) }.filter { $0.end > at && (until == nil || $0.start < until!) }
    }
    // 查找两个有序时段集合的首个真实交集，首尾相接不算重叠。
    private static func overlap(_ first: [Span], _ second: [Span]) -> (Span, Span)? {
        var i = 0, j = 0
        while i < first.count && j < second.count {
            let a = first[i], b = second[j]
            if a.start < b.end && b.start < a.end { return (a, b) }
            if a.end <= b.start { i += 1 } else { j += 1 }
        }
        return nil
    }
    // 时间摘要从实际规则读取频率和星期，避免自定义规则一律显示同一标签。
    static func rptTxt(_ task: TaskFields) -> String {
        let rules = task["recurrence"] as? [String] ?? []
        guard rules.count == 1, rules[0].hasPrefix("RRULE:") else { return rules.isEmpty ? "不重复" : "自定重复" }
        let parts = rules[0].dropFirst(6).split(separator:";").map { $0.split(separator:"=", maxSplits:1) }
        let fields = Dictionary(parts.filter{$0.count == 2}.map{(String($0[0]),String($0[1]))}, uniquingKeysWith:{_,new in new})
        let interval = Int(fields["INTERVAL"] ?? "1") ?? 1
        let days = (fields["BYDAY"] ?? "").split(separator:",").map(String.init)
        let names = ["MO":"一", "TU":"二", "WE":"三", "TH":"四", "FR":"五", "SA":"六", "SU":"日"]
        let units = ["DAILY":"天", "WEEKLY":"周", "MONTHLY":"月", "YEARLY":"年"]
        guard let unit = units[fields["FREQ"] ?? ""] else { return "自定重复" }
        var text = interval == 1 ? ["天":"每天", "周":"每周", "月":"每月", "年":"每年"][unit]! : "每\(interval)"+unit
        if fields["FREQ"] == "WEEKLY", !days.isEmpty, days.allSatisfy({names[$0] != nil}) {
            if interval == 1 && Set(days) == Set(["MO","TU","WE","TH","FR"]) { text = "工作日" }
            else { text += days.compactMap{names[$0]}.joined(separator:"、") }
        } else if let day = fields["BYMONTHDAY"] { text += day+"日" }
        else if !days.isEmpty { return "自定重复" }
        if fields["COUNT"] != nil || fields["UNTIL"] != nil { text += "·有限" }
        return text
    }
    // 返回全部冲突事项，每对事项保留首次冲突时段。
    @objc(check:against:at:error:) static func check(_ tasks: [TaskFields], against peers: [TaskFields], at: Double) throws -> NSArray {
        var patterns: [String: Pattern] = [:], finite: [String: [Span]] = [:], result: [TaskFields] = []
        let candidates = tasks.filter { ($0["routine_kind"] as? String ?? "none") != "none" && ($0["deleted"] as? NSNumber)?.boolValue != true && $0["status"] as? String != "completed" }
        let identities = Set(candidates.compactMap { $0["task_id"] as? String })
        let existing = peers.filter { !identities.contains($0["task_id"] as? String ?? "") && ($0["routine_kind"] as? String ?? "none") != "none" && ($0["deleted"] as? NSNumber)?.boolValue != true && $0["status"] as? String != "completed" && $0["due_at"] is NSNumber && $0["routine_end"] is NSNumber }
        // 每项只解析一次；同身份的编辑排除旧记录。
        func load(_ task: TaskFields) throws -> Pattern {
            let id = task["task_id"] as! String
            if let value = patterns[id] { return value }
            let value = try pattern(task, at: at); patterns[id] = value
            if value.period == nil {
                // 先检查未应用例外的原始规模，避免大量被排除的轮次耗尽展开时间。
                var raw = task; raw["recurrence"] = (task["recurrence"] as! [String]).filter { !$0.hasPrefix("EX") }
                let unfiltered = try TaskRule.cycles(raw, at:at - 172800, limit:20001) as! [NSNumber]
                if unfiltered.filter({$0.doubleValue >= at - 172800}).count >= 20001 { throw fail("重复范围过长") }
                finite[id] = try spans(value, from: at - 172800, until: nil, at: at)
            }
            return value
        }
        // 记录完整事项和真实起止，交给同一个错误面板展示。
        func add(_ a: Pattern, _ b: Pattern, _ pair: (Span, Span)) {
            result.append(["task": a.task, "peer": b.task, "start_at": pair.0.start, "end_at": pair.0.end, "peer_start": pair.1.start, "peer_end": pair.1.end])
        }
        for (index, task) in candidates.enumerated() {
            let a = try load(task), id = task["task_id"] as! String
            if task["routine_kind"] as? String != "work", let own = finite[id], own.count > 1 {
                for i in 1..<own.count where own[i].start < own[i - 1].end { add(a, a, (own[i - 1], own[i])); break }
            }
            for peer in existing + Array(candidates.prefix(index)) where peer["task_id"] as? String != id {
                let b = try load(peer), peerID = peer["task_id"] as! String
                // 工作是可用容量占位，排程时减去具体常律，而非第二条固定事项。
                if task["routine_kind"] as? String == "work" || peer["routine_kind"] as? String == "work" { continue }
                if let aDays = a.period, let bDays = b.period {
                    let days = try period(aDays, bDays), anchor = max(at, (task["due_at"] as! NSNumber).doubleValue, (peer["due_at"] as! NSNumber).doubleValue)
                    let start = anchor - 172800, end = anchor + Double(days + 2) * 86400
                    if let pair = try overlap(spans(a, from: start, until: end, at: at), spans(b, from: start, until: end, at: at)) { add(a, b, pair) }
                } else if let left = finite[id], let right = finite[peerID] {
                    if let pair = overlap(left, right) { add(a, b, pair) }
                } else {
                    let sparse = finite[id] ?? finite[peerID]!, repeating = a.period == nil ? b : a
                    for interval in sparse {
                        let values = try spans(repeating, from: interval.start - 172800, until: interval.end, at: at)
                        if let pair = overlap([interval], values) { add(a, b, a.period == nil ? pair : (pair.1, pair.0)); break }
                    }
                }
            }
        }
        return result as NSArray
    }
}
