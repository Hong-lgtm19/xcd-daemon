//
//  XCDTouchInjector.mm
//

#import "XCDTouchInjector.h"
#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDEvent.h>
#import <mach/mach_time.h>

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

@interface XCDTouchInjector ()
@property (nonatomic, assign) IOHIDEventSystemClientRef client;
@property (nonatomic, assign) BOOL ready;
@end

@implementation XCDTouchInjector

+ (instancetype)sharedInjector {
    static XCDTouchInjector *inst;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[XCDTouchInjector alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        _ready = (self.client != NULL);
        NSLog(@"[XCD] TouchInjector ready=%d", _ready);
    }
    return self;
}

- (void)postTouchX:(float)x y:(float)y touchDown:(BOOL)down touchUp:(BOOL)up {
    if (!_ready) return;

    uint32_t handm, fingerm;
    Boolean tis = down ? true : false;

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

    IOHIDEventRef hand = IOHIDEventCreateDigitizerEvent(
        kCFAllocatorDefault,
        now,
        kIOHIDDigitizerTransducerTypeHand,
        1 << 22,
        1,
        handm,
        0,
        x, y, 0, 0, 0,
        false, false,
        0
    );

    IOHIDEventSetIntegerValue(hand, kIOHIDEventFieldIsBuiltIn, true);
    IOHIDEventSetIntegerValue(hand, kIOHIDEventFieldDigitizerIsDisplayIntegrated, true);

    IOHIDEventRef finger = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault,
        now,
        3, 2,
        fingerm,
        x, y, 0, 0, 0,
        tis, tis,
        0
    );

    IOHIDEventAppendEvent(hand, finger);
    CFRelease(finger);

    IOHIDEventSetSenderID(hand, 0x8000000817319372ULL);
    IOHIDEventSystemClientDispatchEvent(self.client, hand);
    CFRelease(hand);
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
