// 新建流程第三页：主任务只读、备注可编辑，子任务由AI拆分或手动创建。
final class TaskSplitScreen: TaskScreen, UITextViewDelegate {
    private enum Phase { case checking, ready, offline, splitting }
    private let store: TaskStore, estimate: TaskFields?
    private var draft: TaskFields, parts: [TaskFields]
    private let reply: (String, [TaskFields], Bool, Bool, Bool) -> Void
    private var phase = Phase.checking, manual = false, unreachable = false, checked = false, synced = false, saving = false
    private var request: URLSessionDataTask?, ticket = UUID()
    private let notes = UITextView(), list = UIStackView()
    private var scroll: UIScrollView!, splitButton: UIButton!, create: UIButton!, draftButton: UIButton!
    private weak var dragged: UIView?
    private var dragStart: CGFloat = 0
    private var freeLabel: UILabel!, gaugeTicket = UUID(), gaugeWork: DispatchWorkItem?
    // 接收第二页草稿、已有子任务、评估结果与手动拆分状态。
    init(store: TaskStore, draft: TaskFields, parts: [TaskFields], estimate: TaskFields?, manual: Bool, unreachable: Bool, reply: @escaping (String, [TaskFields], Bool, Bool, Bool) -> Void) {
        self.store = store; self.draft = draft; self.parts = parts; self.estimate = estimate; self.reply = reply; self.manual = manual; self.unreachable = unreachable
        super.init(nibName: nil, bundle: nil); preferredContentSize = CGSize(width: 540, height: UIScreen.main.bounds.height)
        if manual { phase = .offline; checked = true } else if !parts.isEmpty { phase = .ready }
    }
    // 禁用归档初始化。
    required init?(coder: NSCoder) { fatalError("Use init(store:draft:parts:estimate:manual:reply:)") }
    // 建立只读主任务、可编辑备注与子任务容器。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "拆分子任务"
        let section = { (text: String) -> UILabel in let label = tu_lbl(text); label.font = lb_fnt(.subheadline, self.traitCollection); label.textColor = TaskTheme.muted; return label }
        let mainLabel = section("主任务"), notesLabel = section("备注"), partsLabel = section("子任务")
        let main = tu_lbl(draft["title"] as? String ?? "")
        main.accessibilityIdentifier = "split.title"; main.accessibilityHint = "只读"
        let box = UIView(); box.backgroundColor = TaskTheme.surface; box.layer.cornerRadius = 12; box.layer.cornerCurve = .continuous; box.clipsToBounds = true
        box.translatesAutoresizingMaskIntoConstraints = false; main.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(main)
        NSLayoutConstraint.activate([main.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12), main.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12), main.topAnchor.constraint(equalTo: box.topAnchor, constant: 12), main.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12), box.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)])
        tu_fld(notes); notes.font = lb_fnt(.body, traitCollection); notes.adjustsFontForContentSizeCategory = true; notes.textColor = TaskTheme.ink; notes.isScrollEnabled = false; notes.delegate = self
        notes.accessibilityIdentifier = "split.notes"; notes.accessibilityLabel = "备注"; notes.text = draft["notes"] as? String ?? ""
        list.axis = .vertical; list.spacing = TaskTheme.gap; list.accessibilityIdentifier = "split.list"
        splitButton = tu_btn("智能拆分", nil, self, #selector(splitTap)); splitButton.accessibilityIdentifier = "split.parts"
        splitButton.contentHorizontalAlignment = .center; tu_fill(splitButton); splitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        let form = tu_stk([mainLabel, box, notesLabel, notes, partsLabel, list])
        scroll = tu_form(self, form, "split.content")
        form.setCustomSpacing(TaskTheme.gap, after: mainLabel); form.setCustomSpacing(TaskTheme.section, after: box)
        form.setCustomSpacing(TaskTheme.gap, after: notesLabel); form.setCustomSpacing(TaskTheme.section, after: notes)
        form.setCustomSpacing(TaskTheme.gap, after: partsLabel)
        let footer = UIView(); footer.backgroundColor = TaskTheme.base; footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer); view.bringSubviewToFront(footer)
        view.constraints.filter { ($0.firstItem as? UIView) === scroll && $0.firstAttribute == .bottom }.forEach { $0.isActive = false }
        let rule = TaskHair(); rule.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(rule)
        freeLabel = tu_lbl("空余—"); freeLabel.font = lb_fnt(.subheadline, traitCollection); freeLabel.textColor = TaskTheme.muted; freeLabel.accessibilityIdentifier = "split.free"; freeLabel.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(freeLabel)
        create = tu_btn("创建", nil, self, #selector(createTap)); create.accessibilityIdentifier = "split.create"; create.contentHorizontalAlignment = .center; tu_fill(create, primary: true)
        create.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(create)
        NSLayoutConstraint.activate([scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -TaskTheme.gap), footer.leadingAnchor.constraint(equalTo: view.leadingAnchor), footer.trailingAnchor.constraint(equalTo: view.trailingAnchor), footer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8), footer.heightAnchor.constraint(equalToConstant: 76), rule.leadingAnchor.constraint(equalTo: footer.leadingAnchor), rule.trailingAnchor.constraint(equalTo: footer.trailingAnchor), rule.topAnchor.constraint(equalTo: footer.topAnchor), rule.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale), create.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16), create.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16), create.bottomAnchor.constraint(equalTo: footer.bottomAnchor), create.heightAnchor.constraint(equalToConstant: 44), freeLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16), freeLabel.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16), freeLabel.bottomAnchor.constraint(equalTo: create.topAnchor, constant: -4)])
        draftButton = tu_ibtn("notes", "保存草稿", "split.draft", self, #selector(saveDraft)); var style = draftButton.configuration; style?.baseForegroundColor = TaskTheme.ink; draftButton.configuration = style
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: draftButton)
        buildList(); render()
    }
    // 统一显示导航栏，避免继承首页隐藏状态。
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); preferredContentSize = CGSize(width: 540, height: UIScreen.main.bounds.height); navigationController?.setNavigationBarHidden(false, animated: false) }
    // 首次进入且没有子任务时探测网关。
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); if !checked && parts.isEmpty { checked = true; ping() }; gaugeDebounced() }
    // 合并连续变化，按当前窗口显示空余时间。
    private func gaugeDebounced() { gaugeWork?.cancel(); let work = DispatchWorkItem { [weak self] in self?.gauge() }; gaugeWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work) }
    private func gauge() {
        guard isViewLoaded else { return }; let token = UUID(); gaugeTicket = token
        DispatchQueue.global(qos: .utility).async {
            var text = "空余—"
            if let raw = try? TaskIntake.ctx(self.store, fields: self.draft as NSDictionary, parts: self.parts as NSArray, at: Date().timeIntervalSince1970), let ctx = raw as? TaskFields, let room = ctx["room"] as? TaskFields, let capacity = room["capacity"] as? NSNumber { text = "空余" + tu_free(capacity.doubleValue) }
            DispatchQueue.main.async { guard self.gaugeTicket == token else { return }; self.freeLabel.text = text }
        }
    }
    // 返回或关闭时取消迟到结果；左滑返回同步本页编辑。
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); ticket = UUID(); request?.cancel(); request = nil; if isMovingFromParent && !synced { sync(false) } }
    // 备注变化不触发重排，只在离开或创建时交回。
    func textViewDidChange(_ textView: UITextView) { scroll.setNeedsLayout() }
    // 探测失败只能手动创建。
    private func ping() {
        phase = .checking; render()
        let token = UUID(); ticket = token
        request = TaskAI.reach(TaskAIConfig.ld() as NSDictionary) { [weak self] ok in
            guard let self, self.ticket == token, self.view.window != nil else { return }
            self.request = nil; self.manual = !ok; self.unreachable = !ok; self.phase = ok ? .ready : .offline; self.render()
        }
    }
    // 拆分按钮在可用时请求AI，离线或失败后手动创建。
    @objc private func splitTap() {
        switch phase {
        case .checking, .splitting: return
        case .offline: addPart()
        case .ready: manual ? addPart() : split()
        }
    }
    // 备注随拆分请求发送，帮助AI贴合用户设想。
    private func split() {
        guard parts.isEmpty else { return }; view.endEditing(true)
        let title = draft["title"] as? String ?? ""
        guard !title.isEmpty else { tu_err(self, TaskAI.err("请先填写标题")); return }
        var value = draft; value["notes"] = notes.text ?? ""
        let at = Date().timeIntervalSince1970
        guard let raw = try? TaskIntake.ctx(store, fields: value as NSDictionary, parts: [] as NSArray, at: at), let ctx = raw as? TaskFields, let room = ctx["room"] as? TaskFields else { tu_err(self, TaskAI.err("无法读取排程空档")); return }
        let span = Int(((room["max_span"] as? NSNumber)?.doubleValue ?? 0) / 60)
        var query: TaskFields = ["mode": "split", "title": title, "notes": notes.text ?? "",
            "window_start": value["due_at"] ?? 0, "window_end": value["deadline_at"] ?? 0,
            "urgency": value["urgency"] ?? 0, "rush": (value["rush"] as? NSNumber)?.boolValue == true,
            "difficulty": value["difficulty"] ?? 0, "capacity_minutes": Int(((room["capacity"] as? NSNumber)?.doubleValue ?? 0) / 60),
            "available_slots": room["gaps"] ?? [], "max_minutes": max(1, span), "policy": TaskTraits.policy(value, maxStep: span)]
        if let duration = draft["planned_duration"] as? NSNumber, duration.doubleValue > 0 { query["total_minutes"] = Int(ceil(duration.doubleValue / 60)) }
        phase = .splitting; render()
        let token = UUID(); ticket = token
        request = TaskAI.gen(query as NSDictionary, config: TaskAIConfig.ld() as NSDictionary) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.ticket == token, self.view.window != nil else { return }
                self.request = nil
                if let error { self.failed(error); return }
                guard let result = result as? TaskFields, let rows = result["steps"] as? [TaskFields], !rows.isEmpty else { self.failed(TaskAI.err("AI结果格式无效")); return }
                self.parts = rows.map { var row = $0; row["task_id"] = UUID().uuidString.lowercased(); return row }
                self.phase = .ready; self.buildList(); self.render(); self.gaugeDebounced(); TaskHaptics.success()
            }
        }
    }
    // 拆分失败提示错误并降级为手动创建。
    private func failed(_ error: Error) { phase = .offline; manual = true; unreachable = (error as NSError).code == 2; render(); tu_err(self, error) }
    // 手动新增一个可调整顺序的子任务。
    private func addPart() {
        view.endEditing(true)
        let row: TaskFields = ["task_id": UUID().uuidString.lowercased(), "title": "", "notes": ""]
        navigationController?.pushViewController(TaskStepEdit(row) { [weak self] updated in
            guard let self, let updated else { return }
            self.parts.append(updated); self.phase = .offline; self.manual = true; self.buildList(); self.render(); self.gaugeDebounced()
        }, animated: true)
    }
    // 修改子任务的标题、步骤和预计耗时。
    @objc private func editPart(_ sender: UIButton) {
        let index = sender.tag
        guard parts.indices.contains(index) else { return }
        view.endEditing(true)
        navigationController?.pushViewController(TaskStepEdit(parts[index]) { [weak self] updated in
            guard let self, let updated else { return }
            self.parts[index] = updated; self.buildList(); self.render(); self.gaugeDebounced()
        }, animated: true)
    }
    // 重建子任务容器，AI结果不提供拖动，手动项保留拖动图标。
    private func buildList() {
        for view in list.arrangedSubviews { list.removeArrangedSubview(view); view.removeFromSuperview() }
        list.addArrangedSubview(splitButton)
        for (index, row) in parts.enumerated() { list.addArrangedSubview(card(row, index)) }
    }
    // 单层卡片同时承载内容、修改与拖动入口。
    private func card(_ row: TaskFields, _ index: Int) -> UIView {
        let card = UIView(); card.backgroundColor = TaskTheme.surface; card.layer.cornerRadius = 12; card.layer.cornerCurve = .continuous; card.clipsToBounds = true
        card.accessibilityIdentifier = "split.card.\(index)"
        let label = tu_lbl(row["title"] as? String ?? ""); label.accessibilityIdentifier = "split.step.\(index)"
        let edit = tu_ibtn("edit", "修改", "split.edit.\(index)", self, #selector(editPart(_:))); edit.tag = index
        var editStyle = edit.configuration; editStyle?.baseForegroundColor = TaskTheme.muted; edit.configuration = editStyle
        edit.widthAnchor.constraint(equalToConstant: 44).isActive = true; edit.setContentHuggingPriority(.required, for: .horizontal)
        var actions: [UIView] = [edit]
        if manual {
            let drag = tu_ibtn("drag", "按住并拖动", "split.drag.\(index)", nil, nil); drag.tag = index
            var dragStyle = drag.configuration; dragStyle?.baseForegroundColor = TaskTheme.muted; drag.configuration = dragStyle
            drag.widthAnchor.constraint(equalToConstant: 44).isActive = true; drag.setContentHuggingPriority(.required, for: .horizontal)
            let press = UILongPressGestureRecognizer(target: self, action: #selector(dragMove(_:))); press.minimumPressDuration = 0.25; press.cancelsTouchesInView = true; drag.addGestureRecognizer(press)
            actions.append(drag)
        }
        let rowView = tu_stk([label] + actions); rowView.axis = .horizontal; rowView.alignment = .center; rowView.spacing = 4
        rowView.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(rowView)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([rowView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12), rowView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4), rowView.topAnchor.constraint(equalTo: card.topAnchor, constant: 8), rowView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8), card.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)])
        return card
    }
    // 按住拖动图标后卡片跟随手指，松手按位置落下并调整顺序。
    @objc private func dragMove(_ gesture: UILongPressGestureRecognizer) {
        guard manual, let button = gesture.view, let card = button.superview?.superview else { return }
        switch gesture.state {
        case .began:
            view.endEditing(true); dragged = card; dragStart = gesture.location(in: list).y; scroll.isScrollEnabled = false; button.transform = .identity
            card.layer.zPosition = 1; TaskMotion.animate(.snappy) { card.alpha = 0.94 }
        case .changed:
            guard let card = dragged else { return }
            card.transform = CGAffineTransform(translationX: 0, y: gesture.location(in: list).y - dragStart)
        default:
            guard let card = dragged else { scroll.isScrollEnabled = true; return }
            dragged = nil; scroll.isScrollEnabled = true; card.layer.zPosition = 0; card.transform = .identity; card.alpha = 1
            if let header = list.arrangedSubviews.firstIndex(of: splitButton), let listIndex = list.arrangedSubviews.firstIndex(of: card) {
                let current = listIndex - header - 1, y = gesture.location(in: list).y
                let cards = list.arrangedSubviews.filter { $0 !== splitButton && $0 !== card }
                let target = cards.firstIndex { y < $0.frame.midY } ?? cards.count
                if parts.indices.contains(current), current != target { let row = parts.remove(at: current); parts.insert(row, at: target) }
            }
            UIView.transition(with: list, duration: 0.2, options: .transitionCrossDissolve) { self.buildList(); self.list.layoutIfNeeded() }
            render()
        }
    }
    // 返回第二页并请求评估创建。
    @objc private func createTap() {
        guard !parts.isEmpty, !saving else { return }
        view.endEditing(true); saving = true; render(); sync(true)
        navigationController?.popViewController(animated: true)
    }
    // 保存备注与子任务后返回第二页，创建标记交给第二页继续评估。
    private func sync(_ create: Bool) {
        guard !synced else { return }; synced = true
        reply(notes.text ?? "", parts, create, manual, unreachable)
    }
    // 保存完整草稿并关闭整个创建面板。
    @objc private func saveDraft() {
        guard !saving else { return }; view.endEditing(true); saving = true; render()
        var fields = draft; fields["notes"] = notes.text ?? ""
        var data: TaskFields = ["fields": fields, "parts": parts, "split": true, "manual": manual, "unreachable": unreachable, "saved_at": Date().timeIntervalSince1970]
        if let estimate { data["estimate"] = estimate }
        DispatchQueue.global(qos: .utility).async {
            var failure: Error?
            do { try self.store.storeDraft(data as [AnyHashable: Any]) } catch { failure = error }
            DispatchQueue.main.async {
                if let failure { self.saving = false; self.render(); tu_err(self, failure); return }
                self.synced = true; if let nav = self.navigationController, nav.presentingViewController != nil { nav.dismiss(animated: true) } else { self.dismiss(animated: true) }
            }
        }
    }
    // 更新拆分按钮、创建与草稿可用状态。
    private func render() {
        guard isViewLoaded, splitButton != nil else { return }
        let busy = phase == .checking || phase == .splitting
        var config = splitButton.configuration
        config?.title = manual ? "手动创建" : "智能拆分"; config?.image = manual ? lb_icon("add") : nil; config?.showsActivityIndicator = busy
        splitButton.configuration = config; splitButton.isEnabled = !busy && !saving; splitButton.isHidden = !parts.isEmpty && !manual
        splitButton.accessibilityLabel = manual ? "手动创建子任务" : "智能拆分子任务"
        create.isEnabled = !parts.isEmpty && !saving; draftButton.isEnabled = !saving
        navigationItem.setHidesBackButton(saving, animated: false); navigationController?.interactivePopGestureRecognizer?.isEnabled = !saving
    }
}