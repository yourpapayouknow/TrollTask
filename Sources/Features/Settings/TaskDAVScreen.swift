// 通过相同的连接测试添加百度代理及自定义WebDAV。
final class TaskDAVScreen: TaskScreen {
    private let store: TaskStore
    private let kind: TaskCloudKind
    private let prior: TaskCloudAccount?
    private let name = UITextField(), endpoint = UITextField(), user = UITextField(), password = UITextField()
    private var save: UIButton!
    private var connecting = false

    // 接收可重新连接的百度代理配置。
    init(store: TaskStore, kind: TaskCloudKind, prior: TaskCloudAccount?) {
        self.store = store
        self.kind = kind
        self.prior = prior
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(store:kind:prior:)") }

    // 表单使用动态字体及原生密码输入。
    override func viewDidLoad() {
        super.viewDidLoad()
        title = kind == .baidu ? "代理连接" : "添加连接"
        save = tu_btn("测试并添加", nil, self, #selector(connect))
        save.accessibilityIdentifier = "cloud.dav.save"
        save.configuration?.baseForegroundColor = lb_acnt()
        let back = tu_ibtn("back", "返回存储", "cloud.dav.back", self, #selector(bck))
        let heading = tu_lbl(title)
        let header = hdr(heading, back, nil)
        name.text = prior?.name
        endpoint.text = prior?.endpoint
        user.text = prior?.user
        password.text = prior?.secret
        endpoint.keyboardType = .URL
        user.textContentType = .username
        password.textContentType = .password
        password.isSecureTextEntry = true
        let inputs: [(UITextField, String, String)] = [(name, "名称", "name"), (endpoint, "WebDAV地址", "url"),
                                                       (user, "用户名", "user"), (password, "密码", "password")]
        var rows: [UIView] = []
        for (field, label, id) in inputs where field !== name || kind == .dav {
            tu_fld(field)
            field.font = lb_fnt(.body, traitCollection)
            field.textColor = TaskTheme.ink
            field.adjustsFontForContentSizeCategory = true
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.accessibilityLabel = label
            field.accessibilityIdentifier = "cloud.dav." + id
            let row = tu_stk([tu_lbl(label), field])
            row.spacing = TaskTheme.gap
            rows.append(row)
        }
        rows.append(save)
        let fields = tu_stk(rows)
        fields.spacing = TaskTheme.group
        _ = tu_form(self, fields, "cloud.dav.form", top: header)
        if kind == .baidu {
            endpoint.attributedPlaceholder = tu_phl("Mac上的WebDAV地址")
            endpoint.accessibilityHint = "填写Mac上的WebDAV代理地址"
        }
    }

    // 校验成功才写入列表，失败保留已填内容。
    @objc private func connect() {
        guard !connecting else { return }
        let title = kind == .dav ? (name.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : kind.name
        guard !title.isEmpty else { tu_err(self, TaskCloudHTTP.err("请输入名称")); return }
        guard !(user.text ?? "").contains(":") else { tu_err(self, TaskCloudHTTP.err("用户名不能含冒号")); return }
        let address = (endpoint.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var account = TaskCloudAccount(kind: kind, name: title, endpoint: address,
                                       user: user.text ?? "", secret: password.text ?? "")
        do { account.endpoint = try account.davURL().absoluteString }
        catch { tu_err(self, error); return }
        view.endEditing(true)
        save.isEnabled = false
        save.configuration?.title = "正在测试"
        connecting = true
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.save.isEnabled = true
                self.save.configuration?.title = "测试并添加"
                self.connecting = false
            }
            do {
                try await TaskCloudClient(account: account).verifyWrite()
                guard self.navigationController?.topViewController === self else { return }
                var config = try TaskCloudConfig.load()
                try config.add(account, replacing: self.prior)
                TaskArchiveSync.shared.run(self.store, force: true)
                self.bck()
            } catch {
                if self.navigationController?.topViewController === self { tu_err(self, error) }
            }
        }
    }
}