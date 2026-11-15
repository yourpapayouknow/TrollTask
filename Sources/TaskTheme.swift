// 定义中性表面、清晰文字和橙色强调。
enum TaskTheme {
    static let edge:CGFloat=16, gap:CGFloat=8, pad:CGFloat=12, group:CGFloat=16, section:CGFloat=24
    static let base = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 29/255, green: 27/255, blue: 25/255, alpha: 1) : UIColor(red: 251/255, green: 249/255, blue: 247/255, alpha: 1) }
    static let ink = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 239/255, green: 235/255, blue: 231/255, alpha: 1) : UIColor(red: 42/255, green: 35/255, blue: 29/255, alpha: 1) }
    static let muted = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 190/255, green: 179/255, blue: 168/255, alpha: 1) : UIColor(red: 111/255, green: 101/255, blue: 93/255, alpha: 1) }
    static let control = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 51/255, green: 44/255, blue: 38/255, alpha: 1) : UIColor(red: 241/255, green: 233/255, blue: 225/255, alpha: 1) }
    static let onAccent = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 70/255, green: 32/255, blue: 7/255, alpha: 1) : .white }
    static let orange = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 255/255, green: 183/255, blue: 124/255, alpha: 1) : UIColor(red: 166/255, green: 68/255, blue: 0, alpha: 1) }
    static let danger = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 255/255, green: 180/255, blue: 171/255, alpha: 1) : UIColor(red: 179/255, green: 38/255, blue: 30/255, alpha: 1) }
}

// 仅提醒卡片与边栏保留原生磨砂材质。
func tu_gls() -> UIVisualEffectView {
    let glass = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
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
    config.baseForegroundColor = TaskTheme.ink
    button.configuration = config; button.tintColor = TaskTheme.ink
    button.imageView?.contentMode = .scaleAspectFit
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth).isActive = true
    button.contentHorizontalAlignment = .leading
    button.titleLabel?.adjustsFontForContentSizeCategory = true
    return button
}
// 只为主操作和HUD次操作提供统一实色背景。
func tu_fill(_ button: UIButton, primary: Bool = false) {
    var config = button.configuration
    config?.background.backgroundColor = primary ? lb_acnt() : TaskTheme.control
    config?.baseForegroundColor = primary ? TaskTheme.onAccent : TaskTheme.ink
    button.configuration = config
}
// 设置图标按钮的无障碍身份。
func tu_ibtn(_ icon: String, _ label: String, _ id: String, _ target: Any?, _ action: Selector?) -> UIButton {
    let button = tu_btn(nil, icon, target, action); var config=button.configuration;config?.contentInsets = .init(top:8,leading:8,bottom:8,trailing:8);button.configuration=config;button.contentHorizontalAlignment = .center
    button.accessibilityLabel = label; button.accessibilityIdentifier = id
    button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    return button
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
// 创建标签与原生控件横向行。
func tu_row(_ title: String, _ control: UIView) -> UIStackView {
    let label = tu_lbl(title); label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
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
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.4); shade.addTarget(self, action: #selector(cls), for: .touchUpInside); container.insertSubview(shade, at: 0)
        observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self, weak container] note in
            guard let self, let container else { return }; self.keyboard = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
            if self.keyboard.minY >= container.bounds.maxY { self.keyboard = .zero }
            let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
            UIView.animate(withDuration: duration) { container.setNeedsLayout(); container.layoutIfNeeded() }
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
    // 响应备注及高级字段展开。
    override func preferredContentSizeDidChange(forChildContentContainer container: UIContentContainer) { super.preferredContentSizeDidChange(forChildContentContainer: container); containerView?.setNeedsLayout() }
    // 注销键盘监听。
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
// 在系统给定的面板尺寸内完成出现和退出动画。
private final class TaskDockMotion: NSObject, UIViewControllerAnimatedTransitioning {
    private let entering: Bool
    // 保存当前转场方向。
    init(_ entering: Bool) { self.entering = entering }
    // 使用短暂原生转场。
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval { 0.2 }
    // 保持面板最终尺寸并完成系统转场。
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let key: UITransitionContextViewControllerKey = entering ? .to : .from
        guard let page = context.viewController(forKey: key) else { context.completeTransition(false); return }
        let panel = page.view!
        if entering { context.containerView.addSubview(panel); panel.frame = context.finalFrame(for: page); panel.transform = CGAffineTransform(translationX: 0, y: panel.bounds.height) }
        UIView.animate(withDuration: transitionDuration(using: context), animations: { panel.transform = self.entering ? .identity : CGAffineTransform(translationX: 0, y: panel.bounds.height) }) { _ in context.completeTransition(!context.transitionWasCancelled) }
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
    content.overrideUserInterfaceStyle = parent.traitCollection.userInterfaceStyle
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
        super.viewDidLoad(); view.accessibilityIdentifier = "menu.sheet"; tableView.backgroundColor = TaskTheme.base; tableView.separatorStyle = .none
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
        content.textProperties.color = item.attributes.contains(.disabled) ? TaskTheme.muted : ((lists || caption != nil) && selected ? lb_acnt()! : TaskTheme.ink)
        content.imageProperties.tintColor = content.textProperties.color; content.imageToTextPadding = 16
        content.directionalLayoutMargins = .init(top: 12, leading: lists && item.image == nil ? 56 : 16, bottom: 12, trailing: 16)
        if item.identifier.rawValue == "list.delete" && item.attributes.contains(.disabled) { cell.accessibilityHint="默认清单不可删除";cell.addInteraction(UIToolTipInteraction(defaultToolTip:"默认清单不可删除")) }
        cell.contentConfiguration = content; cell.accessibilityIdentifier = item.identifier.rawValue
        var background = UIBackgroundConfiguration.clear(); background.backgroundColor = lists && selected ? TaskTheme.control : .clear; background.cornerRadius = lists ? 28 : 0; background.backgroundInsets.trailing = lists ? 8 : 0; cell.backgroundConfiguration = background
        if selected { cell.accessibilityTraits.insert(.selected) }
        if selected && !lists { let check = UIImageView(image: lb_icon("check")); check.frame.size = CGSize(width: 24, height: 24); check.tintColor = lb_acnt(); cell.accessoryView = check }
        if breaks.contains(indexPath.row) { let line = UIView(); line.backgroundColor = UIColor.separator; line.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(line); NSLayoutConstraint.activate([line.leadingAnchor.constraint(equalTo: cell.leadingAnchor), line.trailingAnchor.constraint(equalTo: cell.trailingAnchor), line.topAnchor.constraint(equalTo: cell.topAnchor), line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)]) }
        if item.attributes.contains(.disabled){cell.accessibilityTraits.insert(.notEnabled);cell.selectionStyle = .none}
        cell.contentView.heightAnchor.constraint(greaterThanOrEqualToConstant:56).isActive=true;cell.tintColor = lb_acnt(); return cell
    }
    // 等待面板关闭后执行操作。
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true); run(actions[indexPath.row])
    }
    // 关闭抽屉后再执行跳转，避免在撤下期间叠加页面。
    private func run(_ item: UIAction) { guard !selecting, !isBeingDismissed, !item.attributes.contains(.disabled) else { return }; selecting = true; dismiss(animated: true) { UIButton(configuration: .plain(), primaryAction: item).sendActions(for: .touchUpInside) } }
}
