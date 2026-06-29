#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWPassThroughWindow : UIWindow
@property (nonatomic, copy, nullable) BOOL (^shouldReceivePoint)(CGPoint pointInWindow, UIView *_Nullable hitView);
@end

NS_ASSUME_NONNULL_END
