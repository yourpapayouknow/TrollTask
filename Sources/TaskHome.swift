// 将任务快照绑定到原生按钮而不丢失轮次意图。
private var taskKey: UInt8 = 0

// 显示完整标题、日期时间及独立完成与星标入口。
final class TaskCell: UITableViewCell {
    let check = tu_btn(nil), star = tu_btn(nil, "star")
    let titleLabelView = tu_lbl(nil), day = tu_lbl(nil), clock = tu_lbl(nil)
    private var heights: [NSLayoutConstraint] = []
    // 创建单层透明待办行。
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier); backgroundColor = .clear; selectionStyle = .none
        check.translatesAutoresizingMaskIntoConstraints = false; star.translatesAutoresizingMaskIntoConstraints = false
        var config = check.configuration; config?.preferredSymbolConfigurationForImage = .init(pointSize: 20); check.configuration = config
        titleLabelView.numberOfLines = 0; titleLabelView.adjustsFontSizeToFitWidth = false
        for label in [day, clock] { label.textColor = TaskTheme.muted; label.font = lb_fnt(.subheadline, nil) }
        heights = [titleLabelView, day, clock].map { $0.heightAnchor.constraint(equalToConstant: 1) }
        let labels = tu_stk([titleLabelView, day, clock]); labels.translatesAutoresizingMaskIntoConstraints = false
        [check, labels, star].forEach { contentView.addSubview($0) }
        NSLayoutConstraint.activate([check.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            check.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), check.widthAnchor.constraint(equalToConstant: 44),
            check.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 4), check.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -4),
            labels.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 4), labels.trailingAnchor.constraint(equalTo: star.leadingAnchor, constant: -4),
            star.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4), star.centerYAnchor.constraint(equalTo: check.centerYAnchor), star.widthAnchor.constraint(equalToConstant: 44),
            labels.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4), labels.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)] + heights)
    }
    // 禁用未使用的归档路径。
    required init?(coder: NSCoder) { fatalError("Use init(style:reuseIdentifier:)") }
    // 绑定稳定UUID和完成时的显示快照。
    func bnd(_ task: TaskFields, _ owner: TaskHome) {
        let complete = task["status"] as? String == "completed", starred = (task["starred"] as? NSNumber)?.boolValue == true
        let id = task["task_id"] as! String
        check.accessibilityIdentifier = "task." + id; check.accessibilityLabel = complete ? "恢复待办" : "完成待办"; check.accessibilityValue = task["status"] as? String
        objc_setAssociatedObject(check, &taskKey, task, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        check.setImage(lb_icon(complete ? "check_circle" : "round"), for: .normal)
        star.accessibilityIdentifier = "star." + id; star.accessibilityLabel = starred ? "取消星标" : "添加星标"; star.accessibilityValue = starred ? "1" : "0"
        star.setImage(lb_icon(starred ? "star_fill" : "star"), for: .normal)
        check.removeTarget(nil, action: nil, for: .touchUpInside); star.removeTarget(nil, action: nil, for: .touchUpInside)
        check.addTarget(owner, action: #selector(TaskHome.tglTsk(_:)), for: .touchUpInside); star.addTarget(owner, action: #selector(TaskHome.tglStar(_:)), for: .touchUpInside)
        titleLabelView.text = task["title"] as? String; titleLabelView.accessibilityLabel = titleLabelView.text
        titleLabelView.font = lb_fnt(.body, owner.traitCollection)
        day.font = lb_fnt(.subheadline, owner.traitCollection); clock.font = day.font
        titleLabelView.textColor = complete ? TaskTheme.muted : TaskTheme.ink
        indentationLevel = task["parent_id"] is NSNull ? 0 : 1; indentationWidth = 4
        let stamp = task[complete ? "completed_at" : "remind_at"] as? NSNumber ?? task["due_at"] as? NSNumber ?? task["deadline_at"] as? NSNumber
        clock.isHidden = stamp == nil; day.text = "未设提醒"; clock.text = nil
        if let stamp = stamp {
            let format = DateFormatter(); format.locale = Locale(identifier: "zh_CN"); format.timeZone = .current; format.dateFormat = "yyyy-MM-dd"
            let date = Date(timeIntervalSince1970: stamp.doubleValue); day.text = format.string(from: date); format.dateFormat = "HH:mm"; clock.text = format.string(from: date)
        }
    }
    // 避免动态字体和小数像素产生歧义。
    func sz(_ width: CGFloat) {
        heights[0].constant = max(1, ceil(titleLabelView.sizeThatFits(CGSize(width: max(1, width - 104), height: .greatestFiniteMagnitude)).height))
        heights[1].constant = ceil(day.font.lineHeight); heights[2].constant = clock.isHidden ? 0 : ceil(clock.font.lineHeight)
    }
}

// 用原生Swift首页呈现共享数据库的两类任务。
@objc(TaskHome) final class TaskHome: TaskScreen, UITableViewDataSource, UITableViewDelegate {
    private var store: TaskStore?
    private let settings: ((UINavigationController) -> Void)?
    private let table = UITableView(frame: .zero, style: .plain), tabs = tu_stk([])
    private var tabHeight: NSLayoutConstraint!
    private var pending: [TaskFields] = [], completed: [TaskFields] = [], allPnd: [TaskFields] = [], allCmpl: [TaskFields] = [], lists: [TaskFields] = []
    private var listID = TS_DFLT_LST, sort = "date", busy: Set<String> = []
    private let queue = DispatchQueue(label: "com.iwmei.taskforiwmei.home")
    private var load = 0, token: Int32 = -1
    private var expanded = false, loaded = false, failed = false
    // 注入共享存储和设置入口。
    @objc(initWithStore:settings:) init(store: TaskStore?, settings: ((UINavigationController) -> Void)?) {
        self.store = store; self.settings = settings; super.init(nibName: nil, bundle: nil)
    }
    // 禁用未使用的归档路径。
    required init?(coder: NSCoder) { fatalError("Use init(store:settings:)") }
    // 创建横向清单、透明列表和底部功能入口。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "待办"
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: tu_ibtn("settings", "后台设置", "home.settings", self, #selector(sttng)))
        let create = tu_ibtn("add", "新建待办", "home.create", self, #selector(crt)); var config = create.configuration; config?.baseBackgroundColor = lb_acnt(); config?.baseForegroundColor = .black; create.configuration = config
        let buttons = [tu_ibtn("menu", "选择清单", "home.lists", self, #selector(lstMenu)), create, tu_ibtn("more", "清单选项", "home.more", self, #selector(more))]
        let slots = buttons.map { button -> UIView in
            let slot = UIView(); button.translatesAutoresizingMaskIntoConstraints = false; slot.addSubview(button); let size: CGFloat = button === create ? 60 : 44
            NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: size), button.heightAnchor.constraint(equalToConstant: size), button.centerXAnchor.constraint(equalTo: slot.centerXAnchor), button.centerYAnchor.constraint(equalTo: slot.centerYAnchor), slot.heightAnchor.constraint(equalToConstant: 60)]); return slot
        }
        let toolbar = tu_stk(slots); toolbar.axis = .horizontal; toolbar.distribution = .fillEqually; view.addSubview(toolbar); tu_wdth(toolbar, view)
        let strip = UIScrollView(); strip.showsHorizontalScrollIndicator = false; strip.accessibilityIdentifier = "home.tabs"; view.addSubview(strip); tu_wdth(strip, view)
        tabs.axis = .horizontal; tabs.translatesAutoresizingMaskIntoConstraints = false; strip.addSubview(tabs)
        NSLayoutConstraint.activate([tabs.leadingAnchor.constraint(equalTo: strip.contentLayoutGuide.leadingAnchor), tabs.trailingAnchor.constraint(equalTo: strip.contentLayoutGuide.trailingAnchor), tabs.topAnchor.constraint(equalTo: strip.contentLayoutGuide.topAnchor), tabs.bottomAnchor.constraint(equalTo: strip.contentLayoutGuide.bottomAnchor), tabs.heightAnchor.constraint(equalTo: strip.frameLayoutGuide.heightAnchor)])
        table.accessibilityIdentifier = "home.list"; table.backgroundColor = .clear; table.dataSource = self; table.delegate = self
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 84; table.sectionHeaderTopPadding = 0; table.separatorStyle = .none; table.keyboardDismissMode = .interactive
        table.register(TaskCell.self, forCellReuseIdentifier: "task"); view.addSubview(table); tu_wdth(table, view)
        tabHeight = strip.heightAnchor.constraint(equalToConstant: 52)
        NSLayoutConstraint.activate([toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4), strip.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4), tabHeight, table.topAnchor.constraint(equalTo: strip.bottomAnchor, constant: 4), table.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -4)])
        reg(); NotificationCenter.default.addObserver(self, selector: #selector(rfrsh), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    // 刷新共享数据。
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); rfrsh() }
    // 适应动态字体高度。
    override func viewWillLayoutSubviews() { super.viewWillLayoutSubviews(); tabHeight.constant = max(52, ceil(lb_fnt(.headline, traitCollection).lineHeight) + 16) }
    // 注册跨进程数据通知。
    private func reg() {
        guard token < 0, let store = store else { return }
        let result = notify_register_dispatch(store.changeNote, &token, .main) { [weak self] _ in self?.rfrsh() }
        if result != NOTIFY_STATUS_OK { token = -1 }
    }
    // 从同一事务读取快照，丢弃过时读取。
    @objc func rfrsh() {
        load += 1; let current = load, previous = store
        queue.async {
            var active = previous, pnd: [TaskFields] = [], cmpl: [TaskFields] = [], lists: [TaskFields] = [], issue: Error?
            do {
                if active == nil { active = try TaskStore.shrd() }
                guard let active = active else { throw NSError(domain: "store", code: 1) }
                try active.txn { pnd = try active.lsPnd() as! [TaskFields]; cmpl = try active.lsCmpl() as! [TaskFields]; lists = try active.lsLsts() as! [TaskFields] }
            } catch { issue = error }
            DispatchQueue.main.async {
                guard current == self.load else { return }; self.store = active; self.loaded = true; self.failed = issue != nil
                if let error = issue { self.pending = []; self.completed = []; NSLog("读取待办失败：%@", error as NSError) }
                else { self.allPnd = pnd; self.allCmpl = cmpl; self.lists = lists; self.fltr(); self.bldTabs(); self.reg() }
                self.table.reloadData()
            }
        }
    }
    // 打开服务设置。
    @objc private func sttng() { if let nav = navigationController { settings?(nav) } }
    // 创建快捷草稿。
    @objc private func crt() {
        guard let store = store, presentedViewController == nil else { return }
        let editor = TaskEdit(store: store, task: nil, draft: ["list_id": listID == "starred" ? TS_DFLT_LST : listID, "starred": listID == "starred"], quick: true) { [weak self] in self?.rfrsh() }
        let nav = UINavigationController(rootViewController: editor); nav.preferredContentSize = editor.preferredContentSize; tu_sheet(self, nav)
    }
    // 筛选当前清单和存储排序。
    private func fltr() {
        let star = listID == "starred"
        if !star && !lists.contains(where: { $0["list_id"] as? String == listID }) { listID = TS_DFLT_LST }
        let filter: (TaskFields) -> Bool = { star ? ($0["starred"] as? NSNumber)?.boolValue == true : $0["list_id"] as? String == self.listID }
        pending = allPnd.filter(filter); completed = allCmpl.filter(filter)
        if sort != "date" {
            let key = sort == "star" ? "starred_at" : "position", reverse = sort == "star"
            pending.sort { a, b in
                let av = a[key] as? NSNumber, bv = b[key] as? NSNumber
                if let av = av, let bv = bv, av != bv { return reverse ? av.doubleValue > bv.doubleValue : av.doubleValue < bv.doubleValue }
                if av == nil && bv != nil { return false }; if av != nil && bv == nil { return true }
                return (a["created_at"] as! NSNumber).doubleValue < (b["created_at"] as! NSNumber).doubleValue
            }
        }
    }
    // 更新清单页签。
    private func bldTabs() {
        tabs.arrangedSubviews.forEach { tabs.removeArrangedSubview($0); $0.removeFromSuperview() }
        let count = allPnd.filter { ($0["starred"] as? NSNumber)?.boolValue == true }.count
        for list in [["list_id":"starred", "title":String(count)]] + lists {
            let id = list["list_id"] as! String, selected = id == listID
            let button = tu_btn(lb_shrt(list["title"] as? String), id == "starred" ? "star_fill" : nil, self, #selector(selLst(_:)))
            button.accessibilityIdentifier = "list." + id; button.accessibilityLabel = id == "starred" ? "星标待办" : list["title"] as? String; button.accessibilityValue = selected ? "已选中" : "未选中"
            var config = button.configuration; config?.baseForegroundColor = selected ? lb_acnt() : TaskTheme.muted; button.configuration = config
            if selected { button.accessibilityTraits.insert(.selected) }; tabs.addArrangedSubview(button)
        }
        let button = tu_btn("新建清单", "add", self, #selector(crtLst)); button.accessibilityIdentifier = "home.newlist"; tabs.addArrangedSubview(button)
    }
    // 切换当前清单。
    @objc private func selLst(_ button: UIButton) {
        listID = String(button.accessibilityIdentifier!.dropFirst(5)); expanded = false
        sort = UserDefaults.standard.string(forKey: "\(store!.changeNote!).\(listID).sort") ?? "date"
        table.setEditing(false, animated: false); fltr(); bldTabs(); table.reloadData()
    }
    // 提交事务后刷新，不作乐观显示。
    private func wrt(_ work: @escaping (TaskStore) throws -> Void) {
        guard let store = store else { return }
        queue.async { var issue: Error?; do { try store.txn { try work(store) } } catch { issue = error }
            DispatchQueue.main.async { self.rfrsh(); if let issue = issue { tu_err(self, issue) } }
        }
    }
    // 编辑清单名称。
    private func lstName(_ create: Bool) {
        let alert = UIAlertController(title: create ? "新建清单" : "重命名清单", message: nil, preferredStyle: .alert), id = listID
        alert.addTextField { field in field.placeholder = "清单名称"; field.accessibilityIdentifier = "list.name"; if !create { field.text = self.lists.first { $0["list_id"] as? String == id }?["title"] as? String } }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel)); alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let name = alert.textFields?.first?.text ?? ""; self.wrt { store in if create { _ = try store.crtLst(name) } else { try store.updLst(id, title: name) } }
        }); present(alert, animated: true)
    }
    // 新建清单。
    @objc private func crtLst() { lstName(true) }
    // 展示清单切换菜单。
    @objc private func lstMenu() {
        var actions = lists.map { list -> UIAction in
            let id = list["list_id"] as! String
            let action = tu_act(lb_shrt(list["title"] as? String), "list", id) { [weak self] in let button = UIButton(); button.accessibilityIdentifier = "list." + id; self?.selLst(button) }
            action.state = id == listID ? .on : .off; return action
        }
        actions.append(tu_act("新建清单", "add", "list.create") { [weak self] in self?.crtLst() }); tu_menu(self, "任务清单", actions)
    }
    // 展示排序及清单维护。
    @objc private func more() {
        var actions: [UIAction] = []
        for (key, name) in zip(["manual", "date", "star"], ["我的顺序", "日期", "最近加星时间"]) {
            let action = tu_act(name, "sort", "sort." + key) { [weak self] in
                guard let self = self else { return }; self.sort = key; UserDefaults.standard.set(key, forKey: "\(self.store!.changeNote!).\(self.listID).sort")
                self.table.setEditing(false, animated: false); self.fltr(); self.table.reloadData()
            }; action.state = sort == key ? .on : .off; actions.append(action)
        }
        let reorder = tu_act("调整顺序", "list", "list.reorder") { [weak self] in
            guard let self = self else { return }; self.sort = "manual"; UserDefaults.standard.set("manual", forKey: "\(self.store!.changeNote!).\(self.listID).sort")
            self.fltr(); self.table.reloadData(); self.table.setEditing(!self.table.isEditing, animated: true)
        }
        if listID == "starred" || pending.isEmpty { reorder.attributes = .disabled }; actions.append(reorder)
        let rename = tu_act("重命名清单", "notes", "list.rename") { [weak self] in self?.lstName(false) }, id = listID
        let remove = tu_act("删除清单", "delete", "list.delete") { [weak self] in guard let self = self else { return }; tu_cfrm(self, "删除清单及全部任务") { self.wrt { try $0.delLst(id) } } }; remove.attributes = .destructive
        let clear = tu_act("删除所有已完成任务", "delete", "list.clear") { [weak self] in guard let self = self else { return }; tu_cfrm(self, "删除完成项及子任务") { self.wrt { try $0.clrCmpl(id) } } }; clear.attributes = .destructive
        if id == "starred" { rename.attributes = .disabled; remove.attributes = .disabled; clear.attributes = .disabled }
        if id == TS_DFLT_LST { remove.attributes = .disabled }; if completed.isEmpty { clear.attributes.insert(.disabled) }
        actions += [rename, remove, clear]; tu_menu(self, "清单选项", actions)
    }
    // 提交明确星标意图。
    @objc func tglStar(_ button: UIButton) {
        let id = String(button.accessibilityIdentifier!.dropFirst(5)), starred = button.accessibilityValue != "1"
        wrt { store in try tu_live(try store.rdTsk(id) as! TaskFields); try store.updTsk(id, fields: ["starred": starred]) }
    }
    // 进入完整详情。
    private func edt(_ task: TaskFields) {
        guard let store = store else { rfrsh(); return }
        navigationController?.pushViewController(TaskEdit(store: store, task: task) { [weak self] in self?.rfrsh() }, animated: true)
    }
    // 限定手动排序的可移动行。
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { indexPath.section == 0 && !pending.isEmpty && sort == "manual" }
    // 隐藏重复删除入口。
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }
    // 只接受同一父级的排序。
    func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt from: IndexPath, toProposedIndexPath to: IndexPath) -> IndexPath {
        guard to.section == 0, to.row < pending.count, (pending[from.row]["parent_id"] as! NSObject).isEqual(pending[to.row]["parent_id"]) else { return from }; return to
    }
    // 原子保存排序，失败重新读取。
    func tableView(_ tableView: UITableView, moveRowAt from: IndexPath, to: IndexPath) {
        var order = pending; order.insert(order.remove(at: from.row), at: to.row); tableView.reloadData()
        wrt { store in for (index, task) in order.enumerated() { let id = task["task_id"] as! String; try tu_live(try store.rdTsk(id) as! TaskFields); try store.updTsk(id, fields: ["position": index]) } }
    }
    // 切换完成区。
    @objc private func fld() { expanded.toggle(); table.reloadData() }
    // 空态重试或创建。
    @objc private func empt() { guard loaded else { return }; if failed { rfrsh() } else { crt() } }
    // 保留快照轮次并事务完成或恢复。
    @objc func tglTsk(_ button: UIButton) {
        let id = String(button.accessibilityIdentifier!.dropFirst(5)), restore = button.accessibilityValue == "completed"
        let display = objc_getAssociatedObject(button, &taskKey) as! TaskFields
        guard !busy.contains(id) else { return }; busy.insert(id); button.isEnabled = false
        wrt { store in
            defer { DispatchQueue.main.async { self.busy.remove(id) } }
            try tu_live(try store.rdTsk(id) as! TaskFields)
            if restore { try store.rstrTsk(id) } else { let cycle = display["next_cycle_at"] as? NSNumber; try store.cmplNxt(id, cycle: cycle, generation: cycle == nil ? nil : display["reminder_version"] as? NSNumber) }
        }
    }
    // 将完成任务独立分区。
    func numberOfSections(in tableView: UITableView) -> Int { 2 }
    // 提供空态和折叠完成项。
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? max(pending.count, 1) : (expanded ? completed.count : 0) }
    // 显示原生待办行或功能空态。
    func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        if path.section == 0 && pending.isEmpty {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil); cell.backgroundColor = .clear; cell.selectionStyle = .none
            let empty = tu_btn(failed ? "读取失败" : (loaded ? "暂无待办" : "正在读取"), nil, self, #selector(empt)); empty.isEnabled = loaded; empty.accessibilityIdentifier = "home.empty"
            empty.translatesAutoresizingMaskIntoConstraints = false; cell.contentView.addSubview(empty)
            NSLayoutConstraint.activate([empty.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 4), empty.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -4), empty.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 4), empty.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -4)]); return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "task", for: path) as! TaskCell
        let task = (path.section == 0 ? pending : completed)[path.row]; cell.bnd(task, self); cell.sz(tableView.bounds.width); cell.check.isEnabled = !busy.contains(task["task_id"] as! String); return cell
    }
    // 显示完成区唯一入口。
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section != 0, !completed.isEmpty else { return nil }
        let fold = tu_btn("已完成", "down", self, #selector(fld)); var config = fold.configuration; config?.preferredSymbolConfigurationForImage = .init(pointSize: 20); fold.configuration = config
        fold.accessibilityIdentifier = "home.completed"; fold.accessibilityValue = expanded ? "已展开" : "已折叠"; return fold
    }
    // 避免大字号折叠标题溢出。
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section != 0 && !completed.isEmpty ? max(44, ceil(lb_fnt(.headline, traitCollection).lineHeight + 16)) : 0.01
    }
    // 点击文字区域编辑。
    func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true); if path.section == 0 && pending.isEmpty { empt(); return }; edt((path.section == 0 ? pending : completed)[path.row])
    }
    // 注销所有数据监听。
    deinit { if token >= 0 { notify_cancel(token) }; NotificationCenter.default.removeObserver(self) }
}
