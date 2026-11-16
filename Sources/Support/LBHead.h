#pragma once
#import <Foundation/Foundation.h>
#if !defined(LB_HOST_TEST) || defined(LB_UI_TEST)
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#endif

#ifdef LB_UI_TEST
#import <AVFAudio/AVFAudio.h>
#import "Support/Touch/head.h"
// 在原生模拟器验收同一UIKit触摸路由。
@interface UIApplication (LBTouchSPI)
- (UIEvent *)_touchesEvent;
@end
#endif

#include <CoreFoundation/CoreFoundation.h>
#import <ImageIO/ImageIO.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <mach-o/dyld.h>
#include <notify.h>
#include "ical.h"
#include <objc/message.h>
#include <objc/runtime.h>
#include <pwd.h>
#include <signal.h>
#include <spawn.h>
#include <sqlite3.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef LB_HOST_TEST
#include <assert.h>
extern NSString *lb_tstpath;
extern const char *lb_tstlock;
#define LB_PREF_PATH lb_tstpath
#define LB_OLD_PREF_PATH [lb_tstpath stringByAppendingString:@".legacy"]
#define LB_LOCK_PATH lb_tstlock
#else
#define LB_PREF_PATH @"/var/mobile/Library/Preferences/com.iwmei.taskforiwmei.hudservice.plist"
#define LB_OLD_PREF_PATH @"/var/mobile/Library/Preferences/com.iwmei.taskforiwmei.plist"
#define LB_LOCK_PATH "/var/tmp/com.iwmei.taskforiwmei.hud.lock"
#endif
#define LB_CFG_NOTE "com.iwmei.taskforiwmei.config"
#define LB_STOP_NOTE "com.iwmei.taskforiwmei.stop"
#define LB_TEST_NOTE "com.iwmei.taskforiwmei.preview"
#define LB_READY_NOTE "com.iwmei.taskforiwmei.ready"

extern char **environ;

// 系统通知在隔离测试中使用工程命名空间。
#ifdef LB_HOST_TEST
#define TS_CLOCK_SET "com.iwmei.taskforiwmei.test.clock"
#define TS_TIME_ZONE "com.iwmei.taskforiwmei.test.timezone"
#define TS_DISPLAY_ON "com.iwmei.taskforiwmei.test.display"
#define TS_SB_LAUNCH "com.iwmei.taskforiwmei.test.springboard"
#else
#define TS_CLOCK_SET "com.apple.system.clock_set"
#define TS_TIME_ZONE "com.apple.system.timezone"
#define TS_DISPLAY_ON "com.apple.iokit.hid.displayStatus"
#define TS_SB_LAUNCH "SBSpringBoardDidLaunchNotification"
#endif

#if !defined(LB_HOST_TEST) || defined(LB_UI_TEST)
// 声明现成原生应用激活入口。
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)identifier;
@end
// 按需激活已安装的采集App。
BOOL lb_opnapp(void);
#endif

#ifndef LB_HOST_TEST
#import "Support/Touch/head.h"
@interface UIApplication (LBPrivate)
// 进入UIKit原生事件运行循环。
- (void)_run;
- (void)_accessibilityInit;
- (UIEvent *)_touchesEvent;
- (void)__completeAndRunAsPlugin;
@end

@interface UIWindow (LBPrivate)
- (unsigned int)_contextId;
- (id)_boundContext;
@end

@interface NSObject (LBContext)
- (void)setSecure:(BOOL)secure;
@end

@interface LBApp : UIApplication
@end

#ifndef TT_SWIFT_BRIDGE
@interface LBAppDel : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@interface LBSetCtl : UIViewController
@end
#endif

@interface LBHudApp : UIApplication
@end

@interface LBHudDel : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
- (void)stp;
@end

@interface LBHudWin : UIWindow
@end

@interface LBHudCtl : UIViewController
@property(nonatomic, weak) LBHudWin *hudWindow;
- (void)startMon;
@end

@interface AXEventRepresentation : NSObject
- (BOOL)isTouchDown;
- (BOOL)isMove;
- (id)handInfo;
- (BOOL)isLift;
- (BOOL)isCancel;
- (BOOL)isInRangeLift;
- (CGPoint)location;
+ (instancetype)representationWithHIDEvent:(void *)event hidStreamIdentifier:(NSString *)identifier;
@end

// 声明上游已使用的触摸标识与前台方向接口。
@interface NSObject (LBHudSPI)
- (NSArray *)paths;
- (NSInteger)pathIdentity;
@end

// 集中声明上游前台方向观察者的真实类型。
@interface FBSOrientationUpdate : NSObject
- (long long)orientation;
- (double)duration;
@end
@interface FBSOrientationObserver : NSObject
- (long long)activeInterfaceOrientation;
- (void)setHandler:(void (^)(FBSOrientationUpdate *))handler;
- (void)invalidate;
@end

// 运行TaskReminder独立进程及其系统HUD。
int lb_hudmain(int argc, char **argv);

#endif

#if !defined(LB_HOST_TEST) || defined(LB_UI_TEST)
// 创建统一外观的功能按钮。
UIButton *lb_mkbtn(NSString *title, id target, SEL action);
// 读取统一大字与动态字体。
UIFont *lb_fnt(UIFontTextStyle style, UITraitCollection *traits);
// 读取统一OLED强调色和MingCute模板图标。
UIColor *lb_acnt(void);
UIImage *lb_icon(NSString *name);
// 读取前台方向的统一旋转角。
CGFloat lb_hudang(UIInterfaceOrientation orientation);
// 将安全区右边栏投影到系统窗口物理坐标。
CGRect lb_hudfrm(CGRect screen, UIEdgeInsets insets, UIInterfaceOrientation orientation);
#ifndef TT_SWIFT_BRIDGE
#import "Support/TaskUI.h"
#import "Features/HUD/TaskHUD.h"
#endif
#endif

// 读取共享配置文件。
NSDictionary *lb_ldcfg(void);

// 保存共享配置文件。
BOOL lb_svcfg(NSDictionary *config);

// 获取HUD单实例锁。
int lb_lckhud(void);

// 检查既有提醒服务的真实锁状态。
BOOL lb_svcup(void);
// 发布轻量诊断状态，读取时必须核对真实服务锁和PID。
void lb_svstat(NSString *state, NSNumber *next);
NSDictionary *lb_rdstat(void);
// 使用现有persona方式幂等启动提醒服务。
BOOL lb_spawn(void);

// 判断从按钮内按下并在按钮内结束的触摸。
BOOL lb_btntap(BOOL *active, BOOL inside, BOOL down);

// 截取界面中允许显示的13个完整字形。
NSString *lb_shrt(NSString *text);

// 集中声明待办存储模块。
#import "Core/Data/TaskStore.h"
#import "Core/Domain/TaskRule.h"
#ifndef TT_SWIFT_BRIDGE
#import "Core/Domain/TaskRoutine.h"
#import "Core/Domain/TaskDomain.h"
#import "Core/Domain/TaskTimeMap.h"
#endif
#ifndef TT_SWIFT_BRIDGE
#import "Core/Domain/TaskScheduler.h"
#import "Core/Domain/TaskReminder.h"
#endif
