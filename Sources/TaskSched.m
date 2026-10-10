#import "LBHead.h"

@implementation TaskSched {
    TaskStore *_store;
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    void (^_handler)(NSDictionary *, NSError *);
    NSArray *_alerts;
    NSDictionary *_active;
    long long _revision;
    int _token;
    BOOL _running;
    id _clockObserver;
    id _zoneObserver;
}

// 为单一调度队列创建后台服务。
- (instancetype)initStore:(TaskStore *)store handler:(void (^)(NSDictionary *, NSError *))handler {
    self = [super init];
    if (self) { _store = store; _handler = [handler copy]; _queue = dispatch_queue_create("com.iwmei.taskforiwmei.scheduler", DISPATCH_QUEUE_SERIAL); _token = -1; _revision = -1; }
    return self;
}

// 展示前再次核对数据库，防止排队的旧UI更新出现。
- (void)publish:(NSDictionary *)alert error:(NSError *)error {
    void (^handler)(NSDictionary *, NSError *) = _handler;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        TaskSched *self = weakSelf; if (!self) return;
        NSDictionary *output = alert;
        if (alert) {
            NSError *failure = nil;
            NSDictionary *snapshot = [self->_store snapshot:&failure], *task = nil, *occ = nil;
            for (NSDictionary *item in snapshot[@"tasks"]) if ([item[@"task_id"] isEqual:alert[@"task_id"]]) task = item;
            for (NSDictionary *item in snapshot[@"history"]) if ([item[@"occurrence_id"] isEqual:alert[@"occurrence_id"]]) occ = item;
            if (!task || !occ || [task[@"deleted"] boolValue] || ![task[@"status"] isEqual:@"needsAction"]
                || ![task[@"reminder_version"] isEqual:alert[@"generation"]] || ![occ[@"status"] isEqual:@"triggered"]) {
                handler(nil, failure); [self refresh]; return;
            }
            NSMutableDictionary *fresh = [alert mutableCopy]; fresh[@"task"] = task; output = fresh;
        }
        handler(output, error);
    });
}

// 从一致快照重建计时计划，数据库失败时清除旧计划。
- (void)reload {
    if (!_running) return;
    NSError *error = nil;
    NSDictionary *snapshot = [_store planAt:NSDate.date.timeIntervalSince1970 error:&error];
    if (!snapshot || error) { _revision = -1; _alerts = nil; _active = nil; [self publish:nil error:error]; return; }
    _revision = [snapshot[@"revision"] longLongValue];
    _alerts = snapshot[@"alerts"];
    NSDictionary *current = nil;
    if (_active) for (NSDictionary *item in _alerts) if ([item[@"occurrence_id"] isEqual:_active[@"occurrence_id"]]) { current = item; break; }
    if (_active && !current) { _active = nil; [self publish:nil error:nil]; }
    if (current) { _active = current; [self publish:current error:nil]; return; }
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (_alerts.count && [_alerts.firstObject[@"remind_at"] doubleValue] <= now) {
        NSDictionary *claimed = [_store claim:_alerts.firstObject revision:_revision at:now error:&error];
        if (claimed) { _active = claimed; _revision = [_store revision:nil]; [self publish:claimed error:nil]; }
        else if (error) { _revision = -1; _alerts = nil; [self publish:nil error:error]; }
        else [self refresh];
    }
}

// 监听Darwin变化并以修订号和到期核对补足通知合并。
- (BOOL)start:(NSError **)error {
    if (_running) return YES;
    __weak typeof(self) weakSelf = self;
    uint32_t status = notify_register_dispatch(_store.changeNote.UTF8String, &_token, _queue, ^(__unused int token) { [weakSelf reload]; });
    if (status != NOTIFY_STATUS_OK) {
        if (error) *error = [NSError errorWithDomain:@"com.iwmei.taskforiwmei.sync" code:status userInfo:@{NSLocalizedDescriptionKey: @"数据通知注册失败"}];
        return NO;
    }
    _running = YES;
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0), NSEC_PER_SEC, 10 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(_timer, ^{
        TaskSched *self = weakSelf; if (!self || !self->_running) return;
        long long revision = [self->_store revision:nil];
        if (revision != self->_revision || self->_revision < 0 || (!self->_active && self->_alerts.count
            && [self->_alerts.firstObject[@"remind_at"] doubleValue] <= NSDate.date.timeIntervalSince1970)) [self reload];
    });
    dispatch_resume(_timer);
    _clockObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSSystemClockDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { [weakSelf refresh]; }];
    _zoneObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSSystemTimeZoneDidChangeNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) { [weakSelf refresh]; }];
    [self refresh];
    return YES;
}

// 将重载串行送入调度队列。
- (void)refresh { dispatch_async(_queue, ^{ [self reload]; }); }

// 原子处理当前提醒并重新生成下一条计划。
- (void)act:(NSString *)action until:(NSNumber *)until occID:(NSString *)occID {
    dispatch_async(_queue, ^{
        NSError *error = nil;
        if (!self->_active || ![self->_active[@"occurrence_id"] isEqual:occID]) return;
        if ([self->_store actOcc:occID action:action until:until error:&error]) {
            self->_active = nil; [self publish:nil error:nil]; [self reload];
        } else [self publish:self->_active error:error];
    });
}

// 停止调度并解除所有观察者。
- (void)stop {
    dispatch_sync(_queue, ^{
        self->_running = NO;
        if (self->_timer) { dispatch_source_cancel(self->_timer); self->_timer = nil; }
        if (self->_token >= 0) { notify_cancel(self->_token); self->_token = -1; }
        self->_active = nil; self->_alerts = nil;
    });
    if (_clockObserver) [NSNotificationCenter.defaultCenter removeObserver:_clockObserver];
    if (_zoneObserver) [NSNotificationCenter.defaultCenter removeObserver:_zoneObserver];
    _clockObserver = nil; _zoneObserver = nil;
    [self publish:nil error:nil];
}

// 释放实例时解除后台资源。
- (void)dealloc {
    if (_timer) dispatch_source_cancel(_timer);
    if (_token >= 0) notify_cancel(_token);
    if (_clockObserver) [NSNotificationCenter.defaultCenter removeObserver:_clockObserver];
    if (_zoneObserver) [NSNotificationCenter.defaultCenter removeObserver:_zoneObserver];
}
@end
