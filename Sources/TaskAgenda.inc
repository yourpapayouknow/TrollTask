// 将本地日程展开为区间，提醒仍由原Occurrence状态机处理。
static NSString *ta_key(NSDictionary *task, NSNumber *cycle) {
    return [NSString stringWithFormat:@"%@/%@/%@",task[@"task_id"],task[@"reminder_version"],cycle];
}

// 识别同一任务轮次的完成状态。
static BOOL ta_done(NSDictionary *task, NSNumber *cycle, NSArray *history) {
    if ([task[@"status"] isEqual:@"completed"]) return YES;
    for (NSDictionary *row in history) if ([row[@"task_id"] isEqual:task[@"task_id"]] && [row[@"generation"] isEqual:task[@"reminder_version"]]
        && [row[@"action"] isEqual:@"complete"] && [@[@"resolved",@"completed"] containsObject:row[@"status"]]
        && [row[@"cycle_at"] compare:cycle] != NSOrderedAscending) return YES;
    return NO;
}

// 识别已过期的当前版本轮次及其更早的执行轮次。
static BOOL ta_expired(NSDictionary *task, NSNumber *cycle, NSArray *history) {
    for (NSDictionary *row in history)
        if ([row[@"task_id"] isEqual:task[@"task_id"]] && [row[@"generation"] isEqual:task[@"reminder_version"]]
            && [row[@"action"] isEqual:@"expire"] && [row[@"status"] isEqual:@"resolved"]
            && (!cycle || [row[@"cycle_at"] compare:cycle] != NSOrderedAscending)) return YES;
    return NO;
}

// 把日程覆盖映射回原始提醒身份，已呈现和延后的时刻优先。
static NSArray *ta_alerts(NSDictionary *task, NSArray *history, NSArray *slots, NSTimeInterval stamp, NSError **error) {
    NSArray *base = [TaskRule alerts:task history:history at:stamp error:error]; if (!base) return nil;
    if ([task[@"deleted"] boolValue] || ![task[@"status"] isEqual:@"needsAction"]
        || ![task[@"routine_kind"] ?: @"none" isEqual:@"none"]) return base;
    NSMutableArray *result = [base mutableCopy];
    if([task[@"planning_mode"] isEqual:@"window"]) [result filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *alert,NSDictionary *bindings){(void)bindings;return [alert[@"kind"] isEqual:@"deadline"];}]];
    for (NSDictionary *slot in slots) {
        if (![slot[@"task_id"] isEqual:task[@"task_id"]] || ![slot[@"generation"] isEqual:task[@"reminder_version"]]
            || ta_done(task,slot[@"cycle_at"],history) || ta_expired(task,slot[@"cycle_at"],history)) continue;
        NSDictionary *occ = nil;
        for (NSDictionary *row in history) if ([row[@"task_id"] isEqual:task[@"task_id"]]
            && [row[@"generation"] isEqual:task[@"reminder_version"]] && [row[@"cycle_at"] isEqual:slot[@"cycle_at"]]
            && [@[@"plan",@"both"] containsObject:row[@"kind"]]) { occ = row; break; }
        if (occ && [@[@"resolved",@"completed"] containsObject:occ[@"status"]]) continue;
        NSMutableDictionary *item = nil;
        for (NSDictionary *candidate in result.copy) if ([candidate[@"cycle_at"] isEqual:slot[@"cycle_at"]]
            && [@[@"plan",@"both"] containsObject:candidate[@"kind"]]) { item = [candidate mutableCopy]; [result removeObjectIdenticalTo:candidate]; break; }
        if (!item) {
            if (task[@"due_at"] != NSNull.null && ![task[@"planning_mode"] isEqual:@"window"]) continue;
            item = [@{@"task_id":task[@"task_id"],@"generation":task[@"reminder_version"],@"cycle_at":slot[@"cycle_at"],
                @"kind":@"plan",@"scheduled_at":slot[@"scheduled_at"],@"task":task} mutableCopy];
        }
        item[@"remind_at"] = occ && [@[@"presented",@"snoozed"] containsObject:occ[@"status"]] ? occ[@"next_fire_at"] : slot[@"start_at"];
        if (occ) item[@"occurrence_id"] = occ[@"occurrence_id"];
        [result addObject:item];
    }
    return result;
}

