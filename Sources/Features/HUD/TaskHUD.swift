// 在现有系统安全窗口内显示独占提醒与本地图片打卡。
@objc(TTTaskHUD) final class TaskHUD: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    @objc var reminder: TaskReminder?
    @objc var windowMode: ((Int) -> Void)?
    @objc private(set) var mode = 0
    // 测试轮次仅保留在当前HUD内存，不进入TaskStore。
    @objc private(set) var testOccurrence: NSDictionary?
    @objc var globalCapture = false
#if LB_UI_TEST
    @objc var captureLaunch: (() -> Bool)?
#endif
    private let card = tu_gls(), scroll = UIScrollView(), titleText = tu_lbl(nil), notes = tu_lbl(nil), planned = tu_lbl(nil)
    private let barMaterial = tu_gls()
    private let traits = tu_stk([]), signal = TaskSignal()
    private let attachmentSlot = UIScrollView(), footer = UIView(), sidebar = UIButton(type: .system)
    private var fullLayout: [NSLayoutConstraint] = []
    private var body: UIStackView!, cardWidth: NSLayoutConstraint!, cardHeight: NSLayoutConstraint!, footerHeight: NSLayoutConstraint!
    private var actions: UIStackView!, choices: UIStackView!, done: UIButton!, delay: UIButton!
    private var choiceButtons: [UIButton] = [], attachmentButtons: [UIButton] = [], controlSize: CGFloat = 0
    private var alert: TaskFields?, held: TaskFields?, proofs: [TaskFields] = [], pickingMethod = "image", pickingID: String?
    private var pickVersion = 0, loading = false, loadFailed = false
    private var captureLimit = Int(TS_ATT_MAX), captureToken: String?, captureWatch: DispatchSourceProcess?
    private var captureNotify: Int32 = -1
    private var captureDone: (([TaskFields], String?) -> Void)?
    private var timer: DispatchSourceTimer?, observers: [NSObjectProtocol] = [], busy = false, selecting = false, stopped = false, previewing = false
    private var id: String? { alert?["occurrence_id"] as? String }

    // 创建安全区中的可滚动详情与固定操作入口。
    override func viewDidLoad() {
        super.viewDidLoad(); overrideUserInterfaceStyle = .dark; view.accessibilityIdentifier = "hud.fullscreen"
        // 复用现有HUD的居中原生磨砂卡片。
        view.isOpaque = false; view.tintColor = lb_acnt()
        card.accessibilityIdentifier = "hud.card"
        card.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(card)
        titleText.font = lb_fnt(.title2, nil); titleText.numberOfLines = 0; titleText.adjustsFontSizeToFitWidth = false; titleText.accessibilityIdentifier = "hud.title"
        notes.numberOfLines = 0; notes.adjustsFontSizeToFitWidth = false; notes.textColor = TaskTheme.ink; notes.accessibilityIdentifier = "hud.notes"
        planned.textColor = TaskTheme.muted; planned.font = lb_fnt(.subheadline, nil); planned.numberOfLines = 0; planned.adjustsFontSizeToFitWidth = false; planned.accessibilityIdentifier = "hud.planned"
        done = tu_btn("提交", nil, self, #selector(cmpl)); done.accessibilityIdentifier = "hud.complete"
        delay = tu_btn("延后5分钟", nil, self, #selector(snz)); delay.accessibilityIdentifier = "hud.snooze"
        // 固定操作文字在窄屏大字下保持单行，最低保留20pt。
        for button in [done!,delay!] {var config=button.configuration;config?.titleLineBreakMode = .byClipping;button.configuration=config;button.titleLabel?.numberOfLines=1;button.titleLabel?.adjustsFontSizeToFitWidth=true;button.titleLabel?.minimumScaleFactor=20.0/32.0}
        let shot = tu_ibtn("screenshot", "截图", "hud.screenshot", self, #selector(sht))
        let upload = tu_ibtn("upload", "上传附件", "hud.image", nil, nil)
        upload.menu = UIMenu(children: [
            tu_act("照片图库", "pic", "hud.source.photo") { [weak self] in self?.pht(false) },
            tu_act("拍照", "camera", "hud.source.camera") { [weak self] in self?.cam() },
            tu_act("选择截图", "screenshot", "hud.source.screenshot") { [weak self] in self?.pht(true) },
            tu_act("选取文件", "folder", "hud.source.file") { [weak self] in self?.fl() },
        ]); upload.showsMenuAsPrimaryAction = true
        let back = tu_ibtn("back", "返回", "hud.back", self, #selector(bck))
        tu_fill(done, primary: true); tu_fill(delay)
        choiceButtons = [shot, upload, back]; choiceButtons.forEach { tu_fill($0) }
        choices = tu_stk(choiceButtons); choices.axis = .horizontal; choices.distribution = .fillEqually
        choices.accessibilityIdentifier = "hud.choices"; choices.isHidden = true
        // 固定一排六个图标位，极窄屏只横向滚动附件行。
        var slots: [UIView] = []
        for index in 0..<Int(TS_ATT_MAX) {
            let button = tu_ibtn("pic", "移除附件\(index + 1)", "hud.attachment.\(index)", self, #selector(rmv(_:)))
            tu_fill(button)
            button.tag = index; button.isHidden = true; button.translatesAutoresizingMaskIntoConstraints = false
            let slot = UIView(); slot.addSubview(button); slots.append(slot); attachmentButtons.append(button)
            let close = UIImageView(image: lb_icon("close")); close.isUserInteractionEnabled = false; close.isAccessibilityElement = false
            close.tintColor = lb_acnt(); close.translatesAutoresizingMaskIntoConstraints = false; button.addSubview(close)
            NSLayoutConstraint.activate([slot.widthAnchor.constraint(equalToConstant: 44), slot.heightAnchor.constraint(equalToConstant: 44),
                button.topAnchor.constraint(equalTo: slot.topAnchor), button.bottomAnchor.constraint(equalTo: slot.bottomAnchor),
                button.leadingAnchor.constraint(equalTo: slot.leadingAnchor), button.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
                close.widthAnchor.constraint(equalToConstant: 12), close.heightAnchor.constraint(equalToConstant: 12),
                close.topAnchor.constraint(equalTo: button.topAnchor, constant: 4), close.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4)])
        }
        let grid = tu_stk(slots); grid.axis = .horizontal; grid.spacing = 4; grid.translatesAutoresizingMaskIntoConstraints = false
        attachmentSlot.accessibilityIdentifier = "hud.attachments"; attachmentSlot.addSubview(grid)
        attachmentSlot.showsHorizontalScrollIndicator = false; attachmentSlot.isDirectionalLockEnabled = true
        NSLayoutConstraint.activate([attachmentSlot.heightAnchor.constraint(equalToConstant: 44),
            grid.topAnchor.constraint(equalTo: attachmentSlot.contentLayoutGuide.topAnchor), grid.bottomAnchor.constraint(equalTo: attachmentSlot.contentLayoutGuide.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: attachmentSlot.contentLayoutGuide.leadingAnchor), grid.trailingAnchor.constraint(equalTo: attachmentSlot.contentLayoutGuide.trailingAnchor),
            attachmentSlot.contentLayoutGuide.heightAnchor.constraint(equalTo: attachmentSlot.frameLayoutGuide.heightAnchor)])
        traits.accessibilityIdentifier = "hud.traits"; traits.isHidden = true
        let content = tu_stk([titleText, planned, traits, notes, attachmentSlot]); body = content; content.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false; scroll.alwaysBounceVertical = true; scroll.accessibilityIdentifier = "hud.details"
        card.contentView.addSubview(scroll); scroll.addSubview(content)
        footer.translatesAutoresizingMaskIntoConstraints = false; card.contentView.addSubview(footer)
        actions = tu_stk([done, delay]); actions.axis = .horizontal; actions.distribution = .fillEqually
        for row in [actions!, choices!] {
            row.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(row)
            NSLayoutConstraint.activate([row.topAnchor.constraint(equalTo: footer.topAnchor), row.bottomAnchor.constraint(equalTo: footer.bottomAnchor),
                row.leadingAnchor.constraint(equalTo: footer.leadingAnchor), row.trailingAnchor.constraint(equalTo: footer.trailingAnchor)])
        }
        footerHeight = footer.heightAnchor.constraint(equalToConstant: 44)
        for button in [done, delay] { button?.contentHorizontalAlignment = .center }
        sidebar.layer.cornerRadius = 20; sidebar.backgroundColor = .clear; sidebar.tintColor = lb_acnt()
        barMaterial.frame = sidebar.bounds; barMaterial.autoresizingMask = [.flexibleWidth, .flexibleHeight]; barMaterial.isUserInteractionEnabled = false; sidebar.insertSubview(barMaterial, at: 0)
        sidebar.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        sidebar.accessibilityIdentifier = "hud.sidebar"; sidebar.addTarget(self, action: #selector(exp), for: .touchUpInside)
        sidebar.translatesAutoresizingMaskIntoConstraints = false; sidebar.isHidden = true; view.addSubview(sidebar)
        let contentWidth = content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor); contentWidth.priority = .defaultHigh
        let actionWidth = footer.widthAnchor.constraint(equalTo: scroll.widthAnchor); actionWidth.priority = .defaultHigh
        cardWidth = card.widthAnchor.constraint(equalToConstant: 320); cardHeight = card.heightAnchor.constraint(equalToConstant: 240)
        fullLayout = [
            card.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor), card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor), cardWidth, cardHeight,
            scroll.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 12), scroll.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            content.centerXAnchor.constraint(equalTo: scroll.contentLayoutGuide.centerXAnchor), content.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: scroll.contentLayoutGuide.trailingAnchor), content.widthAnchor.constraint(lessThanOrEqualToConstant: 680),
            contentWidth,
            footer.centerXAnchor.constraint(equalTo: card.contentView.centerXAnchor), footer.leadingAnchor.constraint(greaterThanOrEqualTo: card.contentView.leadingAnchor, constant: 12),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: card.contentView.trailingAnchor, constant: -12),
            actionWidth, footerHeight, footer.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
        ]
        NSLayoutConstraint.activate(fullLayout + [
            sidebar.topAnchor.constraint(equalTo: view.topAnchor, constant: 4), sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            sidebar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4), sidebar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
        ])
        observers = [UIApplication.significantTimeChangeNotification, .NSSystemClockDidChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.tck() }
        }
        // 首次操作立即静音，不拦截按钮、菜单或原生滚动。
        for button in [done!, delay!, sidebar] + choiceButtons + attachmentButtons { button.addTarget(self, action: #selector(quiet), for: .touchDown) }
        let touch = UITapGestureRecognizer(target: self, action: #selector(quiet)); touch.cancelsTouchesInView = false; view.addGestureRecognizer(touch)
        scroll.panGestureRecognizer.addTarget(self, action: #selector(quiet))
    }

    // 确认注意到只停止声振，不提交或解除当前提醒。
    @objc private func quiet() { signal.quiet() }
#if LB_UI_TEST
    // 为模拟器验收暴露同一实例的只读状态和硬件输入。
    @objc(signalState) func sigState() -> NSDictionary { signal.probe() as NSDictionary }
    @objc(signalSample:) func sigSample(_ value: NSDictionary) { signal.probeSample(value as? TaskFields ?? [:]) }
    @objc(signalAudio:) func sigAudio(_ value: Bool) { signal.probeAudio(value) }
#endif

    // 按正文与动态字体确定稳定高度，状态切换共用底部操作区。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard mode == 1 else { return }
        let safe = view.bounds.inset(by: view.safeAreaInsets)
        let attachmentWidth = CGFloat(TS_ATT_MAX) * 44 + CGFloat(TS_ATT_MAX - 1) * 4 + 24
        let width = max(1, min(560, max(safe.width * 0.9, min(attachmentWidth, safe.width - 8))))
        let textWidth = max(1, width - 24)
        let scaled = lb_fnt(.headline, traitCollection)!, font = scaled.withSize(min(32, scaled.pointSize))
        if controlSize != font.pointSize {
            controlSize = font.pointSize
            for button in [done!, delay!] {
                var config = button.configuration
                config?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                    var result = incoming; result.font = font; return result
                }; button.configuration = config
            }
        }
        let labelWidth = max(1, (textWidth - 8) / 2 - 16)
        let label = ("图片读取失败" as NSString).boundingRect(with: CGSize(width: labelWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        let buttonHeight = max(44, ceil(label.height) + 16)
        if abs(footerHeight.constant - buttonHeight) > 0.5 { footerHeight.constant = buttonHeight; view.setNeedsLayout() }
        let fit = CGSize(width: textWidth, height: UIView.layoutFittingCompressedSize.height)
        let textHeight = body.systemLayoutSizeFitting(fit, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let height = max(1, min(max(240, textHeight + buttonHeight + 36), safe.height * 0.9))
        if abs(cardWidth.constant - width) > 0.5 || abs(cardHeight.constant - height) > 0.5 {
            cardWidth.constant = width; cardHeight.constant = height; view.setNeedsLayout()
        }
    }

    // 仅在展示状态变化时更新系统窗口形态。
    private func mdl(_ value: Int) {
        let changed = mode != value
        mode = value; card.isHidden = value != 1; scroll.isHidden = value != 1; sidebar.isHidden = value != 2
        view.backgroundColor = value == 1 ? UIColor.black.withAlphaComponent(0.55) : .clear
        if changed { windowMode?(captureToken == nil ? value : 0) }
        if value == 1 { NSLayoutConstraint.activate(fullLayout) } else { NSLayoutConstraint.deactivate(fullLayout) }
        lay()
    }
    // 切换操作行、图标选择和图片确认的布局。
    private func lay() {
        choices.isHidden = !selecting; actions.isHidden = mode != 1 || selecting
        delay.isHidden = false
        for (index, button) in attachmentButtons.enumerated() {
            button.isHidden = index >= proofs.count; button.isEnabled = !busy && !loading
            if index < proofs.count {
                let file = proofs[index]["method"] as? String == "file"
                var config = button.configuration; config?.image = lb_icon(file ? "folder" : "pic"); button.configuration = config
                button.accessibilityLabel = file ? "移除文件附件\(index + 1)" : "移除图片附件\(index + 1)"
            }
        }
        let confirm = !proofs.isEmpty, back = choiceButtons.last!
        var config = back.configuration; config?.image = lb_icon(confirm ? "check_circle" : "back"); back.configuration = config
        back.accessibilityLabel = confirm ? "提交并完成当前任务" : "返回"
        for button in choiceButtons { button.isEnabled = !busy && !loading }
        let upload = choiceButtons[1]; upload.isEnabled = !busy && !loading && proofs.count < Int(TS_ATT_MAX)
        upload.accessibilityHint = "最多6个附件，已选\(proofs.count)个"
        var source = upload.configuration; source?.showsActivityIndicator = loading; upload.configuration = source
        view.setNeedsLayout()
    }
    // 结束上一轮次的触摸与原生来源菜单。
    private func cncl() {
        for button in [done, delay, sidebar] + choiceButtons + attachmentButtons {
            button?.cancelTracking(with: nil); button?.contextMenuInteraction?.dismissMenu()
        }
    }
    // 从服务快照恢复尚未结束的边栏，不逐秒查询数据库。
    private func hld() {
        var issue: NSError?
        guard let snapshot = reminder?.snap(&issue) as? TaskFields else { held = nil; return }
        let tasks = snapshot["tasks"] as? [TaskFields] ?? []
        held = (snapshot["history"] as? [TaskFields] ?? []).filter { row in
            row["status"] as? String == "snoozed" && row["action"] as? String == "snooze" && row["hold_reason"] is String
                && tasks.contains { $0["task_id"] as? String == row["task_id"] as? String && $0["status"] as? String == "needsAction"
                    && ($0["deleted"] as? NSNumber)?.boolValue == false && ($0["reminder_version"] as? NSNumber) == (row["generation"] as? NSNumber) }
        }.sorted { (($0["hold_until"] as? NSNumber)?.doubleValue ?? .infinity) < (($1["hold_until"] as? NSNumber)?.doubleValue ?? .infinity) }.first
    }
    // 显示标题、说明及当前时刻（实际安排或原计划）。
    @objc(display:error:) func dsp(_ value: NSDictionary?, error: NSError?) {
        guard !stopped else { return }; loadViewIfNeeded(); let previous = id, wasPreview = previewing
        if value == nil, error != nil, mode != 0 { busy = false; done.isEnabled = true; sidebar.isEnabled = true; stt("重试打卡"); lay(); return }
        let incoming = value?["occurrence_id"] as? String
        if incoming != nil, wasPreview { testOccurrence = nil }
        if incoming != nil, incoming == previous, busy, error == nil { return }
        alert = value as? TaskFields; busy = false; sidebar.isEnabled = true; previewing = false; hld()
        if alert == nil, held == nil, wasPreview, error == nil { previewing = true; return }
        if previous != id {
            signal.stop()
            if captureToken != nil { capRestore(nil) }
            cncl()
            proofs.removeAll(); attachmentSlot.setContentOffset(.zero, animated: false); pickVersion += 1; loading = false; selecting = false; pickingID = nil; presentedViewController?.dismiss(animated: false)
        }
        guard let alert else {
            signal.stop()
            if held != nil { mdl(2); tmr(); tck() } else { timer?.cancel(); timer = nil; mdl(0) }
            return
        }
        timer?.cancel(); timer = nil
        let task = alert["task"] as? TaskFields ?? [:], occurrence = alert["occurrence"] as? TaskFields ?? [:]
        traits.arrangedSubviews.forEach { traits.removeArrangedSubview($0); $0.removeFromSuperview() }
        for text in TaskTraits.labels(task) { let label = tu_lbl(text); label.font = lb_fnt(.subheadline, nil); label.textColor = TaskTheme.muted; label.numberOfLines = 0; traits.addArrangedSubview(label) }
        traits.isHidden = traits.arrangedSubviews.isEmpty
        titleText.text = task["title"] as? String; notes.text = task["notes"] as? String; notes.isHidden = notes.text?.isEmpty != false
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = task["schedule_kind"] as? String == "date" ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"; formatter.timeZone = .current
        let arranged = task["due_at"] is NSNull && alert["kind"] as? String == "plan"
        let stamp = (alert[arranged ? "scheduled_at" : "cycle_at"] as? NSNumber)?.doubleValue ?? (alert["scheduled_at"] as? NSNumber)?.doubleValue ?? 0
        planned.text = (arranged ? "日程安排：" : "原计划：") + formatter.string(from: Date(timeIntervalSince1970: stamp))
        delay.isEnabled = (occurrence["defer_count"] as? NSNumber)?.intValue != 1
        done.isEnabled = true
        stt(error == nil ? "提交" : "重试打卡"); mdl(1)
        // 主动补弹只恢复原窗口，保留附件、选择状态与提交锁。
        if (alert["manual_reopen"] as? Bool)==true {windowMode?(captureToken == nil ? 1:0)}
        signal.present(alert, store: reminder?.captureStore)
    }
    // 更新唯一主操作的功能反馈。
    private func stt(_ text: String) {
        var config = done.configuration; config?.title = text; done.configuration = config
        let back = choiceButtons.last!
        back.accessibilityValue = text == "提交" ? nil : text
        var feedback = back.configuration; feedback?.title = text == "提交" ? "返回" : "重试打卡"; feedback?.image = lb_icon(text == "提交" ? "back" : "upload"); back.configuration = feedback
        tu_fill(back, primary: text == "提交")
        if text != "提交" && !proofs.isEmpty { UIAccessibility.post(notification: .announcement, argument: text) }
        if selecting && text != "提交" && proofs.isEmpty { selecting = false; lay() }
    }
    // 选择打卡方式或原子提交已经确认的图片。
    @objc private func cmpl() {
        quiet()
        if previewing { tstEnd("resolved"); return }
        guard let id, !busy, !loading else { return }
        if !proofs.isEmpty { busy = true; done.isEnabled = false; delay.isEnabled = false; lay(); reminder?.chk(id, attachments: proofs) }
        else { selecting = true; lay() }
    }
    // 仅提交当前轮次的一次五分钟延期。
    @objc private func snz() { hld("snooze") }
    // 截图操作释放屏幕两分钟，完成仍须提交图片。
    @objc private func sht() { hld("screenshot") }
    // 固定正在处理的轮次并等待事务后的回调。
    private func hld(_ mode: String) {
        quiet()
        if previewing { tstEnd("snoozed"); return }
        guard let id, !busy else { return }; busy = true; done.isEnabled = false; delay.isEnabled = false; reminder?.hld(mode, occID: id)
    }
    // 无附件时返回提醒，有附件时通过原位对勾正式提交。
    @objc private func bck() {
        guard !busy else { return }
        if !proofs.isEmpty { cmpl() } else { selecting = false; stt("提交"); lay() }
    }
    // 取消附件并原位恢复返回图标。
    @objc private func rmv(_ sender: UIButton) {
        guard !busy, !loading, proofs.indices.contains(sender.tag) else { return }
        proofs.remove(at: sender.tag); pickVersion += 1; pickingID = nil; stt("提交"); lay()
    }
    // 由用户主动展开边栏，保留已用延期次数。
    @objc private func exp() { if !busy, let id = held?["occurrence_id"] as? String { busy = true; sidebar.isEnabled = false; reminder?.rsm(id) } }
    // 只在边栏可见时更新绝对时间倒计时。
    private func tmr() {
        timer?.cancel(); let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(100)); source.setEventHandler { [weak self] in self?.tck() }; timer = source; source.resume()
    }
    // 从保存的截止时刻重新计算秒数，不能累计秒数。
    private func tck() {
        guard mode == 2, let stamp = held?["hold_until"] as? NSNumber else { return }
        let seconds = max(0, Int(ceil(stamp.doubleValue - Date().timeIntervalSince1970)))
        sidebar.setTitle(String(format: "%02d:%02d", seconds/60, seconds%60), for: .normal)
        sidebar.accessibilityLabel = (held?["hold_reason"] as? String == "screenshot" ? "截图打卡" : "延后提醒") + "，剩余\(seconds)秒，展开"
        if seconds == 0 { timer?.cancel(); timer = nil }
    }
    // 使用系统相机；不可用时保留提醒和其他打卡入口。
    @objc private func cam() {
        if capReq("camera") { return }
        guard let id, !busy, !loading, proofs.count < Int(TS_ATT_MAX) else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { stt("相机不可用"); capEnd("相机不可用"); return }
        pickingID = id; pickVersion += 1
        let picker = UIImagePickerController(); picker.overrideUserInterfaceStyle = .dark; picker.sourceType = .camera; picker.delegate = self; picker.isModalInPresentation = true; picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }
    // 使用原生照片选择器，按剩余名额有序选择图片。
    private func pht(_ screenshot: Bool) {
        if capReq(screenshot ? "screenshot" : "image") { return }
        guard let id, !busy, !loading, proofs.count < Int(TS_ATT_MAX) else { return }; pickingID = id; pickVersion += 1; pickingMethod = screenshot ? "screenshot" : "image"
        var config = PHPickerConfiguration(); config.selectionLimit = captureLimit - proofs.count; config.selection = .ordered; config.filter = screenshot ? .screenshots : .images
        let picker = PHPickerViewController(configuration: config); picker.overrideUserInterfaceStyle = .dark; picker.delegate = self; picker.isModalInPresentation = true; picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }
    // 接收系统照片选择结果，过期意图被拒绝。
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let id = pickingID, !results.isEmpty else { picker.dismiss(animated: true) { [weak self] in self?.capEnd(nil) }; return }
        guard results.count <= captureLimit - proofs.count else { stt("最多6个附件"); capEnd("最多6个附件"); return }
        picker.dismiss(animated: true) { [weak self] in
            guard let self, self.id == id, !self.stopped else { return }
            self.loading = true; self.loadFailed = false; self.lay(); self.ldPrf(results, 0, id, self.pickingMethod, self.pickVersion)
        }
    }
    // 按选择顺序逐张读取，过期轮次或删除后的回调直接失效。
    private func ldPrf(_ results: [PHPickerResult], _ index: Int, _ occID: String, _ kind: String, _ version: Int) {
        guard id == occID, !stopped, pickVersion == version else { return }
        guard index < results.count else { loading = false; if loadFailed { stt("图片读取失败") }; lay(); capEnd(loadFailed ? "图片读取失败" : nil); return }
        results[index].itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            DispatchQueue.main.async {
                guard let self, self.id == occID, !self.stopped, self.pickVersion == version else { return }
                if let image = object as? UIImage { self.acc(image, method: kind, occID: occID) } else { self.loadFailed = true; if let error { NSLog("采集照片读取失败：%@", error as NSError) } }
                self.ldPrf(results, index + 1, occID, kind, version)
            }
        }
    }
    // 使用系统文件选择器批量导入普通文件。
    private func fl() {
        if capReq("file") { return }
        guard let id, !busy, !loading, proofs.count < Int(TS_ATT_MAX) else { return }; pickingID = id; pickVersion += 1
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true); picker.allowsMultipleSelection = true; picker.overrideUserInterfaceStyle = .dark; picker.delegate = self; picker.isModalInPresentation = true
        present(picker, animated: true)
    }
    // 撤下面板后接收完整文件批次，取消不改变已有附件。
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let id = pickingID, !urls.isEmpty else { controller.dismiss(animated: true) { [weak self] in self?.capEnd(nil) }; return }; let version = pickVersion
        controller.dismiss(animated: true) { [weak self] in self?.capFile(urls, id, version) }
    }
    // 按系统返回顺序读取整批文件，全部处理后仅交回一次。
    private func capFile(_ urls: [URL], _ occID: String, _ version: Int) {
        guard id == occID, pickVersion == version, !stopped else { return }
        guard urls.count <= captureLimit - proofs.count else { stt("最多6个附件"); capEnd("最多6个附件"); return }
        loading = true; lay(); var issue: String?
        for url in urls {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let info = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .contentTypeKey])
                guard info.isRegularFile == true else { issue = "请选择文件"; continue }
                guard (info.fileSize ?? Int.max) <= 20*1024*1024 else { issue = "文件过大"; continue }
                let data = try Data(contentsOf: url)
                apn(["image": data, "method": "file", "name": url.lastPathComponent, "content_type": info.contentType?.identifier ?? UTType.data.identifier], occID)
            } catch { NSLog("采集文件读取失败：%@", error as NSError); issue = "文件读取失败" }
        }
        loading = false; if let issue { stt(issue) }; lay(); capEnd(issue)
    }
    // 文件选择取消也交回原HUD，不完成任务。
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { controller.dismiss(animated: true) { [weak self] in self?.capEnd(nil) } }
    // 接收相机的原生确认结果。
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            if let id = self.pickingID, let image = info[.originalImage] as? UIImage { self.acc(image, method: "camera", occID: id) }
            else { self.capEnd("图片读取失败") }
        }
    }
    // 取消拍照保持原提醒。
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) { [weak self] in self?.capEnd(nil) } }
    // 保存待提交附件，原位显示对勾并等待用户确认。
    @objc(acceptImage:method:occID:) func acc(_ image: UIImage, method: String, occID: String) {
        guard id == occID, !stopped, !busy else { return }
        guard let bytes = image.jpegData(compressionQuality: 0.85), bytes.count <= 20*1024*1024 else { if loading { loadFailed = true } else { capEnd("图片无法提交") }; stt("图片无法提交"); return }
        apn(["image": bytes, "method": method], occID)
    }
    // 图片与文件共用名额、确认图标和采集交回。
    private func apn(_ proof: TaskFields, _ occID: String) {
        guard id == occID, !stopped, !busy else { return }
        guard proofs.count < captureLimit else { stt("最多6个附件"); capEnd("最多6个附件"); return }
        proofs.append(proof); selecting = true; stt("提交"); lay()
        if !loading { capEnd(nil) }
    }
    // 在正常前台App中复用同一套原生采集回调。
    #if LB_UI_TEST
    @objc(capOpen:completion:)
    #endif
    func capOpen(_ request: TaskFields, completion: @escaping ([TaskFields], String?) -> Void) {
        loadViewIfNeeded(); alert = ["occurrence_id": request["occurrence_id"] ?? ""]; captureLimit = (request["capacity"] as? NSNumber)?.intValue ?? 1
        captureDone = completion; card.isHidden = true; sidebar.isHidden = true
        switch request["source"] as? String {
        case "camera": cam()
        case "file": fl()
        case "screenshot": pht(true)
        default: pht(false)
        }
    }
    // 一次性交回选中附件，取消和失败都保留原任务。
    private func capEnd(_ issue: String?) {
        guard let completion = captureDone else { return }; captureDone = nil
        completion(proofs, issue)
    }
    // 前台采集被用户切走时取消本次交接。
    func capAbort() { proofs.removeAll(); pickVersion += 1; loading = false; capEnd(nil) }
    // 独立HUD只建立同库请求并激活正常App，不直接调用系统采集面板。
    private func capReq(_ source: String) -> Bool {
        guard globalCapture else { return false }
        guard let id, !busy, !loading, captureToken == nil, proofs.count < Int(TS_ATT_MAX), let store = reminder?.captureStore else { return true }
        do {
            let request = try store.reqCap(id, source: source, limit: Int(TS_ATT_MAX) - proofs.count)
            let token = request["token"] as! String; captureToken = token
            if captureNotify < 0 {
                let result = notify_register_dispatch(TS_CAPTURE_NOTE, &captureNotify, .main) { [weak self] _ in self?.capPoll() }
                guard result == NOTIFY_STATUS_OK else { captureNotify = -1; throw NSError(domain: NSPOSIXErrorDomain, code: Int(result)) }
            }
            windowMode?(0)
#if LB_UI_TEST
            let opened = captureLaunch?() ?? lb_opnapp()
#else
            let opened = lb_opnapp()
#endif
            guard opened else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)) }
            notify_post(TS_CAPTURE_NOTE)
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, self.captureToken == token else { return }; self.capPoll()
                if self.captureToken == token && self.captureWatch == nil { self.capRestore("采集未响应") }
            }
        } catch { NSLog("采集交接失败：%@", error as NSError); capRestore("采集失败") }
        return true
    }
    // 核对请求身份后接收结果，前台进程退出立即恢复全局提醒。
    private func capPoll() {
        guard let token = captureToken, let store = reminder?.captureStore else { return }
        do {
            let request = try store.rdCap(token)
            guard request["token"] as? String == token else { capRestore("采集已取消"); return }
            guard request["occurrence_id"] as? String == id else { capRestore(nil); return }
            let state = (request["state"] as? NSNumber)?.intValue ?? 0
            if state == 1, let pid = (request["pid"] as? NSNumber)?.int32Value {
                if kill(pid, 0) != 0 && errno == ESRCH { capRestore("采集已取消"); return }
                if captureWatch == nil {
                    let watch = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
                    watch.setEventHandler { [weak self] in self?.capPoll(); if self?.captureToken == token { self?.capRestore("采集已取消") } }
                    captureWatch = watch; watch.resume()
                }
            }
            if state == 2 {
                let items = request["attachments"] as? [TaskFields] ?? []
                if !items.isEmpty { try TaskStore.vldPrfs(items); guard proofs.count + items.count <= Int(TS_ATT_MAX) else { capRestore("最多6个附件"); return }; proofs.append(contentsOf: items) }
                selecting = true; capRestore(request["issue"] as? String)
            }
        } catch { NSLog("采集结果读取失败：%@", error as NSError); capRestore("图片读取失败") }
    }
    // 释放短期交接和进程观察，保持正文及附件几何。
    private func capRestore(_ issue: String?) {
        let token = captureToken, choosing = selecting; captureToken = nil; captureWatch?.cancel(); captureWatch = nil
        if let token { do { try reminder?.captureStore?.delCap(token); notify_post(TS_CAPTURE_NOTE) } catch { NSLog("采集清理失败：%@", error as NSError) } }
        stt(issue ?? "提交"); selecting = choosing; lay(); windowMode?(mode)
    }
    // 创建隔离的内存轮次，不覆盖真实提醒或边栏。
    @objc(preview) func prvw() {
        guard !stopped, !previewing, alert == nil, held == nil else { return }; loadViewIfNeeded(); previewing = true
        testOccurrence = ["occurrence_id": UUID().uuidString, "task_id": "test", "occurrence_at": Date().timeIntervalSince1970, "status": "presented"] as NSDictionary
        titleText.text = "测试提醒"; planned.text = nil; notes.text = nil; notes.isHidden = true; traits.isHidden = true; selecting = false; proofs.removeAll()
        done.isEnabled = true; delay.isEnabled = true; var config = done.configuration; config?.title = "完成"; done.configuration = config; mdl(1); signal.preview()
    }
    // 完成和延期均结束测试，状态只在内存改变且不安排重弹。
    private func tstEnd(_ state: String) {
        guard previewing, testOccurrence?["status"] as? String == "presented" else { return }
        var value = testOccurrence as? TaskFields ?? [:]; value["status"] = state
        value["handled_at"] = Date().timeIntervalSince1970; testOccurrence = value as NSDictionary
        previewing = false; signal.stop(); mdl(0)
    }
    // 停止后拒绝异步图片回调并释放计时与系统面板。
    @objc(stop) func stp() {
        guard !stopped else { return }; stopped = true; timer?.cancel(); timer = nil; signal.stop()
        if captureToken != nil { capRestore(nil) }
        if captureNotify >= 0 { notify_cancel(captureNotify); captureNotify = -1 }; captureDone = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers.removeAll()
        if isViewLoaded { cncl() }
        presentedViewController?.dismiss(animated: false); proofs.removeAll(); pickVersion += 1; loading = false; pickingID = nil; alert = nil; held = nil; reminder = nil
        if isViewLoaded { mdl(0) } else { windowMode?(0) }; windowMode = nil
    }
    // 释放边栏计时与时钟观察者。
    deinit { timer?.cancel(); observers.forEach { NotificationCenter.default.removeObserver($0) } }
}
