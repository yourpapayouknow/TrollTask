#import "LBHead.h"

static char *tr_tzpath;

// 删除当前进程生成的临时时区数据。
static void tr_clean(void) {
    @autoreleasepool { if (tr_tzpath) [NSFileManager.defaultManager removeItemAtPath:@(tr_tzpath) error:nil]; }
    free(tr_tzpath);
}

// 返回规则校验或展开错误。
static BOOL tr_err(NSError **error, NSString *text) {
    if (error) *error = [NSError errorWithDomain:@"com.iwmei.taskforiwmei.store" code:SQLITE_CONSTRAINT
        userInfo:@{NSLocalizedDescriptionKey: text, @"kind": @"invalid_fields"}];
    return NO;
}

// 取得系统Foundation时区的原生TZif数据。
static icaltimezone *tr_zone(NSString *name, NSError **error) {
    NSTimeZone *zone = [NSTimeZone timeZoneWithName:name];
    if (!zone) { tr_err(error, @"重复规则时区无效"); return NULL; }
    if (!tr_tzpath) {
        tr_tzpath = strdup([NSTemporaryDirectory() stringByAppendingPathComponent:@"trolltask-tz.XXXXXX"].fileSystemRepresentation);
        if (!tr_tzpath || !mkdtemp(tr_tzpath)) { tr_err(error, @"时区缓存创建失败"); free(tr_tzpath); tr_tzpath = NULL; return NULL; }
        atexit(tr_clean);
        NSMutableString *table = [NSMutableString string];
        for (NSString *location in NSTimeZone.knownTimeZoneNames) [table appendFormat:@"ZZ\t+0000+00000\t%@\n", location];
        if (![table writeToFile:[@(tr_tzpath) stringByAppendingPathComponent:@"zone.tab"] atomically:YES encoding:NSUTF8StringEncoding error:error]) return NULL;
        icaltimezone_set_system_zone_directory(tr_tzpath);
        icaltimezone_set_builtin_tzdata(false);
    }
    NSString *path = [@(tr_tzpath) stringByAppendingPathComponent:name];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        NSData *data = zone.data;
        if (data.length < 4 || memcmp(data.bytes, "TZif", 4) != 0
            || ![NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                attributes:@{NSFilePosixPermissions: @0700} error:error]
            || ![data writeToFile:path options:NSDataWritingAtomic error:error]) { tr_err(error, @"系统时区数据不可用"); return NULL; }
    }
    icaltimezone *result = icaltimezone_get_builtin_timezone(name.UTF8String);
    if (!result || (result != icaltimezone_get_utc_timezone() && !icaltimezone_get_component(result))) { tr_err(error, @"原生时区读取失败"); return NULL; }
    return result;
}

// 为当地日历计算建立一致的时区。
static NSCalendar *tr_cal(NSDictionary *task) {
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:task[@"timezone_id"]];
    return calendar;
}

// 为属性附上明确的时区并保留UTC与仅日期语义。
static struct icaltimetype tr_time(struct icaltimetype time, icaltimezone *zone) {
    if (!time.is_date && !icaltime_is_utc(time) && !time.zone) icaltime_set_timezone(&time, zone);
    return time;
}

