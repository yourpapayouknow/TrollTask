#import "LBHead.h"
//
//  TSEventFetcher.mm
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//


static NSArray *_safeTouchAry = nil;
static NSMutableDictionary<NSNumber *, UITouch *> *_touchAry = nil;
static NSMutableArray *_livingTouchAry = nil;
static CFRunLoopSourceRef _source = NULL;
static UIEvent *_ownedEvent = nil;

static UITouch *toRemove = nil;
static UITouch *toStationarify = nil;

// 独立UIKit宿主没有系统缓存时复用原生触摸事件。
static UIEvent *ts_evt(UIApplication *app) {
  UIEvent *event = [app _touchesEvent];
  if (event) return event;
  if (!_ownedEvent) {
    Class type = objc_getClass("UITouchesEvent");
    if ([type instancesRespondToSelector:@selector(_init)]) _ownedEvent = [[type alloc] _init];
  }
  return _ownedEvent;
}

static void __TSEventFetcherCallback(void *info)
{
  (void)info;
  UIApplication *app = [UIApplication sharedApplication];
  UIEvent *event = ts_evt(app);
  if (!event) return;

  // to retain objects from being released
  [event _clearTouches];

  NSArray *myAry = _safeTouchAry;
  // 按KIF原生路径刷新当前事件，系统缓存也可能尚无载荷。
  IOHIDEventRef hid = kif_IOHIDEventWithTouches(myAry);
  [event _setHIDEvent:hid];
  CFRelease(hid);
  for (UITouch *aTouch in myAry)
  {
    switch (aTouch.phase) {
    case UITouchPhaseEnded:
    case UITouchPhaseCancelled:
      toRemove = aTouch;
      break;
    case UITouchPhaseBegan:
      toStationarify = aTouch;
      break;
    default:
      break;
    }

    [event _addTouch:aTouch forDelayedDelivery:NO];
  }

  // 仅在隔离探针记录UIKit收到的触摸与当前循环模式。
#ifdef LB_HUD_PROBE
  static unsigned int traces;
  BOOL trace = traces++ < 8;
  UITouch *first = myAry.firstObject;
  if (trace) {
    NSString *mode = CFBridgingRelease(CFRunLoopCopyCurrentMode(CFRunLoopGetMain()));
    lb_prblog([NSString stringWithFormat:@"send phase:%ld pending:%lu event:%@ touches:%lu app:%ld key:%d view:%@ mode:%@ eventTime:%.6f touchTime:%.6f now:%.6f",
      (long)first.phase,(unsigned long)myAry.count,NSStringFromClass(event.class),(unsigned long)event.allTouches.count,
      (long)app.applicationState,first.window.isKeyWindow,first.view.accessibilityIdentifier,mode,event.timestamp,first.timestamp,NSProcessInfo.processInfo.systemUptime]);
  }
  static unsigned int ends;
  BOOL ending = (first.phase == UITouchPhaseEnded || first.phase == UITouchPhaseCancelled) && ends++ < 8;
#endif
  [app sendEvent:event];
#ifdef LB_HUD_PROBE
  if (trace) lb_prblog(@"send.returned");
  // 独立保留抬手事件的时间基准与原生识别器状态。
  if (ending) {
    NSMutableArray *states = [NSMutableArray new];
    for (UIGestureRecognizer *recognizer in first.gestureRecognizers) [states addObject:[NSString stringWithFormat:@"%@:%ld",NSStringFromClass(recognizer.class),(long)recognizer.state]];
    lb_prblog([NSString stringWithFormat:@"send.end phase:%ld eventTime:%.6f touchTime:%.6f now:%.6f recognizers:%@",(long)first.phase,event.timestamp,first.timestamp,NSProcessInfo.processInfo.systemUptime,states]);
  }
#endif
}

@implementation TSEventFetcher

// 在UIKit宿主就绪后按需初始化。
+ (void)strt
{
  if (_source) return;
  _livingTouchAry = [[NSMutableArray alloc] init];
  // 按真实触摸惰性创建，独立HUD没有普通App场景。
  _touchAry = [[NSMutableDictionary alloc] init];

  CFRunLoopSourceContext context;
  memset(&context, 0, sizeof(CFRunLoopSourceContext));
  context.perform = __TSEventFetcherCallback;

  // content of context is copied
  _source = CFRunLoopSourceCreate(kCFAllocatorDefault, -2, &context);
  CFRunLoopRef loop = CFRunLoopGetMain();
  CFRunLoopAddSource(loop, _source, kCFRunLoopCommonModes);
}

+ (NSInteger)receiveAXEventID:(NSInteger)eventId
           atGlobalCoordinate:(CGPoint)coordinate
               withTouchPhase:(UITouchPhase)phase
                     inWindow:(UIWindow *)window
                       onView:(UIView *)view
{
  [self strt];
  BOOL deleted = NO;
  UITouch *touch = nil;
  BOOL needsCopy = NO;

  if (toRemove != nil)
  {
    touch = toRemove;
    toRemove = nil;
    [_livingTouchAry removeObjectIdenticalTo:touch];
    deleted = YES;
    needsCopy = YES;
  }

  if (toStationarify != nil)
  {
    // in case this is changed during the operations
    touch = toStationarify;
    toStationarify = nil;
    if (touch.phase == UITouchPhaseBegan)
      [touch setPhaseAndUpdateTimestamp:UITouchPhaseStationary];
  }

  eventId -= 1;

  // ideally should be phase began when this hit
  // but if by any means other phases come... well lets be forgiving
  touch = _touchAry[@(eventId)];
  BOOL oldState = touch && [_livingTouchAry containsObject:touch];
  BOOL newState = !oldState;
  if (newState)
  {
    if (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled)
      return deleted;
    touch = [[UITouch alloc] initAtPoint:coordinate inWindow:window onView:view];
    [_livingTouchAry addObject:touch];
    _touchAry[@(eventId)] = touch;
    needsCopy = YES;
  }
  else
  {
    if (touch.phase == UITouchPhaseBegan && phase == UITouchPhaseMoved)
      return deleted;
    [touch setLocationInWindow:coordinate];
  }

  [touch setPhaseAndUpdateTimestamp:phase];

  if (needsCopy)
  {
    CFTypeRef delayRelease = CFBridgingRetain(_safeTouchAry);
    _safeTouchAry = [[NSArray alloc] initWithArray:_livingTouchAry copyItems:NO];
    CFBridgingRelease(delayRelease);
  }

  CFRunLoopSourceSignal(_source);
#ifdef LB_HUD_PROBE
  // 对照硬件回调和实际RunLoop触摸阶段。
  static unsigned int queued;
  if (queued++ < 8) {
    NSString *mode = CFBridgingRelease(CFRunLoopCopyCurrentMode(CFRunLoopGetMain()));
    lb_prblog([NSString stringWithFormat:@"queue phase:%ld id:%ld pending:%lu mode:%@",(long)phase,(long)eventId+1,(unsigned long)_safeTouchAry.count,mode]);
  }
#endif
  // 输入到来时唤醒主循环，空闲时没有额外轮询。
  CFRunLoopWakeUp(CFRunLoopGetMain());
  return deleted;
}

// 注销原生触摸源并释放窗口引用。
+ (void)stop {
  [[[UIApplication sharedApplication] _touchesEvent] _clearTouches];
  [_ownedEvent _clearTouches]; _ownedEvent = nil;
  if (_source) { CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes); CFRelease(_source); _source = NULL; }
  _safeTouchAry = nil; _touchAry = nil; _livingTouchAry = nil; toRemove = nil; toStationarify = nil;
}

@end
