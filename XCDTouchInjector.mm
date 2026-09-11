//
//  XCDTouchInjector.mm
//

#import "XCDTouchInjector.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>
#import <mach/mach_time.h>

typedef void *IOHIDEventRef;

// event masks
enum {
    kIOHIDDigitizerEventRange    = 0x01,
    kIOHIDDigitizerEventTouch    = 0x02,
    kIOHIDDigitizerEventIdentity = 0x04,
    kIOHIDDigitizerEventPosition = 0x08,
};

// event fields
enum {
    kIOHIDEventFieldIsBuiltIn               = 11,
    kIOHIDEventFieldDigitizerIsDisplayIntegrated = 87,
};

typedef void *(*FnCreateClient)(CFAllocatorRef);
typedef void  (*FnDispatchEvent)(void *client, IOHIDEventRef event);
typedef void  (*FnSetSenderID)(IOHIDEventRef event, uint64_t senderID);
typedef void  (*FnSetIntegerValue)(IOHIDEventRef event, int field, int value);
typedef void  (*FnAppendEvent)(IOHIDEventRef parent, IOHIDEventRef child);
typedef IOHIDEventRef (*FnCreateDigitizerEvent)(
    CFAllocatorRef, uint64_t,
    unsigned int, unsigned int, unsigned int,
    unsigned int, unsigned int,
    double, double, double, double, double, double, double, double);
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
    NSLog(@"[XCD] syms: create=%p dispatch=%p setSender=%p setInt=%p append=%p createDig=%p createFinger=%p",
          _createClient, _dispatchEvent, _setSenderID, _setIntegerValue, _appendEvent, _createDigitizerEvent, _createFingerEvent);
    if (!_createClient || !_dispatchEvent || !_createDigitizerEvent || !_createFingerEvent) {
        NSLog(@"[XCD] resolve symbols failed");
        return;
    }
    self.client = _createClient(kCFAllocatorDefault);
    _ready = (self.client != NULL);
    NSLog(@"[XCD] TouchInjector ready=%d client=%p", _ready, self.client);
}

- (void)postTouchX:(float)x y:(float)y touchDown:(BOOL)down touchUp:(BOOL)up {
    if (!_ready) return;

    uint32_t parentFlags, childFlags;
    if (down) {
        parentFlags = kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventIdentity;
        childFlags  = kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch;
    } else if (up) {
        parentFlags = kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventIdentity | kIOHIDDigitizerEventPosition;
        childFlags  = kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch;
    } else {
        parentFlags = kIOHIDDigitizerEventPosition;
        childFlags  = kIOHIDDigitizerEventPosition;
    }

    uint64_t now = mach_absolute_time();
    unsigned char touch = down ? 1 : 0;

    IOHIDEventRef parent = _createDigitizerEvent(
        kCFAllocatorDefault,
        now,
        1,                    // transducerType = Hand
        1 << 22,              // index
        1,                    // identity
        parentFlags,
        0,                    // buttonMask
        x, y, 0, 0, 0, 0, 0, 0
    );

    if (_setIntegerValue) {
        _setIntegerValue(parent, kIOHIDEventFieldIsBuiltIn, 1);
        _setIntegerValue(parent, kIOHIDEventFieldDigitizerIsDisplayIntegrated, 1);
    }
    if (_setSenderID) {
        _setSenderID(parent, 0x8000000817319375ULL);
    }

    IOHIDEventRef child = _createFingerEvent(
        kCFAllocatorDefault,
        now,
        3,                    // index
        2,                    // identity
        childFlags,
        x, y, 0, 0, 0,
        touch, touch,
        0
    );

    if (_appendEvent && parent && child) {
        _appendEvent(parent, child);
    }
    if (child) CFRelease(child);

    if (parent) {
        _dispatchEvent(self.client, parent);
        CFRelease(parent);
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
