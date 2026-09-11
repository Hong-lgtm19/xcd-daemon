//
//  XCDVideoEncoder.h
//  屏幕抓帧 -> H.264 硬编码 -> 回调吐出 Annex-B NALU
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

@protocol XCDVideoEncoderDelegate <NSObject>
// 每个已编码 H.264 访问单元（含起始码）调用一次
- (void)encoderDidOutputNALU:(NSData *)nalu isKeyframe:(BOOL)key;
@end

@interface XCDVideoEncoder : NSObject
@property (nonatomic, weak) id<XCDVideoEncoderDelegate> delegate;
@property (nonatomic, assign, readonly) int width;
@property (nonatomic, assign, readonly) int height;

- (BOOL)configureWithWidth:(int)w height:(int)h fps:(int)fps bitrateKbps:(int)kbps;
// 喂入一帧（CVImageBuffer / CVPixelBuffer），同步触发编码回调
- (void)encodePixelBuffer:(CVPixelBufferRef)pixelBuffer;
- (void)invalidate;
@end
