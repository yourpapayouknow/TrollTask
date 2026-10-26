#pragma once
@class TaskReminder;
// 将待办展示交给Swift，保留已有系统窗口宿主。
@interface TTTaskHUD : UIViewController
@property(nonatomic, strong) TaskReminder *reminder;
@property(nonatomic, copy) void (^windowMode)(NSInteger mode);
@property(nonatomic, readonly) NSInteger mode;
@property(nonatomic, readonly) NSDictionary *testOccurrence;
@property(nonatomic) BOOL globalCapture;
#ifdef LB_UI_TEST
@property(nonatomic, copy) BOOL (^captureLaunch)(void);
- (NSDictionary *)signalState;
- (void)signalSample:(NSDictionary *)value;
- (void)signalAudio:(BOOL)value;
// 在隔离UIKit测试中核对原生采集整批交回。
- (void)capOpen:(NSDictionary *)request completion:(void (^)(NSArray *, NSString *))completion;
#endif
// 显示已核对的真实轮次及错误。
- (void)display:(NSDictionary *)alert error:(NSError *)error;
// 仅在没有真实提醒时显示手动预览。
- (void)preview;
// 停止计时、图片选择与全部展示资源。
- (void)stop;
// 接收系统图片选择结果并显示提交确认。
- (void)acceptImage:(UIImage *)image method:(NSString *)method occID:(NSString *)occID;
@end
