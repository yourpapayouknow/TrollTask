// 按TrollTask色卡定义明暗两套固定角色色，不随对比度设置漂移。
private func tu_col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
func tu_hex(_ rgb: UInt32) -> UIColor { tu_col(CGFloat(rgb >> 16), CGFloat(rgb >> 8 & 255), CGFloat(rgb & 255)) }
// 定义发丝米底、纸面卡片、墨色文字和青橙强调。
enum TaskTheme {
    static let edge:CGFloat=16, gap:CGFloat=8, pad:CGFloat=12, group:CGFloat=16, section:CGFloat=24
    // 页面底色：浅色发丝米，深色夜墨压暗。
    static let base = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0x071A24) : tu_hex(0xD8CDC4) }
    // 浮起卡片与抽屉表面：纸面 / 夜墨。
    static let surface = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0x0A2534) : tu_hex(0xFBF8F5) }
    // 正文主色。
    static let ink = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0xFBF8F5) : tu_hex(0x102F40) }
    // 次级文字，浅色使用发丝米底上仍达标的派生墨青。
    static let muted = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0x8FA6B2) : tu_hex(0x2E4B5A) }
    // 输入填充：暖象牙 / 深墨。
    static let control = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0x102F40) : tu_hex(0xF1EBE5) }
    // 清单底栏：浅色发丝米压暗，深色深墨。
    static let bar = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0x102F40) : tu_hex(0xC4B5A8) }
    // 发丝线与描边，浅色在米底上加深刻线。
    static let line = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0x1B3A4B) : tu_hex(0xB5A395) }
    // 选中胶囊：青雾 / 青墨。
    static let select = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0x006F85) : tu_hex(0xD7F5F9) }
    // 软强调底：橙雾 / 橙墨。
    static let soft = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0xA94F27) : tu_hex(0xFFE2D2) }
    static let onAccent = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0x102F40) : .white }
    static let orange = tu_hex(0xFF925B)
    static let orangeInk = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0xFF925B) : tu_hex(0xA94F27) }
    // 链接与选中：浅色在米底上加深的青，深色保持原生青。
    static let cyanInk = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0x00B5D4) : tu_hex(0x005A6B) }
    static let danger = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0xFF925B) : tu_hex(0xA94F27) }
}

// 读取与保存App明暗模式，仅作用于主App窗口，HUD保持固定深色。
enum TaskLook {
    private static let key = "appearance"
    static let names = ["跟随系统", "浅色", "深色"]
    static let styles: [UIUserInterfaceStyle] = [.unspecified, .light, .dark]
    // 返回已选模式索引。
    static var index: Int { (lb_ldcfg()[key] as? NSNumber).map { min(max($0.intValue, 0), 2) } ?? 0 }
    // 保存并立即应用到全部主窗口。
    static func pick(_ value: Int) {
        _ = lb_svcfg(["enabled": lb_ldcfg()["enabled"] ?? NSNumber(value: false), key: NSNumber(value: min(max(value, 0), 2))])
        aply(value)
    }
    // 将模式应用到主App窗口。
    static func aply(_ value: Int = index) { for scene in UIApplication.shared.connectedScenes { (scene as? UIWindowScene)?.windows.forEach { $0.overrideUserInterfaceStyle = styles[min(max(value, 0), 2)] } } }
}

// 仅提醒卡片与边栏保留原生磨砂材质，深色下偏移到色卡夜墨。
func tu_gls() -> UIVisualEffectView {
    let glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    glass.contentView.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? tu_hex(0x071A24) : .clear }
    glass.layer.cornerRadius = 20; glass.layer.cornerCurve = .continuous; glass.clipsToBounds = true
    glass.layer.borderWidth = 1 / UIScreen.main.scale; glass.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
    return glass
}

// 用不透明中性背景保持各页面对比稳定。
final class TaskBackdrop: UIView {
    // 创建无装饰动画的系统自适应表面。
    override init(frame: CGRect) {
        super.init(frame: frame); isUserInteractionEnabled = false
        accessibilityIdentifier = "theme.surface"; backgroundColor = TaskTheme.base
    }
    // 拒绝未定义的归档初始化。
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
}

