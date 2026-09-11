//
//  XCDTouchInjector.mm
//

#import "XCDTouchInjector.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>

typedef void *IOHIDEventRef;
typedef unsigned int IOHIDEventType;
typedef unsigned int IOHIDDigitizerTransducerType;
typedef unsigned int IOHIDDigitizerEventMask;

static const IOHIDEventType kXCDEventTypeDigitizer = 11;
static const IOHIDDigitizerTransducerType kXCDTransducerHand = 1;
static const IOHIDDigitizerEventMask kXCDEventTouch = 2;
static const IOHIDDigitizerEventMask kXCDEventPosition = 4;
static const IOHIDDigitizerEventMask kXCDEventTouchMove = 6;

typedef void *(*FnCreateClientWithType)(CFAllocatorRef, unsigned int, CFDictionaryRef);
typedef void  (*FnDispatchEvent)(void *client, IOHIDEventRef event);
typedef void  (*FnSetProperty)(void *client, CFStringRef key, CFTypeRef value);
typedef void  (*FnSetSenderID)(IOHIDEventRef event, uint64_t senderID);
typedef IOHIDEventRef (*FnCreateDigitizer)(
    CFAllocatorRef, CFDictionaryRef,
    unsigned int, unsigned int, unsigned int, unsigned int,
    unsigned char, unsigned char,
    double, double, double, double, double, double, double, double, double,
    unsigned int, unsigned long long);

@interface XCDTouchInjector ()
@property (nonatomic, assign) void *client;
@property (nonatomic, assign) BOOL ready;
@end

@implementation XCDTouchInjector {
    FnCreateClientWithType _createClientWithType;
    FnDispatchEvent  _dispatchEvent;
    FnCreateDigitizer _createDigitizer;
    FnSetProperty    _setProperty;
    FnSetSenderID    _setSenderID;
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
    void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!iokit) { NSLog(@"[XCD] IOKit dlopen failed"); return; }
    _createClientWithType = (FnCreateClientWithType) dlsym(iokit, "IOHIDEventSystemClientCreateWithType");
    _dispatchEvent  = (FnDispatchEvent) dlsym(iokit, "IOHIDEventSystemClientDispatchEvent");
    _createDigitizer = (FnCreateDigitizer) dlsym(iokit, "IOHIDEventCreateDigitizerEvent");
    _setProperty    = (FnSetProperty) dlsym(iokit, "IOHIDEventSystemClientSetProperty");
    _setSenderID    = (FnSetSenderID) dlsym(iokit, "IOHIDEventSetSenderID");
    NSLog(@"[XCD] syms: createWithType=%p dispatch=%p createDigitizer=%p setProp=%p setSender=%p",
          _createClientWithType, _dispatchEvent, _createDigitizer, _setProperty, _setSenderID);
    if (!_createClientWithType || !_dispatchEvent || !_createDigitizer) {
        NSLog(@"[XCD] resolve symbols failed");
        return;
    }
    // type=3 = Root（最高权限）
    self.client = _createClientWithType(kCFAllocatorDefault, 3, NULL);
    if (self.client && _setProperty) {
        _setProperty(self.client, CFSTR("HITestRootUserClient"), kCFBooleanTrue);
    }
    _ready = (self.client != NULL);
    NSLog(@"[XCD] TouchInjector ready=%d client=%p screen=%.0fx%.0f", _ready, self.client, _screenW, _screenH);
}

- (CGPoint)denormalizeX:(float)x y:(float)y {
    return CGPointMake(x * _screenW, y * _screenH);
}

- (void)injectTouchType:(IOHIDDigitizerEventMask)type
                     x:(float)x y:(float)y
                touchId:(uint32_t)touchId {
    if (!_ready) return;
    CGPoint p = [self denormalizeX:x y:y];

    NSDictionary *props = @{
        @"DigitizerIndex"     : @(touchId),
        @"DigitizerIdentity"  : @(touchId + 1),
        @"DigitizerEventMask" : @(type),
    };
    CFDictionaryRef propDict = (CFDictionaryRef)CFBridgingRetain(props);

    unsigned char touching = (type != 0) ? 1 : 0;

    IOHIDEventRef event = _createDigitizer(
        kCFAllocatorDefault,
        propDict,
        kXCDEventTypeDigitizer,
        kXCDTransducerHand,
        touchId,
        touchId + 1,
        touching,
        0,
        0.0, 0.0,
        p.x, p.y,
        0.0,
        touching ? 1.0 : 0.0,
        0.0, 0.0, 0.0,
        0,
        0ULL
    );

    if (event) {
        if (_setSenderID) {
            _setSenderID(event, 0xDEFACEDBEEFFECE5ULL);
        }
        _dispatchEvent(self.client, event);
        CFRelease(event);
    }
    CFRelease(propDict);
}

- (void)touchDownX:(float)x y:(float)y touchId:(uint8_t)tid {
    [self injectTouchType:kXCDEventTouchMove x:x y:y touchId:tid];
}

- (void)touchMoveX:(float)x y:(float)y touchId:(uint8_t)tid {
    [self injectTouchType:kXCDEventTouchMove x:x y:y touchId:tid];
}

- (void)touchUpTouchId:(uint8_t)tid {
    [self injectTouchType:0 x:0 y:0 touchId:tid];
}

- (void)swipeFromX:(float)x1 y1:(float)y1 x2:(float)x2 y2:(float)y2 duration:(float)sec {
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
