#import "LBHead.h"

// 创建可滚动、可验证的数值输入。
static UITextField *tp_num(NSString *text, NSString *identifier) {
    UITextField *field = [UITextField new]; field.text = text; field.accessibilityIdentifier = identifier;
    field.keyboardType = UIKeyboardTypeNumberPad; field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    field.adjustsFontForContentSizeCategory = YES; field.textAlignment = NSTextAlignmentRight;
    [field.widthAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES; return field;
}

@implementation TaskRepeat {
    NSDictionary *_original;
    void (^_reply)(NSDictionary *);
    NSString *_type, *_end;
    UITextField *_interval, *_count;
    UIDatePicker *_until;
    UITextView *_raw;
    UIButton *_typeBtn, *_endBtn, *_daysBtn;
    NSMutableSet *_days, *_dirty;
    UIStackView *_basic, *_untilRow, *_countRow;
}
// 保留完整原始规则及回调。
- (instancetype)initWithFields:(NSDictionary *)fields reply:(void (^)(NSDictionary *))reply {
    self = [super init]; if (!self) return nil; _original = fields; _reply = [reply copy];
    _type = fields[@"recurrence_type"] ?: @"none"; _end = @"none"; _days = [NSMutableSet set]; _dirty = [NSMutableSet set]; return self;
}
// 创建系统菜单、结束条件和可选完整规则编辑。
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.blackColor;
    NSMutableDictionary *parts = [NSMutableDictionary dictionary];
    for (NSString *line in _original[@"recurrence"]) if ([line hasPrefix:@"RRULE:"]) {
        for (NSString *pair in [[line substringFromIndex:6] componentsSeparatedByString:@";"]) {
            NSArray *items = [pair componentsSeparatedByString:@"="]; if (items.count == 2) parts[items[0]] = items[1];
        } break;
    }
    if (parts[@"BYDAY"]) [_days addObjectsFromArray:[parts[@"BYDAY"] componentsSeparatedByString:@","]];
    _interval = tp_num(parts[@"INTERVAL"] ?: [_original[@"recurrence_interval"] stringValue] ?: @"1", @"repeat.interval");
    _count = tp_num(parts[@"COUNT"] ?: @"10", @"repeat.count");
    _until = [UIDatePicker new]; _until.datePickerMode = UIDatePickerModeDate; _until.preferredDatePickerStyle = UIDatePickerStyleCompact;
    _until.timeZone = [NSTimeZone timeZoneWithName:_original[@"timezone_id"]] ?: NSTimeZone.localTimeZone;
    _until.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"]; _until.accessibilityIdentifier = @"repeat.until";
    if (parts[@"COUNT"]) _end = @"count";
    if (parts[@"UNTIL"]) {
        _end = @"until"; NSDateFormatter *format = [NSDateFormatter new]; format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        format.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0]; format.dateFormat = [parts[@"UNTIL"] length] == 8 ? @"yyyyMMdd" : @"yyyyMMdd'T'HHmmss'Z'";
        _until.date = [format dateFromString:parts[@"UNTIL"]] ?: NSDate.date;
    }
    for (UIControl *control in @[_interval, _count, _until]) [control addTarget:self action:@selector(chg:) forControlEvents:
        [control isKindOfClass:UITextField.class] ? UIControlEventEditingChanged : UIControlEventValueChanged];
    _typeBtn = tu_btn(nil, @"repeat", nil, NULL); _typeBtn.accessibilityIdentifier = @"repeat.type";
    _endBtn = tu_btn(nil, @"down", nil, NULL); _endBtn.accessibilityIdentifier = @"repeat.end";
    _daysBtn = tu_btn(@"指定星期", @"calendar", nil, NULL); _daysBtn.accessibilityIdentifier = @"repeat.days";
    _raw = [UITextView new]; _raw.delegate = self; _raw.text = [_original[@"recurrence"] componentsJoinedByString:@"\n"] ?: @"";
    _raw.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; _raw.adjustsFontForContentSizeCategory = YES;
    _raw.backgroundColor = UIColor.clearColor; _raw.accessibilityIdentifier = @"repeat.rules"; _raw.accessibilityLabel = @"完整重复规则";
    _raw.textContainerInset = UIEdgeInsetsMake(4,4,4,4); [_raw.heightAnchor constraintEqualToConstant:180].active = YES;
    UIButton *done = tu_btn(@"完成", nil, self, @selector(sv)); done.accessibilityIdentifier = @"repeat.done";
    UIButton *cancel = tu_btn(@"取消", nil, self, @selector(cncl));
    _untilRow = tu_row(@"结束日期",_until); _countRow = tu_row(@"结束次数",_count);
    _basic = tu_stk(@[tu_row(@"重复间隔", _interval), _daysBtn, _endBtn, _untilRow, _countRow]);
    tu_form(self, tu_stk(@[_typeBtn, _basic, _raw, done, cancel]), @"repeat.form"); [self menus];
}
// 保留未修改的规则参数并更新菜单状态。
- (void)menus {
    __weak TaskRepeat *weak = self;
    NSArray *types = @[@"none",@"daily",@"weekly",@"monthly",@"yearly",@"custom"], *titles = @[@"不重复",@"每天",@"每周",@"每月",@"每年",@"完整规则"];
    NSMutableArray *actions = [NSMutableArray array];
    for (NSUInteger index = 0; index < types.count; index++) {
        NSString *type = types[index]; UIAction *action = [UIAction actionWithTitle:titles[index] image:nil identifier:[@"repeat.type." stringByAppendingString:type] handler:^(__unused UIAction *item) {
            TaskRepeat *owner = weak; if (!owner) return; owner->_type = type; [owner->_dirty addObject:@"type"]; [owner menus]; }];
        action.state = [_type isEqual:type] ? UIMenuElementStateOn : UIMenuElementStateOff; [actions addObject:action];
    }
    [_typeBtn setTitle:titles[[types indexOfObject:_type] == NSNotFound ? 0 : [types indexOfObject:_type]] forState:UIControlStateNormal];
    _typeBtn.menu = [UIMenu menuWithChildren:actions]; _typeBtn.showsMenuAsPrimaryAction = YES;
    [actions removeAllObjects]; NSArray *ends = @[@"none",@"until",@"count"], *endTitles = @[@"永不结束",@"指定日期",@"指定次数"];
    for (NSUInteger index = 0; index < ends.count; index++) {
        NSString *end = ends[index]; UIAction *action = [UIAction actionWithTitle:endTitles[index] image:nil identifier:[@"repeat.end." stringByAppendingString:end] handler:^(__unused UIAction *item) {
            TaskRepeat *owner = weak; if (!owner) return; owner->_end = end; [owner->_dirty addObject:@"end"]; [owner menus]; }];
        action.state = [_end isEqual:end] ? UIMenuElementStateOn : UIMenuElementStateOff; [actions addObject:action];
    }
    [_endBtn setTitle:endTitles[[ends indexOfObject:_end]] forState:UIControlStateNormal];
    _endBtn.menu = [UIMenu menuWithChildren:actions]; _endBtn.showsMenuAsPrimaryAction = YES;
    [actions removeAllObjects]; NSArray *days = @[@"MO",@"TU",@"WE",@"TH",@"FR",@"SA",@"SU"], *names = @[@"周一",@"周二",@"周三",@"周四",@"周五",@"周六",@"周日"];
    for (NSUInteger index = 0; index < days.count; index++) {
        NSString *day = days[index]; UIAction *action = [UIAction actionWithTitle:names[index] image:nil identifier:[@"repeat.day." stringByAppendingString:day] handler:^(__unused UIAction *item) {
            TaskRepeat *owner = weak; if (!owner) return;
            if ([owner->_days containsObject:day]) [owner->_days removeObject:day]; else [owner->_days addObject:day];
            [owner->_dirty addObject:@"days"]; [owner menus]; }];
        action.state = [_days containsObject:day] ? UIMenuElementStateOn : UIMenuElementStateOff; [actions addObject:action];
    }
    _daysBtn.menu = [UIMenu menuWithChildren:actions]; _daysBtn.showsMenuAsPrimaryAction = YES;
    _raw.hidden = ![_type isEqual:@"custom"]; _basic.hidden = [_type isEqual:@"custom"] || [_type isEqual:@"none"];
    _daysBtn.hidden = ![_type isEqual:@"weekly"]; _untilRow.hidden = ![_end isEqual:@"until"]; _countRow.hidden = ![_end isEqual:@"count"];
}
// 记录用户修改的重复参数。
- (void)chg:(UIControl *)control { [_dirty addObject:control == _interval ? @"interval" : @"end"]; }
// 记录完整属性编辑。
- (void)textViewDidChange:(UITextView *)view { (void)view; [_dirty addObject:@"raw"]; }
// 取消面板而不改动草稿。
- (void)cncl { [self dismissViewControllerAnimated:YES completion:nil]; }
// 校验并返回完整重复补丁。
- (void)sv {
    if (!_dirty.count) { [self cncl]; return; }
    long long interval = _interval.text.longLongValue, count = _count.text.longLongValue;
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    if (![_type isEqual:@"none"] && ![_type isEqual:@"custom"] && (interval < 1 || [_interval.text rangeOfCharacterFromSet:digits].location != NSNotFound
        || ([_end isEqual:@"count"] && (count < 1 || [_count.text rangeOfCharacterFromSet:digits].location != NSNotFound)))) {
        tu_err(self, [NSError errorWithDomain:@"repeat" code:1 userInfo:@{@"kind":@"invalid_fields"}]); return;
    }
    NSMutableArray *lines = [_original[@"recurrence"] mutableCopy] ?: [NSMutableArray array];
    if ([_type isEqual:@"none"]) { lines = [NSMutableArray array]; interval = 1; }
    else if ([_type isEqual:@"custom"]) {
        [lines removeAllObjects]; for (NSString *line in [_raw.text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString *value = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]; if (value.length) [lines addObject:value];
        }
    } else {
        NSUInteger index = [lines indexOfObjectPassingTest:^BOOL(NSString *line, NSUInteger idx, BOOL *stop) { (void)idx; (void)stop; return [line hasPrefix:@"RRULE:"]; }];
        NSMutableDictionary *parts = [NSMutableDictionary dictionary];
        if (index != NSNotFound) for (NSString *pair in [[lines[index] substringFromIndex:6] componentsSeparatedByString:@";"]) {
            NSArray *items = [pair componentsSeparatedByString:@"="]; if (items.count == 2) parts[items[0]] = items[1];
        }
        if (index == NSNotFound || [_dirty containsObject:@"type"]) {
            if (![parts[@"FREQ"] isEqual:_type.uppercaseString]) {
                for (NSString *key in parts.allKeys.copy) if ([key hasPrefix:@"BY"]) [parts removeObjectForKey:key];
                if ([_type isEqual:@"weekly"] && _days.count) parts[@"BYDAY"] = [[_days.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","];
            }
            parts[@"FREQ"] = _type.uppercaseString;
        }
        if (index == NSNotFound || [_dirty containsObject:@"interval"]) parts[@"INTERVAL"] = @(interval).stringValue;
        if ([_dirty containsObject:@"days"]) { [parts removeObjectForKey:@"BYDAY"]; if (_days.count) parts[@"BYDAY"] = [[_days.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]; }
        if ([_dirty containsObject:@"end"]) {
            [parts removeObjectForKey:@"UNTIL"]; [parts removeObjectForKey:@"COUNT"];
            if ([_end isEqual:@"count"]) parts[@"COUNT"] = @(count).stringValue;
            if ([_end isEqual:@"until"]) {
                NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = _until.timeZone;
                NSDate *end = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:[calendar startOfDayForDate:_until.date] options:0];
                NSDateFormatter *format = [NSDateFormatter new]; format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
                format.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0]; format.dateFormat = @"yyyyMMdd'T'HHmmss'Z'";
                parts[@"UNTIL"] = [format stringFromDate:[end dateByAddingTimeInterval:-1]];
            }
        }
        NSMutableArray *pairs = [NSMutableArray array]; for (NSString *key in [parts.allKeys sortedArrayUsingSelector:@selector(compare:)]) [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, parts[key]]];
        NSString *line = [@"RRULE:" stringByAppendingString:[pairs componentsJoinedByString:@";"]];
        if (index == NSNotFound) [lines insertObject:line atIndex:0]; else lines[index] = line;
    }
    NSDictionary *patch = @{@"recurrence_type":_type, @"recurrence_interval":@(MAX(interval,1)), @"recurrence":lines};
    NSMutableDictionary *task = [_original mutableCopy]; [task addEntriesFromDictionary:patch]; NSError *error = nil;
    if (![TaskRule vld:task error:&error]) { tu_err(self, error); return; }
    [self dismissViewControllerAnimated:YES completion:^{ if (self->_reply) self->_reply(patch); }];
}
@end

