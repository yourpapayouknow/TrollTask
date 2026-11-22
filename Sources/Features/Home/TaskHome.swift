// 将任务快照绑定到原生按钮而不丢失轮次意图。
private var taskKey: UInt8 = 0

// 显示完整标题、日期时间及独立完成与星标入口。
final class TaskCell: UITableViewCell {
    let check = tu_btn(nil, minWidth: 0), trailing = tu_btn(nil, "star", minWidth: 0)
    let titleLabelView = tu_lbl(nil), day = tu_lbl(nil), clock = tu_lbl(nil)
    private var heights: [NSLayoutConstraint] = [],iconHeights:[NSLayoutConstraint]=[]
    private var labelTop: NSLayoutConstraint!
    private var rowEdges: [NSLayoutConstraint] = []
    private let routineCard = UIView()
    private var checkWidth:NSLayoutConstraint!,trailingWidth:NSLayoutConstraint!,trailingEdge:NSLayoutConstraint!,indent:NSLayoutConstraint!,reserved:CGFloat=112
    private var starCenter:NSLayoutConstraint!,deleteCenter:NSLayoutConstraint!
    private var metadata: UIStackView!
    private var shownID: String?, lastComplete = false, lastStarred = false, lastLit = false
    private let metadataSpace = UIView()
    // 创建单层透明待办行。
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier); backgroundColor = .clear; selectionStyle = .none
        check.translatesAutoresizingMaskIntoConstraints = false; trailing.translatesAutoresizingMaskIntoConstraints = false
        check.contentHorizontalAlignment = .center; trailing.contentHorizontalAlignment = .center
        var config = check.configuration; config?.preferredSymbolConfigurationForImage = .init(pointSize: 20); check.configuration = config
        titleLabelView.numberOfLines = 0; titleLabelView.adjustsFontSizeToFitWidth = false
        for label in [day, clock] { label.textColor = TaskTheme.muted; label.font = lb_fnt(.subheadline, nil) }
        heights = [titleLabelView, day, clock].map { $0.heightAnchor.constraint(equalToConstant: 1) }
        metadata = tu_stk([day, clock, metadataSpace]); metadata.axis = .horizontal; metadata.spacing=4; metadata.alignment = .center; metadata.distribution = .fill
        day.setContentHuggingPriority(.required, for: .horizontal); clock.setContentHuggingPriority(.required, for: .horizontal)
        let labels = tu_stk([titleLabelView, metadata]); labels.spacing = 4; labels.translatesAutoresizingMaskIntoConstraints = false
        routineCard.accessibilityIdentifier = "routine.card"
        routineCard.isUserInteractionEnabled = false
        routineCard.isHidden = true
        routineCard.backgroundColor = TaskTheme.surface
        routineCard.layer.cornerRadius = 16
        routineCard.layer.cornerCurve = .continuous
        routineCard.layer.borderColor = TaskTheme.line.cgColor
        routineCard.layer.borderWidth = 1 / UIScreen.main.scale
        contentView.addSubview(routineCard)
        [check, labels, trailing].forEach { contentView.addSubview($0) }
        checkWidth=check.widthAnchor.constraint(equalToConstant:56);trailingWidth=trailing.widthAnchor.constraint(equalToConstant:56)
        trailingEdge=trailing.trailingAnchor.constraint(equalTo:contentView.trailingAnchor)
        starCenter=trailing.centerYAnchor.constraint(equalTo:check.centerYAnchor);indent=check.leadingAnchor.constraint(equalTo:contentView.leadingAnchor)
        deleteCenter=trailing.centerYAnchor.constraint(equalTo:contentView.centerYAnchor)
        labelTop=labels.topAnchor.constraint(equalTo:contentView.topAnchor,constant:12);iconHeights=[check.heightAnchor.constraint(equalToConstant:44),trailing.heightAnchor.constraint(equalToConstant:44)]
        rowEdges = [check.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
                    check.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
                    labels.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)]
        NSLayoutConstraint.activate([indent!,
            checkWidth,
            labels.leadingAnchor.constraint(equalTo: check.trailingAnchor), labels.trailingAnchor.constraint(equalTo: trailing.leadingAnchor),
            trailingEdge!, starCenter!, trailingWidth!,
            labelTop!] + rowEdges + heights + iconHeights)
    }
    // 单层卡片只保留发丝描边，半身高卡片不使用硬阴影。
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !routineCard.isHidden, contentView.bounds.width > TaskTheme.edge * 2,
              contentView.bounds.height > TaskTheme.gap else { return }
        routineCard.frame = contentView.bounds.insetBy(dx: TaskTheme.edge, dy: TaskTheme.gap / 2)
    }
    // 明暗切换后刷新常律卡片描边。
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        routineCard.layer.borderColor = TaskTheme.line.cgColor
    }
    // 禁用未使用的归档路径。
    required init?(coder: NSCoder) { fatalError("Use init(style:reuseIdentifier:)") }
    // 绑定稳定UUID和完成时的显示快照。
    func bnd(_ task: TaskFields, _ owner: TaskHome) {
        let complete = task["status"] as? String == "completed", starred = (task["starred"] as? NSNumber)?.boolValue == true
        let halfway = TaskWindow.halfway(task).map { $0 <= Date().timeIntervalSince1970 } ?? false
        let lit = starred || halfway
        let id = task["task_id"] as! String
        let same = shownID == id
        let completeChanged = same && lastComplete != complete
        let starChanged = same && (lastStarred != starred || lastLit != lit)
        let today = owner.todayOnly, routine = task["list_id"] as? String == TS_RTN_LST
        let card = owner.routineOnly
        check.isHidden = !today || complete
        trailing.isHidden = !card && (today || routine)
        trailing.isEnabled = !card || !owner.isBusy(id)
        let cardInset = TaskTheme.edge + TaskTheme.pad
        checkWidth.constant = card ? cardInset : today ? 56 : 16
        trailingWidth.constant = card ? 44 : today ? 0 : routine ? 16 : 56
        trailingEdge.constant = card ? -TaskTheme.edge : 0
        if card {
            starCenter.isActive = false; deleteCenter.isActive = true
        } else {
            deleteCenter.isActive = false; starCenter.isActive = true
        }
        reserved = checkWidth.constant + trailingWidth.constant - trailingEdge.constant
        routineCard.isHidden = !card
        accessibilityIdentifier=owner.routineOnly ? "routine.task."+id:nil;metadata.isHidden=false
        let large = owner.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        metadata.axis = large ? .vertical : .horizontal; metadata.alignment = large ? .fill : .center; metadataSpace.isHidden = large
        check.accessibilityIdentifier = "task." + id; check.accessibilityLabel = "打开提醒提交"; check.accessibilityValue = task["status"] as? String
        objc_setAssociatedObject(check, &taskKey, task, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        check.setImage(lb_icon(complete ? "check_circle" : "round"), for: .normal)
        var mark = check.configuration; mark?.baseForegroundColor = complete ? lb_acnt() : TaskTheme.muted; check.configuration = mark
        if completeChanged, let image = check.imageView {
            image.transform = CGAffineTransform(scaleX: 0.78, y: 0.78)
            TaskMotion.animate(.gentle) { image.transform = .identity }
        }
        trailing.accessibilityIdentifier = (card ? "routine.delete." : "star.") + id
        trailing.accessibilityLabel = card ? "删除常律" : (starred ? "取消星标" : "添加星标")
        trailing.accessibilityValue = card ? task["title"] as? String : (starred ? "1" : halfway ? "时间已过半" : "0")
        objc_setAssociatedObject(trailing, &taskKey, card ? task : nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        trailing.setImage(lb_icon(card ? "close" : (lit ? "star_fill" : "star")), for: .normal)
        var action = trailing.configuration
        action?.contentInsets = .init(top:8,leading:card ? 8 : 12,bottom:8,trailing:card ? 8 : 12)
        action?.baseForegroundColor = card ? TaskTheme.muted : (lit ? TaskTheme.orangeInk : TaskTheme.muted)
        trailing.configuration = action
        if starChanged, let image = trailing.imageView {
            image.transform = CGAffineTransform(scaleX: 0.78, y: 0.78)
            TaskMotion.animate(.gentle) { image.transform = .identity }
        }
        check.removeTarget(nil, action: nil, for: .touchUpInside); trailing.removeTarget(nil, action: nil, for: .touchUpInside)
        check.addTarget(owner, action: #selector(TaskHome.tglTsk(_:)), for: .touchUpInside)
        trailing.addTarget(owner, action: card ? #selector(TaskHome.delRtn(_:)) : #selector(TaskHome.tglStar(_:)), for: .touchUpInside)
        let role = task["routine_kind"] as? String ?? "none"
        check.isEnabled = today && !complete && (role == "none" || (!["work","rest"].contains(role) && (task["routine_enabled"] as? NSNumber)?.boolValue == true)) && ((task["remind_at"] as? NSNumber)?.doubleValue ?? .infinity)<=Date().timeIntervalSince1970
        if !check.isEnabled { check.setImage(lb_icon("time"), for: .normal); check.accessibilityLabel = ["work":"一般任务时段","rest":"休息"][role] ?? "已停用" }
        titleLabelView.text = task["title"] as? String; titleLabelView.accessibilityLabel = titleLabelView.text
        titleLabelView.font = lb_fnt(.body, owner.traitCollection)
        // 常律卡片按正文高度排版，其他行沿用图标触摸列。
        let line = titleLabelView.font.lineHeight
        let height = card ? line : max(44, line)
        let rowPadding = TaskTheme.pad + (card ? TaskTheme.gap / 2 : 0)
        rowEdges[0].constant = rowPadding
        rowEdges[1].constant = -rowPadding
        rowEdges[2].constant = -rowPadding
        iconHeights[0].constant = height
        iconHeights[1].constant = card ? 44 : height
        labelTop.constant = rowPadding + (height - line) / 2
        day.font = lb_fnt(.subheadline, owner.traitCollection); clock.font = day.font
        titleLabelView.textColor = complete ? TaskTheme.muted : TaskTheme.ink
        indent.constant = task["parent_id"] is NSNull ? 0 : TaskTheme.edge
        let stamp = task[complete ? "completed_at" : "remind_at"] as? NSNumber ?? task["due_at"] as? NSNumber ?? task["deadline_at"] as? NSNumber
        day.isHidden = stamp == nil; clock.isHidden = stamp == nil; day.text = nil; clock.text = nil
        if !complete, task["planning_mode"] as? String == "window",
           let from = task["due_at"] as? NSNumber, let to = task["deadline_at"] as? NSNumber,
           from.doubleValue > 0, to.doubleValue > 0 {
            let format = DateFormatter(); format.locale = Locale(identifier: "zh_CN")
            format.timeZone = TimeZone(identifier: task["timezone_id"] as? String ?? "") ?? .current; format.dateFormat = "MM-dd"
            day.text = format.string(from: Date(timeIntervalSince1970: from.doubleValue)) + "–" + format.string(from: Date(timeIntervalSince1970: to.doubleValue))
            day.isHidden = false; clock.isHidden = true
        } else if let stamp = stamp {
            let format = DateFormatter(); format.locale = Locale(identifier: "zh_CN"); format.timeZone = .current; format.dateFormat = "yyyy-MM-dd"
            let date = Date(timeIntervalSince1970: stamp.doubleValue); day.text = format.string(from: date); format.dateFormat = "HH:mm"; clock.text = format.string(from: date)
        }
        if !today, !complete, TaskWindow.dayOnly(task), let end = task["deadline_at"] as? NSNumber,
           let zone = TimeZone(identifier: task["timezone_id"] as? String ?? "") {
            let last = TaskWindow.deadline(Date(timeIntervalSince1970: end.doubleValue), in: TaskWindow.calendar(zone))
            let format = DateFormatter(); format.timeZone = zone; format.dateFormat = "yyyy-MM-dd"
            day.text = format.string(from: last); day.isHidden = false; clock.isHidden = true
        }
        if let end=task["today_end"] as? NSNumber,let start=task["remind_at"] as? NSNumber {let format=DateFormatter();format.dateFormat="HH:mm";let boundary=Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:Date(timeIntervalSince1970:start.doubleValue)))!.timeIntervalSince1970;day.text=format.string(from:Date(timeIntervalSince1970:start.doubleValue))+"–"+(end.doubleValue==boundary ? "24:00":format.string(from:Date(timeIntervalSince1970:end.doubleValue)));clock.isHidden=true;day.isHidden=false}
        if (task["today_unplaced"] as? Bool)==true {day.text="待安排";day.isHidden=false;clock.isHidden=true}
        if (task["today_resolved"] as? Bool)==true {check.isEnabled=false}
        if role != "none", (task["routine_enabled"] as? NSNumber)?.boolValue == false { day.text = "已停用"; day.isHidden = false; clock.isHidden = true; titleLabelView.textColor = TaskTheme.muted }
        if owner.routineOnly {
            let first=(task["routine_group_first"] as? Bool)==true,disabled=(task["routine_enabled"] as? NSNumber)?.boolValue != true
            let format=DateFormatter();format.dateFormat="HH:mm"
            let time=(task["routine_fire_at"] as? NSNumber).map{format.string(from:Date(timeIntervalSince1970:$0.doubleValue))}
            day.text=first ? (disabled ? "已停用":nil):time.map{$0+(disabled ? "·已停用":"")};day.isHidden=day.text==nil;clock.isHidden=true;metadata.isHidden=day.isHidden
            titleLabelView.accessibilityLabel=(task["title"] as? String ?? "")+(time.map{"，触发"+$0} ?? "")
        }
        shownID = id; lastComplete = complete; lastStarred = starred; lastLit = lit
    }
    // 避免动态字体和小数像素产生歧义。
    func sz(_ width: CGFloat) {
        heights[0].constant = max(1, ceil(titleLabelView.sizeThatFits(CGSize(width: max(1, width - reserved), height: .greatestFiniteMagnitude)).height))
        heights[1].constant = day.isHidden ? 0 : ceil(day.sizeThatFits(CGSize(width: max(1, width - reserved), height: .greatestFiniteMagnitude)).height); heights[2].constant = clock.isHidden ? 0 : ceil(clock.sizeThatFits(CGSize(width: max(1, width - reserved), height: .greatestFiniteMagnitude)).height)
    }
}

// 用原生Swift首页呈现共享数据库的两类任务。
@objc(TaskHome) final class TaskHome: TaskScreen, UITableViewDataSource, UITableViewDelegate {
    private var store: TaskStore?
    @objc var onStore: ((TaskStore?) -> Void)?
    private let settings: ((UINavigationController) -> Void)?
    private let table = UITableView(frame: .zero, style: .plain), tabs = tu_stk([])
    private let strip = UIScrollView()
    private let tabRule = UIView()
    private var tabRuleID: String?
    private var tabFocus=true,tabWidth:CGFloat=0
    private var tabHeight: NSLayoutConstraint!,listBottom:NSLayoutConstraint!
    private let toolbar=UIView()
    private let heading = tu_lbl("TrollTask")
    private var create:UIButton!,dueTimer:Timer?
    fileprivate var todayOnly:Bool {listID=="today"}
    fileprivate var routineOnly:Bool {listID==TS_RTN_LST}
    private var pending: [TaskFields] = [], allPnd: [TaskFields] = [], lists: [TaskFields] = []
    private var listID = "today", sort = "date", busy: Set<String> = []
    private let queue = DispatchQueue(label: "com.iwmei.taskforiwmei.home")
    private var load = 0, token: Int32 = -1
    private var loaded = false, failed = false
        private var todayRows:[TaskFields]=[]
    private var tdyDay: Date?, tdyAnchor: String?, tdyManual = false
    private var tdyBottom: CGFloat = 16
    private var rtnPicker:TaskRtnPicker?
    private var listTop: NSLayoutConstraint!
    private var rtnSections:[TaskFields]=[]
    private let rtnQueue = DispatchQueue(label: "com.iwmei.taskforiwmei.routine")
    private var rtnLoading = false, rtnReload = false, rtnZone = ""
    private var rtnOffset: CGFloat = 0
    private var rtnRevision = 0
    private let rtnBatch = 7, rtnLimit = 21
    // 注入共享存储和设置入口。
    @objc(initWithStore:settings:) init(store: TaskStore?, settings: ((UINavigationController) -> Void)?) {
        self.store = store; self.settings = settings; super.init(nibName: nil, bundle: nil)
    }
    // 禁用未使用的归档路径。
    required init?(coder: NSCoder) { fatalError("Use init(store:settings:)") }
    // 创建横向清单、透明列表和底部功能入口。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "待办"
        heading.font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: .systemFont(ofSize: 28, weight: .regular)); heading.accessibilityIdentifier = "home.title"
        let settings = tu_ibtn("settings", "设置", "home.settings", self, #selector(sttng))
        let header=hdr(heading,nil,settings,large:true)
        create = tu_ibtn("add_large", "新建待办", "home.create", self, #selector(crt)); tu_fill(create, primary: true)
        var createStyle = create.configuration; createStyle?.background.cornerRadius = 28; create.configuration = createStyle
        let buttons = [tu_ibtn("menu", "选择清单", "home.lists", self, #selector(lstMenu)), create!, tu_ibtn("more", "清单选项", "home.more", self, #selector(more))]
        toolbar.accessibilityIdentifier="home.toolbar";toolbar.isHidden=todayOnly;create.isEnabled = !todayOnly;view.addSubview(toolbar); tu_wdth(toolbar, view, inset: 0)
        let bar = UIView(); bar.backgroundColor = TaskTheme.bar; bar.translatesAutoresizingMaskIntoConstraints = false; toolbar.addSubview(bar)
        NSLayoutConstraint.activate([bar.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor), bar.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor), bar.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 28), bar.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor)])
        for button in buttons { button.translatesAutoresizingMaskIntoConstraints = false; toolbar.addSubview(button)
            NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 56), button.heightAnchor.constraint(equalToConstant: 56)]) }
        NSLayoutConstraint.activate([toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -84), toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            buttons[0].leadingAnchor.constraint(equalTo: toolbar.leadingAnchor), buttons[0].topAnchor.constraint(equalTo: bar.topAnchor),
            buttons[2].trailingAnchor.constraint(equalTo: toolbar.trailingAnchor), buttons[2].topAnchor.constraint(equalTo: bar.topAnchor),
            create.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor), create.centerYAnchor.constraint(equalTo: bar.topAnchor)])
        strip.showsHorizontalScrollIndicator = false;strip.showsVerticalScrollIndicator=false;strip.contentInsetAdjustmentBehavior = .never;strip.isDirectionalLockEnabled=true; strip.accessibilityIdentifier = "home.tabs"; view.addSubview(strip); tu_wdth(strip, view, inset: 0)
        tabs.axis = .horizontal;tabs.spacing=8; tabs.translatesAutoresizingMaskIntoConstraints = false; strip.addSubview(tabs)
        NSLayoutConstraint.activate([tabs.leadingAnchor.constraint(equalTo: strip.contentLayoutGuide.leadingAnchor), tabs.trailingAnchor.constraint(equalTo: strip.contentLayoutGuide.trailingAnchor), tabs.topAnchor.constraint(equalTo: strip.contentLayoutGuide.topAnchor), tabs.bottomAnchor.constraint(equalTo: strip.contentLayoutGuide.bottomAnchor), tabs.heightAnchor.constraint(equalTo: strip.frameLayoutGuide.heightAnchor)])
        tabRule.backgroundColor = TaskTheme.cyanInk; tabRule.layer.cornerRadius = 1; tabRule.isUserInteractionEnabled = false; tabRule.isHidden = true; strip.addSubview(tabRule)
        table.accessibilityIdentifier = "home.list"; table.backgroundColor = .clear; table.dataSource = self; table.delegate = self
        table.rowHeight = UITableView.automaticDimension; table.estimatedRowHeight = 84; table.sectionHeaderTopPadding = 0; table.separatorStyle = .none; table.keyboardDismissMode = .interactive
        table.register(TaskCell.self, forCellReuseIdentifier: "task"); view.addSubview(table); tu_wdth(table, view, inset: 0)
        table.contentInset = .init(top: 8, left: 0, bottom: todayOnly ? 16:44, right: 0)
        listBottom=table.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:todayOnly ? 0:-56)
        tabHeight = strip.heightAnchor.constraint(equalToConstant: 48)
        let rule = TaskHair(); rule.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(rule)
        table.estimatedSectionHeaderHeight=44
        listTop = table.topAnchor.constraint(equalTo: strip.bottomAnchor, constant: TaskTheme.gap)
        NSLayoutConstraint.activate([strip.topAnchor.constraint(equalTo: header.bottomAnchor,constant:8), tabHeight,
            listTop, listBottom,
            rule.leadingAnchor.constraint(equalTo: strip.leadingAnchor), rule.trailingAnchor.constraint(equalTo: strip.trailingAnchor), rule.bottomAnchor.constraint(equalTo: strip.bottomAnchor), rule.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)])

        view.bringSubviewToFront(toolbar)
        for name in [NSNotification.Name.NSCalendarDayChanged, .NSSystemTimeZoneDidChange, UIApplication.significantTimeChangeNotification] {NotificationCenter.default.addObserver(self,selector:#selector(rfrsh),name:name,object:nil)}
        reg(); NotificationCenter.default.addObserver(self, selector: #selector(activated), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    // 刷新共享数据。
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(true, animated: false); tdyReset(); rfrsh() }
    // 已有缓存时在转场完成后完成初始定位。
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); tdyFollow() }
    // 应用回到前台时重新跟随当前时段。
    @objc private func activated() { tdyReset(); rfrsh() }
    // 离开后丢弃尚未返回的AI排序。
    override func viewWillDisappear(_ animated:Bool){super.viewWillDisappear(animated);dueTimer?.invalidate();dueTimer=nil}
    // 适应动态字体高度。
    override func viewWillLayoutSubviews() { super.viewWillLayoutSubviews(); tabHeight.constant = max(48, ceil(lb_fnt(.subheadline, traitCollection).lineHeight) + 8 + 8) }
    // 切换清单或屏幕宽度后完整显示选中页签，不干扰普通刷新时的浏览位置。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard tabFocus || tabWidth != strip.bounds.width else{return}
        strip.layoutIfNeeded();tabs.layoutIfNeeded()
        guard let selected=tabs.arrangedSubviews.first(where:{$0.accessibilityIdentifier=="list."+listID}),selected.bounds.width>0 else{return}
        tabFocus=false;tabWidth=strip.bounds.width
        strip.scrollRectToVisible(selected.convert(selected.bounds,to:strip).insetBy(dx:-4,dy:0),animated:false)
    }
    // 字号变化后重新计算页签内容宽度。
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if isViewLoaded, previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {tabFocus=true;bldTabs()}
    }
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
            var todayRows:[TaskFields]=[]
            var active = previous, pnd: [TaskFields] = [], lists: [TaskFields] = [], issue: Error?
            do {
                if active == nil { active = try TaskStore.shrd() }
                guard let active = active else { throw NSError(domain: "store", code: 1) }
                try active.txn {
                    try active.rtnList()
                    let at = Date().timeIntervalSince1970, zone = TimeZone.current.identifier
                    let plan = try active.plan(at:at) as! TaskFields
                    pnd = TaskStore.pndRows(plan) as! [TaskFields]
                    lists = try active.lsLsts() as! [TaskFields]
                    todayRows = try TaskToday.rows(active,snapshot:plan,at:at,zone:zone)
                }
            } catch { issue = error }
            DispatchQueue.main.async {
                guard current == self.load else { return }; self.store = active; self.loaded = true; self.failed = issue != nil
                self.onStore?(issue == nil ? active : nil)
                if let error = issue { self.pending = [];self.rtnSections=[];self.rtnRevision+=1;self.tdyReset(); NSLog("读取待办失败：%@", error as NSError) }
                else {
                    if let note = active?.changeNote { self.sort = self.srtSaved(note) }
                    self.allPnd = pnd;self.todayRows=todayRows
                    self.lists = lists.filter { $0["list_id"] as? String == TS_RTN_LST } + lists.filter { $0["list_id"] as? String != TS_RTN_LST }
                    self.fltr(); self.bldTabs(); self.reg()
                    if self.routineOnly && !self.rtnSections.isEmpty { self.rtnRead(0) }
                }
                if !self.routineOnly || self.rtnSections.isEmpty { self.table.reloadData() }
                if issue == nil { self.tdyFollow() }
            }
        }
    }
    // 打开服务设置。
    @objc private func sttng() { if let nav = navigationController { settings?(nav) } }
    // 清除本次浏览的手动位置，下次刷新定位当前时段。
    private func tdyReset() {
        tdyAnchor = nil; tdyManual = false; tdyBottom = 16
    }

    // 保留完整时间顺序，只调整今日律的起始阅读位置。
    private func tdyFollow() {
        guard todayOnly, view.window != nil, navigationController?.topViewController === self else { return }
        let now = Date(), day = Calendar.current.startOfDay(for: now)
        if day != tdyDay { tdyReset(); tdyDay = day }
        guard !tdyManual, !table.isTracking, !table.isDecelerating else { return }
        let index = TaskToday.focus(pending, at: now.timeIntervalSince1970)
        guard pending.indices.contains(index) else {
            tdyAnchor = nil; tdyBottom = 16; table.contentInset.bottom = tdyBottom
            return
        }
        let key = "\(index)/\(pending[index]["today_key"] ?? "")"
        guard key != tdyAnchor else { return }
        view.layoutIfNeeded()
        guard table.bounds.height > 0 else { return }
        tdyAnchor = key
        let path = IndexPath(row:index,section:0)
        // 留出足够滚动余量，当前任务靠近当天末尾时也能贴顶。
        UIView.performWithoutAnimation {
            table.contentInset.bottom = 16
            table.scrollToRow(at:path,at:.top,animated:false)
            table.layoutIfNeeded()
            let y = table.rectForRow(at:path).minY - table.adjustedContentInset.top
            let extra = y + table.bounds.height - table.contentSize.height - table.adjustedContentInset.bottom
            tdyBottom = 16 + max(0,extra)
            table.contentInset.bottom = tdyBottom
            table.scrollToRow(at:path,at:.top,animated:false)
        }
    }

    // 用户主动向上找逾期任务时保留浏览位置。
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if scrollView === table && todayOnly { tdyManual = true }
    }

    // 向可见边缘读取相邻七天，内存中最多保留连续三周。
    private func rtnRead(_ direction: Int) {
        guard let store, routineOnly else { return }
        if rtnLoading {
            if direction == 0 { rtnReload = true }
            return
        }
        let calendar = Calendar.current, zone = calendar.timeZone.identifier, today = calendar.startOfDay(for: Date())
        let cutoff = calendar.date(byAdding: .day, value: -3, to: today)!
        let first = Date(timeIntervalSince1970: (rtnSections.first?["day_at"] as? NSNumber)?.doubleValue ?? today.timeIntervalSince1970)
        let last = Date(timeIntervalSince1970: (rtnSections.last?["day_at"] as? NSNumber)?.doubleValue ?? first.timeIntervalSince1970)
        let reset = rtnSections.isEmpty || rtnZone != zone || last < cutoff
        let mode = reset || first < cutoff ? 0 : direction
        let start: Date
        let count: Int
        if reset {
            start = cutoff
            count = rtnBatch
        } else {
            let base = mode > 0 ? last : first
            let candidate = calendar.date(byAdding:.day,value:mode < 0 ? -rtnBatch : mode,to:base)!
            start = max(cutoff,candidate)
            count = mode > 0 ? rtnBatch : (calendar.dateComponents([.day],from:start,to:mode < 0 ? first : last).day ?? 0) + (mode == 0 ? 1 : 0)
        }
        guard count > 0 else { return }
        rtnLoading = true
        let revision = rtnRevision
        rtnQueue.async {
            let result = Result { () throws -> [TaskFields] in
                let stamp = start.timeIntervalSince1970
                let days = try store.rtnDays(stamp, count: UInt(count), zone: zone) as! [TaskFields]
                return TaskRoutineView.sections(days)
            }
            DispatchQueue.main.async {
                guard self.routineOnly else { self.rtnLoading = false; self.rtnReload = false; return }
                guard revision == self.rtnRevision else {
                    self.rtnLoading = false; self.rtnReload = false; self.rtnRead(0); return
                }
                guard Calendar.current.timeZone.identifier == zone, Calendar.current.startOfDay(for: Date()) == today else {
                    self.rtnLoading = false; self.rtnReload = false; self.rtnRead(0); return
                }
                if case let .success(sections) = result {
                    self.rtnZone = zone
                    self.rtnApply(sections, direction: mode, initial: reset ? today : nil)
                } else if case let .failure(error) = result {
                    NSLog("读取常律失败：%@", error as NSError)
                    if self.rtnSections.isEmpty { self.failed = true; self.table.reloadData() }
                }
                self.rtnLoading = false
                if self.rtnReload { self.rtnReload = false; self.rtnRead(0) }
            }
        }
    }

    // 批量插入和裁剪日期，以上屏行的像素位置作为滚动锚点。
    private func rtnApply(_ sections: [TaskFields], direction: Int, initial: Date?) {
        let top = table.contentOffset.y
        let visible = table.indexPathsForVisibleRows?.sorted().first {
            $0.section < rtnSections.count && table.rectForRow(at: $0).maxY > top
        }
        let stamp = initial.map { NSNumber(value: $0.timeIntervalSince1970) }
            ?? visible.flatMap { rtnSections[$0.section]["day_at"] as? NSNumber }
        let gap = visible.map { table.rectForRow(at: $0).minY - top } ?? 0
        let oldCount = rtnSections.count
        var merged = direction < 0 ? sections + rtnSections : direction > 0 ? rtnSections + sections : sections
        let trim = max(0, merged.count - rtnLimit)
        if direction < 0 { merged.removeLast(trim) }
        if direction > 0 { merged.removeFirst(trim) }
        let index = merged.firstIndex { ($0["day_at"] as? NSNumber) == stamp }
        if direction != 0 && visible != nil && index == nil { return }
        UIView.performWithoutAnimation {
            if direction == 0 {
                rtnSections = merged
                table.reloadData()
            } else {
                let insert = IndexSet(integersIn: direction < 0 ? 0..<sections.count : (oldCount-trim)..<merged.count)
                let delete = IndexSet(integersIn: direction < 0 ? (oldCount-trim)..<oldCount : 0..<trim)
                table.performBatchUpdates {
                    rtnSections = merged
                    table.deleteSections(delete, with: .none)
                    table.insertSections(insert, with: .none)
                }
            }
            table.layoutIfNeeded()
            if let index {
                let count = (merged[index]["rows"] as? [TaskFields])?.count ?? 0
                let row = IndexPath(row: initial != nil ? 0 : min(visible?.row ?? 0, max(0,count-1)), section: index)
                // 先让目标日布局实际行高，避免用未测量的行高定位首屏。
                if initial != nil {
                    table.scrollToRow(at: row, at: .top, animated: false)
                    table.layoutIfNeeded()
                }
                let y = initial != nil ? table.rectForHeader(inSection:index).minY : table.rectForRow(at:row).minY - gap
                let low = -table.adjustedContentInset.top
                let high = max(low, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
                let anchored = min(high, max(low, y))
                if abs(table.contentOffset.y - anchored) > 0.5 { table.contentOffset.y = anchored }
            }
        }
    }

    // 只在用户朝日期边缘滚动时预读，布局变化不触发级联加载。
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === table else { return }
        let y = table.contentOffset.y, delta = y - rtnOffset, height = table.bounds.height
        rtnOffset = y
        guard routineOnly, !rtnLoading, !rtnSections.isEmpty,
              table.isDragging || table.isDecelerating else { return }
        if y < height && delta < 0 { rtnRead(-1) }
        else if table.contentSize.height - y - height < height && delta > 0 { rtnRead(1) }
    }
    // 创建快捷草稿；有未完成草稿时先让用户选择继续或丢弃。
    @objc private func crt() {
        guard !todayOnly else{return}
        guard let store = store else { rfrsh(); return }; guard presentedViewController == nil else { return }
        if !routineOnly, let value = try? store.draft(), let saved = value as? TaskFields, !saved.isEmpty {
            let alert=UIAlertController(title:"继续上次的编辑？",message:nil,preferredStyle:.alert)
            alert.addAction(UIAlertAction(title:"继续",style:.default){[weak self] _ in self?.resumeDraft(saved,store)})
            alert.addAction(UIAlertAction(title:"丢弃",style:.destructive){[weak self] _ in _ = try? store.clearDraft();self?.openCreate(store)})
            present(alert,animated:true);return
        }
        openCreate(store)
    }
    // 从保存的草稿直接回到创建评估页。
    private func resumeDraft(_ saved:TaskFields,_ store:TaskStore){
        guard let fields=saved["fields"] as? TaskFields else{openCreate(store);return}
        let parts=saved["parts"] as? [TaskFields] ?? [],estimate=saved["estimate"] as? TaskFields,split=(saved["split"] as? NSNumber)?.boolValue,manual=(saved["manual"] as? NSNumber)?.boolValue,unreachable=(saved["unreachable"] as? NSNumber)?.boolValue
        let page=TaskAdmissionScreen(store:store,fields:fields,parts:parts,estimate:estimate,split:split,manual:manual,unreachable:unreachable){[weak self] in self?.rfrsh();self?.dismiss(animated:true)}
        tu_sheet(self,UINavigationController(rootViewController:page),compact:true)
    }
    // 打开新的快捷创建面板。
    private func openCreate(_ store:TaskStore){
        let draft: TaskFields = routineOnly ? tr_draft() : ["list_id": listID == "starred" ? TS_DFLT_LST : listID]
        let editor = TaskEdit(store: store, task: nil, draft: draft, quick: true) { [weak self] in self?.rfrsh() }
        let nav = UINavigationController(rootViewController: editor); nav.preferredContentSize = editor.preferredContentSize
        tu_sheet(self, nav, compact: true) { [weak editor] in editor?.focusDraft() }
    }
    // 筛选当前清单和存储排序。
    private func fltr() {
        dueTimer?.invalidate();dueTimer=nil
        if view.window != nil {
            let now = Date(), calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            let at = now.timeIntervalSince1970
            var next = min(tomorrow.timeIntervalSince1970, TaskStore.nextExpiry(at, zone: calendar.timeZone.identifier))
            if todayOnly {
                for row in todayRows where row["status"] as? String != "completed" {
                    for key in ["remind_at","today_end"] {
                        if let boundary = (row[key] as? NSNumber)?.doubleValue, boundary > at { next = min(next,boundary) }
                    }
                }
            } else if !routineOnly && listID != "starred" {
                for task in allPnd where task["list_id"] as? String == listID {
                    if let halfway = TaskWindow.halfway(task), halfway > at { next = min(next, halfway) }
                }
            }
            let timer = Timer(timeInterval: max(0.01,next-at), repeats: false) { [weak self] _ in self?.rfrsh() }
            dueTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        listTop.constant = routineOnly ? 0 : TaskTheme.gap
        table.contentInset.top = routineOnly ? 0 : TaskTheme.gap
        table.contentInsetAdjustmentBehavior = routineOnly ? .never : .automatic
        table.contentInset.bottom=todayOnly ? tdyBottom:44;create.isEnabled = !todayOnly;toolbar.isHidden=todayOnly;listBottom.constant=todayOnly ? 0:-56;heading.text="TrollTask"
        if routineOnly && rtnSections.isEmpty { rtnRead(0) }
        create.accessibilityLabel=routineOnly ? "新增常律":"新建待办"
        if listID=="today" {pending=todayRows.filter{$0["status"] as? String != "completed"};return}
        let star = listID == "starred"
        if !star && !lists.contains(where: { $0["list_id"] as? String == listID }) { listID = TS_DFLT_LST }
        let now = Date().timeIntervalSince1970
        let lit: (TaskFields) -> Bool = { $0["routine_kind"] as? String == "none" && (($0["starred"] as? NSNumber)?.boolValue == true || (TaskWindow.halfway($0).map { $0 <= now } ?? false)) }
        let filter: (TaskFields) -> Bool = { star ? lit($0) : $0["list_id"] as? String == self.listID }
        pending = allPnd.filter(filter)
        pending = TaskTraits.group(TaskTraits.order(pending, by: sort))
    }
    // 页签文字和图标采用同一居中布局。
    private func tabBtn(_ title:String?,_ icon:String?,_ action:Selector)->UIButton {
        let button=tu_btn(title,icon,self,action)
        var config=button.configuration
        config?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [weak self] attributes in var value=attributes;value.font=lb_fnt(.subheadline,self?.traitCollection);return value }
        config?.titleAlignment = .center;config?.titleLineBreakMode = .byTruncatingTail;config?.imagePadding=8
        config?.contentInsets = .init(top:8,leading:12,bottom:8,trailing:12);config?.background.cornerRadius=12;button.configuration=config
        button.contentHorizontalAlignment = .center;button.titleLabel?.numberOfLines=1
        return button
    }
    // 更新清单页签。
    private func bldTabs() {
        tabFocus = tabFocus || !tabs.arrangedSubviews.contains{$0.accessibilityIdentifier=="list."+listID && $0.accessibilityTraits.contains(.selected)}
        tabs.arrangedSubviews.forEach { tabs.removeArrangedSubview($0); $0.removeFromSuperview() }
        let now = Date().timeIntervalSince1970
        let count = allPnd.filter { $0["routine_kind"] as? String=="none" && (($0["starred"] as? NSNumber)?.boolValue == true || (TaskWindow.halfway($0).map { $0 <= now } ?? false)) }.count
        let ordered:[[String:Any]] = [["list_id":"today","title":"今日律"]] + lists.filter{$0["list_id"] as? String==TS_RTN_LST} + [["list_id":"starred","title":"星标"]] + lists.filter{$0["list_id"] as? String != TS_RTN_LST}
        for list in ordered {
            let id = list["list_id"] as! String, selected = id == listID
            let button = tabBtn(id == "starred" ? (count>0 ? String(count):nil) : lb_shrt(list["title"] as? String), id == "starred" ? "star_fill" : nil, #selector(selLst(_:)))
            button.accessibilityIdentifier = "list." + id; button.accessibilityLabel = id == "starred" ? "星标待办" : list["title"] as? String; button.accessibilityValue = selected ? "已选中" : "未选中"
            var config = button.configuration; config?.baseForegroundColor = TaskTheme.muted
            button.configuration = config
            if selected { button.accessibilityTraits.insert(.selected) }; tabs.addArrangedSubview(button)
        }
        let button = tabBtn("新建清单", "add", #selector(crtLst)); button.accessibilityIdentifier = "home.newlist";button.isEnabled = !todayOnly; tabs.addArrangedSubview(button)
        for item in tabs.arrangedSubviews {item.widthAnchor.constraint(lessThanOrEqualTo:strip.frameLayoutGuide.widthAnchor,constant:-4-4).isActive=true}
        rfrshTints()
        view.setNeedsLayout()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.layoutIfNeeded()
            self.plcTabRule(animated: self.tabRuleID != nil && self.tabRuleID != self.listID)
            self.tabRuleID = self.listID
        }
    }
    // 将单条青色时间线放到当前页签下方，切换时弹过去。
    private func plcTabRule(animated: Bool) {
        guard let selected = tabs.arrangedSubviews.first(where: { $0.accessibilityIdentifier == "list." + listID }) else { tabRule.isHidden = true; return }
        tabRule.isHidden = false
        let frame = selected.convert(selected.bounds, to: strip)
        let target = CGRect(x: frame.minX + 12, y: frame.maxY - 2, width: max(0, frame.width - 24), height: 2)
        if animated && !tabRule.frame.isEmpty { TaskMotion.animate(.snappy) { self.tabRule.frame = target } } else { tabRule.frame = target }
    }
    // 选中页签保持可见，未选中页签降为次级色。
    private func rfrshTints() {
        for item in tabs.arrangedSubviews as! [UIButton] {
            var config = item.configuration; config?.baseForegroundColor = item.accessibilityTraits.contains(.selected) ? TaskTheme.ink : TaskTheme.muted; item.configuration = config
        }
    }
    // 切换当前清单。
    @objc private func selLst(_ button: UIButton) {
        guard let store else { rfrsh(); return }
        let selected = String(button.accessibilityIdentifier!.dropFirst(5))
        let changed = selected != listID
        let reset = changed && (routineOnly || selected == TS_RTN_LST)
        if reset { rtnSections = []; rtnRevision += 1 }
        if changed { TaskHaptics.pick() }
        listID = selected
        if todayOnly { tdyReset() }
        sort = srtSaved(store.changeNote!); fltr(); bldTabs()
        if changed { TaskMotion.crossfade(table) { self.table.reloadData() } } else { table.reloadData() }
        if routineOnly { rtnRead(0) }
        if reset { table.setContentOffset(CGPoint(x:0,y:-table.adjustedContentInset.top),animated:false) }
        tdyFollow()
    }
    // 提交事务后刷新，不作乐观显示。
    private func wrt(_ work: @escaping (TaskStore) throws -> Void, done: ((Error?) -> Void)? = nil) {
        guard let store = store else { return }
        queue.async { var issue: Error?; do { try store.txn { try work(store) } } catch { issue = error }
            DispatchQueue.main.async { self.rfrsh(); if let done { done(issue) } else if let issue { tu_err(self, issue) } }
        }
    }
    // 编辑清单名称。
    private func lstName(_ create: Bool) {
        guard store != nil else { rfrsh(); return }; let id = listID
        let name = create ? "" : lists.first { $0["list_id"] as? String == id }?["title"] as? String ?? ""
        let page = TaskName(title: create ? "新建清单" : "重命名清单", name: name) { [weak self] name, done in
            self?.wrt({ store in
                if create {
                    let row = try store.crtLst(name) as! TaskFields
                    DispatchQueue.main.async { self?.listID = row["list_id"] as! String; self?.sort = "date" }
                } else { try store.updLst(id, title: name) }
            }, done: done)
        }
        navigationItem.backButtonTitle = "返回"; navigationController?.setNavigationBarHidden(false, animated: false); navigationController?.pushViewController(page, animated: true)
    }
    // 新建清单。
    @objc private func crtLst() { guard !todayOnly else{return}; lstName(true) }
    // 展示清单切换菜单。
    @objc private func lstMenu() {
        guard !todayOnly else{return}
        guard store != nil else { rfrsh(); return }
        let starred = tu_act("已加星标", "star_fill", "list.starred") { [weak self] in let button = UIButton(); button.accessibilityIdentifier = "list.starred"; self?.selLst(button) }; starred.state = listID == "starred" ? .on : .off
        let today=tu_act("今日律","calendar","list.today") { [weak self] in let button=UIButton();button.accessibilityIdentifier="list.today";self?.selLst(button) };today.state=listID=="today" ? .on:.off
        var actions = [today,starred] + lists.map { list -> UIAction in
            let id = list["list_id"] as! String
            let action = tu_act(list["title"] as? String ?? "", nil, id) { [weak self] in let button = UIButton(); button.accessibilityIdentifier = "list." + id; self?.selLst(button) }
            action.state = id == listID ? .on : .off; return action
        }
        let add=tu_act("新建清单", "add", "list.create") { [weak self] in self?.crtLst() };if todayOnly{add.attributes = .disabled};actions.append(add); tu_menu(self, "清单", actions, breaks: [actions.count - 1], lists: true)
    }
    // 只保留四项显示排序和清单维护。
    @objc private func more() {
        guard !todayOnly else{return}
        guard let store else { rfrsh(); return }
        if listID == TS_RTN_LST {
            tu_menu(self,"常律选项",[tu_act("导入常律","upload","rules.import"){[weak self] in
                guard let self else{return}
                if self.rtnPicker == nil {self.rtnPicker=TaskRtnPicker(store:store,host:self){[weak self] in self?.rfrsh()}}
                self.rtnPicker?.open()
            }]);return
        }
        let rename = tu_act("重命名清单", nil, "list.rename") { [weak self] in self?.lstName(false) }, id = listID
        let remove = tu_act("删除清单", nil, "list.delete") { [weak self] in guard let self = self else { return }; tu_cfrm(self, "删除清单及全部任务") { self.wrt { try $0.delLst(id) } } }; remove.attributes = .destructive
        if ["today","starred"].contains(id) { rename.attributes = .disabled; remove.attributes = .disabled }
        if id == TS_DFLT_LST { remove.attributes = .disabled }
        let sorts = zip(["date","name","urgency","difficulty"],["日期","名称","紧急优先","困难优先"]).map { srtAct($0,$1) }
        tu_menu(self, "清单选项", sorts + [rename, remove], breaks: [4])
    }
    // 读取并校验显示排序，旧值回落到日期。
    private func srtSaved(_ note: String) -> String {
        let value = UserDefaults.standard.string(forKey: "\(note).\(listID).sort") ?? "date"
        return ["date","name","urgency","difficulty"].contains(value) ? value : "date"
    }
    // 保存显示排序，不修改任何任务的排程。
    private func srtAct(_ key: String, _ name: String) -> UIAction {
        let action = tu_act(name, nil, "sort." + key) { [weak self] in
            guard let self, let store = self.store else { return }; self.sort = key; UserDefaults.standard.set(key, forKey: "\(store.changeNote!).\(self.listID).sort")
            self.fltr(); self.table.reloadData()
        }; action.state = sort == key ? .on : .off; return action
    }
    // 提交明确星标意图。
    @objc func tglStar(_ button: UIButton) {
        guard !todayOnly else{return}
        TaskHaptics.tap()
        let id = String(button.accessibilityIdentifier!.dropFirst(5)), starred = button.accessibilityValue != "1"
        wrt { store in try tu_live(try store.rdTsk(id) as! TaskFields); try store.updTsk(id, fields: ["starred": starred]) }
    }
    // 进入完整详情。
    private func edt(_ task: TaskFields) {
        guard !todayOnly else{return}
        guard let store = store else { rfrsh(); return }
        navigationController?.setNavigationBarHidden(false, animated: false)
        if task["list_id"] as? String == TS_RTN_LST {
            navigationController?.pushViewController(TaskEdit(store: store, task: task) { [weak self] in self?.rfrsh() }, animated: true)
        } else {
            navigationController?.pushViewController(TaskDetailScreen(store: store, task: task) { [weak self] in self?.rfrsh() }, animated: true)
        }
    }
    // 空态重试或创建。
    @objc private func empt() { guard loaded else { return }; if failed { rfrsh() } else { crt() } }
    // 同一事项跨日期复用UUID，提交期间只允许一次写入。
    fileprivate func isBusy(_ id: String) -> Bool { busy.contains(id) }

    // 明确确认整条常律后再删除模板。
    @objc fileprivate func delRtn(_ button: UIButton) {
        guard routineOnly, button.isEnabled, presentedViewController == nil,
              let task = objc_getAssociatedObject(button,&taskKey) as? TaskFields,
              let id = task["task_id"] as? String, !busy.contains(id) else { return }
        let name = lb_shrt(task["title"] as? String)
        tu_cfrm(self, "删除常律？", message: "\(name ?? "")\n各天安排与提醒将移除") { [weak self, weak button] in
            guard let self, self.busy.insert(id).inserted else { return }
            TaskHaptics.warning()
            button?.isEnabled = false
            self.wrt({ try $0.delTsk(id) }, done: { [weak self] error in
                guard let self else { return }
                self.busy.remove(id)
                if let error { tu_err(self, error) }
            })
        }
    }

    // 只唤起原有提醒队列，任务完成仍须HUD提交附件。
    @objc func tglTsk(_ button: UIButton) {
        guard todayOnly,button.isEnabled,let store,let display=objc_getAssociatedObject(button,&taskKey) as? TaskFields,let id=display["task_id"] as? String,!busy.contains(id) else{return}
        TaskHaptics.tap()
        busy.insert(id);button.isEnabled=false
        queue.async {var failure:Error?
            do {_ = try TaskToday.alrt(store,task:display as NSDictionary,at:Date().timeIntervalSince1970)
                guard (lb_ldcfg()["enabled"] as? NSNumber)?.boolValue==true else{throw TaskAI.err("请先开启后台服务")}
                guard lb_spawn() else{throw TaskAI.err("提醒服务启动失败")}
                let code=TaskToday.note(store).withCString{notify_post($0)};if code != NOTIFY_STATUS_OK{throw TaskAI.err("提醒请求发送失败")}
            }catch{failure=error}
            DispatchQueue.main.async {self.busy.remove(id);self.rfrsh();if let failure{tu_err(self,failure)}}
        }
    }
    // 常律按日期分区，待办保持单一列表。
    func numberOfSections(in tableView: UITableView) -> Int { routineOnly ? max(1,rtnSections.count):1 }
    // 提供待办行和空态。
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { if routineOnly{return rtnSections.isEmpty ? 1:max(1,(rtnSections[section]["rows"] as! [TaskFields]).count)};return max(pending.count, 1) }
    // 空态占据视口中部，避免文字贴顶。
    func tableView(_ tableView: UITableView, heightForRowAt path: IndexPath) -> CGFloat {
        if path.section == 0 && (routineOnly ? rtnSections.isEmpty : pending.isEmpty) { return max(240, tableView.bounds.height * 0.55) }
        return UITableView.automaticDimension
    }
    // 显示原生待办行或功能空态。
    func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        if path.section == 0 && (routineOnly ? rtnSections.isEmpty:pending.isEmpty) {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil); cell.backgroundColor = .clear; cell.selectionStyle = .none
            let title = failed ? "读取失败" : (loaded ? "暂无待办" : "正在读取")
            let empty = tu_btn(title, "list", self, #selector(empt)); empty.isEnabled = loaded && (!todayOnly || failed); empty.accessibilityIdentifier = "home.empty"
            var config = empty.configuration
            config?.imagePlacement = .top; config?.imagePadding = 12; config?.contentInsets = .init(top: 20, leading: 24, bottom: 20, trailing: 24)
            config?.baseForegroundColor = TaskTheme.ink
            config?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in var value = attributes; value.font = lb_fnt(.body, nil); return value }
            empty.configuration = config; empty.contentHorizontalAlignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false; cell.contentView.addSubview(empty)
            NSLayoutConstraint.activate([empty.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor), empty.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor), empty.leadingAnchor.constraint(greaterThanOrEqualTo: cell.contentView.leadingAnchor, constant: 24), empty.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -24)])
            return cell
        }
        if routineOnly && rtnRow(path) == nil {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.backgroundColor = .clear; cell.selectionStyle = .none
            return cell
        }
        if routineOnly,let row=rtnRow(path),(row["routine_marker"] as? Bool)==true {
            let cell=UITableViewCell(style:.default,reuseIdentifier:nil);cell.backgroundColor = .clear;cell.selectionStyle = .none;cell.accessibilityIdentifier="routine.mark.\(path.section).\(path.row)"
            let label=tu_lbl(nil);label.font=lb_fnt(.subheadline,traitCollection);label.textColor=TaskTheme.muted;label.accessibilityTraits.insert(.header)
            if let stamp=row["routine_fire_at"] as? NSNumber {let format=DateFormatter();format.dateFormat="HH:mm";label.text=format.string(from:Date(timeIntervalSince1970:stamp.doubleValue))}
            let line=TaskHair();line.translatesAutoresizingMaskIntoConstraints = false;line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
            let contents=tu_stk([label,line]);contents.axis = .horizontal;contents.alignment = .center;contents.spacing=8;contents.translatesAutoresizingMaskIntoConstraints=false;cell.contentView.addSubview(contents);label.setContentHuggingPriority(.required,for:.horizontal)
            NSLayoutConstraint.activate([contents.leadingAnchor.constraint(equalTo:cell.contentView.leadingAnchor,constant:16),contents.trailingAnchor.constraint(equalTo:cell.contentView.trailingAnchor,constant:-16),contents.topAnchor.constraint(equalTo:cell.contentView.topAnchor,constant:8),contents.bottomAnchor.constraint(equalTo:cell.contentView.bottomAnchor,constant:-8)]);return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "task", for: path) as! TaskCell
        let task = routineOnly ? rtnRow(path)!:pending[path.row]; cell.bnd(task, self); cell.sz(tableView.bounds.width); cell.check.isEnabled = cell.check.isEnabled && !busy.contains(task["task_id"] as! String); return cell
    }
    // 显示常律日期标题。
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if routineOnly {
            guard rtnSections.indices.contains(section) else{return nil};let header=UIView();header.backgroundColor=TaskTheme.base
            let label=tu_lbl(nil);label.accessibilityIdentifier="routine.day.\(section)";label.accessibilityTraits.insert(.header);label.font=lb_fnt(.headline,traitCollection)
            if let stamp=rtnSections[section]["day_at"] as? NSNumber {let format=DateFormatter();format.locale=Locale(identifier:"zh_CN");format.dateFormat=Calendar.current.component(.year,from:Date(timeIntervalSince1970:stamp.doubleValue))==Calendar.current.component(.year,from:Date()) ? "M月d日EEE":"yyyy年M月d日";label.text=format.string(from:Date(timeIntervalSince1970:stamp.doubleValue))}else{label.text="无后续时刻"}
            header.addSubview(label);label.translatesAutoresizingMaskIntoConstraints=false;NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:header.leadingAnchor,constant:16),label.trailingAnchor.constraint(equalTo:header.trailingAnchor,constant:-16),label.topAnchor.constraint(equalTo:header.topAnchor,constant:12),label.bottomAnchor.constraint(equalTo:header.bottomAnchor,constant:-12)]);return header
        }
        return nil
    }
    // 按常律标题实际字号计算高度。
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        routineOnly && !rtnSections.isEmpty ? UITableView.automaticDimension : 0.01
    }
    // 点击文字区域编辑。
    func tableView(_ tableView: UITableView, didSelectRowAt path: IndexPath) {
        tableView.deselectRow(at: path, animated: true); if path.section == 0 && (routineOnly ? rtnSections.isEmpty:pending.isEmpty) { empt(); return };if routineOnly{guard let task=rtnRow(path),(task["routine_marker"] as? Bool) != true else{return};edt(task);return};edt(pending[path.row])
    }
    // 根据日期分区取真实任务或只读时间分隔行。
    private func rtnRow(_ path:IndexPath)->TaskFields?{guard rtnSections.indices.contains(path.section),let rows=rtnSections[path.section]["rows"] as? [TaskFields],rows.indices.contains(path.row) else{return nil};return rows[path.row]}
    // 注销所有数据监听。
    deinit { dueTimer?.invalidate();if token >= 0 { notify_cancel(token) }; NotificationCenter.default.removeObserver(self) }
}

