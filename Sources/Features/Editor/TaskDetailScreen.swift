// 只读任务详情；所有修改从右上角编辑进入创建管道第二页。
@objc(TaskDetailScreen) final class TaskDetailScreen: TaskScreen {
    private let store: TaskStore
    private var task: TaskFields
    private let saved: (() -> Void)?
    private let queue = DispatchQueue(label: "com.iwmei.taskforiwmei.detail")
    private var content: UIStackView!
    private weak var moreButton: UIButton?
    private var scheduleLabel: UILabel?
    private var scheduleToken = UUID()
    private var parts: [TaskFields] = [], siblings: [TaskFields] = []
    private var noteToken: Int32 = -1

    private var id: String { task["task_id"] as? String ?? "" }
    private var parentID: String? { task["parent_id"] as? String }
    private var starred: Bool { (task["starred"] as? NSNumber)?.boolValue == true }
    private var zone: TimeZone { (task["timezone_id"] as? String).flatMap(TimeZone.init(identifier:)) ?? TaskTimeZone.current }

    // 接收稳定任务快照和首页刷新回调。
    @objc(initWithStore:task:saved:) init(store: TaskStore, task: TaskFields, saved: (() -> Void)?) {
        self.store = store; self.task = task; self.saved = saved; super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(store:task:saved:)") }

    // 建立只读导航、编辑入口和更多菜单。
    override func viewDidLoad() {
        super.viewDidLoad(); title = "任务详情"
        let back = tu_ibtn("back", "返回", "detail.back", self, #selector(bk))
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: back)
        let edit = tu_ibtn("edit", "编辑", "detail.edit", self, #selector(edt))
        let more = tu_ibtn("more", "任务选项", "detail.menu", nil, nil)
        more.menu = UIMenu(children: menuActions()); more.showsMenuAsPrimaryAction = true; moreButton = more
        navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: more), UIBarButtonItem(customView: edit)]
        content = tu_stk([]); content.spacing = TaskTheme.group
        tu_form(self, content, "detail.content")
        reg(); reload()
    }
    deinit { if noteToken >= 0 { notify_cancel(noteToken) } }
    // 订阅数据库变更，保持详情与 HUD 和其他进程一致。
    private func reg() {
        guard noteToken < 0 else { return }
        var token: Int32 = -1
        let result = notify_register_dispatch(store.changeNote, &token, .main) { [weak self] _ in self?.reload() }
        noteToken = result == NOTIFY_STATUS_OK ? token : -1
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); navigationController?.setNavigationBarHidden(false, animated: false); reload() }
    @objc private func bk() { navigationController?.popViewController(animated: true) }

    // 重新读取任务、步骤和父任务上下文。
    private func reload() {
        guard !id.isEmpty, let latest = (try? store.rdTsk(id)) as? TaskFields else { return }
        task = latest
        let all = (try? store.lsTsks()) as? [TaskFields] ?? []
        func rows(_ parent: String) -> [TaskFields] {
            all.filter { (($0["deleted"] as? NSNumber)?.boolValue == false) && ($0["parent_id"] as? String == parent) }
                .sorted { (($0["position"] as? NSNumber)?.intValue ?? 0) < (($1["position"] as? NSNumber)?.intValue ?? 0) }
        }
        parts = rows(id)
        siblings = parentID.map(rows) ?? []
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        build()
        moreButton?.menu = UIMenu(children: menuActions())
    }

    // 构建标题、内容和分区卡片。
    private func build() {
        let titleLabel = tu_lbl(task["title"] as? String ?? "")
        titleLabel.font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: .systemFont(ofSize: 28, weight: .semibold), maximumPointSize: 32)
        titleLabel.accessibilityIdentifier = "detail.title"
        content.addArrangedSubview(titleLabel)
        let notes = (task["notes"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if parentID == nil, !notes.isEmpty {
            let label = tu_lbl(notes); label.font = lb_fnt(.body, nil); label.accessibilityIdentifier = "detail.notes"; content.addArrangedSubview(label)
        }
        if let parentID, let parent = (try? store.rdTsk(parentID)) as? TaskFields {
            let full = parent["title"] as? String ?? ""
            content.addArrangedSubview(tu_link("所属  " + full, id: "detail.parent", muted: false) { [weak self] in self?.open(parent) })
        }
        if parentID == nil {
            windowCard()
            stepsCard()
            evalCard()
        } else {
            stepCard(notes)
        }
    }

    // 只读时间窗口。
    private func windowCard() {
        var rows: [UIView] = [tu_header("时间")]
        if let deadline = dateText("deadline_at", kind: task["deadline_kind"] as? String, deadline: true) { rows.append(readRow("截止", deadline)) }
        if let plan = dateText("due_at", kind: task["schedule_kind"] as? String, deadline: false) { rows.append(readRow("日期", plan)) }
        guard rows.count > 1 else { return }
        content.addArrangedSubview(tu_card(rows))
    }

    // 主任务的执行步骤，只读进入子任务详情。
    private func stepsCard() {
        guard !parts.isEmpty else { return }
        let done = parts.filter { $0["status"] as? String == "completed" }.count
        let title = tu_lbl("执行步骤"), count = tu_lbl("\(done)/\(parts.count) 完成")
        for label in [title, count] { label.font = lb_fnt(.subheadline, nil); label.textColor = TaskTheme.muted; label.numberOfLines = 1 }
        count.setContentHuggingPriority(.required, for: .horizontal)
        let header = tu_stk([title, UIView(), count]); header.axis = .horizontal; header.alignment = .center
        header.isLayoutMarginsRelativeArrangement = true; header.layoutMargins = .init(top: 4, left: 12, bottom: 4, right: 12)
        var rows: [UIView] = [header]
        for part in parts {
            let id = part["task_id"] as? String ?? "", complete = part["status"] as? String == "completed"
            let row = tu_link(part["title"] as? String ?? "", icon: complete ? "check_circle" : nil, id: "detail.step." + id, muted: complete) { [weak self] in self?.open(part) }
            row.accessibilityValue = complete ? "已完成" : nil; rows.append(row)
        }
        content.addArrangedSubview(tu_card(rows))
    }

    // 主任务评估值，只读展示。
    private func evalCard() {
        let rows: [UIView] = [tu_header("评估"), readRow("紧急程度", urgencyText), readRow("难易程度", difficultyText), readRow("预计分钟", minutesText)]
        content.addArrangedSubview(tu_card(rows))
    }

    // 子任务执行步骤：AI 说明、预计分钟和实际排程时段。
    private func stepCard(_ notes: String) {
        let index = siblings.firstIndex { ($0["task_id"] as? String) == id }
        let title = index.map { "执行步骤 \($0 + 1)/\(siblings.count)" } ?? "执行步骤"
        var rows: [UIView] = [tu_header(title)]
        if !notes.isEmpty { let label = tu_lbl(notes); label.font = lb_fnt(.body, nil); let wrap = UIView(); wrap.addSubview(label); label.translatesAutoresizingMaskIntoConstraints = false; NSLayoutConstraint.activate([label.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 8), label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -8), label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12), label.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12)]); rows.append(wrap) }
        rows.append(readRow("预计", minutesText))
        let schedule = tu_lbl("待安排"); schedule.font = lb_fnt(.body, nil); schedule.textColor = TaskTheme.ink; schedule.numberOfLines = 0
        let row = tu_stk([tu_lbl("排程"), UIView(), schedule]); row.axis = .horizontal; row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true; row.layoutMargins = .init(top: 8, left: 12, bottom: 8, right: 12)
        schedule.setContentHuggingPriority(.required, for: .horizontal); scheduleLabel = schedule; rows.append(row)
        content.addArrangedSubview(tu_card(rows))
        loadSchedule()
    }

    // 只读字段行：左标签、右值。
    private func readRow(_ title: String, _ value: String) -> UIView {
        let name = tu_lbl(title), detail = tu_lbl(value)
        name.font = lb_fnt(.body, nil); detail.font = lb_fnt(.body, nil); detail.textColor = TaskTheme.ink
        detail.numberOfLines = 0; detail.setContentHuggingPriority(.required, for: .horizontal)
        let row = tu_stk([name, UIView(), detail]); row.axis = .horizontal; row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true; row.layoutMargins = .init(top: 8, left: 12, bottom: 8, right: 12)
        return row
    }

    private func dateText(_ key: String, kind: String?, deadline: Bool) -> String? {
        guard let kind, kind != "none", let stamp = (task[key] as? NSNumber)?.doubleValue else { return nil }
        var date = Date(timeIntervalSince1970: stamp)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        if deadline && kind == "date" { date = calendar.date(byAdding: .day, value: -1, to: date)! }
        let format = DateFormatter(); format.timeZone = zone; format.locale = Locale(identifier: "zh_CN"); format.dateFormat = kind == "timed" ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return format.string(from: date)
    }
    private var urgencyText: String {
        if (task["rush"] as? NSNumber)?.boolValue == true { return "赶DDL" }
        let value = (task["urgency"] as? NSNumber)?.intValue ?? 0
        return ["未设置", "低", "中", "高"][min(max(value, 0), 3)]
    }
    private var difficultyText: String {
        let value = (task["difficulty"] as? NSNumber)?.intValue ?? 0
        return ["未评估", "简单", "一般", "困难"][min(max(value, 0), 3)]
    }
    private var minutesText: String {
        guard let seconds = (task["planned_duration"] as? NSNumber)?.doubleValue, seconds.isFinite, seconds > 0 else { return "未设置" }
        let minutes = Int((seconds / 60).rounded()); return "\(minutes) 分钟"
    }

    // 从调度器实际落点读取子任务时段。
    private func loadSchedule() {
        scheduleToken = UUID(); let token = scheduleToken
        guard parentID != nil else { return }
        let window = (try? store.rdTsk(parentID!)) as? TaskFields ?? task
        guard let start = (window["due_at"] as? NSNumber)?.doubleValue, let end = (window["deadline_at"] as? NSNumber)?.doubleValue, start > 0, end > start else { return }
        let id = self.id, zone = self.zone
        queue.async {
            let calendar = TaskWindow.calendar(zone); var day = calendar.startOfDay(for: Date(timeIntervalSince1970: start)); var slot: (Double, Double)?
            for _ in 0..<40 where day.timeIntervalSince1970 < end {
                if let raw = try? self.store.day(at: day.timeIntervalSince1970, zone: zone.identifier, now: Date().timeIntervalSince1970), let plan = raw as? TaskFields,
                   let allocations = plan["allocations"] as? [TaskFields], let hit = allocations.first(where: { ($0["task_id"] as? String) == id }),
                   let from = (hit["start_at"] as? NSNumber)?.doubleValue, let to = (hit["end_at"] as? NSNumber)?.doubleValue { slot = (from, to); break }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            DispatchQueue.main.async { guard self.scheduleToken == token else { return }; self.scheduleLabel?.text = slot.map { self.formatSlot($0.0, $0.1) } ?? "待安排" }
        }
    }
    private func formatSlot(_ start: Double, _ end: Double) -> String {
        let format = DateFormatter(); format.timeZone = zone; format.locale = Locale(identifier: "zh_CN")
        let clock = DateFormatter(); clock.timeZone = zone; clock.locale = format.locale; clock.dateFormat = "HH:mm"
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let from = Date(timeIntervalSince1970: start), to = Date(timeIntervalSince1970: end)
        format.dateFormat = calendar.isDateInToday(from) ? "HH:mm" : "MM-dd HH:mm"
        return format.string(from: from) + "–" + clock.string(from: to)
    }

    // 打开子任务或父任务只读详情。
    private func open(_ task: TaskFields) { navigationController?.pushViewController(TaskDetailScreen(store: store, task: task, saved: saved), animated: true) }

    // 编辑直接进入创建管道第二页，预填全部现有字段和步骤。
    @objc private func edt() {
        guard !id.isEmpty else { return }
        var fields = task.filter { TaskIntake.keys.contains($0.key) }; fields["task_id"] = id
        if let parentID, let parent = (try? store.rdTsk(parentID)) as? TaskFields {
            for key in ["due_at", "deadline_at"] where fields[key] == nil || fields[key] is NSNull { fields[key] = parent[key] }
            for key in ["schedule_kind", "deadline_kind"] where fields[key] == nil || fields[key] is NSNull || fields[key] as? String == "none" { fields[key] = parent[key] }
            if fields["timezone_id"] == nil { fields["timezone_id"] = parent["timezone_id"] }
        }
        let rows = parentID == nil ? parts.map { $0.filter { TaskIntake.partKeys.contains($0.key) } } : []
        let page = TaskAdmissionScreen(store: store, fields: fields, parts: rows) { [weak self] in
            guard let self else { return }
            if let nav = self.navigationController, let index = nav.viewControllers.firstIndex(where: { $0 === self }), index > 0 { nav.popToViewController(self, animated: true) }
            self.saved?(); self.reload()
        }
        navigationController?.pushViewController(page, animated: true)
    }

    // 只读详情动作：星标、移动、记录、独立和删除。
    private func menuActions() -> [UIAction] {
        var actions: [UIAction] = [tu_act(starred ? "取消星标" : "添加星标", nil, "detail.star") { [weak self] in self?.toggleStar() }]
        if parentID == nil && (task["recurrence"] as? [String] ?? []).isEmpty { actions.append(tu_act("将任务移动至…", nil, "detail.move") { [weak self] in self?.moveList() }) }
        actions.append(tu_act("完成记录", nil, "detail.history") { [weak self] in self?.history() })
        if parentID != nil { actions.append(tu_act("转为独立任务", nil, "detail.detach") { [weak self] in self?.detach() }) }
        let remove = tu_act("删除任务", nil, "detail.delete") { [weak self] in guard let self else { return }; tu_cfrm(self, parentID == nil ? "删除任务及子任务" : "删除子任务") { [weak self] in self?.delete() } }; remove.attributes = .destructive; actions.append(remove)
        return actions
    }
    private func toggleStar() {
        guard !id.isEmpty else { return }
        do { try store.updTsk(id, fields: ["starred": starred ? 0 : 1]); saved?(); reload() } catch { tu_err(self, error) }
    }
    private func moveList() {
        do {
            let lists = try store.lsLsts() as! [TaskFields]
            let actions = lists.filter { ($0["list_id"] as? String) != TS_RTN_LST }.map { list -> UIAction in
                let target = list["list_id"] as! String
                let action = tu_act(list["title"] as? String ?? "", nil, target) { [weak self] in
                    guard let self else { return }
                    do { try self.store.updTsk(self.id, fields: ["list_id": target]); self.saved?(); self.reload() } catch { tu_err(self, error) }
                }
                action.state = target == task["list_id"] as? String ? .on : .off; return action
            }
            tu_menu(self, "清单", actions, caption: "将任务移动至")
        } catch { tu_err(self, error) }
    }
    private func history() {
        do {
            let format = DateFormatter(); format.dateFormat = "MM-dd HH:mm"; format.timeZone = .current
            var actions = try (store.lsOcc(id) as! [TaskFields]).filter { $0["action"] as? String == "complete" }.map { occ -> UIAction in
                let title = format.string(from: Date(timeIntervalSince1970: (occ["handled_at"] as! NSNumber).doubleValue))
                return tu_act(title, "check_circle", occ["occurrence_id"] as! String) { [weak self] in guard let self else { return }; self.navigationController?.pushViewController(TaskProofScreen(store: self.store, occurrence: occ["occurrence_id"] as! String), animated: true) }
            }
            if actions.isEmpty { let item = tu_act("暂无完成记录", nil, "detail.history.empty") {}; item.attributes = .disabled; actions = [item] }
            tu_menu(self, "完成记录", actions, caption: "完成记录")
        } catch { tu_err(self, error) }
    }
    private func detach() {
        let old = parentID
        do { try store.updTsk(id, fields: ["parent_id": NSNull()]); recalc(old); saved?(); reload() } catch { tu_err(self, error) }
    }
    private func delete() {
        let old = parentID
        do { try store.delTsk(id); recalc(old); saved?(); navigationController?.popViewController(animated: true) } catch { tu_err(self, error) }
    }
    // 从指定父级起逐级重算预计分钟。
    private func recalc(_ parent: String?) {
        var current = parent
        while let pid = current, pid != id {
            let all = (try? store.lsTsks() as? [TaskFields]) ?? []
            let total = all.filter { ($0["parent_id"] as? String) == pid && ($0["deleted"] as? NSNumber)?.boolValue == false }
                .reduce(0.0) { $0 + (($1["planned_duration"] as? NSNumber)?.doubleValue ?? 0) }
            do { try store.updTsk(pid, fields: ["planned_duration": total]) } catch { return }
            current = all.first { ($0["task_id"] as? String) == pid }?["parent_id"] as? String
        }
    }
}