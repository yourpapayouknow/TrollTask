#pragma once
@class TaskStore;

// 为原生Objective-C验收入口声明Swift界面类型。

// 保留、读取并在设置页清空最近运行日志。
@interface TaskLog : NSObject
+ (void)write:(NSString *)text;
+ (void)clear;
+ (NSArray<NSString *> *)lines;
@end

// 编辑完整重复属性，保留未修改的例外和日期集合。
@interface TaskRepeat : UIViewController <UIPickerViewDataSource, UIPickerViewDelegate>
- (instancetype)initWithFields:(NSDictionary *)fields reply:(void (^)(NSDictionary *))reply;
@end

// 用iOS16系统月历选择独立日期和时刻。
API_AVAILABLE(ios(16.0))
@interface TaskCalendar : UIViewController <UICalendarSelectionSingleDateDelegate>
- (instancetype)initWithDate:(NSDate *)date timed:(BOOL)timed zone:(NSTimeZone *)zone deadline:(BOOL)deadline
    repeat:(NSString *)repeat action:(void (^)(UIViewController *))action reply:(void (^)(NSDate *, BOOL, BOOL, NSDictionary *))reply;
- (void)rptName:(NSString *)name;
@end

// 展示共享数据库中的轻量待办列表。
@interface TaskHome : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, copy) void (^onStore)(TaskStore *);
- (instancetype)initWithStore:(TaskStore *)store settings:(void (^)(UINavigationController *))settings;
- (void)rfrsh;
@end

// 展示只读任务详情，修改从编辑进入创建管道第二页。
@interface TaskDetailScreen : UIViewController
- (instancetype)initWithStore:(TaskStore *)store task:(NSDictionary *)task saved:(void (^)(void))saved;
@end

// 快捷草稿与常律模板编辑，普通任务详情由只读页承担。
@interface TaskEdit : UIViewController <UITextViewDelegate, UITextFieldDelegate>
- (instancetype)initWithStore:(TaskStore *)store task:(NSDictionary *)task saved:(void (^)(void))saved;
// 用同一编辑器呈现快捷草稿或子任务。
- (instancetype)initWithStore:(TaskStore *)store task:(NSDictionary *)task draft:(NSDictionary *)draft quick:(BOOL)quick saved:(void (^)(void))saved;
@end
