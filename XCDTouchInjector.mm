//
//  XCDTouchInjector.mm
//

#import "XCDTouchInjector.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>
#import <mach/mach_time.h>

typedef void *IOHIDEventRef;

enum {
    kIOHIDDigitizerEventRange     = 0x01,
    kIOHIDDigitizerEventTouch     = 0x02,
    kIOHIDDigitizerEventIdentity  = 0x04,
    kIOHIDDigitizerEventPosition  = 0x08,
};

enum {
    kIOHIDEventFieldIsBuiltIn                    = 11,
    kIOHIDEventFieldDigitizerIsDisplayIntegrated = 87,
};

typedef void *(*FnCreateClient)(CFAllocatorRef);
typedef void  (*FnDispatchEvent)(void *client, IOHIDEventRef event);
typedef void  (*FnSetSenderID)(IOHIDEventRef event, uint64_t senderID);
typedef void  (*FnSetIntegerValue)(IOHIDEventRef event, unsigned int field, int value);
typedef void  (*FnAppendEvent)(IOHIDEventRef parent, IOHIDEventRef child);
typedef IOHIDEventRef (*FnCreateDigitizerEvent)(
    CFAllocatorRef, uint64_t,
    unsigned int, unsigned int, unsigned int,
    unsigned int, unsigned int,
    double, double, double, double, double,
    unsigned char, unsigned char, unsigned int);
typedef IOHIDEventRef (*FnCreateFingerEvent)(
    CFAllocatorRef, uint64_t,
    unsigned int, unsigned int, unsigned int,
    double, double, double, double, double,
    unsigned char, unsigned char, unsigned int);

@interface XCDTouchInjector ()
@property (nonatomic, assign) void *client;
@property (nonatomic, assign) BOOL ready;
@end

@implementation XCDTouchInjector {
    FnCreateClient       _createClient;
    FnDispatchEvent     _dispatchEvent;
    FnSetSenderID        _setSenderID;
    FnSetIntegerValue    _setIntegerValue;
    FnAppendEvent        _appendEvent;
    FnCreateDigitizerEvent _createDigitizerEvent;
    FnCreateFingerEvent  _createFingerEvent;
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
        [self resolvePrivateSymbols];
    }
    return self;
}

- (void)resolvePrivateSymbols {
    void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!iokit) { NSLog(@"[XCD] IOKit dlopen failed"); return; }
    _createClient       = (FnCreateClient) dlsym(iokit, "IOHIDEventSystemClientCreate");
    _dispatchEvent      = (FnDispatchEvent) dlsym(iokit, "IOHIDEventSystemClientDispatchEvent");
    _setSenderID        = (FnSetSenderID) dlsym(iokit, "IOHIDEventSetSenderID");
    _setIntegerValue    = (FnSetIntegerValue) dlsym(iokit, "IOHIDEventSetIntegerValue");
    _appendEvent        = (FnAppendEvent) dlsym(iokit, "IOHIDEventAppendEvent");
    _createDigitizerEvent = (FnCreateDigitizerEvent) dlsym(iokit, "IOHIDEventCreateDigitizerEvent");
    _createFingerEvent  = (FnCreateFingerEvent) dlsym(iokit, "IOHIDEventCreateDigitizerFingerEvent");
    if (!_createClient || !_dispatchEvent || !_createDigitizerEvent || !_createFingerEvent) {
        NSLog(@"[XCD] resolve symbols failed");
        return;
    }
    self.client = _createClient(kCFAllocatorDefault);
    _ready = (self.client != NULL);
    NSLog(@"[XCD] TouchInjector ready=%d", _ready);
}

- (void)postTouchX:(float)x y:(float)y touchDown:(BOOL)down touchUp:(BOOL)up {
    if (!_ready) return;

    uint32_t handm, fingerm;
    unsigned char tis = down ? 1 : 0;

    if (down) {
        handm  = kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventIdentity;
        fingerm = kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch;
    } else if (up) {
        handm  = kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventIdentity | kIOHIDDigitizerEventPosition;
        fingerm = kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch;
    } else {
        handm  = kIOHIDDigitizerEventPosition;
        fingerm = kIOHIDDigitizerEventPosition;
    }

    uint64_t now = mach_absolute_time();

    IOHIDEventRef hand = _createDigitizerEvent(
        kCFAllocatorDefault,
        now,
        1,                    // transducerType = Hand
        1 << 22,              // index
        1,                    // identity
        handm,
        0,                    // buttonMask
        x, y, 0, 0, 0,        // x, y, z, tipPressure, barrelPressure
        0, 0,                 // range, touch (parent 不用)
        0                     // options
    );

    if (_setIntegerValue) {
        _setIntegerValue(hand, kIOHIDEventFieldIsBuiltIn, 1);
        _setIntegerValue(hand, kIOHIDEventFieldDigitizerIsDisplayIntegrated, 1);
    }

    IOHIDEventRef finger = _createFingerEvent(
        kCFAllocatorDefault,
        now,
        3, 2,                 // index, identity
        fingerm,
        x, y, 0, 0, 0,        // x, y, z, tipPressure, twist
        tis, tis,             // range, touch
        0                     // options
    );

    if (_appendEvent && hand && finger) {
        _appendEvent(hand, finger);
    }
    if (finger) CFRelease(finger);

    if (hand) {
        if (_setSenderID) {
            _setSenderID(hand, 0x8000000817319372ULL);
        }
        _dispatchEvent(self.client, hand);
        CFRelease(hand);
    }
}

- (void)touchDownX:(float)x y:(float)y touchId:(uint8_t)tid {
    [self postTouchX:x y:y touchDown:YES touchUp:NO];
}

- (void)touchMoveX:(float)x y:(float)y touchId:(uint8_t)tid {
    [self postTouchX:x y:y touchDown:NO touchUp:NO];
}

- (void)touchUpTouchId:(uint8_t)tid {
    [self postTouchX:0 y:0 touchDown:NO touchUp:YES];
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
