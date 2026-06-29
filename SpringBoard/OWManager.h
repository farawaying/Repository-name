#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWManager : NSObject
+ (instancetype)shared;
- (void)start;
- (void)reloadPreferences;
- (void)showWheelFromEdge:(UIRectEdge)edge;
- (void)openBundleIDFloating:(NSString *)bundleID reason:(NSString *)reason;
@end

NS_ASSUME_NONNULL_END
