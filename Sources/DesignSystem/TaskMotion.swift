// 统一主App的弹簧、内容转场、按压与触感；HUD保持既有原生材质与节奏。
enum TaskMotion {
    enum Preset {
        case snappy, gentle, sheet, momentum
    }
    // 按response与damping换算UIKit弹簧参数；减弱动态时退回短淡入。
    private static func makeAnimator(_ preset: Preset) -> UIViewPropertyAnimator {
        if UIAccessibility.isReduceMotionEnabled { return UIViewPropertyAnimator(duration: 0.18, curve: .easeOut) }
        let value: (CGFloat, CGFloat)
        switch preset {
        case .snappy: value = (0.28, 1.0)
        case .gentle: value = (0.42, 1.0)
        case .sheet: value = (0.36, 0.9)
        case .momentum: value = (0.34, 0.84)
        }
        let stiffness = pow(2 * Double.pi / Double(value.0), 2)
        let friction = 2 * Double(value.1) * sqrt(stiffness)
        return UIViewPropertyAnimator(duration: 0.42, timingParameters: UISpringTimingParameters(mass: 1, stiffness: CGFloat(stiffness), damping: CGFloat(friction), initialVelocity: CGVector(dx: 0, dy: 0)))
    }
    // 执行一段可中断的弹簧动画。
    @discardableResult
    static func animate(_ preset: Preset = .snappy, _ animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) -> UIViewPropertyAnimator {
        let animator = makeAnimator(preset); animator.addAnimations(animations)
        if let completion { animator.addCompletion { _ in completion(true) } }
        animator.startAnimation(); return animator
    }
    // 内容切换使用短交叉淡入，避免整页跳变。
    static func crossfade(_ view: UIView, duration: TimeInterval = 0.22, _ changes: @escaping () -> Void) {
        UIView.transition(with: view, duration: UIAccessibility.isReduceMotionEnabled ? 0.16 : duration, options: [.transitionCrossDissolve, .allowAnimatedContent], animations: changes)
    }
}

// 只在实际改变状态的节点触发触感，避免整屏反馈。
enum TaskHaptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let notice = UINotificationFeedbackGenerator()
    // 页签、清单或选项切换。
    static func pick() { selection.prepare(); selection.selectionChanged() }
    // 完成、星标与短按操作。
    static func tap() { light.prepare(); light.impactOccurred() }
    // 成功与失败使用系统通知节奏。
    static func success() { notice.prepare(); notice.notificationOccurred(.success) }
    static func warning() { notice.prepare(); notice.notificationOccurred(.warning) }
}

// 为自定义按钮提供按下缩放；使用控件事件，不抢滚动视图的 Pan 手势。
private var taskPressKey: UInt8 = 0
enum TaskPress {
    static func attach(_ button: UIButton) {
        guard objc_getAssociatedObject(button, &taskPressKey) == nil else { return }
        button.addTarget(TaskPressTarget.shared, action: #selector(TaskPressTarget.down(_:)), for: [.touchDown, .touchDragEnter])
        button.addTarget(TaskPressTarget.shared, action: #selector(TaskPressTarget.up(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        objc_setAssociatedObject(button, &taskPressKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
private final class TaskPressTarget: NSObject {
    static let shared = TaskPressTarget()
    // 按下立即缩小，抬起、取消或被滚动取消时弹回。
    @objc func down(_ button: UIButton) { TaskMotion.animate(.snappy) { button.transform = CGAffineTransform(scaleX: 0.97, y: 0.97) } }
    @objc func up(_ button: UIButton) { TaskMotion.animate(.gentle) { button.transform = .identity } }
}