@implementation TaskCalendar {
    NSDate *_date;
    NSTimeZone *_zone;
    BOOL _timed, _deadline;
    UIDatePicker *_time;
    UISwitch *_toggle;
    UICalendarView *_calendar;
    UIButton *_repeatBtn;
    NSString *_repeat;
    void (^_action)(UIViewController *);
    void (^_reply)(NSDate *, BOOL, BOOL);
}
// 接收草稿时间和独立截止模式。
- (instancetype)initWithDate:(NSDate *)date timed:(BOOL)timed zone:(NSTimeZone *)zone deadline:(BOOL)deadline
    repeat:(NSString *)repeat action:(void (^)(UIViewController *))action reply:(void (^)(NSDate *, BOOL, BOOL))reply {
    self = [super init]; if (!self) return nil; _date = date; _timed = timed; _zone = zone; _deadline = deadline;
    _repeat = repeat; _action = [action copy]; _reply = [reply copy]; return self;
}
// 用系统月历、时刻控件及开关构建选择面板。
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.blackColor;
    _calendar = [UICalendarView new]; _calendar.accessibilityIdentifier = @"calendar.month";
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = _zone;
    _calendar.calendar = calendar; _calendar.timeZone = _zone; _calendar.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    UICalendarSelectionSingleDate *selection = [[UICalendarSelectionSingleDate alloc] initWithDelegate:self];
    _calendar.selectionBehavior = selection;
    NSDateComponents *parts = [calendar components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:_date];
    [selection setSelectedDate:parts animated:NO]; [_calendar setVisibleDateComponents:parts animated:NO];
    _time = [UIDatePicker new]; _time.datePickerMode = UIDatePickerModeTime; _time.preferredDatePickerStyle = UIDatePickerStyleCompact;
    _time.timeZone = _zone; _time.locale = _calendar.locale; _time.date = _date; _time.accessibilityIdentifier = @"calendar.time";
    _toggle = [UISwitch new]; _toggle.on = _timed; _toggle.onTintColor = lb_acnt(); _toggle.accessibilityIdentifier = @"calendar.timed";
    [_toggle addTarget:self action:@selector(tgl) forControlEvents:UIControlEventValueChanged]; _time.hidden = !_timed;
    UIButton *done = tu_btn(@"完成", nil, self, @selector(sv)); done.accessibilityIdentifier = @"calendar.done";
    UIButton *clear = tu_btn(_deadline ? @"清除截止" : @"清除日期及重复", @"close", self, @selector(clr)); clear.accessibilityIdentifier = @"calendar.clear";
    _repeatBtn = tu_btn(_repeat ?: @"不重复", @"repeat", self, @selector(rpt)); _repeatBtn.hidden = _deadline;
    _repeatBtn.enabled = _action != nil;
    _repeatBtn.accessibilityIdentifier = @"calendar.repeat";
    UIStackView *header = tu_row(_deadline ? @"截止日期" : @"日期和时间",done);
    tu_form(self, tu_stk(@[header,_calendar,tu_row(@"设置时间",_toggle),_time,_repeatBtn,clear]), @"calendar.form");
}
// 同步当前草稿的重复功能标签。
- (void)rptName:(NSString *)name { _repeat = name; [_repeatBtn setTitle:name forState:UIControlStateNormal]; }
// 切换独立时刻输入。
- (void)tgl { _time.hidden = !_toggle.on; }
// 接收系统月历选中的当地日期。
- (void)dateSelection:(UICalendarSelectionSingleDate *)selection didSelectDate:(NSDateComponents *)parts {
    (void)selection; if (parts) _date = [_calendar.calendar dateFromComponents:parts];
}
// 保持始终有一项有效日期选择。
- (BOOL)dateSelection:(UICalendarSelectionSingleDate *)selection canSelectDate:(NSDateComponents *)parts { (void)selection; return parts != nil; }
// 打开独立的重复面板。
- (void)rpt { if (_reply) _reply([self dt],_toggle.on,NO); if (_action) _action(self); }
// 将选中的日期与独立时刻合成为绝对时间。
- (NSDate *)dt {
    NSDateComponents *clock = [_calendar.calendar components:NSCalendarUnitHour|NSCalendarUnitMinute fromDate:_time.date];
    NSDate *date = [_calendar.calendar startOfDayForDate:_date];
    return _toggle.on ? [_calendar.calendar dateBySettingHour:clock.hour minute:clock.minute second:0 ofDate:date options:0] : date;
}
// 返回当地日期和可选时刻，不直接写数据库。
- (void)sv {
    NSDate *date = [self dt];
    [self dismissViewControllerAnimated:YES completion:^{ if (self->_reply) self->_reply(date,self->_toggle.on,NO); }];
}
// 明确清除日期并回传用户意图。
- (void)clr { [self dismissViewControllerAnimated:YES completion:^{ if (self->_reply) self->_reply(nil,NO,YES); }]; }
@end
