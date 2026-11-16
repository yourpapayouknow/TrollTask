#pragma once
// 集中声明上游原生UIKit触摸接口。
#import <IOKit/IOKitLib.h>
#include <mach/mach_time.h>
NS_ASSUME_NONNULL_BEGIN
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDNotification *IOHIDNotificationRef;
typedef struct __IOHIDService *IOHIDServiceRef;
typedef struct __GSEvent *GSEventRef;

//
//  IOHIDEvent+KIF.h
//  KIF
//
//  Created by Thomas Bonnin on 7/6/15.
//


typedef struct __IOHIDEvent * IOHIDEventRef;
IOHIDEventRef kif_IOHIDEventWithTouches(NSArray *touches) CF_RETURNS_RETAINED;

//
//  UITouch+Private.h
//  FakeTouch
//
//  Created by Watanabe Toshinori on 2/6/19.
//  Copyright © 2019 Watanabe Toshinori. All rights reserved.
//


@interface UITouch (Private)

- (void)setWindow:(UIWindow *)window;
- (void)setTapCount:(NSUInteger)count;
- (void)setView:(UIView *)view;
- (void)setIsTap:(BOOL)isTap;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(UITouchPhase)touchPhase;
- (void)setGestureView:(UIView *)view;
- (void)_setLocationInWindow:(CGPoint)location
               resetPrevious:(BOOL)resetPrevious;
- (void)_setIsFirstTouchForView:(BOOL)firstTouchForView;
- (void)_setIsTapToClick:(BOOL)isTapToClick;

- (void)_setHidEvent:(IOHIDEventRef)event;

@end

//
//  UITouch-KIFAdditions.h
//  KIF
//
//  Created by Eric Firestone on 5/20/11.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//


@interface UITouch (KIFAdditions)

- (instancetype)initAtPoint:(CGPoint)point
                   inWindow:(UIWindow *)window
                     onView:(UIView *)view;

- (void)setLocationInWindow:(CGPoint)location;
- (void)setPhaseAndUpdateTimestamp:(UITouchPhase)phase;

@end

//
//  UIEvent+Private.h
//  FakeTouch
//
//  Created by Watanabe Toshinori on 2/6/19.
//  Copyright © 2019 Watanabe Toshinori. All rights reserved.
//


@interface UIEvent (Private)
- (instancetype)_init;
- (void)_setHIDEvent:(IOHIDEventRef)event;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_clearTouches;
@end

//
//  TSEventFetcher.h
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//




@interface TSEventFetcher : NSObject
// 释放本进程的触摸路由资源。
+ (void)stop;
+ (NSInteger)receiveAXEventID:(NSInteger)pointId
           atGlobalCoordinate:(CGPoint)point
               withTouchPhase:(UITouchPhase)phase
                     inWindow:(UIWindow *)window
                       onView:(UIView *)view;
@end



NS_ASSUME_NONNULL_END