// 系统分隔线换成色卡发丝线。
final class TaskHair: UIView {
    // 在父视图中插入1像素发丝线。
    override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false; backgroundColor = TaskTheme.line }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    // 在布局中固定物理1像素，不重复添加约束。
    override func layoutSubviews() { super.layoutSubviews(); let scale = window?.screen.scale ?? UIScreen.main.scale; if abs(bounds.height - 1 / scale) > 0.01 { frame.size.height = 1 / scale } }
    // 布局后保持物理1像素并在模式切换时取新颜色。
    override func didMoveToWindow() { super.didMoveToWindow(); traitCollectionDidChange(nil) }
    // 刷新动态发丝色。
    override func traitCollectionDidChange(_ previous: UITraitCollection?) { super.traitCollectionDidChange(previous); backgroundColor = TaskTheme.line }
}
// 用发丝线替换原生分隔色。
extension UITableView { func tu_rule() { separatorColor = TaskTheme.line } }

// 统一导航栏层次与中性表面。
func tu_nav(_ page: UIViewController) {
    let bar = UINavigationBarAppearance(); bar.configureWithTransparentBackground()
    bar.titleTextAttributes = [.foregroundColor: TaskTheme.ink, .font: lb_fnt(.headline, page.traitCollection)!]
    bar.largeTitleTextAttributes = [.foregroundColor: TaskTheme.ink, .font: lb_fnt(.title1, page.traitCollection)!]
    for item in [bar.buttonAppearance, bar.doneButtonAppearance, bar.backButtonAppearance] {
        item.normal.titleTextAttributes = [.foregroundColor: lb_acnt()!, .font: lb_fnt(.headline, page.traitCollection)!]
    }
    let navigation = page.navigationController?.navigationBar
    navigation?.standardAppearance = bar; navigation?.scrollEdgeAppearance = bar; navigation?.compactAppearance = bar; navigation?.tintColor = lb_acnt()
}

// 统一所有Swift页面的中性底层。
class TaskScreen: UIViewController {
    private var headHeight:NSLayoutConstraint?
    // 在安全区内容下插入原生背景。
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = TaskTheme.base; view.tintColor = lb_acnt(); navigationItem.backButtonDisplayMode = .minimal
        let backdrop = TaskBackdrop(frame: view.bounds)
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.insertSubview(backdrop, at: 0)
        tu_nav(self)
    }
    // 共用首页与直属子页的固定触摸位置。
    func hdr(_ title:UILabel,_ left:UIButton?,_ right:UIButton?,large:Bool=false) -> UIView {
        if !large {title.font=UIFontMetrics(forTextStyle:.headline).scaledFont(for:.systemFont(ofSize:20,weight:.semibold),maximumPointSize:32,compatibleWith:traitCollection);title.numberOfLines=1}
        let header=UIView();header.accessibilityIdentifier="screen.header";view.addSubview(header);tu_wdth(header,view,inset:0)
        title.translatesAutoresizingMaskIntoConstraints=false;header.addSubview(title)
        headHeight=header.heightAnchor.constraint(equalToConstant:56)
        NSLayoutConstraint.activate([header.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),headHeight!,title.centerXAnchor.constraint(equalTo:header.centerXAnchor),title.centerYAnchor.constraint(equalTo:header.centerYAnchor),title.leadingAnchor.constraint(greaterThanOrEqualTo:header.leadingAnchor,constant:56),title.trailingAnchor.constraint(lessThanOrEqualTo:header.trailingAnchor,constant:-56)])
        for (button,leading) in [(left,true),(right,false)] {
            guard let button else{continue};button.translatesAutoresizingMaskIntoConstraints=false;var style=button.configuration;style?.contentInsets=NSDirectionalEdgeInsets(top:8,leading:button.configuration?.title == nil ? 8:12,bottom:8,trailing:button.configuration?.title == nil ? 8:12);style?.imagePadding=8;style?.background.cornerRadius=12;button.configuration=style;header.addSubview(button)
            NSLayoutConstraint.activate([button.centerYAnchor.constraint(equalTo:header.centerYAnchor),button.heightAnchor.constraint(equalToConstant:56),button.widthAnchor.constraint(greaterThanOrEqualToConstant:56),leading ? button.leadingAnchor.constraint(equalTo:header.leadingAnchor):button.trailingAnchor.constraint(equalTo:header.trailingAnchor)])
            if button.configuration?.title==nil {button.widthAnchor.constraint(equalToConstant:56).isActive=true}
        }
        return header
    }
    // 直属子页沿用同一顶栏，其他页面保留系统导航。
    override func viewWillAppear(_ animated:Bool) {super.viewWillAppear(animated);navigationController?.setNavigationBarHidden(headHeight != nil,animated:false)}
    // 动态大字下保持首页与子页按钮中心一致。
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        headHeight?.constant=max(56,ceil(UIFontMetrics(forTextStyle:.title1).scaledFont(for:.systemFont(ofSize:28),compatibleWith:traitCollection).lineHeight)+8+8)
    }
    // 返回导航上一级或关闭独立设置页。
    @objc func bck() {if let navigationController,navigationController.viewControllers.count>1{navigationController.popViewController(animated:true)}else{dismiss(animated:true)}}
}

