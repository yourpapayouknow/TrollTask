#pragma once
// 为HUD、CLI和宿主验收声明同一Swift绝对时间调度器。
@interface TaskScheduler : NSObject
@property(nonatomic, readonly, copy) NSDate *nextFireAt;
// 注入共享存储与主线程展示回调。
- (instancetype)initStore:(TaskStore *)store handler:(void (^)(NSDictionary *, NSError *))handler;
// 注册变化通知并读取最近的绝对时刻。
- (BOOL)start:(NSError **)error;
// 撤销计时和观察者。
- (void)stop;
// 打断原计划并合并重读请求。
- (void)refresh;
// 原子处理当前展示轮次并立即调度下一条。
- (void)act:(NSString *)action until:(NSNumber *)until occID:(NSString *)occID;
// 提交持久化边栏状态。
- (void)hold:(NSString *)mode occID:(NSString *)occID;
// 提前展开仍然有效的边栏轮次。
- (void)resumeOcc:(NSString *)occID;
// 提交本次打卡证据。
- (void)check:(NSString *)occID method:(NSString *)method image:(NSData *)image;
// 通过同一事务提交最多六个附件。
- (void)check:(NSString *)occID attachments:(NSArray<NSDictionary *> *)attachments;
@end
