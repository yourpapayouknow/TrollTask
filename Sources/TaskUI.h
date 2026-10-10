#pragma once
@class TaskStore;

// 共用原生表单、主题按钮及面板布局。
UILabel *tu_lbl(NSString *text);
UIStackView *tu_stk(NSArray<UIView *> *views);
UIStackView *tu_row(NSString *title, UIView *control);
UIButton *tu_btn(NSString *title, NSString *icon, id target, SEL action);
UIScrollView *tu_form(UIViewController *parent, UIStackView *fields, NSString *identifier);
void tu_sheet(UIViewController *parent, UIViewController *content);
void tu_err(UIViewController *view, NSError *error);

// 编辑完整重复属性，保留未修改的例外和日期集合。
@interface TaskRepeat : UIViewController <UITextViewDelegate>
- (instancetype)initWithFields:(NSDictionary *)fields reply:(void (^)(NSDictionary *))reply;
@end

// 用iOS16系统月历选择独立日期和时刻。
API_AVAILABLE(ios(16.0))
@interface TaskCalendar : UIViewController <UICalendarSelectionSingleDateDelegate>
- (instancetype)initWithDate:(NSDate *)date timed:(BOOL)timed zone:(NSTimeZone *)zone deadline:(BOOL)deadline
    repeat:(NSString *)repeat action:(void (^)(UIViewController *))action reply:(void (^)(NSDate *, BOOL, BOOL))reply;
- (void)rptName:(NSString *)name;
@end

// 展示共享数据库中的轻量待办列表。
@interface TaskHome : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (instancetype)initWithStore:(TaskStore *)store settings:(void (^)(UINavigationController *))settings;
- (void)rfrsh;
@end

// 编辑任务基础字段并保留未呈现的数据。
@interface TaskEdit : UIViewController <UITextViewDelegate>
- (instancetype)initWithStore:(TaskStore *)store task:(NSDictionary *)task saved:(void (^)(void))saved;
// 用同一编辑器呈现快捷草稿或子任务。
- (instancetype)initWithStore:(TaskStore *)store task:(NSDictionary *)task draft:(NSDictionary *)draft quick:(BOOL)quick saved:(void (^)(void))saved;
@end
