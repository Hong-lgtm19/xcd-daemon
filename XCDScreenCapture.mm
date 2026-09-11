//
//  XCDScreenCapture.mm
//  越狱设备屏幕帧采集：IOMobileFramebuffer 拿共享 IOSurface，定时读回。
//

#import "XCDScreenCapture.h"
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOSurface/IOSurface.h>
#import <dlfcn.h>

typedef void *IOMFBConnection;

typedef IOReturn (*IOMFBGetMainDisplay_t)(IOMFBConnection *);
typedef IOReturn (*IOMFBGetSurface_t)(IOMFBConnection, int plane, IOSurfaceRef *);

@interface XCDScreenCapture () {
    IOMFBConnection _framebuffer;
    IOSurfaceRef _surface;
    int _width, _height;
    dispatch_source_t _timer;
    BOOL _running;
}
@end

@implementation XCDScreenCapture
@synthesize width = _width, height = _height;

- (BOOL)startWithFPS:(int)fps {
    void *h = dlopen("/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer", RTLD_LAZY);
    if (!h) { NSLog(@"[XCD] IOMobileFramebuffer dlopen failed"); return NO; }

    IOMFBGetMainDisplay_t getMain = (IOMFBGetMainDisplay_t)dlsym(h, "IOMobileFramebufferGetMainDisplay");
    IOMFBGetSurface_t getSurface = (IOMFBGetSurface_t)dlsym(h, "IOMobileFramebufferGetLayerDefaultSurface");

    if (!getMain || !getSurface) {
        NSLog(@"[XCD] IOMFB symbols not found");
        return NO;
    }
    if (getMain(&_framebuffer) != kIOReturnSuccess) {
        NSLog(@"[XCD] getMainDisplay failed"); return NO;
    }
    if (getSurface(_framebuffer, 0, &_surface) != kIOReturnSuccess || !_surface) {
        NSLog(@"[XCD] getSurface failed"); return NO;
    }

    _width  = (int)IOSurfaceGetWidth(_surface);
    _height = (int)IOSurfaceGetHeight(_surface);
    NSLog(@"[XCD] screen surface %dx%d", _width, _height);

    _running = YES;
    NSTimeInterval interval = 1.0 / fps;
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                    dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              (uint64_t)(interval * NSEC_PER_SEC), 10 * NSEC_PER_MSEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_timer, ^{ [weakSelf grabFrame]; });
    dispatch_resume(_timer);
    return YES;
}

- (void)grabFrame {
    if (!_running || !_surface) return;

    CVPixelBufferRef pb = NULL;
    CVPixelBufferCreateWithBytes(kCFAllocatorDefault,
                                 _width, _height,
                                 kCVPixelFormatType_32BGRA,
                                 IOSurfaceGetBaseAddress(_surface),
                                 IOSurfaceGetBytesPerRow(_surface),
                                 NULL, NULL, NULL, &pb);
    if (pb) {
        [self.delegate captureDidOutputPixelBuffer:pb];
        CVPixelBufferRelease(pb);
    }
}

- (void)stop {
    _running = NO;
    if (_timer) { dispatch_source_cancel(_timer); _timer = NULL; }
    if (_surface) { CFRelease(_surface); _surface = NULL; }
}

- (void)dealloc { [self stop]; }

@end
