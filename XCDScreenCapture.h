//
//  XCDScreenCapture.h
//  越狱设备屏幕帧采集：输出 CVPixelBuffer 给编码器
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

@protocol XCDScreenCaptureDelegate <NSObject>
- (void)captureDidOutputPixelBuffer:(CVPixelBufferRef)pb;
@end

@interface XCDScreenCapture : NSObject
@property (nonatomic, weak) id<XCDScreenCaptureDelegate> delegate;
@property (nonatomic, assign, readonly) int width;
@property (nonatomic, assign, readonly) int height;
- (BOOL)startWithFPS:(int)fps;
- (void)stop;
@end
