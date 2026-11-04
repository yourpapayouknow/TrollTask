#pragma once
// 将Markdown时间表解析为结构化禁用草稿。
@interface TaskRoutineImport : NSObject
+ (NSDictionary *)parse:(NSString *)text source:(NSString *)source anchor:(NSDate *)anchor zone:(NSString *)zone error:(NSError **)error;
// 固化结构化周表，验证七天区间并从下一未来时段开始。
+ (NSDictionary *)formal:(TaskStore *)store document:(NSDictionary *)document anchor:(NSDate *)anchor zone:(NSString *)zone error:(NSError **)error;
@end

// 只读常律触发日期及五项分组。
@interface TaskRoutineView : NSObject
+ (NSArray *)sections:(NSArray *)days;
@end
