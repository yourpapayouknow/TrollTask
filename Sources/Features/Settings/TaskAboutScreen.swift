// 关于页：版本、作者、仓库与鸣谢。
@objc(TaskAboutScreen) final class TaskAboutScreen: TaskScreen {
    // 建立应用标识、版本信息与来源说明。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "关于"
        let back = tu_ibtn("back", "返回设置", "about.back", self, #selector(bck))
        let header = hdr(tu_lbl(title), back, nil)
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        var marks: [UIView] = []
        if let image = appIcon() {
            let icon = UIImageView(image: image); icon.contentMode = .scaleAspectFit; icon.layer.cornerRadius = 16; icon.layer.cornerCurve = .continuous; icon.clipsToBounds = true
            NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 72), icon.heightAnchor.constraint(equalToConstant: 72)]); marks.append(icon)
        }
        let name = tu_lbl("TrollTask"); name.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 28, weight: .semibold))
        let number = tu_lbl("版本 \(version)（\(build)）"); number.font = lb_fnt(.subheadline, nil); number.textColor = TaskTheme.muted; number.accessibilityIdentifier = "about.version"
        for label in [name, number] { label.textAlignment = .center }
        marks += [name, number]
        let head = tu_stk(marks); head.alignment = .center; head.spacing = 8
        let author = row("作者", "yourpapayouknow", "about.author")
        let github = row("GitHub", "yourpapayouknow/TrollTask", "about.github", #selector(open))
        let thanks = row("MingCute", "图标 · Apache-2.0", "about.mingcute", #selector(open))
        let libical = row("Libical", "重复规则 · LGPL-2.1 / MPL-2.0", "about.libical", #selector(open))
        author.isUserInteractionEnabled = false
        let card = tu_card([author, github])
        let creditCard = tu_card([thanks, libical])
        let copyright = tu_lbl("© 2026 yourpapayouknow"); copyright.font = lb_fnt(.footnote, nil); copyright.textColor = TaskTheme.muted; copyright.textAlignment = .center
        let fields = tu_stk([head, card, tu_header("鸣谢"), creditCard, copyright]); fields.spacing = TaskTheme.section
        _ = tu_form(self, fields, "about.content", top: header)
    }
    // 构建一行只读信息，可选的链接行保留原生按压反馈。
    private func row(_ title: String, _ value: String, _ id: String, _ action: Selector? = nil) -> UIButton {
        let button = tu_btn(title, nil, action == nil ? nil : self, action); button.accessibilityIdentifier = id
        var config = button.configuration; config?.subtitle = value; config?.subtitleLineBreakMode = .byWordWrapping
        config?.contentInsets = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
        config?.titleAlignment = .leading; config?.baseForegroundColor = TaskTheme.ink
        config?.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [weak button] attributes in
            var result = attributes; result.font = lb_fnt(.subheadline, button?.traitCollection); result.foregroundColor = TaskTheme.muted; return result
        }
        button.configuration = config; button.titleLabel?.numberOfLines = 0; button.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        button.accessibilityValue = value
        return button
    }
    // 读取打包后的应用图标。
    private func appIcon() -> UIImage? {
        if let icons = (Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any],
           let names = icons["CFBundleIconFiles"] as? [String], let last = names.last, let image = UIImage(named: last) { return image }
        return UIImage(named: "AppIcon")
    }
    // 按行标识打开对应项目主页。
    @objc private func open(_ sender: UIButton) {
        let links = ["about.github": "https://github.com/yourpapayouknow/TrollTask",
                     "about.mingcute": "https://github.com/mingcute-design/mingcute-icons",
                     "about.libical": "https://github.com/libical/libical"]
        if let link = links[sender.accessibilityIdentifier ?? ""], let url = URL(string: link) { UIApplication.shared.open(url) }
    }
}