// 集中复用原生桥接中的UIKit、Foundation与QuartzCore类型。
typealias TaskFields = [String: Any]

// 定义压暗青橙渐变及统一文字颜色。
enum TaskTheme {
    static let teal = UIColor(red: 8/255, green: 43/255, blue: 40/255, alpha: 1)
    static let base = UIColor(red: 8/255, green: 31/255, blue: 32/255, alpha: 1)
    static let orange = UIColor(red: 53/255, green: 33/255, blue: 22/255, alpha: 1)
    static let ink = UIColor(white: 244/255, alpha: 1)
    static let muted = UIColor(red: 163/255, green: 173/255, blue: 178/255, alpha: 1)
    static let danger = UIColor(red: 1, green: 138/255, blue: 128/255, alpha: 1)
}

// 用系统图层绘制低亮渐变，离屏或减少动态效果时停止动画。
final class TaskBackdrop: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var observers: [NSObjectProtocol] = []
    // 初始化无需逐帧回调的背景。
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityIdentifier = "theme.gradient"
        let gradient = layer as! CAGradientLayer
        gradient.colors = [TaskTheme.teal.cgColor, TaskTheme.base.cgColor, TaskTheme.orange.cgColor]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        for name in [UIAccessibility.reduceMotionStatusDidChangeNotification, UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.mtn(note.name != UIApplication.willResignActiveNotification)
            })
        }
    }
    // 拒绝未定义的归档初始化。
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    // 同步窗口可见性与原生缓动。
    override func didMoveToWindow() { super.didMoveToWindow(); mtn(UIApplication.shared.applicationState == .active) }
    // 根据无障碍及前台状态启停动画。
    func mtn(_ active: Bool) {
        let gradient = layer as! CAGradientLayer
        gradient.removeAnimation(forKey: "teal-orange")
        guard active, window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        let motion = CABasicAnimation(keyPath: "colors")
        motion.fromValue = gradient.colors
        motion.toValue = [TaskTheme.orange.cgColor, TaskTheme.base.cgColor, TaskTheme.teal.cgColor]
        motion.duration = 18; motion.autoreverses = true; motion.repeatCount = .infinity
        motion.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(motion, forKey: "teal-orange")
    }
    // 释放系统通知观察者。
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
}

// 统一所有Swift页面的渐变背景。
class TaskScreen: UIViewController {
    // 在安全区内容下插入原生背景。
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = TaskTheme.base; view.tintColor = lb_acnt()
        let backdrop = TaskBackdrop(frame: view.bounds)
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.insertSubview(backdrop, at: 0)
    }
}

