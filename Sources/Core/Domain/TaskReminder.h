#pragma once
// 以同一Swift核心持有独立进程的存储、调度和单实例锁。
@interface TaskReminder : NSObject
@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly, copy) NSDate *nextFireAt;
// 注入已有HUD呈现、资源清理和进程退出入口。
- (instancetype)initAt:(NSString *)path handler:(void (^)(NSDictionary *, NSError *))handler cleanup:(void (^)(void))cleanup finish:(void (^)(BOOL))finish;
// 在私有窗口初始化前获取锁并打开自己的存储。
- (BOOL)open:(NSError **)error;
// 在窗口就绪后启动调度并发布服务就绪。
- (BOOL)start:(NSError **)error;
// 按顺序停止调度、关闭存储、释放窗口及单实例锁。
- (void)stop;
// 转交当前轮次的处理动作。
- (void)act:(NSString *)action until:(NSNumber *)until occID:(NSString *)occID;
// 读取当前服务的任务与提醒快照。
- (NSDictionary *)snapshot:(NSError **)error;
// 收起当前轮次并保持唯一延期次数。
- (void)hold:(NSString *)mode occID:(NSString *)occID;
// 主动展开当前边栏提醒。
- (void)resumeOcc:(NSString *)occID;
// 通过同一事务提交最多六个附件。
- (void)check:(NSString *)occID attachments:(NSArray<NSDictionary *> *)attachments;
@end
