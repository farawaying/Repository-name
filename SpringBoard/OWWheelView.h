#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWWheelView : UIView
@property (nonatomic, copy) NSArray<NSString *> *bundleIDs;
@property (nonatomic, copy, nullable) void (^selectionHandler)(NSString *bundleID);
- (void)reloadIcons;
@end

NS_ASSUME_NONNULL_END