// 创建同一格式的日程条目。
static NSDictionary *ta_entry(NSDictionary *task, NSNumber *cycle, double start, double end, NSString *kind, BOOL done) {
    return @{@"id":ta_key(task,cycle),@"task":task,@"task_id":task[@"task_id"],@"cycle_at":cycle,
        @"start_at":@(start),@"end_at":@(end),@"kind":kind,@"completed":@(done)};
}

// 合并可用时段并扣除固定占用。
static NSMutableArray *ta_free(NSArray *windows, NSArray *busy) {
    NSMutableArray *merged = [NSMutableArray array];
    NSArray *ordered = [windows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"start_at"] compare:b[@"start_at"]]; }];
    for (NSDictionary *window in ordered) {
        NSMutableDictionary *last = merged.lastObject;
        if (last && [last[@"end_at"] doubleValue] >= [window[@"start_at"] doubleValue]) last[@"end_at"] = @(fmax([last[@"end_at"] doubleValue],[window[@"end_at"] doubleValue]));
        else [merged addObject:[window mutableCopy]];
    }
    for (NSDictionary *block in busy) {
        NSMutableArray *next = [NSMutableArray array]; double lo = [block[@"start_at"] doubleValue], hi = [block[@"end_at"] doubleValue];
        for (NSDictionary *gap in merged) {
            double start = [gap[@"start_at"] doubleValue], end = [gap[@"end_at"] doubleValue];
            if (hi <= start || lo >= end) [next addObject:gap];
            else {
                if (start < lo) [next addObject:[@{@"start_at":@(start),@"end_at":@(lo)} mutableCopy]];
                if (hi < end) [next addObject:[@{@"start_at":@(hi),@"end_at":@(end)} mutableCopy]];
            }
        }
        merged = next;
    }
    return merged;
}

