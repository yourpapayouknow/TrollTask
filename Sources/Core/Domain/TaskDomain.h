#pragma once
// 读取原任务树和原子提交拆分草稿。
@interface TaskDivision : NSObject
+ (NSDictionary *)draft:(TaskStore *)store task:(NSString *)task error:(NSError **)error;
+ (NSDictionary *)apply:(TaskStore *)store task:(NSString *)task parts:(NSArray *)parts expected:(NSDictionary *)expected error:(NSError **)error;
@end
// 调用兼容接口只生成建议，任务保存走原TaskStore事务。
@interface TaskAI : NSObject
+ (NSURLSessionDataTask *)gen:(NSDictionary *)input config:(NSDictionary *)config completion:(void (^)(NSDictionary *, NSError *))completion;
@end

// 统一创建评估和重复提交保护。
@interface TaskIntake : NSObject
+ (NSDictionary *)context:(TaskStore *)store fields:(NSDictionary *)fields parts:(NSArray *)parts at:(double)at error:(NSError **)error;
+ (NSDictionary *)verdict:(NSDictionary *)context estimate:(NSDictionary *)estimate effort:(double)effort ddl:(BOOL)ddl error:(NSError **)error;
+ (NSDictionary *)commit:(TaskStore *)store context:(NSDictionary *)context estimate:(NSDictionary *)estimate effort:(double)effort ddl:(BOOL)ddl at:(double)at error:(NSError **)error;
+ (NSDictionary *)review:(TaskStore *)store task:(NSString *)task error:(NSError **)error;
@end

// 当天执行清单复用真实任务与轮次。
@interface TaskToday : NSObject
+ (NSString *)note:(TaskStore *)store;
+ (NSDictionary *)reminder:(TaskStore *)store task:(NSDictionary *)task at:(double)at error:(NSError **)error;
+ (NSArray *)rows:(TaskStore *)store at:(double)at zone:(NSString *)zone error:(NSError **)error;
+ (NSInteger)focus:(NSArray *)pending at:(double)at;
@end
