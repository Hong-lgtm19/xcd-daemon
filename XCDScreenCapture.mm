//
//  XCDScreenCapture.mm
//  越狱设备屏幕帧采集。
//
//  原理：通过 IOKit 打开显示控制器（display controller），建立一块与
//  屏幕背后共享的 IOSurface，按帧率把它读回为 CVPixelBuffer。
//  这是 Veency / ioscpy 等同类工具采用的标准路径，属私有 API。
//
//  【版本敏感提示】IOService 名与 IOConnect 选择器在不同 iOS 小版本上
//  可能不同；在 iOS 13.6 上若编译/运行报错，按以下顺序核对：
//    1) IOService 名（常见 "AppleCLCD" / "H11CBUART" / display driver）
//    2) connect/scalar 选择器索引
//  参考开源：github.com/nicknah/veency、github.com/lautarovculic/ioscpy
//

#import "XCDScreenCapture.h"
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOMobileFramebuffer.h>
#import <IOSurface/IOSurface.h>
#import <dlfcn.h>

@interface XCDScreenCapture () {
    IOMobileFramebufferConnection _framebuffer;
    IOSurfaceRef _surface;
    CVPixelBufferPoolRef _pool;
    int _width, _height;
    dispatch_source_t _timer;
    BOOL _running;
}
@end

@implementation XCDScreenCapture
@synthesize width = _width, height = _height;

- (BOOL)startWithFPS:(int)fps {
    // 1) 打开 mobile framebuffer（私有框架 IOMobileFramebuffer）
    void *h = dlopen("/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer", RTLD_LAZY);
    if (!h) { NSLog(@"[XCD] IOMobileFramebuffer dlopen failed"); return NO; }

    typedef IOReturn (*IOMFBGetMainDisplay_t)(IOMobileFramebufferConnection *);
    typedef IOReturn (*IOMFBLGetSurface_t)(IOMobileFramebufferConnection, IOSurfaceRef *);
    IOMFBGetMainDisplay_t getMain = dlsym(h, "IOMobileFramebufferGetMainDisplay");
    IOMFBLGetSurface_t getSurface = dlsym(h, "IOMobileFramebufferGetLayerDefaultSurface");

    if (!getMain || !getSurface) {
        NSLog(@"[XCD] IOMFB symbols not found (version-specific)");
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

    // 2) 定时抓帧
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

    // 把 IOSurface 锁内存，包成 CVPixelBuffer 交给编码器
    // （这里直接复用 surface；生产中为避免与显示合成竞争，可复制一层）
    CVPixelBufferRef pb = NULL;
    // IOSurface 与 CVPixelBuffer 可桥接；直接让编码器吃 IOSurface-backed buffer。
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
