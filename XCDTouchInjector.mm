//
//  XCDTouchInjector.mm
//  越狱 iOS 触摸注入：通过 IOHIDEventSystemClient 合成 Digitizer（触摸）事件。
//  原理：向系统 HID 系统注入一块"手"，再向其下发 finger down/move/up。
//  对应 iOS 11~14（用户设备 iOS 13.6 验证范围）。
//
//  注意：iOS 安全机制要求——每次 respring / 重连后，系统只信任来自真实
//  触摸屏的事件，必须先用手指在屏幕上物理点一下，注入事件才会被接受。
//  这是硬件级信任链，软件无法绕过，使用时在 UI 上提示用户即可。
//

#import "XCDTouchInjector.h"
#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDEvent.h>
#import <IOKit/hid/IOHIDEventSystemClient.h>
#import <dlfcn.h>

// 私有符号：从 IOKit 框架动态加载，避免编译期链接私有头
typedef struct IOHIDEventSystemClient *(*IOHIDEventSystemClientCreate_t)(CFAllocatorRef);
typedef void (*IOHIDEventSystemClientDispatchEvent_t)(struct IOHIDEventSystemClient *, IOHIDEventRef);

// Digitizer 事件构造（私有 API，运行时解析）
typedef IOHIDEventRef (*IOHIDEventCreateDigitizerEvent_t)(CFAllocatorRef, CFDictionaryRef,
                                                          IOHIDEventType, IOHIDDigitizerTransducerType,
                                                          uint32_t, uint32_t, Boolean, Boolean,
                                                          double, double, double, double,
                                                          double, double, double, double, uint32_t);

@interface XCDTouchInjector ()
@property (nonatomic, assign) IOHIDEventSystemClientRef client;
@property (nonatomic, assign) BOOL ready;
@end

@implementation XCDTouchInjector {
    IOHIDEventSystemClientCreate_t        _createClient;
    IOHIDEventSystemClientDispatchEvent_t _dispatchEvent;
    IOHIDEventCreateDigitizerEvent_t      _createDigitizer;
    CGFloat _screenW;
    CGFloat _screenH;
}

+ (instancetype)sharedInjector {
    static XCDTouchInjector *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[XCDTouchInjector alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        UIScreen *s = [UIScreen mainScreen];
        _screenW = s.nativeBounds.size.width;
        _screenH = s.nativeBounds.size.height;
        [self resolvePrivateSymbols];
    }
    return self;
}

- (void)resolvePrivateSymbols {
    // IOHIDEventSystemClientCreate 在 IOKit 中
    void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!iokit) { NSLog(@"[XCD] IOKit dlopen failed"); return; }

    _createClient   = dlsym(iokit, "IOHIDEventSystemClientCreate");
    _dispatchEvent  = dlsym(iokit, "IOHIDEventSystemClientDispatchEvent");
    _createDigitizer = dlsym(iokit, "IOHIDEventCreateDigitizerEvent");

    if (!_createClient || !_dispatchEvent || !_createDigitizer) {
        NSLog(@"[XCD] resolve symbols failed: create=%p dispatch=%p digitizer=%p",
              _createClient, _dispatchEvent, _createDigitizer);
        return;
    }
    _client = _createClient(kCFAllocatorDefault);
    _ready = (_client != NULL);
    NSLog(@"[XCD] TouchInjector ready=%d screen=%.0fx%.0f", _ready, _screenW, _screenH);
}

// 将归一化坐标转换为物理像素
- (CGPoint)denormalizeX:(float)x y:(float)y {
    return CGPointMake(x * _screenW, y * _screenH);
}

- (void)injectTouchType:(IOHIDDigitizerEventMask)type
                     x:(float)x y:(float)y
                touchId:(uint32_t)touchId {
    if (!_ready) return;
    CGPoint p = [self denormalizeX:x y:y];

    // 属性字典：定义这根手指的身份
    NSDictionary *props = @{
        @"DigitizerIndex"     : @(touchId),
        @"DigitizerIdentity"  : @(touchId + 1),
        @"DigitizerEventMask" : @(type),
    };
    CFDictionaryRef propDict = CFBridgingRetain(props);

    IOHIDEventRef event = _createDigitizer(
        kCFAllocatorDefault,
        propDict,
        kIOHIDEventTypeDigitizer,
        kIOHIDDigitizerTransducerTypeHand,  // 模拟"手"
        touchId,                             // index
        touchId + 1,                         // identity
        (type == kIOHIDDigitizerEventTouch), // touching
        false,                               // child event
        0.0, 0.0,                            // range
        p.x, p.y,                            // position x, y（物理像素）
        0.0, 0.0,                            // z, pressure 由系统补
        1.0,                                 // pressure
        0                                    // eventInfo
    );

    if (event) {
        _dispatchEvent(_client, event);
        CFRelease(event);
    }
    CFRelease(propDict);
}

- (void)touchDownX:(float)x y:(float)y touchId:(uint8_t)tid {
    [self injectTouchType:kIOHIDDigitizerEventTouch x:x y:y touchId:tid];
}

- (void)touchMoveX:(float)x y:(float)y touchId:(uint8_t)tid {
    [self injectTouchType:kIOHIDDigitizerEventPosition x:x y:y touchId:tid];
}

- (void)touchUpTouchId:(uint8_t)tid {
    if (!_ready) return;
    NSDictionary *props = @{
        @"DigitizerIndex"     : @(tid),
        @"DigitizerIdentity"  : @(tid + 1),
        @"DigitizerEventMask" : @(kIOHIDDigitizerEventRelease | kIOHIDDigitizerEventTouch),
    };
    CFDictionaryRef propDict = CFBridgingRetain(props);
    IOHIDEventRef event = _createDigitizer(
        kCFAllocatorDefault, propDict,
        kIOHIDEventTypeDigitizer,
        kIOHIDDigitizerTransducerTypeHand,
        tid, tid + 1, false, false,
        0,0, 0,0, 0,0, 0, 0);
    if (event) { _dispatchEvent(_client, event); CFRelease(event); }
    CFRelease(propDict);
}

- (void)swipeFromX:(float)x1 y1:(float)y1 x2:(float)x2 y2:(float)y2 duration:(float)sec {
    // 用插值模拟一段平滑滑动
    int steps = MAX(8, (int)(sec * 60));
    [self touchDownX:x1 y:y1 touchId:0];
    for (int i = 1; i <= steps; i++) {
        float t = (float)i / steps;
        float x = x1 + (x2 - x1) * t;
        float y = y1 + (y2 - y1) * t;
        [self touchMoveX:x y:y touchId:0];
        usleep((useconds_t)(sec * 1e6 / steps));
    }
    [self touchUpTouchId:0];
}

@end