// 将完整Calendar属性解析为原生组件。
static icalcomponent *tr_comp(NSDictionary *task, NSError **error) {
    icaltimezone *zone = tr_zone(task[@"timezone_id"], error);
    if (!zone) return NULL;
    struct icaltimetype base = icaltime_from_timet_with_zone((time_t)floor([task[@"due_at"] doubleValue]), [task[@"schedule_kind"] isEqual:@"date"], zone);
    NSMutableString *text = [NSMutableString stringWithFormat:@"BEGIN:VEVENT\r\nDTSTART%@:%s\r\n",
        base.is_date ? @";VALUE=DATE" : (icaltime_is_utc(base) ? @"" : [@";TZID=" stringByAppendingString:task[@"timezone_id"]]), icaltime_as_ical_string(base)];
    for (NSString *line in task[@"recurrence"]) [text appendFormat:@"%@\r\n", line];
    [text appendString:@"END:VEVENT\r\n"];
    icalerror_clear_errno();
    icalcomponent *component = icalcomponent_new_from_string(text.UTF8String);
    if (!component || icalcomponent_count_errors(component) || icalerrno != ICAL_NO_ERROR) {
        if (component) icalcomponent_free(component);
        tr_err(error, @"重复规则语法无效"); return NULL;
    }
    icalcomponent_set_dtstart(component, base);
    for (icalproperty *property = icalcomponent_get_first_property(component, ICAL_ANY_PROPERTY); property;
         property = icalcomponent_get_next_property(component, ICAL_ANY_PROPERTY)) {
        icalproperty_kind kind = icalproperty_isa(property);
        if (kind == ICAL_RRULE_PROPERTY || kind == ICAL_EXRULE_PROPERTY) {
            struct icalrecurrencetype *rule = kind == ICAL_RRULE_PROPERTY ? icalproperty_get_rrule(property) : icalproperty_get_exrule(property);
            icalrecur_iterator *iterator = rule ? icalrecur_iterator_new(rule, base) : NULL;
            if (!iterator) { icalcomponent_free(component); tr_err(error, @"重复规则组合不可用"); return NULL; }
            icalrecur_iterator_free(iterator);
        } else if (kind == ICAL_RDATE_PROPERTY || kind == ICAL_EXDATE_PROPERTY) {
            icalparameter *parameter = icalproperty_get_first_parameter(property, ICAL_TZID_PARAMETER);
            icaltimezone *propertyZone = parameter ? tr_zone(@(icalparameter_get_tzid(parameter)), error) : zone;
            if (!propertyZone) { icalcomponent_free(component); return NULL; }
            if (kind == ICAL_RDATE_PROPERTY) {
                struct icaldatetimeperiodtype value = icalproperty_get_rdate(property);
                value.time = tr_time(value.time, propertyZone);
                value.period.start = tr_time(value.period.start, propertyZone);
                value.period.end = tr_time(value.period.end, propertyZone);
                icalproperty_set_rdate(property, value);
            } else icalproperty_set_exdate(property, tr_time(icalproperty_get_exdate(property), propertyZone));
        } else if (kind != ICAL_DTSTART_PROPERTY) {
            icalcomponent_free(component); tr_err(error, @"重复属性类型不受支持"); return NULL;
        }
    }
    return component;
}

// 按原生例外规则收集绝对时间。
static void tr_add(NSMutableSet *values, icalcomponent *component, struct icaltimetype base, struct icaltimetype time, double fraction) {
    if (!icaltime_is_null_time(time) && !icalproperty_recurrence_is_excluded(component, &base, &time)) {
        icaltimezone *zone = (icaltimezone *)(time.zone ?: base.zone);
        [values addObject:@((double)icaltime_as_timet_with_zone(time, zone) + fraction)];
    }
}

@implementation TaskRule

// 在两个进程复用同一原生语法校验。
+ (BOOL)vld:(NSDictionary *)task error:(NSError **)error {
    if (![task[@"recurrence"] count]) return YES;
    @synchronized(self) {
        icalcomponent *component = tr_comp(task, error);
        if (!component) return NO;
        icalcomponent_free(component);
        return YES;
    }
}

