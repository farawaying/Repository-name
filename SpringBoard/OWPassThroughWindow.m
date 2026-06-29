#import "OWPassThroughWindow.h"

@implementation OWPassThroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;
    if (self.shouldReceivePoint && !self.shouldReceivePoint(point, hit)) {
        return nil;
    }
    return hit;
}
@end
