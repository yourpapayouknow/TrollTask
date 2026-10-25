// 共享隔离时钟，生产测试不修改设备或Mac系统时间。
final class TestClock {
    private let lock = NSLock()
    private var value: TimeInterval
    // 设置测试绝对时间。
    init(_ value: TimeInterval) { self.value = value }
    // 跨调度线程读取同一绝对时间。
    func rd() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
    // 模拟前后跳时或挂起期间经过的时间。
    func set(_ value: TimeInterval) { lock.lock(); self.value = value; lock.unlock() }
}