// 合并全部RRULE和RDATE，应用EXRULE与EXDATE。
+ (NSArray *)cycles:(NSDictionary *)task at:(NSTimeInterval)stamp limit:(NSUInteger)limit error:(NSError **)error {
    if (task[@"due_at"] == NSNull.null) return @[];
    if (![task[@"recurrence"] count]) return @[task[@"due_at"]];
    @synchronized(self) {
        icalcomponent *component = tr_comp(task, error);
        if (!component) return nil;
        struct icaltimetype base = icalcomponent_get_dtstart(component);
        // DATE属性不携带TZID，转换绝对日界时仍采用任务的时区。
        if (base.is_date) base.zone = tr_zone(task[@"timezone_id"], error);
        struct icaltimetype reference = icaltime_from_timet_with_zone((time_t)floor(stamp), false, (icaltimezone *)base.zone);
        NSMutableSet *values = [NSMutableSet set];
        double fraction = [task[@"due_at"] doubleValue] - floor([task[@"due_at"] doubleValue]);
        for (icalproperty *property = icalcomponent_get_first_property(component, ICAL_RRULE_PROPERTY); property;
             property = icalcomponent_get_next_property(component, ICAL_RRULE_PROPERTY)) {
            struct icalrecurrencetype *rule = icalproperty_get_rrule(property);
            icalrecur_iterator *iterator = icalrecur_iterator_new(rule, base);
            NSNumber *previous = nil;
            if (!rule->count && stamp > [task[@"due_at"] doubleValue]) {
                // 保留已经结束的规则最后一个有效边界轮次。
                if (!icaltime_is_null_time(rule->until) && icaltime_compare(reference, rule->until) > 0) {
                    icalrecur_iterator_set_start(iterator, rule->until);
                    tr_add(values, component, base, icalrecur_iterator_next(iterator), fraction);
                    icalrecur_iterator_free(iterator);
                    iterator = icalrecur_iterator_new(rule, base);
                }
                if (icalrecur_iterator_set_range(iterator, reference, base)) {
                    for (struct icaltimetype past = icalrecur_iterator_prev(iterator); !icaltime_is_null_time(past); past = icalrecur_iterator_prev(iterator)) {
                        if (icalproperty_recurrence_is_excluded(component, &base, &past)) continue;
                        tr_add(values, component, base, past, fraction); break;
                    }
                }
                icalrecur_iterator_free(iterator);
                iterator = icalrecur_iterator_new(rule, base);
                icalrecur_iterator_set_start(iterator, reference);
            }
            NSUInteger future = 0;
            for (struct icaltimetype next = icalrecur_iterator_next(iterator); !icaltime_is_null_time(next);
                 next = icalrecur_iterator_next(iterator)) {
                double absolute = (double)icaltime_as_timet_with_zone(next, (icaltimezone *)(next.zone ?: base.zone)) + fraction;
                if (icalproperty_recurrence_is_excluded(component, &base, &next)) continue;
                if (absolute < stamp) previous = @(absolute);
                else { [values addObject:@(absolute)]; if (++future >= MAX(limit, 1)) break; }
            }
            if (previous) [values addObject:previous];
            icalrecur_iterator_free(iterator);
        }
        if (!icalcomponent_count_properties(component, ICAL_RRULE_PROPERTY)) tr_add(values, component, base, base, fraction);
        for (icalproperty *property = icalcomponent_get_first_property(component, ICAL_RDATE_PROPERTY); property;
             property = icalcomponent_get_next_property(component, ICAL_RDATE_PROPERTY)) {
            struct icaldatetimeperiodtype value = icalproperty_get_rdate(property);
            icalparameter *parameter = icalproperty_get_first_parameter(property, ICAL_TZID_PARAMETER);
            icaltimezone *zone = parameter ? tr_zone(@(icalparameter_get_tzid(parameter)), error) : (icaltimezone *)base.zone;
            if (!zone) { icalcomponent_free(component); return nil; }
            tr_add(values, component, base, tr_time(icaltime_is_null_time(value.time) ? value.period.start : value.time, zone), 0);
        }
        icalcomponent_free(component);
        NSArray *sorted = [[values allObjects] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableArray *result = [NSMutableArray array]; NSNumber *past = nil;
        for (NSNumber *value in sorted) if (value.doubleValue < stamp) past = value; else if (result.count < MAX(limit, 1)) [result addObject:value];
        if (past) [result insertObject:past atIndex:0];
        return result;
    }
}

// 以当地日历平移重复任务的独立截止日期。
+ (NSNumber *)ddl:(NSDictionary *)task cycle:(NSNumber *)cycle {
    if (task[@"deadline_at"] == NSNull.null) return nil;
    NSCalendar *calendar = tr_cal(task);
    NSDate *deadline = [NSDate dateWithTimeIntervalSince1970:[task[@"deadline_at"] doubleValue]];
    if ([task[@"deadline_kind"] isEqual:@"date"]) {
        NSDateComponents *day = [NSDateComponents new]; day.day = -1;
        deadline = [calendar dateByAddingComponents:day toDate:deadline options:0];
        deadline = [calendar dateBySettingHour:9 minute:0 second:0 ofDate:deadline options:0];
    }
    if (cycle && task[@"due_at"] != NSNull.null && [task[@"recurrence"] count]) {
        NSDate *base = [NSDate dateWithTimeIntervalSince1970:[task[@"due_at"] doubleValue]];
        NSDateComponents *offset = [calendar components:NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond | NSCalendarUnitNanosecond
            fromDate:base toDate:deadline options:0];
        deadline = [calendar dateByAddingComponents:offset toDate:[NSDate dateWithTimeIntervalSince1970:cycle.doubleValue] options:0];
    }
    return deadline ? @(deadline.timeIntervalSince1970) : nil;
}

// 根据当前轮次及处理记录计算有效的双提醒。
+ (NSArray *)alerts:(NSDictionary *)task history:(NSArray *)history at:(NSTimeInterval)stamp error:(NSError **)error {
    if ([task[@"deleted"] boolValue] || ![task[@"status"] isEqual:@"needsAction"]) return @[];
    BOOL repeats = [task[@"recurrence"] count] > 0;
    NSArray *cycles = [self cycles:task at:stamp limit:4 error:error];
    if (!cycles) return nil;
    NSMutableSet *set = [NSMutableSet setWithArray:cycles];
    NSCalendar *calendar = tr_cal(task);
    if (repeats && task[@"deadline_at"] != NSNull.null) {
        NSDate *base = [NSDate dateWithTimeIntervalSince1970:[task[@"due_at"] doubleValue]];
        NSDate *deadline = [NSDate dateWithTimeIntervalSince1970:[[self ddl:task cycle:nil] doubleValue]];
        NSDateComponents *offset = [calendar components:NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond
            fromDate:base toDate:deadline options:0];
        offset.day = -offset.day; offset.hour = -offset.hour; offset.minute = -offset.minute; offset.second = -offset.second;
        NSDate *anchor = [calendar dateByAddingComponents:offset toDate:[NSDate dateWithTimeIntervalSince1970:stamp] options:0];
        NSArray *extra = [self cycles:task at:anchor.timeIntervalSince1970 limit:4 error:error];
        if (!extra) return nil;
        [set addObjectsFromArray:extra];
    }
    if (!set.count && !repeats && task[@"deadline_at"] != NSNull.null) [set addObject:task[@"deadline_at"]];
    NSMutableArray *records = [NSMutableArray array];
    NSMutableSet *completed = [NSMutableSet set];
    NSMutableDictionary *floor = [NSMutableDictionary dictionary];
    NSNumber *completedFloor = nil;
    for (NSDictionary *row in history) if ([row[@"task_id"] isEqual:task[@"task_id"]] && [row[@"generation"] isEqual:task[@"reminder_version"]]) {
        [records addObject:row];
        if ([row[@"action"] isEqual:@"complete"]) {
            [completed addObject:row[@"cycle_at"]];
            if (!completedFloor || [completedFloor compare:row[@"cycle_at"]] == NSOrderedAscending) completedFloor = row[@"cycle_at"];
        }
        if ([row[@"status"] isEqual:@"handled"] && ![row[@"action"] isEqual:@"snooze"]) {
            NSArray *keys = [row[@"kind"] isEqual:@"both"] ? @[@"plan", @"deadline", @"both"] : @[row[@"kind"]];
            for (NSString *key in keys) if (!floor[key] || [floor[key] compare:row[@"scheduled_at"]] == NSOrderedAscending) floor[key] = row[@"scheduled_at"];
        }
        if ([row[@"action"] isEqual:@"snooze"] || [row[@"status"] isEqual:@"triggered"]) [set addObject:row[@"cycle_at"]];
    }
    // 提前完成超出预取窗口后，从已完成轮次继续展开原始规则。
    if (repeats && completedFloor && completedFloor.doubleValue >= stamp) {
        NSArray *future = [self cycles:task at:nextafter(completedFloor.doubleValue, INFINITY) limit:4 error:error];
        if (!future) return nil;
        [set addObjectsFromArray:future];
    }
    NSMutableArray *result = [NSMutableArray array];
    NSMutableDictionary *latest = [NSMutableDictionary dictionary];
    for (NSNumber *cycle in set) {
        if ([completed containsObject:cycle] || (repeats && completedFloor && [cycle compare:completedFloor] != NSOrderedDescending)) continue;
        NSNumber *plan = task[@"due_at"] == NSNull.null ? nil : cycle;
        if (plan && [task[@"schedule_kind"] isEqual:@"date"]) {
            NSDate *date = [calendar dateBySettingHour:9 minute:0 second:0 ofDate:[NSDate dateWithTimeIntervalSince1970:plan.doubleValue] options:0];
            plan = @(date.timeIntervalSince1970);
        }
        NSNumber *deadline = [self ddl:task cycle:cycle];
        NSArray *kinds = plan && deadline && [plan isEqualToNumber:deadline] ? @[@"both"] : @[@"plan", @"deadline"];
        for (NSString *kind in kinds) {
            NSNumber *scheduled = [kind isEqual:@"deadline"] ? deadline : plan;
            if (!scheduled) continue;
            NSMutableDictionary *item = [@{@"task_id": task[@"task_id"], @"generation": task[@"reminder_version"], @"cycle_at": cycle,
                @"kind": kind, @"scheduled_at": scheduled, @"remind_at": scheduled, @"task": task} mutableCopy];
            if (![kind isEqual:@"deadline"] && task[@"snooze_until"] != NSNull.null)
                item[@"remind_at"] = @(fmax(scheduled.doubleValue, [task[@"snooze_until"] doubleValue]));
            BOOL handled = NO, pinned = NO;
            for (NSDictionary *row in records) if ([row[@"cycle_at"] isEqual:cycle] && [row[@"kind"] isEqual:kind]) {
                item[@"occurrence_id"] = row[@"occurrence_id"];
                if ([row[@"status"] isEqual:@"handled"] && ![row[@"action"] isEqual:@"snooze"]) handled = YES;
                if ([row[@"action"] isEqual:@"snooze"] && row[@"snooze_until"] != NSNull.null) {
                    item[@"remind_at"] = @(fmax([item[@"remind_at"] doubleValue], [row[@"snooze_until"] doubleValue])); pinned = YES;
                }
                if ([row[@"status"] isEqual:@"triggered"]) pinned = YES;
            }
            if (handled) continue;
            if (repeats && !pinned && floor[kind] && [scheduled compare:floor[kind]] != NSOrderedDescending) continue;
            if (!repeats || pinned || [item[@"remind_at"] doubleValue] >= stamp) [result addObject:item];
            else if (!latest[kind] || [latest[kind][@"remind_at"] doubleValue] < [item[@"remind_at"] doubleValue]) latest[kind] = item;
        }
    }
    [result addObjectsFromArray:latest.allValues];
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult order = [a[@"remind_at"] compare:b[@"remind_at"]];
        return order == NSOrderedSame ? [a[@"kind"] compare:b[@"kind"]] : order;
    }];
}
@end
