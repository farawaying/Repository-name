#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

static NSString * const OWPrefsDomain = @"com.openai.orbitwindow";

@interface OWPrefs : NSObject
+ (BOOL)enabled;
+ (BOOL)enableNotificationFloating;
+ (BOOL)enableAppJumpFloating;
+ (BOOL)bottomCornersEnabled;
+ (CGFloat)triggerCornerWidth;
+ (CGFloat)triggerBottomHeight;
+ (NSArray<NSString *> *)selectedBundleIDs;
+ (CGFloat)pointsPerCentimeter;
+ (CGFloat)topMarginPoints;
+ (CGFloat)bottomMarginPoints;
+ (CGFloat)sideMarginPoints;
+ (CGFloat)dockWidthRatio;
+ (CGFloat)dockTopPoints;
+ (CGFloat)hiddenStripWidth;
+ (void)reload;
@end

NS_ASSUME_NONNULL_END