// 创建透明青绿按钮并复用原生统一形状。
func tu_btn(_ title: String?, _ icon: String? = nil, _ target: Any? = nil, _ action: Selector? = nil) -> UIButton {
    let button = lb_mkbtn(title, target, action)!
    var config = button.configuration!
    config.baseBackgroundColor = .clear; config.baseForegroundColor = lb_acnt()
    config.image = icon.flatMap { lb_icon($0) }; config.imagePadding = 4
    button.configuration = config; button.tintColor = lb_acnt()
    button.contentHorizontalAlignment = title?.isEmpty == false ? .leading : .center
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    return button
}
// 设置图标按钮的无障碍身份。
func tu_ibtn(_ icon: String, _ label: String, _ id: String, _ target: Any?, _ action: Selector?) -> UIButton {
    let button = tu_btn(nil, icon, target, action)
    button.accessibilityLabel = label; button.accessibilityIdentifier = id
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    return button
}
// 创建动态字体标签。
func tu_lbl(_ text: String?) -> UILabel {
    let label = UILabel(); label.text = text; label.font = .preferredFont(forTextStyle: .body)
    label.adjustsFontForContentSizeCategory = true; label.textColor = TaskTheme.ink
    label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.5
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}
// 创建唯一间距的纵向布局。
func tu_stk(_ views: [UIView]) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: views); stack.axis = .vertical; stack.spacing = 4; return stack
}
// 创建标签与原生控件横向行。
func tu_row(_ title: String, _ control: UIView) -> UIStackView {
    let label = tu_lbl(title); label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    if control is UITextField { control.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true }
    let row = tu_stk([label, control]); row.axis = .horizontal; row.alignment = .center
    control.setContentHuggingPriority(.required, for: .horizontal)
    control.setContentCompressionResistancePriority(control is UITextField || control is UIDatePicker ? .defaultLow : .required, for: .horizontal)
    return row
}
// 约束单列最大宽度和统一边距。
func tu_wdth(_ content: UIView, _ parent: UIView) {
    content.translatesAutoresizingMaskIntoConstraints = false
    let width = content.widthAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.widthAnchor, constant: -8); width.priority = .defaultHigh
    NSLayoutConstraint.activate([width, content.widthAnchor.constraint(lessThanOrEqualToConstant: 680),
        content.centerXAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.centerXAnchor),
        content.leadingAnchor.constraint(greaterThanOrEqualTo: parent.safeAreaLayoutGuide.leadingAnchor, constant: 4),
        content.trailingAnchor.constraint(lessThanOrEqualTo: parent.safeAreaLayoutGuide.trailingAnchor, constant: -4)])
}
// 使用原生键盘布局指南避让输入。
@discardableResult func tu_form(_ parent: UIViewController, _ fields: UIStackView, _ id: String) -> UIScrollView {
    let scroll = UIScrollView(); scroll.accessibilityIdentifier = id; scroll.keyboardDismissMode = .interactive
    parent.view.addSubview(scroll); tu_wdth(scroll, parent.view); fields.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(fields)
    NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: parent.view.safeAreaLayoutGuide.topAnchor, constant: 4),
        scroll.bottomAnchor.constraint(equalTo: parent.view.keyboardLayoutGuide.topAnchor, constant: -4),
        fields.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 4),
        fields.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -4),
        fields.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 4),
        fields.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -4),
        fields.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -8)])
    return scroll
}
// 保留数据库错误分类并显示简短提示。
func tu_err(_ parent: UIViewController, _ error: Error) {
    NSLog("待办界面操作失败：%@", error as NSError)
    let names = ["invalid_fields":"请检查输入", "not_found":"任务已删除", "database_busy":"数据库忙碌", "duplicate_uuid":"任务编号重复"]
    let alert = UIAlertController(title: names[(error as NSError).userInfo["kind"] as? String ?? ""] ?? "操作失败", message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .cancel))
    if parent.presentedViewController == nil { parent.present(alert, animated: true) }
}
// 拒绝对已删除任务继续编辑。
func tu_live(_ task: TaskFields) throws {
    if (task["deleted"] as? NSNumber)?.boolValue == true { throw NSError(domain: "com.iwmei.taskforiwmei.ui", code: Int(SQLITE_NOTFOUND), userInfo: ["kind":"not_found", NSLocalizedDescriptionKey:"任务已删除"]) }
}
// 在原生事务中转交Swift错误，保留回滚和提交后通知。
extension TaskStore {
    func txn(_ work: () throws -> Void) throws {
        try wrTxn { error in
            do { try work(); return true } catch let issue { error?.pointee = issue as NSError; return false }
        }
    }
}
// 建立原生功能菜单项。
func tu_act(_ title: String, _ icon: String?, _ id: String, _ work: @escaping () -> Void) -> UIAction {
    UIAction(title: title, image: icon.flatMap { lb_icon($0) }, identifier: UIAction.Identifier(id)) { _ in work() }
}
// 显示具有自适应高度的原生面板。
func tu_sheet(_ parent: UIViewController, _ content: UIViewController) {
    content.modalPresentationStyle = .pageSheet; content.overrideUserInterfaceStyle = .dark; content.view.tintColor = lb_acnt()
    let sheet = content.sheetPresentationController
    sheet?.detents = [.medium(), .large()]
    if #available(iOS 16, *), content.preferredContentSize.height > 0 {
        let height = content.preferredContentSize.height
        sheet?.detents = [.custom(identifier: .init("content")) { min(height, $0.maximumDetentValue) }, .large()]
    }
    sheet?.prefersGrabberVisible = true; parent.present(content, animated: true)
}
// 请求原生删除确认。
func tu_cfrm(_ parent: UIViewController, _ title: String, _ work: @escaping () -> Void) {
    let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in work() }); parent.present(alert, animated: true)
}
// 在系统面板中显示完整可滚动选项。
func tu_menu(_ parent: UIViewController, _ title: String, _ actions: [UIAction]) {
    let menu = TaskMenu(style: .plain); menu.actions = actions; menu.title = title
    tu_sheet(parent, UINavigationController(rootViewController: menu))
}

// 用原生列表实现无卡片嵌套的功能菜单。
final class TaskMenu: UITableViewController {
    var actions: [UIAction] = []
    // 设置透明菜单及关闭入口。
    override func viewDidLoad() {
        super.viewDidLoad(); tableView.backgroundView = TaskBackdrop(frame: tableView.bounds); tableView.backgroundColor = .clear
        tableView.separatorColor = .clear; tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 52
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "关闭", style: .plain, target: self, action: #selector(cls))
    }
    // 关闭原生面板。
    @objc private func cls() { dismiss(animated: true) }
    // 返回菜单数量。
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { actions.count }
    // 绑定选项状态和完整标签。
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = actions[indexPath.row]; let cell = UITableViewCell(style: .default, reuseIdentifier: nil); cell.backgroundColor = .clear
        var content = UIListContentConfiguration.cell(); content.text = item.title; content.image = item.image; content.textProperties.numberOfLines = 0
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.color = item.attributes.contains(.disabled) ? TaskTheme.muted : (item.attributes.contains(.destructive) ? TaskTheme.danger : TaskTheme.ink)
        content.imageProperties.tintColor = lb_acnt(); content.directionalLayoutMargins = .init(top: 4, leading: 4, bottom: 4, trailing: 4)
        cell.contentConfiguration = content; cell.accessibilityIdentifier = item.identifier.rawValue
        cell.accessoryType = item.state == .on ? .checkmark : .none; cell.tintColor = lb_acnt(); cell.isUserInteractionEnabled = !item.attributes.contains(.disabled); return cell
    }
    // 等待面板关闭后执行操作。
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true); let item = actions[indexPath.row]; guard !item.attributes.contains(.disabled) else { return }
        dismiss(animated: true) { UIButton(configuration: .plain(), primaryAction: item).sendActions(for: .touchUpInside) }
    }
}
