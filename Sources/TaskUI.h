#pragma once
@class TaskStore;

// 为原生Objective-C验收入口声明Swift界面类型。

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

// 编辑任务基础字段并保留未呈现的数据。
@interface TaskEdit : UIViewController <UITextViewDelegate, UITextFieldDelegate>
- (instancetype)initWithStore:(TaskStore *)store task:(NSDictionary *)task saved:(void (^)(void))saved;
// 用同一编辑器呈现快捷草稿或子任务。
- (instancetype)initWithStore:(TaskStore *)store task:(NSDictionary *)task draft:(NSDictionary *)draft quick:(BOOL)quick saved:(void (^)(void))saved;
@end

// 为原生验收公开草稿页面，不暴露网络密钥。
@interface TaskAssistantScreen : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate>
- (instancetype)initWithStore:(TaskStore *)store task:(NSString *)task;
@end
