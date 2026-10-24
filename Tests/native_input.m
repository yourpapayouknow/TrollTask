// 复用触摸回归：app为普通应用，loop为旧启动，full为修正后的独立启动。
#define main ni_apmn
#include "test_ui.m"
#undef main

// 声明上游独立宿主已使用的无参启动入口。
@interface UIApplication (NIHost)
- (void)_accessibilityInit;
- (void)__completeAndRunAsPlugin;
- (void)_run;
@end

static NSString *ni_md;
static id ni_dl;
static __weak UIWindow *ni_tw;

// 记录原生减速计算实际收到的帧时间，不修改参数或结果。
static void ni_clk(void) {
    SEL selector = NSSelectorFromString(@"_smoothScrollWithUpdateTime:");
    Method method = class_getInstanceMethod(UIScrollView.class,selector);
    if (!method) return;
    IMP original = method_getImplementation(method);
    fprintf(stderr,"NATIVE_INPUT update.signature:%s\n",method_getTypeEncoding(method));
    IMP trace = imp_implementationWithBlock(^(UIScrollView *scroll,double time){
        static NSUInteger samples;
        BOOL record = scroll.decelerating && samples<12;
        CGFloat before = scroll.contentOffset.y;
        ((void (*)(id,SEL,double))original)(scroll,selector,time);
        if (record) {
            fprintf(stderr,"NATIVE_INPUT update time:%.6f before:%.1f after:%.1f\n",time,before,scroll.contentOffset.y);
            samples++;
        }
    });
    method_setImplementation(method,trace);
}

// 找到既有回归夹具中的滚动控件。
static UIScrollView *ni_sc(UIView *view) {
    if ([view isKindOfClass:UIScrollView.class] && CGRectEqualToRect(view.frame,CGRectMake(40,160,240,300))) return (UIScrollView *)view;
    for (UIView *child in view.subviews) { UIScrollView *scroll = ni_sc(child); if (scroll) return scroll; }
    return nil;
}

// 只读记录UIKit自身的滚动时钟与当前运行模式。
static void ni_smp(UIApplication *app) {
    static NSUInteger samples;
    if (samples>=16) return;
    (void)app;
    for (UIWindow *window in ni_tw ? @[ni_tw] : @[]) {
        UIScrollView *scroll = ni_sc(window.rootViewController.view);
        if (!scroll || window.hidden) continue;
        Ivar field = class_getInstanceVariable(UIScrollView.class,"_scrollHeartbeat");
        id value = field ? object_getIvar(scroll,field) : nil;
        CADisplayLink *link = [value isKindOfClass:CADisplayLink.class] ? value : nil;
        NSString *mode = CFBridgingRelease(CFRunLoopCopyCurrentMode(CFRunLoopGetMain()));
        fprintf(stderr,"NATIVE_INPUT clock offset:%.1f dragging:%d decelerating:%d link:%s paused:%d time:%.6f mode:%s\n",
            scroll.contentOffset.y,scroll.dragging,scroll.decelerating,NSStringFromClass([value class]).UTF8String,link.paused,link.timestamp,mode.UTF8String);
        samples++; return;
    }
}

// 为独立插件接入既有上游输入源。
@interface NIApp : UIApplication
@end
@implementation NIApp
// 对照完整原生准备流程后继续使用独立插件运行方式。
- (void)_run {
    fprintf(stderr,"NATIVE_INPUT run mode:%s\n",ni_md.UTF8String);
    if ([ni_md isEqual:@"full"]) {
        [self _accessibilityInit];
        // 等原生运行入口安装事件源后，再完成独立插件的启动回调。
        dispatch_async(dispatch_get_main_queue(), ^{ [self __completeAndRunAsPlugin]; });
        [super _run];
        return;
    }
    [super _run];
}

// 只记录实际事件窗口，转发仍交给UIApplication。
- (void)sendEvent:(UIEvent *)event {
    UIWindow *window = event.allTouches.anyObject.window;
    if (window) ni_tw = window;
    [super sendEvent:event];
}
@end

// 限定验证进程的最长运行时间。
static void ni_tmo(int number) {
    (void)number;
    static const char message[] = "NATIVE_INPUT timeout\n";
    write(STDERR_FILENO,message,sizeof(message)-1);
    _exit(124);
}