// 以纯快照计算当地一天，不移动固定安排或正在处理的提醒。
static NSDictionary *ta_plan(NSDictionary *snapshot, double stamp, NSString *zone, double now, NSError **error) {
    NSTimeZone *tz = [NSTimeZone timeZoneWithName:zone];
    if (!tz || !isfinite(stamp) || !isfinite(now)) { ts_err(error,SQLITE_CONSTRAINT,@"日程日期或时区无效"); return nil; }
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = tz;
    NSDate *day = [calendar startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:stamp]];
    NSDate *next = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:day options:0];
    NSDate *previous = [calendar dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:day options:0];
    double lo = day.timeIntervalSince1970, hi = next.timeIntervalSince1970;
    NSArray *tasks = snapshot[@"tasks"], *slots = snapshot[@"slots"] ?: @[];
    NSMutableDictionary *records = [NSMutableDictionary dictionary], *taskMap = [NSMutableDictionary dictionary];
    NSMutableSet *parents = [NSMutableSet set]; BOOL active = NO;
    for (NSDictionary *task in tasks) { taskMap[task[@"task_id"]] = task; if (task[@"parent_id"] != NSNull.null && ![task[@"deleted"] boolValue]) [parents addObject:task[@"parent_id"]]; }
    for (NSDictionary *row in snapshot[@"history"]) {
        NSString *id = row[@"task_id"]; if (!records[id]) records[id] = [NSMutableArray array]; [records[id] addObject:row];
        NSDictionary *task = taskMap[id];
        if (task && ![task[@"deleted"] boolValue] && [row[@"generation"] isEqual:task[@"reminder_version"]]
            && [@[@"presented",@"snoozed"] containsObject:row[@"status"]]) active = YES;
    }
    NSMutableArray *entries = [NSMutableArray array], *busy = [NSMutableArray array], *windows = [NSMutableArray array];
    NSMutableArray *flex = [NSMutableArray array], *unplaced = [NSMutableArray array], *conflicts = [NSMutableArray array], *allocations = [NSMutableArray array];
    NSUInteger drafts = 0; BOOL templates = [snapshot[@"templates"] boolValue];
    NSArray *orderedTasks = [tasks sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL first = ![a[@"routine_kind"] ?: @"none" isEqual:@"none"], second = ![b[@"routine_kind"] ?: @"none" isEqual:@"none"];
        return first == second ? NSOrderedSame : first ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (NSDictionary *task in orderedTasks) {
        if ([task[@"deleted"] boolValue] || (!templates && [task[@"status"] isEqual:@"completed"])) continue;
        NSString *id = task[@"task_id"], *role = task[@"routine_kind"] ?: @"none"; NSArray *history = records[id] ?: @[];
        BOOL routine = ![role isEqual:@"none"];
        if (routine && !templates && ![task[@"routine_enabled"] boolValue]) { drafts++; continue; }
        if (routine && (task[@"due_at"] == NSNull.null || !ts_num(task[@"routine_end"]) || ![task[@"recurrence"] count])) {
            [conflicts addObject:@{@"task":task,@"reason":@"常律时间待确认"}]; continue;
        }
        // 有子任务的父级只作汇总，实际叶子参与安排。
        if (!routine && [parents containsObject:id]) {
            BOOL remaining=NO;for(NSDictionary *child in tasks)if([child[@"parent_id"] isEqual:id] && ![child[@"deleted"] boolValue] && ![child[@"status"] isEqual:@"completed"])remaining=YES;
            if(!remaining)[unplaced addObject:@{@"task":task,@"reason":@"确认父任务完成"}];continue;
        }
        if (routine || ([task[@"schedule_kind"] isEqual:@"timed"] && ![task[@"planning_mode"] isEqual:@"window"])) {
            NSArray *cycles = [TaskRule cycles:task at:previous.timeIntervalSince1970 limit:8 error:error]; if (!cycles) return nil;
            for (NSNumber *cycle in cycles) {
                double start = cycle.doubleValue, end = start + (ts_num(task[@"planned_duration"]) ? [task[@"planned_duration"] doubleValue] : 0);
                if (routine) {
                    NSCalendar *local = [calendar copy]; local.timeZone = [NSTimeZone timeZoneWithName:task[@"timezone_id"]];
                    NSInteger minute = [task[@"routine_end"] integerValue]; NSDate *base = [NSDate dateWithTimeIntervalSince1970:start];
                    NSDate *finish = [local dateBySettingHour:minute/60 minute:minute%60 second:0 ofDate:base options:0];
                    if (finish.timeIntervalSince1970 <= start) finish = [local dateByAddingUnit:NSCalendarUnitDay value:1 toDate:finish options:0];
                    end = finish.timeIntervalSince1970;
                }
                if (!routine && start >= lo && start < hi && !ts_num(task[@"planned_duration"])) {
                    [conflicts addObject:@{@"task":task,@"reason":@"固定任务缺少预计用时"}]; continue;
                }
                if (start >= hi) break;
                if (end <= lo || (!templates && !routine && ta_expired(task,cycle,history))) continue;
                BOOL done = ta_done(task,cycle,history);
                if (done && !routine) continue;
                NSDictionary *entry = ta_entry(task,cycle,fmax(lo,start),fmin(hi,end),routine ? role : @"task",done);
                [entries addObject:entry];
                if (templates) continue;
                if ([role isEqual:@"work"]) [windows addObject:entry];
                else [busy addObject:entry];
            }
            continue;
        }
        if (![task[@"recurrence"] count] && ta_expired(task,nil,history)) continue;
        if (!ts_num(task[@"planned_duration"])) { [unplaced addObject:@{@"task":task,@"reason":@"待估时"}]; continue; }
        NSNumber *cycle = @(lo), *scheduled = nil; NSDictionary *old = nil;
        for (NSDictionary *slot in slots) if ([slot[@"task_id"] isEqual:id] && [slot[@"generation"] isEqual:task[@"reminder_version"]]
            && !ta_done(task,slot[@"cycle_at"],history)) { old = slot; break; }
        if (old && ([old[@"end_at"] doubleValue]<=lo || [old[@"start_at"] doubleValue]>=hi)) { [unplaced addObject:@{@"task":task,@"reason":[old[@"end_at"] doubleValue]<=lo ? @"此前安排尚未完成" : @"已有后续日期安排"}]; continue; }
        if (old && [old[@"end_at"] doubleValue]>lo && [old[@"start_at"] doubleValue]<hi && ([old[@"start_at"] doubleValue] <= now || active || !windows.count)) {
            NSDictionary *entry = ta_entry(task,old[@"cycle_at"],[old[@"start_at"] doubleValue],[old[@"end_at"] doubleValue],@"task",NO);
            [entries addObject:entry]; [busy addObject:entry]; continue;
        }
        if ([task[@"schedule_kind"] isEqual:@"date"] && ![task[@"planning_mode"] isEqual:@"window"]) {
            NSArray *cycles = [TaskRule cycles:task at:lo limit:4 error:error]; if (!cycles) return nil; cycle = nil;
            for (NSNumber *candidate in cycles) if (candidate.doubleValue >= lo && candidate.doubleValue < hi) { cycle = candidate; break; }
            if (!cycle || ta_done(task,cycle,history) || ta_expired(task,cycle,history)) continue;
            NSArray *alerts = [TaskRule alerts:task history:history at:now error:error]; if (!alerts) return nil;
            NSDictionary *alert = nil;
            for (NSDictionary *candidate in alerts) if ([candidate[@"cycle_at"] isEqual:cycle] && [@[@"plan",@"both"] containsObject:candidate[@"kind"]]) { alert = candidate; break; }
            if (!alert || (!old && [alert[@"remind_at"] doubleValue] <= now)) { [unplaced addObject:@{@"task":task,@"reason":@"保留原定提醒"}]; continue; }
            scheduled = alert[@"scheduled_at"];
        }
        if([task[@"planning_mode"] isEqual:@"window"]){cycle=task[@"due_at"];scheduled=task[@"due_at"];}
        // 时区变化只改变日界，已经分配的轮次身份不能改变。
        if(old){cycle=old[@"cycle_at"];scheduled=old[@"scheduled_at"];}
        NSNumber *release=[task[@"planning_mode"] isEqual:@"window"] ? task[@"due_at"] : nil,*inherited=nil;NSMutableArray *order=[NSMutableArray arrayWithObject:task];NSDictionary *ancestor=task;
        // 子任务继承父级起点和最早截止，保留父级自身字段。
        while(ancestor[@"parent_id"]!=NSNull.null && taskMap[ancestor[@"parent_id"]]) {
            ancestor=taskMap[ancestor[@"parent_id"]];[order insertObject:ancestor atIndex:0];
            if(ts_num(ancestor[@"due_at"]) && (!release || [release compare:ancestor[@"due_at"]]==NSOrderedAscending))release=ancestor[@"due_at"];
            if(ts_num(ancestor[@"deadline_at"]) && (!inherited || [inherited compare:ancestor[@"deadline_at"]]==NSOrderedDescending))inherited=ancestor[@"deadline_at"];
        }
        if(release && release.doubleValue>=hi)continue;
        [flex addObject:@{@"task":task,@"cycle_at":cycle,@"old":old ?: (NSDictionary *)NSNull.null,@"scheduled_at":scheduled ?: (NSNumber *)NSNull.null,
            @"release":release ?: (NSNumber *)NSNull.null,@"inherited":inherited ?: (NSNumber *)NSNull.null,@"order":order}];
    }
    // 固定开始的普通长任务也要提供拆分，不能只留下无法消除的时段冲突。
    for(NSDictionary *entry in entries) {
        NSDictionary *task=entry[@"task"];if(![entry[@"kind"] isEqual:@"task"] || ![task[@"schedule_kind"] isEqual:@"timed"] || [task[@"recurrence"] count] || !windows.count)continue;
        NSMutableArray *other=[busy mutableCopy];[other removeObject:entry];double capacity=0;
        for(NSDictionary *gap in ta_free(windows,other)) {
            double start=fmax([gap[@"start_at"] doubleValue],fmax([entry[@"start_at"] doubleValue],ceil(now/60)*60)),end=[gap[@"end_at"] doubleValue];
            if(ts_num(task[@"deadline_at"]))end=fmin(end,[task[@"deadline_at"] doubleValue]);capacity=fmax(capacity,end-start);
        }
        if(capacity>0 && [task[@"planned_duration"] doubleValue]>capacity)[unplaced addObject:@{@"task":task,@"reason":@"需要拆分长任务",@"needs_split":@YES,@"max_span":@(capacity)}];
    }
    for (NSUInteger i = 0; i < busy.count; i++) for (NSUInteger j = i+1; j < busy.count; j++) {
        NSDictionary *a = busy[i], *b = busy[j];
        if ([a[@"start_at"] doubleValue] < [b[@"end_at"] doubleValue] && [b[@"start_at"] doubleValue] < [a[@"end_at"] doubleValue]) {
            [conflicts addObject:@{@"task":a[@"task"],@"peer":b[@"task"],@"reason":@"固定时段重叠"}];
        }
    }
    NSMutableArray *free = ta_free(windows,busy);
    double maxSpan=0;for(NSDictionary *gap in free)maxSpan=fmax(maxSpan,[gap[@"end_at"] doubleValue]-fmax([gap[@"start_at"] doubleValue],ceil(now/60)*60));
    [flex sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSArray *left=a[@"order"],*right=b[@"order"];
        for(NSUInteger index=0;index<MIN(left.count,right.count);index++)for(NSString *key in @[@"position",@"created_at",@"task_id"]) {
            NSComparisonResult order=[left[index][key] compare:right[index][key]];if(order!=NSOrderedSame)return order;
        }
        return [a[@"cycle_at"] compare:b[@"cycle_at"]];
    }];
    NSMutableDictionary *familyEnds=[NSMutableDictionary dictionary];
    for (NSDictionary *candidate in flex) {
        NSDictionary *task = candidate[@"task"], *old = candidate[@"old"] == NSNull.null ? nil : candidate[@"old"];
        NSString *reason = conflicts.count ? @"请先调整冲突" : active ? @"当前提醒尚未处理" : !windows.count ? @"未设置一般任务时段" : @"剩余时段不足";
        BOOL placed = NO; double duration = [task[@"planned_duration"] doubleValue];
        NSNumber *deadline = [TaskRule ddl:task cycle:task[@"due_at"] == NSNull.null ? nil : candidate[@"cycle_at"]];
        if(candidate[@"inherited"]!=NSNull.null && (!deadline || [deadline compare:candidate[@"inherited"]]==NSOrderedDescending))deadline=candidate[@"inherited"];
        if (!active && !conflicts.count) for (NSMutableDictionary *gap in free) {
            double start = fmax([gap[@"start_at"] doubleValue],ceil(now/60)*60);
            if(candidate[@"release"]!=NSNull.null)start=fmax(start,[candidate[@"release"] doubleValue]);
            for(NSDictionary *ancestor in candidate[@"order"])if(![ancestor[@"task_id"] isEqual:task[@"task_id"]])start=fmax(start,[familyEnds[ancestor[@"task_id"]] doubleValue]);double end=start+duration;
            if (end > [gap[@"end_at"] doubleValue] || (deadline && end > deadline.doubleValue)) continue;
            NSDictionary *entry = ta_entry(task,candidate[@"cycle_at"],start,end,@"task",NO); [entries addObject:entry];
            [allocations addObject:@{@"task_id":task[@"task_id"],@"generation":task[@"reminder_version"],@"cycle_at":candidate[@"cycle_at"],
                @"scheduled_at":old ? old[@"scheduled_at"] : (candidate[@"scheduled_at"] == NSNull.null ? @(start) : candidate[@"scheduled_at"]),
                @"day_at":@(lo),@"start_at":@(start),@"end_at":@(end)}]; gap[@"start_at"] = @(end);for(NSDictionary *ancestor in candidate[@"order"])if(![ancestor[@"task_id"] isEqual:task[@"task_id"]])familyEnds[ancestor[@"task_id"]]=@(end); placed = YES; break;
        }
        if (!placed) {
            double capacity=0;for(NSDictionary *gap in ta_free(windows,busy)) {
                double start=fmax([gap[@"start_at"] doubleValue],ceil(now/60)*60),end=[gap[@"end_at"] doubleValue];
                if(candidate[@"release"]!=NSNull.null)start=fmax(start,[candidate[@"release"] doubleValue]);if(deadline)end=fmin(end,deadline.doubleValue);
                capacity=fmax(capacity,end-start);
            }
            BOOL split=![task[@"recurrence"] count] && !active && !conflicts.count && capacity>0 && duration>capacity;
            [unplaced addObject:@{@"task":task,@"reason":split ? @"需要拆分长任务" : deadline && !active && !conflicts.count && windows.count ? @"截止前无可用时段" : reason,@"needs_split":@(split),@"max_span":@(capacity)}];
        }
    }
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult order = [a[@"start_at"] compare:b[@"start_at"]]; return order == NSOrderedSame ? [a[@"id"] compare:b[@"id"]] : order;
    }];
    return @{@"day_at":@(lo),@"day_end":@(hi),@"timezone_id":zone,@"entries":entries,@"allocations":allocations,
        @"unplaced":unplaced,@"conflicts":conflicts,@"draft_count":@(drafts),@"revision":snapshot[@"revision"],@"has_windows":@(windows.count>0),@"max_span":@(maxSpan)};
}
