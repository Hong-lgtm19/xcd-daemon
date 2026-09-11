//
//  main.mm — XCDDaemon 入口（越狱 iOS 后台守护进程）
//
//  职责：
//    - 监听视频端口：把 H.264 流推给已连接的电脑端
//    - 监听控制端口：解析触摸/按键消息，调用 TouchInjector
//    - 串起 ScreenCapture -> VideoEncoder -> 网络发送
//
//  编译：用 theos 编成可执行文件；通过 launchd plist 开机自启。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "XCDProtocol.h"
#import "XCDTouchInjector.h"
#import "XCDVideoEncoder.h"
#import "XCDScreenCapture.h"

@interface XCDServer : NSObject <XCDVideoEncoderDelegate, XCDScreenCaptureDelegate>
@end

@implementation XCDServer {
    int _videoFd;
    int _controlFd;
    XCDScreenCapture *_capture;
    XCDVideoEncoder *_encoder;
    dispatch_queue_t _ioQueue;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _videoFd = -1;
        _controlFd = -1;
        _ioQueue = dispatch_queue_create("com.xcd.net", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)listenOn:(int)port {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);  // 监听所有网卡，电脑通过 Wi-Fi IP 直连
    addr.sin_port = htons(port);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) { close(fd); return NO; }
    listen(fd, 4);

    // GCD 异步 accept
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, _ioQueue);
    dispatch_source_set_event_handler(src, ^{
        int cfd = accept(fd, NULL, NULL);
        if (cfd < 0) return;
        NSLog(@"[XCD] client connected on port %d (fd=%d)", port, cfd);
        if (port == XCD_VIDEO_PORT) {
            self->_videoFd = cfd;
        } else {
            self->_controlFd = cfd;
            [self startControlReader:cfd];
        }
    });
    dispatch_resume(src);
    return YES;
}

- (void)start {
    [self listenOn:XCD_VIDEO_PORT];
    [self listenOn:XCD_CONTROL_PORT];

    // 握手 hello：等控制通道连上后，电脑端会发 hello/ack
    // 初始化采集 + 编码
    _capture = [[XCDScreenCapture alloc] init];
    _capture.delegate = self;
    _encoder = [[XCDVideoEncoder alloc] init];
    _encoder.delegate = self;

    UIScreen *s = [UIScreen mainScreen];
    int w = (int)s.nativeBounds.size.width;
    int h = (int)s.nativeBounds.size.height;
    [_encoder configureWithWidth:w height:h fps:30 bitrateKbps:4000];
    [_capture startWithFPS:30];

    NSLog(@"[XCD] daemon started. video=%d control=%d screen=%dx%d",
          XCD_VIDEO_PORT, XCD_CONTROL_PORT, w, h);
}

#pragma mark - ScreenCapture delegate
- (void)captureDidOutputPixelBuffer:(CVPixelBufferRef)pb {
    [_encoder encodePixelBuffer:pb];
}

#pragma mark - Encoder delegate -> video socket
- (void)encoderDidOutputNALU:(NSData *)nalu isKeyframe:(BOOL)key {
    if (_videoFd < 0) return;
    dispatch_async(_ioQueue, ^{
        send(self->_videoFd, nalu.bytes, nalu.length, MSG_NOSIGNAL);
    });
}

#pragma mark - Control channel reader
- (void)startControlReader:(int)fd {
    // 每个连接一个串行读循环
    dispatch_async(_ioQueue, ^{
        uint8_t buf[4096];
        while (self->_controlFd == fd) {
            ssize_t n = recv(fd, buf, sizeof(buf), 0);
            if (n <= 0) {
                NSLog(@"[XCD] control closed");
                close(fd);
                self->_controlFd = -1;
                break;
            }
            [self dispatchBytes:buf length:n];
        }
    });
}

- (void)dispatchBytes:(uint8_t *)buf length:(ssize_t)n {
    size_t off = 0;
    XCDTouchInjector *inj = [XCDTouchInjector sharedInjector];
    while (off < n) {
        uint8_t type = buf[off];
        switch (type) {
            case XCDMsgTouchDown:
            case XCDMsgTouchMove: {
                if (off + sizeof(xcd_touch_t) > n) return;
                xcd_touch_t *m = (xcd_touch_t *)&buf[off];
                if (type == XCDMsgTouchDown) [inj touchDownX:m->x y:m->y touchId:m->touch_id];
                else [inj touchMoveX:m->x y:m->y touchId:m->touch_id];
                off += sizeof(xcd_touch_t); break;
            }
            case XCDMsgTouchUp: {
                if (off + 2 > n) return;
                [inj touchUpTouchId:buf[off+1]];
                off += 2; break;
            }
            case XCDMsgSwipe: {
                if (off + sizeof(xcd_swipe_t) > n) return;
                xcd_swipe_t *m = (xcd_swipe_t *)&buf[off];
                [inj swipeFromX:m->x1 y1:m->y1 x2:m->x2 y2:m->y2 duration:m->duration];
                off += sizeof(xcd_swipe_t); break;
            }
            case XCDMsgPing: {
                uint8_t pong = XCDMsgPong;
                send(_controlFd, &pong, 1, MSG_NOSIGNAL);
                off += 1; break;
            }
            default:
                off += 1; // 未识别，跳过
                break;
        }
    }
}

@end

// 后台 daemon：需要 UIApplication 来访问 UIScreen 等
@interface XCDAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation XCDAppDelegate
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        // 以 UIApplication 方式启动（无界面），便于访问 UIScreen / IOHID
        NSString *appid = @"com.xcd.daemon";
        XCDAppDelegate *del = [XCDAppDelegate new];
        [UIApplication sharedApplication];
        [[NSNotificationCenter defaultCenter] addObserverForName:nil object:nil queue:nil usingBlock:nil];

        XCDServer *server = [XCDServer new];
        [server start];

        // 跑主运行循环
        [[NSRunLoop mainRunLoop] run];
        return 0;
    }
}