// 只建立原生输入夹具，不启动任务服务或数据库。
@interface NIDel : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) NSTimer *trace;
@end
@implementation NIDel
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)options;
    ut_checks = [NSMutableArray new];
    ut_nav = [[UINavigationController alloc] initWithRootViewController:[UIViewController new]];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = ut_nav;
    [self.window makeKeyAndVisible];
    alarm(30);
    fprintf(stderr,"NATIVE_INPUT launched mode:%s state:%ld scenes:%lu uptime:%.3f\n",ni_md.UTF8String,(long)app.applicationState,(unsigned long)app.connectedScenes.count,NSProcessInfo.processInfo.systemUptime);
    self.trace = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(__unused NSTimer *timer){ ni_smp(app); }];
    [NSRunLoop.mainRunLoop addTimer:self.trace forMode:NSRunLoopCommonModes];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            BOOL passed = YES;
            NSString *failure = @"";
            @try {
                fprintf(stderr,"NATIVE_INPUT empty.begin\n"); ut_evc(NO);
                fprintf(stderr,"NATIVE_INPUT cached.begin\n"); ut_evc(YES);
            }
            @catch (NSException *exception) { passed = NO; failure = exception.reason; }
            __block NSDictionary *report;
            ut_ui(^{
                report = @{@"mode":ni_md,@"passed":@(passed),@"failure":failure,@"checks":ut_checks,
                    @"applicationState":@(app.applicationState),@"scenes":@(app.connectedScenes.count),@"runtime":UIDevice.currentDevice.systemVersion};
            });
            NSData *data = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
            fprintf(stdout,"NATIVE_INPUT %s\n",[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] UTF8String]);
            fflush(stdout);
            exit(passed ? 0 : 1);
        }
    });
    return YES;
}
@end

// 使用同一夹具和事件适配，仅切换宿主启动入口。
int main(int argc,char **argv) {
    @autoreleasepool {
        ni_md = argc>1 && strncmp(argv[1],"--",2)==0 ? [NSString stringWithUTF8String:argv[1]+2] : @"app";
        if (![@[@"app",@"loop",@"full"] containsObject:ni_md]) return 64;
        fprintf(stderr,"NATIVE_INPUT main mode:%s pid:%d uptime:%.3f\n",ni_md.UTF8String,getpid(),NSProcessInfo.processInfo.systemUptime);
        signal(SIGALRM,ni_tmo); alarm(argc>2 && strcmp(argv[2],"--debug")==0 ? 45 : 20);
        ni_clk();
        if (![ni_md isEqual:@"loop"]) return UIApplicationMain(argc,argv,NSStringFromClass(NIApp.class),NSStringFromClass(NIDel.class));
        dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices",RTLD_NOW|RTLD_GLOBAL);
        dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",RTLD_NOW|RTLD_GLOBAL);
        void (*gs)(void) = dlsym(RTLD_DEFAULT,"GSInitialize");
        void (*bks)(void) = dlsym(RTLD_DEFAULT,"BKSDisplayServicesStart");
        void (*ui)(void) = dlsym(RTLD_DEFAULT,"UIApplicationInitialize");
        void (*singleton)(Class) = dlsym(RTLD_DEFAULT,"UIApplicationInstantiateSingleton");
        void (*events)(int) = dlsym(RTLD_DEFAULT,"GSEventInitialize");
        void (*push)(CFStringRef) = dlsym(RTLD_DEFAULT,"GSEventPushRunLoopMode");
        void (*run)(Boolean) = dlsym(RTLD_DEFAULT,"GSEventRunModal");
        if (!gs || !bks || !ui || !singleton || !events || !push || !run) {
            fprintf(stderr,"NATIVE_INPUT missing startup symbol\n"); return 3;
        }
        [UIScreen initialize]; CFRunLoopGetCurrent();
        gs(); bks(); ui(); singleton(NIApp.class);
        UIApplication *app = UIApplication.sharedApplication;
        ni_dl = [NIDel new]; app.delegate = ni_dl;
        [app _accessibilityInit];
        events(0); push(kCFRunLoopDefaultMode);
        [app __completeAndRunAsPlugin];
        CFRunLoopRun(); run(false);
        return 0;
    }
}
