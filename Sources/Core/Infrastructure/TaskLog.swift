// 保留最近运行日志，供设置页查看与复制。
@objc(TaskLog) final class TaskLog: NSObject {
    private static let lock = NSLock()
    private static let limit = 200, lineLimit = 500
    private static let stamp: DateFormatter = {
        let format = DateFormatter(); format.locale = Locale(identifier: "zh_CN"); format.dateFormat = "MM-dd HH:mm:ss"; return format
    }()
    // 日志文件位于应用容器文档目录，宿主测试使用临时目录。
    private static var url: URL {
#if os(iOS)
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tasklog.txt")
#else
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tasklog.txt")
#endif
    }
    // 读取现有日志行。
    private static func read() -> [String] {
        (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
    }
    // 追加一条日志，只保留最近上限条。
    @objc static func write(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        var lines = read(); lines.append(stamp.string(from: Date()) + " " + String(flat.prefix(lineLimit)))
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    // 返回界面使用的日志行。
    @objc static func lines() -> [String] { lock.lock(); defer { lock.unlock() }; return read() }
    // 清空全部日志。
    @objc static func clear() { lock.lock(); defer { lock.unlock() }; try? FileManager.default.removeItem(at: url) }
}