// 创建门禁独立流转，网络结果不会直接写入正式待办。
private enum IntakePhase {case editing,checking,review,offline,saving,done}

// 统一新建、修改后重评和离线补评估页面。
@objc(TaskAdmissionScreen) final class TaskAdmissionScreen:TaskScreen,UITextViewDelegate {
    private let store:TaskStore,done:()->Void
    private var fields:TaskFields,parts:[TaskFields],context:TaskFields?,estimate:TaskFields?,phase=IntakePhase.editing
    private var lastOffline=false,completed=Set<String>()
    private var request:URLSessionDataTask?,ticket=UUID(),ddl=false,escalated=false
    private let name=UITextView(),notes=UITextView(),start=UIDatePicker(),end=UIDatePicker(),startTime=UIDatePicker(),endTime=UIDatePicker(),minutes=UITextField()
    private var check:UIButton!,save:UIButton!,steps:UIButton!,detail:UIButton!,adopt:UIButton!,offline:UIButton!
    private var dateWidths:[NSLayoutConstraint]=[],dateRows:[UIStackView]=[]
    private var dayOnly: Bool { TaskWindow.dayOnly(fields) }
    private var newTodo: Bool { dayOnly && fields["task_id"] == nil }
    // 接收未提交的输入与可编辑子任务。
    init(store:TaskStore,fields:TaskFields,parts:[TaskFields]=[],done:@escaping()->Void) {self.store=store;self.fields=fields;self.parts=parts;self.done=done;if let id=fields["task_id"] as? String{self.fields["_baseline"]=try? TaskIntake.sig(store,id,strict:true)};super.init(nibName:nil,bundle:nil);preferredContentSize=CGSize(width:540,height:UIScreen.main.bounds.height)}
    // 禁用归档初始化。
    required init?(coder:NSCoder){fatalError("Use init(store:fields:parts:done:)")}
    // 用统一表单展示窗口、工时和功能入口。
    override func viewDidLoad(){
        super.viewDidLoad();title="创建评估"
        for (view,key) in [(name,"title"),(notes,"notes")] {tu_fld(view);view.font=lb_fnt(.body,traitCollection);view.adjustsFontForContentSizeCategory=true;view.textColor=TaskTheme.ink;view.isScrollEnabled=false;view.delegate=self;view.accessibilityIdentifier="intake."+key;view.text=fields[key] as? String ?? "";if view === notes {view.heightAnchor.constraint(greaterThanOrEqualToConstant:72).isActive=true}}
        let zone=TimeZone(identifier:fields["timezone_id"] as? String ?? "") ?? .current
        for (picker,key) in [(start,"start"),(end,"end"),(startTime,"start.time"),(endTime,"end.time")] {picker.datePickerMode = key.hasSuffix("time") ? .time:.date;picker.maximumContentSizeCategory = .extraExtraExtraLarge;picker.preferredDatePickerStyle = .compact;picker.locale=Locale(identifier:"zh_CN");picker.timeZone=zone;picker.accessibilityIdentifier="intake."+key;picker.addTarget(self,action:#selector(chg),for:.valueChanged);picker.heightAnchor.constraint(equalToConstant:44).isActive=true}
        start.date=Date(timeIntervalSince1970:(fields["due_at"] as? NSNumber)?.doubleValue ?? ceil(Date().timeIntervalSince1970/60)*60)
        end.date=Date(timeIntervalSince1970:(fields["deadline_at"] as? NSNumber)?.doubleValue ?? start.date.timeIntervalSince1970+3600)
        if dayOnly { end.date = TaskWindow.deadline(end.date, in: TaskWindow.calendar(zone)) }
        startTime.date=start.date;endTime.date=end.date
        dateWidths=[start,startTime,end,endTime].map{$0.widthAnchor.constraint(equalToConstant:max(44,$0.sizeThatFits(.zero).width))};NSLayoutConstraint.activate(dateWidths)
        tu_fld(minutes);minutes.font=lb_fnt(.body,traitCollection);minutes.adjustsFontForContentSizeCategory=true;minutes.textColor=TaskTheme.ink;minutes.keyboardType = .numberPad;minutes.attributedPlaceholder=tu_phl("由AI估算");minutes.accessibilityIdentifier="intake.minutes";minutes.addTarget(self,action:#selector(budget),for:.editingChanged)
        if let all=try? store.lsTsks() as? [TaskFields]{completed=Set(all.filter{$0["status"] as? String=="completed"}.map{$0["task_id"] as! String})}
        if let amount=fields["planned_duration"] as? NSNumber{let finished=parts.filter{completed.contains($0["task_id"] as? String ?? "")}.reduce(0.0){$0+(($1["planned_duration"] as? NSNumber)?.doubleValue ?? 0)};minutes.text=String(Int(ceil(max(0,amount.doubleValue-finished)/60)))}
        check=tu_btn("智能评估","subtask",self,#selector(evaluate));check.accessibilityIdentifier="intake.evaluate"
        steps=tu_btn("编辑子任务","subtask",self,#selector(editParts));steps.accessibilityIdentifier="intake.parts"
        detail=tu_btn("查看评估","list",self,#selector(info));detail.accessibilityIdentifier="intake.info"
        adopt=tu_btn("采用建议",nil,self,#selector(suggest));adopt.accessibilityIdentifier="intake.adopt"
        offline=tu_btn("离线创建",nil,self,#selector(local));offline.accessibilityIdentifier="intake.offline";offline.isHidden=true
        let single=tu_btn("改为单次",nil,self,#selector(single));single.accessibilityIdentifier="intake.single";single.isHidden=(fields["recurrence"] as? [String] ?? []).isEmpty
        let rules=tu_btn("编辑常律","calendar",self,#selector(routines));rules.accessibilityIdentifier="intake.routines"
        save=tu_btn("确认创建",nil,self,#selector(confirm));save.accessibilityIdentifier="intake.save";tu_fill(save,primary:true)
        dateRows=[(start,startTime),(end,endTime)].map { day,clock -> UIStackView in
            let space=UIView();space.heightAnchor.constraint(equalToConstant:0).isActive=true;let row=tu_stk(dayOnly ? [day,space] : [day,clock,space]);row.axis = .horizontal;row.alignment = .center;return row
        };let begin=dateRows[0],finish=dateRows[1]
        var controls: [UIView] = [tu_stk([tu_lbl("标题"), name])]
        if !newTodo { controls.append(tu_stk([tu_lbl("说明"), notes])) }
        controls += [tu_stk([tu_lbl(dayOnly ? "起始日期" : "开始时间"), begin]), tu_stk([tu_lbl(dayOnly ? "截止日期" : "结束时间"), finish])]
        if newTodo {
            let starred = (fields["starred"] as? NSNumber)?.boolValue == true
            if starred {
                let urgency = tu_lbl("紧急程度：高")
                urgency.accessibilityIdentifier = "intake.urgency"
                controls.append(urgency)
            } else {
                controls.append(tu_grade("urgency", "intake", (fields["urgency"] as? NSNumber)?.intValue ?? 0) { [weak self] in self?.fields["urgency"] = $0; self?.chg() })
            }
            controls.append(tu_grade("difficulty", "intake", (fields["difficulty"] as? NSNumber)?.intValue ?? 0) { [weak self] in self?.fields["difficulty"] = $0; self?.chg() })
        }
        controls += [tu_stk([tu_lbl("预计分钟"), minutes]), check, steps, detail, adopt, offline, single, rules, save]
        _ = tu_form(self, tu_stk(controls), "intake.content")
        let settings=tu_ibtn("settings","助手设置","intake.settings",self,#selector(settings));navigationItem.rightBarButtonItem=UIBarButtonItem(customView:settings);render()
    }
    // 按原生测量值更新日期宽度，覆盖日期和动态字号变化。
    override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();for (picker,width) in zip([start,startTime,end,endTime],dateWidths){let value=max(44,picker.sizeThatFits(.zero).width);if abs(width.constant-value)>0.1{width.constant=value}};if dayOnly{return};for (index,row) in dateRows.enumerated(){let vertical=dateWidths[index*2].constant+dateWidths[index*2+1].constant+TaskTheme.gap>row.bounds.width;row.axis=vertical ? .vertical:.horizontal;row.alignment=vertical ? .leading:.center;row.arrangedSubviews.last?.isHidden=vertical}}
    // 返回编辑后主动丢弃上一轮容量与估时结果。
    override func viewWillAppear(_ animated:Bool){super.viewWillAppear(animated);navigationController?.setNavigationBarHidden(false,animated:false);navigationController?.presentationController?.containerView?.setNeedsLayout()}
    // 离开时取消请求，保存事务期间禁止返回。
    override func viewWillDisappear(_ animated:Bool){super.viewWillDisappear(animated);if phase != .saving {cancel()}}
    // 撤销网络代次而不修改用户草稿。
    private func cancel(){ticket=UUID();request?.cancel();request=nil;if phase == .checking{phase = .editing};if isViewLoaded{render()}}
    // 输入变化使评估失效，迟到响应被丢弃。
    @objc private func chg(){view.setNeedsLayout();cancel();context=nil;estimate=nil;ddl=false;phase = .editing;offline.isHidden = !lastOffline;render()}
    // 工时只重新进行本地匹配判断。
    @objc private func budget(){ddl=false;render()}
    // 标题和说明改动必须重新请求评估。
    func textViewDidChange(_ textView:UITextView){chg()}
    // 读取当前表单，保留原有重复及任务身份。
    private func input() -> TaskFields {
        var value = fields
        value["title"] = name.text ?? ""
        value["notes"] = notes.text ?? ""
        if dayOnly {
            let calendar = TaskWindow.calendar(start.timeZone ?? .current)
            value["due_at"] = calendar.startOfDay(for: start.date).timeIntervalSince1970
            value["deadline_at"] = TaskWindow.end(end.date, in: calendar).timeIntervalSince1970
        } else {
            value["due_at"] = stamp(start, startTime); value["deadline_at"] = stamp(end, endTime)
            value["schedule_kind"] = "timed"; value["deadline_kind"] = "timed"
        }
        if let amount = Double(minutes.text ?? ""), amount > 0 { value["planned_duration"] = amount * 60 }
        value["timezone_id"] = fields["timezone_id"] as? String ?? TimeZone.current.identifier
        return value
    }
    // 日期与时刻分开呈现，使用同一当地日历合并。
    private func stamp(_ date:UIDatePicker,_ time:UIDatePicker)->Double{var calendar=Calendar(identifier:.gregorian);calendar.timeZone=date.timeZone ?? .current;let clock=calendar.dateComponents([.hour,.minute],from:time.date);return calendar.date(bySettingHour:clock.hour!,minute:clock.minute!,second:0,of:date.date)!.timeIntervalSince1970}
    // 根据纯逻辑门禁控制按钮，连续点击不能开启第二次保存。
    private func verdict()->TaskFields? {guard let context,let estimate,let number=Double(minutes.text ?? "") else{return nil};return try? TaskIntake.vld(context as NSDictionary,estimate:estimate as NSDictionary,effort:number*60,ddl:ddl) as? TaskFields}
    // 只展示有功能的控制，详情放在点击后的系统面板。
    private func render(){
        guard isViewLoaded,save != nil else{return};let busy=phase == .checking || phase == .saving || phase == .done
        navigationItem.setHidesBackButton(phase == .saving,animated:false);navigationController?.interactivePopGestureRecognizer?.isEnabled = phase != .saving;navigationController?.isModalInPresentation=phase == .saving
        for field in [name,notes,minutes,start,end,startTime,endTime]{field.isUserInteractionEnabled = !busy}
        check.isEnabled=phase != .saving && phase != .done;var config=check.configuration;config?.title=phase == .checking ? "取消评估":"智能评估";check.configuration=config
        steps.isEnabled = !busy;detail.isEnabled=estimate != nil && !busy;adopt.isEnabled=(verdict()?["suggested_end"] != nil) && !busy;offline.isEnabled = !busy
        let result=verdict(),state=result?["state"] as? String
        save.isEnabled = !busy && ["ready","offline","ddl"].contains(state ?? "");var button=save.configuration;button?.title=state=="ddl" ? "确认赶DDL":fields["task_id"] == nil ? "确认创建":"保存评估";save.configuration=button
        save.accessibilityValue=result?["reason"] as? String ?? "等待评估"
    }
    // 普通待办先快速评估，复杂结果只升级一次；DDL使用最高服务档。
    @objc private func evaluate(){if phase == .checking{cancel();return};escalated=false;ddl=false;run(false)}
    // 先读一致上下文再发请求；整个过程不提前创建正式任务。
    private func run(_ urgent:Bool){
        view.endEditing(true);cancel();phase = .checking;let value=input(),rows=parts,token=UUID();ticket=token;render()
        DispatchQueue.global(qos:.userInitiated).async {
            do {let context=try TaskIntake.ctx(self.store,fields:value as NSDictionary,parts:rows as NSArray,at:Date().timeIntervalSince1970) as! TaskFields
                DispatchQueue.main.async {guard self.ticket==token,self.view.window != nil else{return};self.context=context
                    let room=context["room"] as! TaskFields;var query:TaskFields=["mode":"assessment","title":value["title"]!,"window_start":value["due_at"]!,"window_end":value["deadline_at"]!,"capacity_minutes":Int((room["capacity"] as! NSNumber).doubleValue/60),"available_slots":room["gaps"]!,"existing_steps":rows,"completed_ids":context["completed_ids"] ?? [],"difficulty":self.escalated ? 3:value["difficulty"] ?? 0,"ddl":urgent]
                    if let amount=Double(self.minutes.text ?? ""),urgent{query["total_minutes"]=Int(amount)}
                    if (room["max_span"] as! NSNumber).doubleValue>=60{query["max_minutes"]=Int((room["max_span"] as! NSNumber).doubleValue/60)}
                    self.request=TaskAI.gen(query as NSDictionary,config:TaskAIConfig.ld() as NSDictionary){[weak self] result,error in DispatchQueue.main.async {
                        guard let self,self.ticket==token,self.view.window != nil else{return};self.request=nil;self.phase = .review
                        if let error {self.estimate=nil;self.lastOffline=error.code==2;self.offline.isHidden = !self.lastOffline;self.render();tu_err(self,error);return}
                        guard let result=result as? TaskFields else{return}
                        if !urgent && !self.escalated && (value["difficulty"] as? NSNumber)?.intValue ?? 0 < 2 && (result["difficulty"] as? NSNumber)?.intValue ?? 0 >= 2 {self.escalated=true;self.run(false);return}
                        self.estimate=result;self.lastOffline=false;self.offline.isHidden=true;self.ddl=urgent
                        if (self.minutes.text ?? "").isEmpty{self.minutes.text=String((result["recommended_minutes"] as! NSNumber).intValue)}
                        if urgent,let rows=result["steps"] as? [TaskFields]{self.parts=self.parts.filter{self.completed.contains($0["task_id"] as? String ?? "")}+rows.map{var row=$0;row["task_id"]=UUID().uuidString.lowercased();return row};self.context?["parts"]=self.parts}
                        self.render();self.info()
                    }}
                }
            }catch{DispatchQueue.main.async{guard self.ticket==token else{return};self.phase = .editing;self.render();self.failure(error)}}
        }
    }
    // 外部修改时保留本地草稿，只有用户选择重载才覆盖表单。
    private func failure(_ error:Error){guard error.localizedDescription=="任务已变更，请重载" else{tu_err(self,error);return};let alert=UIAlertController(title:"任务已变更",message:nil,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"保留草稿",style:.cancel));alert.addAction(UIAlertAction(title:"载入最新",style:.destructive){[weak self] _ in self?.reload()});present(alert,animated:true)}
    // 重新读取最新任务和子任务后恢复可评估状态。
    private func reload(){guard let id=fields["task_id"] as? String else{return};do{let latest=try store.rdTsk(id) as! TaskFields;fields=latest.filter{TaskIntake.keys.contains($0.key)};fields["task_id"]=id;fields["_baseline"]=try TaskIntake.sig(store,id,strict:true);let all=try store.lsTsks() as! [TaskFields];parts=all.filter{$0["parent_id"] as? String==id && ($0["deleted"] as? Bool)==false}.sorted{($0["position"] as! NSNumber).intValue<($1["position"] as! NSNumber).intValue}.map{$0.filter{["task_id","title","notes","planned_duration"].contains($0.key)}};completed=Set(all.filter{$0["status"] as? String=="completed"}.map{$0["task_id"] as! String});name.text=latest["title"] as? String;notes.text=latest["notes"] as? String;if let value=latest["due_at"] as? NSNumber{start.date=Date(timeIntervalSince1970:value.doubleValue);startTime.date=start.date};if let value=latest["deadline_at"] as? NSNumber{end.date=Date(timeIntervalSince1970:value.doubleValue);endTime.date=end.date};let finished=parts.filter{completed.contains($0["task_id"] as? String ?? "")}.reduce(0.0){$0+(($1["planned_duration"] as? NSNumber)?.doubleValue ?? 0)};minutes.text=(latest["planned_duration"] as? NSNumber).map{String(Int(ceil(max(0,$0.doubleValue-finished)/60)))} ?? "";chg()}catch{tu_err(self,error)}}
    // 展示可理解的评估原因、投入区间、容量和实际模型。
    @objc private func info(){guard let result=verdict(),let estimate else{return};let formatter=DateFormatter();formatter.timeZone=start.timeZone;formatter.dateFormat=dayOnly ? "MM-dd" : "MM-dd HH:mm";var message="最低\(Int((result["minimum"] as! NSNumber).doubleValue/60))分钟\n建议\(Int((result["recommended"] as! NSNumber).doubleValue/60))分钟\n上限\(Int((result["maximum"] as! NSNumber).doubleValue/60))分钟\n可用\(Int((result["capacity"] as! NSNumber).doubleValue/60))分钟"
        if let end=result["suggested_end"] as? NSNumber{message+="\n建议结束："+formatter.string(from:suggestedDay(end))};if let model=estimate["model"] as? String{message+="\n模型："+model}
        let alert=UIAlertController(title:result["reason"] as? String,message:message,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"继续修改",style:.cancel));if result["state"] as? String=="split" {alert.addAction(UIAlertAction(title:"创建子任务",style:.default){[weak self] _ in self?.editParts()})};present(alert,animated:true)
    }
    // 采用推荐工时和实际可到达的结束时刻后重新评估。
    @objc private func suggest(){guard let result=verdict() else{return};minutes.text=String(Int((result["recommended"] as! NSNumber).doubleValue/60));if let value=result["suggested_end"] as? NSNumber{end.date=suggestedDay(value);endTime.date=end.date};chg()}
    // 结束恰好到日界时仍展示前一天为截止日期。
    private func suggestedDay(_ value: NSNumber) -> Date { Date(timeIntervalSince1970: value.doubleValue - (dayOnly ? 1 : 0)) }
    // 编辑草稿步骤，不用临时父任务污染正式数据库。
    @objc private func editParts(){if !(fields["recurrence"] as? [String] ?? []).isEmpty{tu_err(self,TaskAI.err("请先改为单次任务"));return};cancel();let suggestions=parts.isEmpty ? estimate?["steps"] as? [TaskFields] ?? []:parts;let rows=suggestions.map{row->TaskFields in var row=row;if row["task_id"]==nil{row["task_id"]=UUID().uuidString.lowercased()};return row}
        var draft=input();if !ddl,let recommended=estimate?["recommended_minutes"] as? NSNumber{draft["planned_duration"]=recommended.doubleValue*60}
        navigationController?.pushViewController(TaskAssistantScreen(store:store,draft:draft,parts:rows){[weak self] rows in guard let self else{return};self.parts=rows;let total=rows.filter{!self.completed.contains($0["task_id"] as? String ?? "")}.reduce(0.0){$0+(($1["planned_duration"] as? NSNumber)?.doubleValue ?? 0)};self.minutes.text=String(Int(ceil(total/60)));self.chg()},animated:true)
    }
    // 离线仅提供短窗口、有效估时与明确确认的例外。
    @objc private func local(){guard !offline.isHidden else{return};do {let ctx=try TaskIntake.ctx(store,fields:input() as NSDictionary,parts:parts as NSArray,at:Date().timeIntervalSince1970) as! TaskFields;context=ctx;estimate=["offline":true];phase = .offline;ddl=false;render();if verdict()?["state"] as? String != "offline"{info()}}catch{tu_err(self,error)}}
    // 常律编辑返回后必须重新评估容量。
    @objc private func routines(){chg();navigationController?.pushViewController(TaskRoutineRules(store:store),animated:true)}
    // 重复与子任务沿用互斥规则，由用户明确选择改单次。
    @objc private func single(){tu_cfrm(self,"改为单次任务"){[weak self] in guard let self else{return};self.fields["recurrence"]=[];self.fields["recurrence_type"]="none";self.fields["recurrence_interval"]=1;self.chg()}}
    // 设置变化不沿用先前评估。
    @objc private func settings(){lastOffline=false;chg();navigationController?.pushViewController(TaskAISettings(),animated:true)}
    // DDL必须先显式确认，再取得最高档的有效步骤。
    @objc private func confirm(){guard save.isEnabled,let result=verdict() else{return}
        if result["state"] as? String=="ddl"{let alert=UIAlertController(title:"确认赶DDL",message:"当前投入低于建议。确认后使用最高服务档重新规划子任务。",preferredStyle:.alert);alert.addAction(UIAlertAction(title:"返回调整",style:.cancel));alert.addAction(UIAlertAction(title:"仍然创建",style:.default){[weak self] _ in self?.run(true)});present(alert,animated:true);return}
        if result["state"] as? String=="offline"{let alert=UIAlertController(title:"离线创建",message:"当前工时由你确认，联网后可重新评估。",preferredStyle:.alert);alert.addAction(UIAlertAction(title:"返回调整",style:.cancel));alert.addAction(UIAlertAction(title:"确认创建",style:.default){[weak self] _ in self?.commit()});present(alert,animated:true);return};commit()
    }
    // 数据变化或时间流逝导致容量不足时保留完整草稿。
    private func commit(){guard phase != .saving,let context,let estimate,let effort=Double(minutes.text ?? "") else{return};phase = .saving;render()
        DispatchQueue.global(qos:.userInitiated).async {var failure:Error?;do{_ = try TaskIntake.cmt(self.store,context:context as NSDictionary,estimate:estimate as NSDictionary,effort:effort*60,ddl:self.ddl,at:Date().timeIntervalSince1970)}catch{failure=error}
            DispatchQueue.main.async {if let failure{self.phase = .editing;self.context=nil;self.estimate=nil;self.ddl=false;self.render();tu_err(self,failure)}else{self.phase = .done;self.render();self.navigationController?.interactivePopGestureRecognizer?.isEnabled=true;self.done()}}
        }
    }
}
