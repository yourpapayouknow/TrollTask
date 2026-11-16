#pragma once
// 使用原生RFC5545实现校验和展开重复规则。
@interface TaskRule : NSObject
// 检查完整规则，非法或不支持的规则明确报错。
+ (BOOL)vld:(NSDictionary *)task error:(NSError **)error;
// 返回给定时刻前后最近的轮次和接下来的轮次。
+ (NSArray *)cycles:(NSDictionary *)task at:(NSTimeInterval)stamp limit:(NSUInteger)limit error:(NSError **)error;
// 将某轮计划日期转换为该轮独立截止提醒时刻。
+ (NSNumber *)ddl:(NSDictionary *)task cycle:(NSNumber *)cycle;
// 结合完成及延后记录生成当前有效提醒。
+ (NSArray *)alerts:(NSDictionary *)task history:(NSArray *)history at:(NSTimeInterval)stamp error:(NSError **)error;
@end
