//
//  XCDTouchInjector.h
//  越狱 iOS 触摸注入封装
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface XCDTouchInjector : NSObject
+ (instancetype)sharedInjector;

- (void)touchDownX:(float)x y:(float)y touchId:(uint8_t)tid;
- (void)touchMoveX:(float)x y:(float)y touchId:(uint8_t)tid;
- (void)touchUpTouchId:(uint8_t)tid;
- (void)swipeFromX:(float)x1 y1:(float)y1 x2:(float)x2 y2:(float)y2 duration:(float)sec;

@property (nonatomic, readonly) BOOL ready;
@end
