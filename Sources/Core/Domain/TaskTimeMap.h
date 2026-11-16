#pragma once
// 共享宿主回归与原生时间轴的连续时间映射。
@interface TaskTimeMap : NSObject
+ (NSDictionary *)map:(NSDictionary *)plan width:(double)width scale:(double)scale error:(NSError **)error;
@end
