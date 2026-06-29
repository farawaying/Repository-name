#import "OWWheelView.h"
#import <objc/runtime.h>

static UIImage *OWIconForBundle(NSString *bundleID) {
    Class UIImageClass = UIImage.class;
    SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if ([UIImageClass respondsToSelector:sel]) {
        NSMethodSignature *sig = [UIImageClass methodSignatureForSelector:sel];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        inv.target = UIImageClass;
        inv.selector = sel;
        NSString *bid = bundleID;
        NSInteger format = 2;
        CGFloat scale = UIScreen.mainScreen.scale;
        [inv setArgument:&bid atIndex:2];
        [inv setArgument:&format atIndex:3];
        [inv setArgument:&scale atIndex:4];
        [inv invoke];
        __unsafe_unretained UIImage *img = nil;
        [inv getReturnValue:&img];
        if (img) return img;
    }
    return nil;
}

static NSString *OWShortNameForBundle(NSString *bundleID) {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = nil;
    if ([workspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
        workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
    }
    id proxy = nil;
    SEL appProxySel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (workspace && [workspace respondsToSelector:appProxySel]) {
        proxy = [workspace performSelector:appProxySel withObject:bundleID];
    }
    for (NSString *key in @[@"localizedName", @"bundleExecutable", @"itemName"]) {
        @try {
            id value = [proxy valueForKey:key];
            if ([value isKindOfClass:NSString.class] && [value length] > 0) return value;
        } @catch (__unused NSException *e) {}
    }
    return bundleID.lastPathComponent ?: bundleID;
}

@implementation OWWheelView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.22];
        self.layer.cornerRadius = MIN(frame.size.width, frame.size.height) / 2.0;
        self.layer.masksToBounds = YES;
        self.bundleIDs = @[];
    }
    return self;
}

- (void)setFrame:(CGRect)frame {
    [super setFrame:frame];
    self.layer.cornerRadius = MIN(frame.size.width, frame.size.height) / 2.0;
    [self setNeedsLayout];
}

- (void)reloadIcons {
    for (UIView *v in self.subviews) [v removeFromSuperview];
    NSArray<NSString *> *ids = self.bundleIDs ?: @[];
    if (ids.count == 0) return;

    CGFloat side = 62.0;
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.34;

    [ids enumerateObjectsUsingBlock:^(NSString *bundleID, NSUInteger idx, BOOL *stop) {
        CGFloat angle = -M_PI_2 + ((CGFloat)idx / MAX((CGFloat)ids.count, 1.0)) * M_PI * 2.0;
        CGPoint p = CGPointMake(center.x + cos(angle) * radius, center.y + sin(angle) * radius);
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(p.x - side / 2.0, p.y - side / 2.0, side, side);
        button.layer.cornerRadius = 16.0;
        button.layer.masksToBounds = YES;
        button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
        button.accessibilityLabel = bundleID;
        button.tag = idx;

        UIImage *icon = OWIconForBundle(bundleID);
        if (icon) {
            [button setImage:icon forState:UIControlStateNormal];
            button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        } else {
            NSString *name = OWShortNameForBundle(bundleID);
            NSString *first = name.length ? [[name substringToIndex:1] uppercaseString] : @"?";
            [button setTitle:first forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont boldSystemFontOfSize:28];
        }
        [button addTarget:self action:@selector(iconTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];
    }];
}

- (void)iconTapped:(UIButton *)sender {
    if (sender.tag < self.bundleIDs.count && self.selectionHandler) {
        self.selectionHandler(self.bundleIDs[sender.tag]);
    }
}

@end
