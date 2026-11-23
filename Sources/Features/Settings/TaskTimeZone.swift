// 读取新任务使用的时区设置。
enum TaskTimeZone {
    static let key = "task.defaultTimeZone"

    static var selection: String? { UserDefaults.standard.string(forKey: key) }
    static var fixed: TimeZone? { selection.flatMap { TimeZone(identifier: $0) } }
    static var current: TimeZone { fixed ?? .current }

    // 使用系统的中文城市名；保留未本地化的城市名。
    static func city(_ zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "VVV"
        return city(zone, formatter, Date())
    }

    static func city(_ zone: TimeZone, _ formatter: DateFormatter, _ date: Date) -> String {
        if zone.secondsFromGMT() == 0 && ["GMT", "UTC", "Etc/UTC", "Etc/GMT"].contains(zone.identifier) {
            return "协调世界时"
        }
        formatter.timeZone = zone
        let value = formatter.string(from: date)
        return value == "未知地点" ? zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier : value
    }
}