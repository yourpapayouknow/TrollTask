// 显示四种连接方式及已经通过验证的归档目标。
final class TaskCloudScreen: TaskScreen, UITableViewDataSource, UITableViewDelegate, ASWebAuthenticationPresentationContextProviding {
    private let store: TaskStore
    private let table = UITableView(frame: .zero, style: .plain)
    private var config = TaskCloudConfig()
    private var session: ASWebAuthenticationSession?
    private var connecting = false

    // 使用与归档列表相同的任务库。
    init(store: TaskStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    // 保持原生设置布局、字号和返回方式。
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "云端存储"
        let header = hdr(tu_lbl(title), tu_ibtn("back", "返回设置", "cloud.back", self, #selector(bck)), nil)
        table.dataSource = self
        table.delegate = self
        table.backgroundColor = .clear
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 56
        table.accessibilityIdentifier = "cloud.table"
        view.addSubview(table)
        tu_wdth(table, view, inset: 0)
        NSLayoutConstraint.activate([table.topAnchor.constraint(equalTo: header.bottomAnchor),
                                     table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)])
    }

    // 返回表单后显示已经验证的账户。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    // 读取钥匙串中的连接。
    private func load() {
        do { config = try TaskCloudConfig.load(); table.reloadData() }
        catch { tu_err(self, error) }
    }

    // 默认目标一直可见，已连接列表按需显示。
    func numberOfSections(in tableView: UITableView) -> Int { config.accounts.isEmpty ? 2 : 3 }

    // 提供四种固定入口和保存的连接。
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return TaskCloudKind.allCases.count
        default: return config.accounts.count
        }
    }

    // 连接和默认目标分别呈现。
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 2 ? "已连接" : nil
    }

    // 以对勾标记当前上传目标。
    func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        var content = tu_cell()
        cell.backgroundColor = TaskTheme.base
        if path.section == 0 {
            content.text = "归档顺序"
            content.secondaryText = config.archiveOrder.first.map { orderName($0) } ?? "未设置"
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "cloud.default"
        } else if path.section == 1 {
            let kind = TaskCloudKind.allCases[path.row]
            content.text = kind.name
            if !kind.isDAV && TaskCloudOAuth.registeredID(kind) == nil { content.secondaryText = "待配置授权" }
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityIdentifier = "cloud.provider." + kind.rawValue
        } else {
            let account = config.accounts[path.row]
            content.text = accountName(account)
            content.secondaryText = account.kind.isDAV ? (try? account.davURL().host) : account.user
            if account.id == config.archiveAccounts.first?.id {
                cell.accessoryType = .checkmark
                cell.accessibilityTraits.insert(.selected)
            }
            cell.accessibilityIdentifier = "cloud.account." + account.id
        }
        cell.contentConfiguration = content
        return cell
    }

    // 打开默认选择、新连接或已有账户的重新连接。
    func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true)
        guard !connecting else { return }
        switch path.section {
        case 0: showOrder()
        case 1:
            let kind = TaskCloudKind.allCases[path.row]
            open(kind, prior: kind == .baidu ? config.accounts.last(where: { $0.kind == kind }) : nil)
        default:
            let account = config.accounts[path.row]
            open(account.kind, prior: account)
        }
    }

    // 连接项和默认状态使用同一账户显示名。
    private func accountName(_ account: TaskCloudAccount) -> String {
        switch account.kind {
        case .dav: return account.name
        case .baidu: return "百度代理"
        case .google: return "Google账户"
        case .one: return "微软账户"
        }
    }

    // 使用服务名标记尚未连接的顺位。
    private func orderName(_ key: String) -> String {
        if let account = config.account(for: key) { return accountName(account) }
        return TaskCloudKind(rawValue: key)?.name ?? "连接不可用"
    }

    // 按实际归档顺序列出目标，以及可加入的已连接账户。
    private func showOrder() {
        let ordered = config.archiveOrder
        let activeIDs = Set(config.archiveAccounts.map(\.id))
        var actions = ordered.enumerated().map { index, key in
            let action = tu_act(orderName(key), nil, "cloud.order." + key) { [weak self] in self?.editOrder(key) }
            action.subtitle = config.account(for: key) == nil ? "第\(index + 1)顺位 · 未连接" : "第\(index + 1)顺位"
            return action
        }
        let others = config.accounts.filter { !activeIDs.contains($0.id) }
        actions += others.map { account in
            let action = tu_act(accountName(account), nil, "cloud.order.add." + account.id) { [weak self] in
                self?.saveOrder(ordered + [account.id])
            }
            action.subtitle = "加入顺序"
            return action
        }
        guard !actions.isEmpty else { tu_err(self, TaskCloudHTTP.err("请先连接网盘")); return }
        tu_menu(self, "归档顺序", actions, breaks: others.isEmpty ? [] : [ordered.count])
    }

    // 调整一个顺位或将其移出归档顺序。
    private func editOrder(_ key: String) {
        let order = config.archiveOrder
        guard let index = order.firstIndex(of: key) else { return }
        var actions: [UIAction] = []
        for (label, suffix, next) in [("上移", "up", index - 1), ("下移", "down", index + 1)] where order.indices.contains(next) {
            var updated = order
            updated.swapAt(index, next)
            actions.append(tu_act(label, nil, "cloud.order." + suffix) { [weak self] in self?.saveOrder(updated) })
        }
        actions.append(tu_act("移出顺序", nil, "cloud.order.remove") { [weak self] in self?.saveOrder(order.filter { $0 != key }) })
        tu_menu(self, orderName(key), actions)
    }

    // 立即保存顺序，并在可用目标上继续待上传任务。
    private func saveOrder(_ order: [String]) {
        do {
            var latest = try TaskCloudConfig.load()
            let previous = latest.archiveAccounts.map(\.id)
            try latest.setOrder(order)
            load()
            if previous != latest.archiveAccounts.map(\.id) { TaskArchiveSync.shared.run(store, force: true) }
            if !order.isEmpty || !config.accounts.isEmpty { showOrder() }
        } catch { tu_err(self, error) }
    }

    // 复用各服务已验证的连接入口。
    private func open(_ kind: TaskCloudKind, prior: TaskCloudAccount?) {
        if kind.isDAV {
            navigationController?.pushViewController(TaskDAVScreen(store: store, kind: kind, prior: prior), animated: true)
        } else { signIn(kind) }
    }

    // OAuth凭证只经系统认证窗口返回。
    private func signIn(_ kind: TaskCloudKind) {
        do {
            let flow = try TaskCloudOAuth(kind)
            let auth = ASWebAuthenticationSession(url: flow.url, callbackURLScheme: flow.scheme) { [weak self] url, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.session = nil
                    defer { self.connecting = false }
                    do {
                        if let error { throw error }
                        guard let url else { throw TaskCloudHTTP.err("登录回调无效") }
                        let account = try await flow.connect(url)
                        var latest = try TaskCloudConfig.load()
                        try latest.add(account)
                        self.load()
                        TaskArchiveSync.shared.run(self.store, force: true)
                    } catch {
                        if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin { tu_err(self, error) }
                    }
                }
            }
            auth.presentationContextProvider = self
            session = auth
            connecting = auth.start()
            if !connecting { session = nil; throw TaskCloudHTTP.err("无法打开登录窗口") }
        } catch { tu_err(self, error) }
    }

    // 使用当前可见设置窗口呈现系统授权。
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window ?? ASPresentationAnchor()
    }
}

// 通过相同的连接测试添加百度代理及自定义WebDAV。
private final class TaskDAVScreen: TaskScreen {
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
            endpoint.accessibilityHint = "填写Mac上的WebDAV代理地址"
            endpoint.addInteraction(UIToolTipInteraction(defaultToolTip: "填写Mac上的WebDAV代理地址"))
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
