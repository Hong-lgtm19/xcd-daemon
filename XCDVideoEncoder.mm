//
//  XCDVideoEncoder.mm
//  VideoToolbox H.264 硬编码实现（公开 API，跨 iOS 版本稳定）
//

#import "XCDVideoEncoder.h"
#import <VideoToolbox/VideoToolbox.h>
#import <VideoToolbox/VTCompressionSession.h>
#import <CoreMedia/CoreMedia.h>
#import <QuartzCore/QuartzCore.h>

@interface XCDVideoEncoder () {
    VTCompressionSessionRef _session;
    int _width;
    int _height;
    CMTime _frameDuration;
    dispatch_queue_t _queue;
}
@end

@implementation XCDVideoEncoder
@synthesize width = _width, height = _height;

- (BOOL)configureWithWidth:(int)w height:(int)h fps:(int)fps bitrateKbps:(int)kbps {
    _width = w;
    _height = h;
    _frameDuration = CMTimeMake(1, fps);
    _queue = dispatch_queue_create("com.xcd.encoder", DISPATCH_QUEUE_SERIAL);

    // 必须是偶数
    w &= ~1; h &= ~1;

    OSStatus st = VTCompressionSessionCreate(
        kCFAllocatorDefault,
        w, h,
        kCMVideoCodecType_H264,
        NULL, NULL, NULL,
        compressionOutputCallback,
        (__bridge void *)self,
        &_session);

    if (st != noErr) { NSLog(@"[XCD] VTCompressionSessionCreate failed: %d", (int)st); return NO; }

    // 实时编码配置
    VTSessionSetProperty(_session, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(_session, kVTCompressionPropertyKey_ProfileLevel,
                         kVTProfileLevel_H264_Baseline_AutoLevel);
    int bits = kbps * 1000;
    CFNumberRef bitrate = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &bits);
    VTSessionSetProperty(_session, kVTCompressionPropertyKey_AverageBitRate, bitrate);
    CFRelease(bitrate);
    int maxKey = 2;
    CFNumberRef maxKeyInt = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &maxKey);
    VTSessionSetProperty(_session, kVTCompressionPropertyKey_MaxKeyFrameInterval, maxKeyInt);
    CFRelease(maxKeyInt);

    VTCompressionSessionPrepareToEncodeFrames(_session);
    NSLog(@"[XCD] encoder %dx%d @ %d fps, %d kbps", w, h, fps, kbps);
    return YES;
}

static void compressionOutputCallback(void *outputCallbackRefCon,
                                      void *sourceFrameRefCon,
                                      OSStatus status,
                                      VTEncodeInfoFlags infoFlags,
                                      CMSampleBufferRef sampleBuffer) {
    if (status != noErr || !sampleBuffer) return;

    XCDVideoEncoder *self = (__bridge XCDVideoEncoder *)outputCallbackRefCon;
    bool isKey = false;
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFDictionaryRef att = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFBooleanRef notSync = (CFBooleanRef)CFDictionaryGetValue(att, kCMSampleAttachmentKey_NotSync);
        isKey = (notSync == NULL);
    }

    // 从 sampleBuffer 取 CMBlockBuffer，转 Annex-B（加 start code）
    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!block) return;

    size_t lengthAtOffset = 0, totalLength = 0;
    char *dataPtr = NULL;
    CMBlockBufferGetDataPointer(block, 0, &lengthAtOffset, &totalLength, &dataPtr);

    // 首帧需要把 SPS/PPS 也内联进关键帧（computer-endian -> Annex-B）
    NSMutableData *out = [NSMutableData dataWithLength:totalLength + 4];
    // 简化：直接长度前缀转 start code 00 00 00 01。
    // 生产实现应遍历 NALU header 做长度前缀->start code 转换；
    // 这里在关键帧上补一个内联 SPS/PPS 的常见做法见 docs/编码说明.md。
    static const uint8_t startCode[4] = {0x00, 0x00, 0x00, 0x01};
    [out replaceBytesInRange:NSMakeRange(0, 4) withBytes:startCode];
    [out replaceBytesInRange:NSMakeRange(4, totalLength) withBytes:dataPtr];

    [self.delegate encoderDidOutputNALU:out isKeyframe:isKey];
}

- (void)encodePixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!_session || !pixelBuffer) return;
    CMTime pts = CMTimeMake(CACurrentMediaTime() * 1000, 1000);
    VTEncodeInfoFlags flags;
    VTCompressionSessionEncodeFrame(_session, pixelBuffer, pts, _frameDuration, NULL, NULL, &flags);
}

- (void)invalidate {
    if (_session) {
        VTCompressionSessionCompleteFrames(_session, kCMTimeInvalid);
        VTCompressionSessionInvalidate(_session);
        CFRelease(_session);
        _session = NULL;
    }
}

- (void)dealloc { [self invalidate]; }

@end
