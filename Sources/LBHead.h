#pragma once
#import <Foundation/Foundation.h>
#if !defined(LB_HOST_TEST) || defined(LB_UI_TEST)
#import <UIKit/UIKit.h>
#endif

#include <CoreFoundation/CoreFoundation.h>
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
#define LB_LOCK_PATH lb_tstlock
#else
#define LB_PREF_PATH @"/var/mobile/Library/Preferences/com.iwmei.taskforiwmei.plist"
#define LB_LOCK_PATH "/var/tmp/com.iwmei.taskforiwmei.hud.lock"
#endif
#define LB_CFG_NOTE "com.iwmei.taskforiwmei.config"
#define LB_STOP_NOTE "com.iwmei.taskforiwmei.stop"
#define LB_TEST_NOTE "com.iwmei.taskforiwmei.preview"
#define LB_READY_NOTE "com.iwmei.taskforiwmei.ready"

extern char **environ;

#ifndef LB_HOST_TEST
@interface UIApplication (LBPrivate)
- (void)_accessibilityInit;
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

@interface LBAppDel : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@interface LBSetCtl : UIViewController
@end

@interface LBHudApp : UIApplication
@end

@interface LBHudDel : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@interface LBHudWin : UIWindow
@end

@interface LBHudCtl : UIViewController
@property(nonatomic, weak) LBHudWin *hudWindow;
- (void)startMon;
@end

@interface AXEventRepresentation : NSObject
- (BOOL)isTouchDown;
- (BOOL)isLift;
- (BOOL)isCancel;
- (BOOL)isInRangeLift;
- (CGPoint)location;
+ (instancetype)representationWithHIDEvent:(void *)event hidStreamIdentifier:(NSString *)identifier;
@end

// 启动独立系统HUD进程。
BOOL lb_spawn(void);

// 运行全局 HUD 进程。
int lb_hudmain(void);

#endif

#if !defined(LB_HOST_TEST) || defined(LB_UI_TEST)
// 创建统一外观的功能按钮。
UIButton *lb_mkbtn(NSString *title, id target, SEL action);
// 读取统一OLED强调色和MingCute模板图标。
UIColor *lb_acnt(void);
UIImage *lb_icon(NSString *name);
#import "TaskUI.h"
#endif

// 读取共享配置文件。
NSDictionary *lb_ldcfg(void);

// 保存共享配置文件。
BOOL lb_svcfg(NSDictionary *config);

// 获取HUD单实例锁。
int lb_lckhud(void);

// 判断从按钮内按下并在按钮内结束的触摸。
BOOL lb_btntap(BOOL *active, BOOL inside, BOOL down);

// 截取界面中允许显示的13个完整字形。
NSString *lb_shrt(NSString *text);

// 集中声明待办存储模块。
#import "TaskStore.h"
#import "TaskRule.h"
#import "TaskSched.h"