// 新建和重命名共用独立输入页，取消不保存。
private final class TaskName: TaskScreen, UITextFieldDelegate {
    private let initial: String, save: (String, @escaping (Error?) -> Void) -> Void
    private let field = UITextField()
    private var saving = false, done: UIButton!
    // 接收当前名称与既有事务入口。
    init(title: String, name: String, save: @escaping (String, @escaping (Error?) -> Void) -> Void) { initial = name; self.save = save; super.init(nibName: nil, bundle: nil); self.title = title }
    // 禁用归档初始化。
    required init?(coder: NSCoder) { fatalError("Use init(title:name:save:)") }
    // 保持顶部标题、返回、完成与单行输入的原版层级。
    override func viewDidLoad() {
        super.viewDidLoad(); tu_fld(field);field.text = initial; field.attributedPlaceholder=tu_phl("清单名称", lb_fnt(.body, traitCollection)); field.font = lb_fnt(.body, traitCollection); field.textColor = TaskTheme.ink; field.adjustsFontForContentSizeCategory = true
        field.accessibilityIdentifier = "list.name"; field.returnKeyType = .done; field.delegate = self; field.addTarget(self, action: #selector(chg), for: .editingChanged); field.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(field)
        NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16), field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16), field.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,constant:16), field.heightAnchor.constraint(greaterThanOrEqualToConstant: max(44, lb_fnt(.body, traitCollection).lineHeight + 8))])
        done = tu_btn("完成", nil, self, #selector(sv)); done.accessibilityIdentifier = "list.done"; var config = done.configuration; config?.baseForegroundColor = lb_acnt(); done.configuration = config; navigationItem.rightBarButtonItem = UIBarButtonItem(customView: done); chg()
    }
    // 进入页面即可输入。
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); field.becomeFirstResponder() }
    // 空白名称不能提交。
    @objc private func chg() { done.isEnabled = !saving && !(field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    // 键盘完成复用同一提交入口。
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { sv(); return false }
    // 防重复提交，保存失败保留输入。
    @objc private func sv() {
        guard done.isEnabled, !saving else { return }; let name = field.text ?? ""
        if name == initial { navigationController?.popViewController(animated: true); return }
        saving = true; field.isEnabled = false; navigationItem.hidesBackButton = true; navigationController?.interactivePopGestureRecognizer?.isEnabled = false; chg()
        save(name) { [weak self] error in
            guard let self else { return }; self.saving = false; self.field.isEnabled = true; self.navigationItem.hidesBackButton = false; self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true; self.chg()
            if let error { tu_err(self, error) } else { self.navigationController?.popViewController(animated: true) }
        }
    }
}
