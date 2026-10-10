#pragma once
// 维护真实后台计时并在触发前核对最新提交数据。
@interface TaskSched : NSObject
// 使用当前进程的存储连接与主线程提醒回调。
- (instancetype)initStore:(TaskStore *)store handler:(void (^)(NSDictionary *, NSError *))handler;
// 注册数据变化和系统时间变化，开始调度。
- (BOOL)start:(NSError **)error;
// 取消通知、计时器及当前显示。
- (void)stop;
// 请求立即重读数据库。
- (void)refresh;
// 在后台事务处理当前提醒。
- (void)act:(NSString *)action until:(NSNumber *)until occID:(NSString *)occID;
@end
