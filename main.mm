#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <errno.h>
#import <string.h>
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
}

- (instancetype)init {
    self = [super init];
    if (self) { _videoFd = -1; _controlFd = -1; }
    return self;
}

- (BOOL)listenOn:(int)port {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        NSLog(@"[XCD] socket failed: %s", strerror(errno));
        return NO;
    }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NSLog(@"[XCD] bind port %d failed: %s (errno=%d)", port, strerror(errno), errno);
        close(fd);
        return NO;
    }
    listen(fd, 4);
    NSLog(@"[XCD] listening on port %d", port);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        while (YES) {
            int cfd = accept(fd, NULL, NULL);
            if (cfd < 0) continue;
            NSLog(@"[XCD] client connected on port %d (fd=%d)", port, cfd);
            if (port == XCD_VIDEO_PORT) {
                self->_videoFd = cfd;
            } else {
                self->_controlFd = cfd;
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
                    [self controlLoop:cfd];
                });
            }
        }
    });
    return YES;
}

- (void)controlLoop:(int)fd {
    uint8_t buf[4096];
    while (YES) {
        ssize_t n = recv(fd, buf, sizeof(buf), 0);
        if (n <= 0) { close(fd); break; }
        [self dispatchBytes:buf length:n];
    }
}

- (void)start {
    [self listenOn:XCD_VIDEO_PORT];
    [self listenOn:XCD_CONTROL_PORT];
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

- (void)captureDidOutputPixelBuffer:(CVPixelBufferRef)pb { [_encoder encodePixelBuffer:pb]; }
- (void)encoderDidOutputNALU:(NSData *)nalu isKeyframe:(BOOL)key {
    if (_videoFd < 0) return;
    send(self->_videoFd, nalu.bytes, nalu.length, 0);
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
                send(_controlFd, &pong, 1, 0);
                off += 1; break;
            }
            default: off += 1; break;
        }
    }
}

@end

@interface XCDAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation XCDAppDelegate
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        system("killall XCDDaemon 2>/dev/null");
        sleep(1);

        [UIApplication sharedApplication];
        XCDServer *server = [XCDServer new];
        [server start];
        [[NSRunLoop mainRunLoop] run];
        return 0;
    }
}