// 复用统一圆角按钮并设置模板图标。
func tu_btn(_ title: String?, _ icon: String? = nil, _ target: Any? = nil, _ action: Selector? = nil, minWidth: CGFloat = 44) -> UIButton {
    let button = lb_mkbtn(title, target, action)!
    var config = button.configuration!
    config.image = icon.flatMap { lb_icon($0) }; config.imagePadding = TaskTheme.gap; config.contentInsets = .init(top:8,leading:12,bottom:8,trailing:12)
    config.baseForegroundColor = lb_acnt()
    button.configuration = config; button.tintColor = lb_acnt()
    button.imageView?.contentMode = .scaleAspectFit
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
    button.contentHorizontalAlignment = .leading
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    TaskPress.attach(button)
    return button
}
// 只为主操作和HUD次操作提供统一实色背景和按下浅色反馈。
func tu_fill(_ button: UIButton, primary: Bool = false) {
    var config = button.configuration
    config?.background.backgroundColor = primary ? lb_acnt() : TaskTheme.control
    config?.baseForegroundColor = primary ? TaskTheme.onAccent : TaskTheme.ink
    let tint = primary ? TaskTheme.muted : TaskTheme.line
    config?.background.strokeColor = primary ? .clear : tint
    config?.background.strokeWidth = primary ? 0 : 1
    button.configuration = config
    button.configurationUpdateHandler = { [weak button] view in
        guard let button else { return }
        var style = button.configuration
        let pressed = button.isHighlighted || (view.isUserInteractionEnabled && !button.isEnabled)
        style?.background.backgroundColor = pressed ? tint : (primary ? lb_acnt() : TaskTheme.control)
        style?.baseForegroundColor = !button.isEnabled ? TaskTheme.muted : (primary ? TaskTheme.onAccent : TaskTheme.ink)
        button.configuration = style
    }
}
// 设置图标按钮的无障碍身份。
func tu_ibtn(_ icon: String, _ label: String, _ id: String, _ target: Any?, _ action: Selector?) -> UIButton {
    let button = tu_btn(nil, icon, target, action); var config=button.configuration;config?.contentInsets = .init(top:8,leading:8,bottom:8,trailing:8);button.configuration=config;button.contentHorizontalAlignment = .center
    button.accessibilityLabel = label; button.accessibilityIdentifier = id
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    return button
}
// 统一正文和输入提示的次级文字色，避免系统动态灰在中性底上对比不足。
func tu_phl(_ text: String, _ font: UIFont? = nil) -> NSAttributedString {
    var style: [NSAttributedString.Key: Any] = [.foregroundColor: TaskTheme.muted]
    if let font { style[.font] = font }
    return NSAttributedString(string: text, attributes: style)
}
// 创建动态字体标签。
func tu_lbl(_ text: String?) -> UILabel {
    let label = UILabel(); label.text = text; label.font = lb_fnt(.body, nil)
    label.adjustsFontForContentSizeCategory = true; label.textColor = TaskTheme.ink
    label.numberOfLines = 0; label.adjustsFontSizeToFitWidth = false
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}
// 统一表单输入边界、圆角和文字内边距。
func tu_fld(_ field:UIView) {
    field.backgroundColor=TaskTheme.control;field.layer.cornerRadius=12;field.layer.cornerCurve = .continuous;field.clipsToBounds=true;field.heightAnchor.constraint(greaterThanOrEqualToConstant:44).isActive=true
    if let text=field as? UITextView {text.textContainerInset = .init(top:8,left:12,bottom:8,right:12);text.textContainer.lineFragmentPadding=0}
    if let text=field as? UITextField {text.leftView=UIView(frame:CGRect(x:0,y:0,width:12,height:1));text.rightView=UIView(frame:CGRect(x:0,y:0,width:12,height:1));text.leftViewMode = .always;text.rightViewMode = .always}
}
// 统一平面列表的字体、颜色和内容边距。
func tu_cell() -> UIListContentConfiguration {
    var content=UIListContentConfiguration.subtitleCell();content.textProperties.font=lb_fnt(.body,nil);content.textProperties.color=TaskTheme.ink;content.textProperties.numberOfLines=0
    content.secondaryTextProperties.font=lb_fnt(.subheadline,nil);content.secondaryTextProperties.color=TaskTheme.muted;content.secondaryTextProperties.numberOfLines=0
    content.imageProperties.tintColor=lb_acnt()
    content.directionalLayoutMargins = .init(top:12,leading:16,bottom:12,trailing:16);content.imageToTextPadding=12;return content
}
// 使用同一组分档标签编辑待办属性。
func tu_grade(_ key: String, _ prefix: String, _ rating: Int, selected: @escaping (Int) -> Void) -> UIButton {
    let label = key == "urgency" ? "紧急程度" : "难易程度"
    let titles = key == "urgency" ? ["未设置", "低", "中", "高"] : ["未评估", "简单", "一般", "困难"]
    let button = tu_btn(label + "：" + titles[rating], "down")
    button.accessibilityIdentifier = prefix + "." + key
    button.menu = UIMenu(children: titles.enumerated().map { index, title in
        let action = tu_act(title, nil, prefix + ".\(key).\(index)") { [weak button] in
            selected(index)
            var config = button?.configuration; config?.title = label + "：" + title; button?.configuration = config
            (button?.menu?.children as? [UIAction])?.forEach { $0.state = $0.title == title ? .on : .off }
        }
        action.state = rating == index ? .on : .off
        return action
    }); button.showsMenuAsPrimaryAction = true
    return button
}
// 创建同组内容的纵向布局。
func tu_stk(_ views: [UIView]) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: views); stack.axis = .vertical; stack.spacing = TaskTheme.gap; return stack
}
// 将功能行组合为单层卡片，行间使用发丝线。
func tu_card(_ rows: [UIView]) -> UIView {
    let card = UIView(); card.backgroundColor = TaskTheme.surface; card.layer.cornerRadius = 16; card.layer.cornerCurve = .continuous; card.clipsToBounds = true
    let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 0; stack.translatesAutoresizingMaskIntoConstraints = false
    for (index, row) in rows.enumerated() {
        if index > 0 {
            let line = TaskHair(); line.translatesAutoresizingMaskIntoConstraints = false
            line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
            stack.addArrangedSubview(line)
        }
        stack.addArrangedSubview(row)
    }
    card.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: card.leadingAnchor), stack.trailingAnchor.constraint(equalTo: card.trailingAnchor), stack.topAnchor.constraint(equalTo: card.topAnchor), stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)])
    return card
}
// 创建标签与原生控件横向行。
func tu_row(_ title: String, _ control: UIView) -> UIStackView {
    let label = tu_lbl(title); label.numberOfLines = 1; label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    if control is UITextField { NSLayoutConstraint.activate([control.widthAnchor.constraint(greaterThanOrEqualToConstant:44),control.heightAnchor.constraint(greaterThanOrEqualToConstant:44)]) }
    let row = tu_stk([label, control]); row.axis = .horizontal; row.alignment = .center
    control.setContentHuggingPriority(.required, for: .horizontal)
    control.setContentCompressionResistancePriority(control is UITextField || control is UIDatePicker ? .defaultLow : .required, for: .horizontal)
    return row
}
// 约束单列最大宽度和统一边距。
func tu_wdth(_ content: UIView, _ parent: UIView, inset: CGFloat = TaskTheme.edge) {
    content.translatesAutoresizingMaskIntoConstraints = false
    let width = content.widthAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.widthAnchor, constant: -inset * 2); width.priority = UILayoutPriority(999)
    NSLayoutConstraint.activate([width, content.widthAnchor.constraint(lessThanOrEqualToConstant: 680),
        content.centerXAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.centerXAnchor),
        content.leadingAnchor.constraint(greaterThanOrEqualTo: parent.safeAreaLayoutGuide.leadingAnchor, constant: inset),
        content.trailingAnchor.constraint(lessThanOrEqualTo: parent.safeAreaLayoutGuide.trailingAnchor, constant: -inset)])
}
// 使用原生键盘布局指南避让输入。
@discardableResult func tu_form(_ parent: UIViewController, _ fields: UIStackView, _ id: String, top:UIView?=nil) -> UIScrollView {
    let scroll = UIScrollView(); scroll.accessibilityIdentifier = id; scroll.keyboardDismissMode = .interactive
    fields.spacing=TaskTheme.group;parent.view.addSubview(scroll); tu_wdth(scroll, parent.view); fields.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(fields)
    NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: top?.bottomAnchor ?? parent.view.safeAreaLayoutGuide.topAnchor, constant: 16),
        scroll.bottomAnchor.constraint(equalTo: parent.view.keyboardLayoutGuide.topAnchor, constant: -16),
        fields.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
        fields.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
        fields.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
        fields.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        fields.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
    return scroll
}
// 保留数据库错误分类并显示简短提示。
func tu_err(_ parent: UIViewController, _ error: Error) {
    NSLog("待办界面操作失败：%@", error as NSError)
    let names = ["invalid_fields":"请检查输入", "not_found":"任务已删除", "database_busy":"数据库忙碌", "duplicate_uuid":"任务编号重复"]
    if let conflicts = (error as NSError).userInfo["routine_conflicts"] as? [TaskFields] {
        let format = DateFormatter(); format.dateFormat = "MM-dd HH:mm"
        // 完整保留全部冲突标题及各自时段，系统提示在内容较多时可滚动。
        let message = conflicts.map { row -> String in
            let a = row["task"] as! TaskFields, b = row["peer"] as! TaskFields
            func span(_ start: String, _ end: String, _ task: TaskFields) -> String {
                format.timeZone = TimeZone(identifier:task["timezone_id"] as! String)
                return format.string(from:Date(timeIntervalSince1970:(row[start] as! NSNumber).doubleValue)) + "—" + format.string(from:Date(timeIntervalSince1970:(row[end] as! NSNumber).doubleValue))
            }
            return (a["title"] as! String) + "\n" + span("start_at", "end_at", a) + "\n与" + (b["title"] as! String) + "\n" + span("peer_start", "peer_end", b)
        }.joined(separator:"\n\n")
        let alert = UIAlertController(title:"常律时段冲突", message:message, preferredStyle:.alert); alert.view.tintColor = lb_acnt()
        alert.addAction(UIAlertAction(title:"返回修改", style:.cancel))
        if parent.presentedViewController == nil { parent.present(alert, animated:true) }; return
    }
    let detail = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String
    let title = detail.flatMap { !$0.isEmpty && $0.count <= 13 ? $0 : nil }
    let alert = UIAlertController(title: title ?? names[(error as NSError).userInfo["kind"] as? String ?? ""] ?? "操作失败", message: nil, preferredStyle: .alert)
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
// 用原生呈现控制器将快捷草稿贴在键盘上方。
private final class TaskDock: UIPresentationController, UIGestureRecognizerDelegate {
    private let shade = UIControl()
    private var keyboard: CGRect = .zero
    private var observer: NSObjectProtocol?
    private var contentHeight: CGFloat { (presentedViewController as? UINavigationController)?.topViewController?.preferredContentSize.height ?? presentedViewController.preferredContentSize.height }
    // 计算紧凑输入面板及展开表单的可用区域。
    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        let bounds = container.bounds, frame = container.convert(keyboard, from: nil)
        let bottom = keyboard.isEmpty ? bounds.maxY : min(bounds.maxY, frame.minY)
        let height = min(bottom - container.safeAreaInsets.top - 4, contentHeight + (keyboard.isEmpty ? container.safeAreaInsets.bottom : 0))
        return CGRect(x: 0, y: bottom - height, width: bounds.width, height: max(0, height))
    }
    // 注册键盘变化和外部取消入口。
    override func presentationTransitionWillBegin() {
        guard let container = containerView else { return }
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.4); shade.alpha = 0; shade.addTarget(self, action: #selector(cls), for: .touchUpInside); container.insertSubview(shade, at: 0)
        TaskMotion.animate(.sheet) { self.shade.alpha = 1 }
        observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self, weak container] note in
            guard let self, let container else { return }; self.keyboard = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
            if self.keyboard.minY >= container.bounds.maxY { self.keyboard = .zero }
            let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) { container.setNeedsLayout(); container.layoutIfNeeded() }
        }
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swp)); swipe.direction = .down; swipe.delegate = self; presentedView?.addGestureRecognizer(swipe)
    }
    // 顶部下拉退出，正文滚动和控件操作不触发取消。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !presentedViewController.isModalInPresentation, touch.location(in: presentedView).y <= 72 else { return false }
        var view = touch.view
        while let current = view {
            if current is UIControl { return false }
            if let scroll = current as? UIScrollView, scroll.contentOffset.y > -scroll.adjustedContentInset.top + 1 { return false }
            view = current.superview
        }
        return true
    }
    // 共用退出保护，不以卡片高度限制取消。
    @objc private func swp() { cls() }
    // 退出未提交草稿。
    @objc private func cls() { guard !presentedViewController.isModalInPresentation else{return};presentedViewController.dismiss(animated: true) }
    // 根据键盘和动态字号更新原生容器尺寸。
    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews(); shade.frame = containerView?.bounds ?? .zero
        presentedView?.frame = frameOfPresentedViewInContainerView; presentedView?.layer.cornerRadius = 20; presentedView?.layer.cornerCurve = .continuous; presentedView?.clipsToBounds = true
    }
    // 响应备注及高级字段展开，让高度变化连续而不是跳变。
    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        guard let view = containerView else { return }
        TaskMotion.animate(.gentle) { view.setNeedsLayout(); view.layoutIfNeeded() }
    }
    // 退出时同步淡出遮罩，和面板保持同一路径。
    override func dismissalTransitionWillBegin() { super.dismissalTransitionWillBegin(); TaskMotion.animate(.sheet) { self.shade.alpha = 0 } }
    // 注销键盘监听。
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
// 在系统给定的面板尺寸内完成出现和退出动画。
private final class TaskDockMotion: NSObject, UIViewControllerAnimatedTransitioning {
    private let entering: Bool
    // 保存当前转场方向。
    init(_ entering: Bool) { self.entering = entering }
    // 使用短暂原生转场。
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.38 }
    // 保持面板最终尺寸并完成系统转场。
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let key: UITransitionContextViewControllerKey = entering ? .to : .from
        guard let page = context.viewController(forKey: key) else { context.completeTransition(false); return }
        let panel = page.view!
        if entering { context.containerView.addSubview(panel); panel.frame = context.finalFrame(for: page); panel.transform = CGAffineTransform(translationX: 0, y: panel.bounds.height) }
        let target = entering ? CGAffineTransform.identity : CGAffineTransform(translationX: 0, y: panel.bounds.height)
        TaskMotion.animate(.sheet, { panel.transform = target }) { _ in context.completeTransition(!context.transitionWasCancelled) }
    }
}
// 为既有快捷编辑器提供同一个原生呈现入口。
private final class TaskDockDelegate: NSObject, UIViewControllerTransitioningDelegate {
    static let shared = TaskDockDelegate()
    // 使用原生呈现及退出动画。
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? { TaskDockMotion(true) }
    // 使用同一面板的退出动画。
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? { TaskDockMotion(false) }
    // 注入贴键盘布局，不复制编辑和保存逻辑。
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? { TaskDock(presentedViewController: presented, presenting: presenting) }
}

