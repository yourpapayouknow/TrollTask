#pragma once
// 解析Markdown并保留原文；正式导入使用严格模板。
@interface TaskRoutineImport : NSObject
+ (NSString *)template;
+ (NSDictionary *)load:(NSString *)text source:(NSString *)source anchor:(NSDate *)anchor zone:(NSString *)zone error:(NSError **)error;
+ (NSDictionary *)parse:(NSString *)text source:(NSString *)source anchor:(NSDate *)anchor zone:(NSString *)zone error:(NSError **)error;
// 固化结构化常律模板，验证七天区间并从下一未来时段开始。
+ (NSDictionary *)formal:(TaskStore *)store document:(NSDictionary *)document anchor:(NSDate *)anchor zone:(NSString *)zone error:(NSError **)error;
@end

// 所有常律类型使用同一互斥校验，不写入数据库。
@interface TaskRoutineCheck : NSObject
+ (NSArray *)check:(NSArray *)tasks against:(NSArray *)peers at:(NSTimeInterval)stamp error:(NSError **)error;
@end

// 只读常律触发日期及五项分组。
@interface TaskRoutineView : NSObject
+ (NSArray *)sections:(NSArray *)days;
@end
