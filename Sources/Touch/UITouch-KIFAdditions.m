#import "LBHead.h"
//
//  UITouch-KIFAdditions.m
//  KIF
//
//  Created by Eric Firestone on 5/20/11.
//  Licensed to Square, Inc. under one or more contributor license agreements.
//


@implementation UITouch (KIFAdditions)

- (instancetype)initAtPoint:(CGPoint)point
                   inWindow:(UIWindow *)window
                     onView:(UIView *)view
{
  self = [super init];
  if (self == nil)
    return nil;

  // Create a fake tap touch
  [self setWindow:window];  // Wipes out some values. Needs to be first.
  // UIKit按钮的原生点击识别需要有效点击次数。
  [self setTapCount:1];
  [self _setLocationInWindow:point resetPrevious:YES];

  UIView *hitTestView = view;

  [self setView:hitTestView];
  [self setPhase:UITouchPhaseBegan];
  [self _setIsFirstTouchForView:YES];
  if (![[NSProcessInfo processInfo] isiOSAppOnMac] &&
      ![[NSProcessInfo processInfo] isMacCatalystApp])
  {
    [self _setIsTapToClick:NO];
  }
  else
  {
    [self setIsTap:NO];
  }

  [self setTimestamp:[[NSProcessInfo processInfo] systemUptime]];

  if ([self respondsToSelector:@selector(setGestureView:)])
    [self setGestureView:hitTestView];

  [self kif_setHidEvent];
  return self;
}

- (void)setLocationInWindow:(CGPoint)location
{
  [self setTimestamp:[[NSProcessInfo processInfo] systemUptime]];
  [self _setLocationInWindow:location resetPrevious:NO];
}

- (void)setPhaseAndUpdateTimestamp:(UITouchPhase)phase
{
  [self setTimestamp:[[NSProcessInfo processInfo] systemUptime]];
  [self setPhase:phase];
}

- (void)kif_setHidEvent
{
  IOHIDEventRef event = kif_IOHIDEventWithTouches(@[ self ]);
  [self _setHidEvent:event];
  CFRelease(event);
}

@end