// 显示具有自适应高度的原生面板。
func tu_sheet(_ parent: UIViewController, _ content: UIViewController, compact: Bool = false, completion: (() -> Void)? = nil) {
    content.modalPresentationStyle = compact ? .custom : .pageSheet
    if compact {
        content.transitioningDelegate = TaskDockDelegate.shared; parent.present(content, animated: true, completion: completion); return
    }
    content.view.tintColor = lb_acnt()
    let sheet = content.sheetPresentationController
    sheet?.detents = [.medium(), .large()]
    if #available(iOS 16, *), content.preferredContentSize.height > 0 {
        let detent = UISheetPresentationController.Detent.custom(identifier: .init("content")) { [weak content] in min(content?.preferredContentSize.height ?? 0, $0.maximumDetentValue) }
        sheet?.detents = content is TaskMenu ? [detent] : [detent, .large()]
    }
    sheet?.prefersGrabberVisible = !(content is TaskMenu); parent.present(content, animated: true, completion: completion)
    sheet?.preferredCornerRadius = 20
}
// 请求原生删除确认。
func tu_cfrm(_ parent: UIViewController, _ title: String, message: String? = nil, _ work: @escaping () -> Void) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in work() }); parent.present(alert, animated: true)
}
// 在系统面板中显示完整可滚动选项。
func tu_menu(_ parent: UIViewController, _ title: String, _ actions: [UIAction], breaks: Set<Int> = [], header: UIAction? = nil, lists: Bool = false, caption: String? = nil) {
    parent.view.endEditing(true)
    let menu = TaskMenu(style: .plain); menu.actions = actions; menu.title = title; menu.breaks = breaks; menu.header = header; menu.lists = lists; menu.caption = caption
    tu_sheet(parent, menu)
}

