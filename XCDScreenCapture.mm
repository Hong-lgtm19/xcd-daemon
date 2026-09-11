//
//  XCDScreenCapture.mm
//  越狱设备屏幕帧采集。
//  IOMobileFramebuffer 和 IOSurface 全部运行时 dlopen/dlsym。
//

#import "XCDScreenCapture.h"
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <dlfcn.h>

typedef void *IOMFBConnection;
typedef void *IOSurfaceRef;

typedef IOReturn (*IOMFBGetMainDisplay_t)(IOMFBConnection *);
typedef IOReturn (*IOMFBGetSurface_t)(IOMFBConnection, int plane, IOSurfaceRef *);

typedef size_t  (*ISGetWidth_t)(IOSurfaceRef);
typedef size_t  (*ISGetHeight_t)(IOSurfaceRef);
typedef void *  (*ISGetBaseAddr_t)(IOSurfaceRef);
typedef size_t  (*ISGetBytesPerRow_t)(IOSurfaceRef);

@interface XCDScreenCapture () {
    IOMFBConnection _framebuffer;
    IOSurfaceRef _surface;
    int _width, _height;
    dispatch_source_t _timer;
    BOOL _running;

    ISGetWidth_t       _isWidth;
    ISGetHeight_t      _isHeight;
    ISGetBaseAddr_t    _isBaseAddr;
    ISGetBytesPerRow_t _isBPR;
}
@end

@implementation XCDScreenCapture
@synthesize width = _width, height = _height;

- (BOOL)startWithFPS:(int)fps {
    void *h = dlopen("/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer", RTLD_LAZY);
    if (!h) { NSLog(@"[XCD] IOMobileFramebuffer dlopen failed"); return NO; }

    IOMFBGetMainDisplay_t getMain = (IOMFBGetMainDisplay_t)dlsym(h, "IOMobileFramebufferGetMainDisplay");
    IOMFBGetSurface_t getSurface = (IOMFBGetSurface_t)dlsym(h, "IOMobileFramebufferGetLayerDefaultSurface");
    if (!getMain || !getSurface) { NSLog(@"[XCD] IOMFB symbols not found"); return NO; }
    if (getMain(&_framebuffer) != kIOReturnSuccess) { NSLog(@"[XCD] getMainDisplay failed"); return NO; }
    if (getSurface(_framebuffer, 0, &_surface) != kIOReturnSuccess || !_surface) { NSLog(@"[XCD] getSurface failed"); return NO; }

    void *ish = dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface", RTLD_LAZY);
    if (!ish) { NSLog(@"[XCD] IOSurface dlopen failed"); return NO; }
    _isWidth    = (ISGetWidth_t)dlsym(ish, "IOSurfaceGetWidth");
    _isHeight   = (ISGetHeight_t)dlsym(ish, "IOSurfaceGetHeight");
    _isBaseAddr = (ISGetBaseAddr_t)dlsym(ish, "IOSurfaceGetBaseAddress");
    _isBPR      = (ISGetBytesPerRow_t)dlsym(ish, "IOSurfaceGetBytesPerRow");
    if (!_isWidth || !_isHeight || !_isBaseAddr || !_isBPR) { NSLog(@"[XCD] IOSurface symbols not found"); return NO; }

    _width  = (int)_isWidth(_surface);
    _height = (int)_isHeight(_surface);
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
                                 _isBaseAddr(_surface),
                                 _isBPR(_surface),
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