// 按内容高度呈现无导航栏的底部抽屉。
final class TaskMenu: UITableViewController {
    var actions: [UIAction] = []
    var breaks: Set<Int> = [], header: UIAction?, lists = false
    var caption: String?
    private var selecting = false
    // 创建分组平面行，外部点击和下拉由原生面板处理。
    override func viewDidLoad() {
        super.viewDidLoad(); view.accessibilityIdentifier = "menu.sheet"; tableView.backgroundColor = TaskTheme.surface; tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension; tableView.estimatedRowHeight = 56; tableView.contentInset.top = 8
        if let header {
            let button = tu_btn(header.title); button.accessibilityIdentifier = header.identifier.rawValue; button.accessibilityLabel = "更多排序"
            var config = button.configuration; config?.baseForegroundColor = TaskTheme.muted; config?.contentInsets = .init(top: 8, leading: 16, bottom: 8, trailing: 48)
            config?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in var value = attributes; value.font = lb_fnt(.subheadline, nil); return value }; button.configuration = config
            let image = UIImageView(image: lb_icon("more")); image.tintColor = TaskTheme.muted; image.translatesAutoresizingMaskIntoConstraints = false; button.addSubview(image)
            NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 24), image.heightAnchor.constraint(equalToConstant: 24), image.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -16), image.centerYAnchor.constraint(equalTo: button.centerYAnchor)])
            button.addAction(UIAction { [weak self] _ in self?.run(header) }, for: .touchUpInside)
            button.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: max(44, lb_fnt(.subheadline, traitCollection).lineHeight + 16)); tableView.tableHeaderView = button
        }
        if let caption {
            let container = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: max(44, lb_fnt(.subheadline, traitCollection).lineHeight + 16)))
            let label = tu_lbl(caption); label.font = lb_fnt(.subheadline, traitCollection); label.textColor = TaskTheme.muted; label.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(label)
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16), label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16), label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8), label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)]); tableView.tableHeaderView = container
        }
        preferredContentSize.height = CGFloat(actions.count) * tableView.estimatedRowHeight + (tableView.tableHeaderView?.bounds.height ?? 0) + 8
    }
    // 用实际行高适配长清单和动态字号。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); let height = ceil(tableView.contentSize.height + 8)
        guard height > 8, abs(preferredContentSize.height - height) > 1 else { return }; preferredContentSize.height = height
        if #available(iOS 16, *) { sheetPresentationController?.invalidateDetents() }
    }
    // 返回菜单数量。
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { actions.count }
    // 绑定选项状态和完整标签。
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = actions[indexPath.row]; let cell = UITableViewCell(style: .default, reuseIdentifier: nil); cell.backgroundColor = .clear
        var content = UIListContentConfiguration.cell(); content.text = item.title; content.image = item.image; content.textProperties.numberOfLines = 0
        content.textProperties.font = lb_fnt(.body, traitCollection)
        content.secondaryText = item.subtitle
        content.secondaryTextProperties.font = lb_fnt(.subheadline, traitCollection)
        content.secondaryTextProperties.color = TaskTheme.muted
        content.secondaryTextProperties.numberOfLines = 0
        let selected = item.state == .on
        content.textProperties.color = item.attributes.contains(.disabled) ? TaskTheme.muted : ((lists || caption != nil) && selected ? (lists ? TaskTheme.ink : lb_acnt()!) : TaskTheme.ink)
        content.imageProperties.tintColor = content.textProperties.color; content.imageToTextPadding = 16
        content.directionalLayoutMargins = .init(top: 12, leading: lists && item.image == nil ? 56 : 16, bottom: 12, trailing: 16)
        if item.identifier.rawValue == "list.delete" && item.attributes.contains(.disabled) { cell.accessibilityHint="默认清单不可删除";cell.addInteraction(UIToolTipInteraction(defaultToolTip:"默认清单不可删除")) }
        cell.contentConfiguration = content; cell.accessibilityIdentifier = item.identifier.rawValue
        var background = UIBackgroundConfiguration.clear(); background.backgroundColor = lists && selected ? TaskTheme.select : .clear; background.cornerRadius = lists ? 28 : 0; background.backgroundInsets.trailing = lists ? 8 : 0; cell.backgroundConfiguration = background
        if selected { cell.accessibilityTraits.insert(.selected) }
        if selected && !lists { let check = UIImageView(image: lb_icon("check")); check.frame.size = CGSize(width: 24, height: 24); check.tintColor = lb_acnt(); cell.accessoryView = check }
        if breaks.contains(indexPath.row) { let line = UIView(); line.backgroundColor = UIColor.separator; line.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(line); NSLayoutConstraint.activate([line.leadingAnchor.constraint(equalTo: cell.leadingAnchor), line.trailingAnchor.constraint(equalTo: cell.trailingAnchor), line.topAnchor.constraint(equalTo: cell.topAnchor), line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)]) }
        if item.attributes.contains(.disabled){cell.accessibilityTraits.insert(.notEnabled);cell.selectionStyle = .none}
        cell.contentView.heightAnchor.constraint(greaterThanOrEqualToConstant:56).isActive=true;cell.tintColor = lb_acnt(); return cell
    }
    // 等待面板关闭后执行操作。
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if !actions[indexPath.row].attributes.contains(.disabled) { TaskHaptics.pick() }
        run(actions[indexPath.row])
    }
    // 关闭抽屉后再执行跳转，避免在撤下期间叠加页面。
    private func run(_ item: UIAction) { guard !selecting, !isBeingDismissed, !item.attributes.contains(.disabled) else { return }; selecting = true; dismiss(animated: true) { UIButton(configuration: .plain(), primaryAction: item).sendActions(for: .touchUpInside) } }
}
