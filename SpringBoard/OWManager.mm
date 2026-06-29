#import "OWManager.h"
#import "OWPassThroughWindow.h"
#import "OWWheelView.h"
#import "OWPrefs.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>

#define OWLog(fmt, ...) NSLog(@"[OrbitWindow] " fmt, ##__VA_ARGS__)

typedef NS_ENUM(NSInteger, OWMode) {
    OWModeIdle = 0,
    OWModeWheel,
    OWModeCenter,
    OWModeDock,
    OWModeHidden,
};

@interface OWChromeView : UIView
@property (nonatomic, weak) id manager;
@property (nonatomic) CGRect floatingFrame;
@property (nonatomic) OWMode mode;
@property (nonatomic, strong) UIView *handlePill;
@property (nonatomic, strong) UIView *whiteBar;
@property (nonatomic, strong) UIView *hiddenStrip;
@end

@implementation OWChromeView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.handlePill = [[UIView alloc] initWithFrame:CGRectZero];
        self.handlePill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.24];
        self.handlePill.layer.borderWidth = 0.5;
        self.handlePill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.36].CGColor;
        self.handlePill.layer.cornerRadius = 12;
        self.handlePill.layer.masksToBounds = YES;
        [self addSubview:self.handlePill];

        self.whiteBar = [[UIView alloc] initWithFrame:CGRectZero];
        self.whiteBar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.92];
        self.whiteBar.layer.cornerRadius = 2.5;
        self.whiteBar.layer.masksToBounds = YES;
        [self.handlePill addSubview:self.whiteBar];

        self.hiddenStrip = [[UIView alloc] initWithFrame:CGRectZero];
        self.hiddenStrip.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
        self.hiddenStrip.layer.cornerRadius = 7;
        self.hiddenStrip.layer.masksToBounds = YES;
        self.hiddenStrip.hidden = YES;
        [self addSubview:self.hiddenStrip];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect f = self.floatingFrame;
    if (CGRectIsEmpty(f)) return;
    CGFloat pillW = 118, pillH = 24;
    self.handlePill.frame = CGRectMake(CGRectGetMidX(f)-pillW/2.0, CGRectGetMaxY(f)+8, pillW, pillH);
    self.whiteBar.frame = CGRectMake((pillW-54)/2.0, (pillH-5)/2.0, 54, 5);
}
@end

@interface OWManager () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) OWPassThroughWindow *gestureWindow;
@property (nonatomic, strong) OWPassThroughWindow *overlayWindow;
@property (nonatomic, strong) OWWheelView *wheelView;
@property (nonatomic, strong) OWChromeView *chromeView;
@property (nonatomic, weak) UIView *hostView;
@property (nonatomic, weak) UIView *hostSuperview;
@property (nonatomic) CGRect originalHostFrame;
@property (nonatomic) CGRect currentFloatingFrame;
@property (nonatomic) OWMode mode;
@property (nonatomic, copy) NSString *currentBundleID;
@property (nonatomic, strong) CADisplayLink *enforceLink;
@property (nonatomic) BOOL started;
@property (nonatomic) CGPoint dockPanStartCenter;
@property (nonatomic) CGRect dockPanStartFrame;
@property (nonatomic) UIRectEdge dockAttachedEdge;
@property (nonatomic) CGPoint triggerPanStart;
@end

@implementation OWManager

+ (instancetype)shared {
    static OWManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [OWManager new]; });
    return m;
}

- (void)start {
    if (self.started) return;
    self.started = YES;
    self.mode = OWModeIdle;
    self.dockAttachedEdge = UIRectEdgeRight;

    [self createGestureWindow];
    [self createOverlayWindow];
    [self installDarwinNotifications];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadPreferences) name:@"OWPreferencesChanged" object:nil];
    OWLog(@"started; selected=%@", [OWPrefs selectedBundleIDs]);
}

- (void)reloadPreferences {
    [OWPrefs reload];
    self.gestureWindow.hidden = ![OWPrefs enabled];
    OWLog(@"preferences reloaded; selected=%@", [OWPrefs selectedBundleIDs]);
}

- (void)installDarwinNotifications {
    int token = 0;
    notify_register_dispatch("com.openai.orbitwindow.preferences.changed", &token, dispatch_get_main_queue(), ^(__unused int t) {
        [self reloadPreferences];
    });
    int token2 = 0;
    notify_register_dispatch("com.openai.orbitwindow.open.bundle", &token2, dispatch_get_main_queue(), ^(__unused int t) {
        CFPreferencesAppSynchronize(CFSTR("com.openai.orbitwindow.pending"));
        NSString *bundleID = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("bundleID"), CFSTR("com.openai.orbitwindow.pending")));
        if ([bundleID isKindOfClass:NSString.class] && bundleID.length) {
            [self openBundleIDFloating:bundleID reason:@"darwin-open-bundle"];
        }
    });
}

- (void)createGestureWindow {
    self.gestureWindow = [[OWPassThroughWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.gestureWindow.windowLevel = UIWindowLevelStatusBar + 920;
    self.gestureWindow.backgroundColor = UIColor.clearColor;
    self.gestureWindow.hidden = ![OWPrefs enabled];
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    self.gestureWindow.rootViewController = vc;

    __weak typeof(self) weakSelf = self;
    self.gestureWindow.shouldReceivePoint = ^BOOL(CGPoint p, UIView *hit) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![OWPrefs enabled]) return NO;
        if (self.mode != OWModeIdle) return NO;
        CGRect b = self.gestureWindow.bounds;
        CGFloat bottomH = [OWPrefs triggerBottomHeight];
        CGFloat cornerW = [OWPrefs triggerCornerWidth];
        BOOL bottomLeft = [OWPrefs bottomCornersEnabled] && p.y >= CGRectGetHeight(b)-bottomH && p.x <= cornerW;
        BOOL bottomRight = [OWPrefs bottomCornersEnabled] && p.y >= CGRectGetHeight(b)-bottomH && p.x >= CGRectGetWidth(b)-cornerW;
        return bottomLeft || bottomRight;
    };

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(edgePan:)];
    pan.delegate = self;
    [vc.view addGestureRecognizer:pan];
}

- (void)createOverlayWindow {
    self.overlayWindow = [[OWPassThroughWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.overlayWindow.windowLevel = UIWindowLevelStatusBar + 930;
    self.overlayWindow.backgroundColor = UIColor.clearColor;
    self.overlayWindow.hidden = YES;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    self.overlayWindow.rootViewController = vc;

    self.chromeView = [[OWChromeView alloc] initWithFrame:vc.view.bounds];
    self.chromeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:self.chromeView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(overlayTapped:)];
    tap.delegate = self;
    [vc.view addGestureRecognizer:tap];

    UIPanGestureRecognizer *handlePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.chromeView.handlePill addGestureRecognizer:handlePan];

    UIPanGestureRecognizer *dockPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dockPan:)];
    [vc.view addGestureRecognizer:dockPan];
    dockPan.delegate = self;

    __weak typeof(self) weakSelf = self;
    self.overlayWindow.shouldReceivePoint = ^BOOL(CGPoint p, UIView *hit) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.mode == OWModeIdle) return NO;
        if (self.mode == OWModeWheel) return YES;
        if (self.mode == OWModeCenter) {
            if (CGRectContainsPoint(self.currentFloatingFrame, p)) {
                // Allow app content to receive normal touches, except the bottom handle.
                CGPoint inHandle = [self.chromeView.handlePill convertPoint:p fromView:self.overlayWindow];
                return [self.chromeView.handlePill pointInside:inHandle withEvent:nil];
            }
            return YES; // outside tap closes
        }
        if (self.mode == OWModeDock) {
            return CGRectContainsPoint(CGRectInset(self.currentFloatingFrame, -12, -12), p);
        }
        if (self.mode == OWModeHidden) {
            return CGRectContainsPoint(self.chromeView.hiddenStrip.frame, p);
        }
        return NO;
    };
}

#pragma mark - Edge gestures / wheel

- (void)edgePan:(UIPanGestureRecognizer *)gr {
    if (![OWPrefs enabled]) return;
    CGPoint p = [gr locationInView:self.gestureWindow];
    CGPoint v = [gr velocityInView:self.gestureWindow];
    CGPoint t = [gr translationInView:self.gestureWindow];
    CGRect b = self.gestureWindow.bounds;
    CGFloat bottomH = [OWPrefs triggerBottomHeight] + 18.0;
    CGFloat cornerW = [OWPrefs triggerCornerWidth];

    if (gr.state == UIGestureRecognizerStateBegan) {
        self.triggerPanStart = p;
        return;
    }

    if (gr.state == UIGestureRecognizerStateEnded || gr.state == UIGestureRecognizerStateCancelled) {
        CGPoint start = self.triggerPanStart;
        BOOL startLeft = start.y >= CGRectGetHeight(b)-bottomH && start.x <= cornerW;
        BOOL startRight = start.y >= CGRectGetHeight(b)-bottomH && start.x >= CGRectGetWidth(b)-cornerW;
        BOOL upward = (v.y < -120.0) || (t.y < -42.0);
        BOOL inwardFromLeft = (v.x > 120.0) || (t.x > 42.0);
        BOOL inwardFromRight = (v.x < -120.0) || (t.x < -42.0);

        if (startLeft && upward && inwardFromLeft) {
            [self showWheelFromEdge:UIRectEdgeLeft];
        } else if (startRight && upward && inwardFromRight) {
            [self showWheelFromEdge:UIRectEdgeRight];
        }
    }
}

- (void)showWheelFromEdge:(UIRectEdge)edge {
    if (![OWPrefs enabled]) return;
    [self restoreHostIfNeeded];
    self.mode = OWModeWheel;
    self.overlayWindow.hidden = NO;
    self.chromeView.hidden = YES;

    if (!self.wheelView) {
        self.wheelView = [[OWWheelView alloc] initWithFrame:CGRectZero];
        __weak typeof(self) weakSelf = self;
        self.wheelView.selectionHandler = ^(NSString *bundleID) {
            [weakSelf hideWheel];
            [weakSelf openBundleIDFloating:bundleID reason:@"wheel"];
        };
        [self.overlayWindow.rootViewController.view addSubview:self.wheelView];
    }
    CGRect screen = self.overlayWindow.bounds;
    CGFloat side = MIN(270.0, CGRectGetWidth(screen)-32.0);
    CGFloat x = edge == UIRectEdgeLeft ? 16.0 : CGRectGetWidth(screen)-side-16.0;
    CGFloat y = CGRectGetHeight(screen)-side-96.0;
    self.wheelView.frame = CGRectMake(x, MAX(70.0, y), side, side);
    self.wheelView.bundleIDs = [OWPrefs selectedBundleIDs];
    [self.wheelView reloadIcons];

    self.wheelView.alpha = 0;
    self.wheelView.transform = CGAffineTransformMakeScale(0.86, 0.86);
    [UIView animateWithDuration:0.18 animations:^{
        self.wheelView.alpha = 1;
        self.wheelView.transform = CGAffineTransformIdentity;
    }];
}

- (void)hideWheel {
    [UIView animateWithDuration:0.12 animations:^{ self.wheelView.alpha = 0; } completion:^(__unused BOOL finished) {
        self.wheelView.hidden = YES;
    }];
    self.mode = OWModeIdle;
    self.overlayWindow.hidden = YES;
    self.chromeView.hidden = NO;
}

#pragma mark - Launch / floating

- (void)openBundleIDFloating:(NSString *)bundleID reason:(NSString *)reason {
    if (![OWPrefs enabled] || bundleID.length == 0) return;
    self.currentBundleID = bundleID;
    OWLog(@"open floating %@ reason=%@", bundleID, reason);

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)] ? [workspaceClass performSelector:@selector(defaultWorkspace)] : nil;
    BOOL launched = NO;
    SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
    if (workspace && [workspace respondsToSelector:openSel]) {
        launched = ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, openSel, bundleID);
    }
    if (!launched) OWLog(@"LSApplicationWorkspace open returned NO; will still try to float foreground scene");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self enterCenterModeForCurrentForegroundScene];
    });
}

- (CGRect)centerFrameForScreen:(CGRect)screen {
    CGFloat left = [OWPrefs sideMarginPoints];
    CGFloat right = [OWPrefs sideMarginPoints];
    CGFloat top = [OWPrefs topMarginPoints];
    CGFloat bottom = [OWPrefs bottomMarginPoints];
    CGRect frame = CGRectMake(left, top, CGRectGetWidth(screen)-left-right, CGRectGetHeight(screen)-top-bottom);
    return CGRectIntegral(frame);
}

- (CGRect)dockFrameNearEdge:(UIRectEdge)edge fromFrame:(CGRect)source {
    CGRect screen = self.overlayWindow.bounds;
    CGFloat w = CGRectGetWidth(screen) * [OWPrefs dockWidthRatio];
    CGFloat aspect = source.size.height / MAX(source.size.width, 1.0);
    CGFloat h = MIN(w * aspect, CGRectGetHeight(screen) * 0.34);
    CGFloat y = [OWPrefs dockTopPoints];
    CGFloat x = edge == UIRectEdgeLeft ? 10.0 : CGRectGetWidth(screen)-w-10.0;
    return CGRectIntegral(CGRectMake(x, y, w, h));
}

- (void)enterCenterModeForCurrentForegroundScene {
    UIView *host = [self findLikelyAppHostView];
    if (!host) {
        OWLog(@"no app host view found; cannot float yet");
        return;
    }
    self.hostView = host;
    self.hostSuperview = host.superview;
    self.originalHostFrame = host.frame;
    self.currentFloatingFrame = [self centerFrameForScreen:self.overlayWindow.bounds];
    self.mode = OWModeCenter;
    self.overlayWindow.hidden = NO;
    self.chromeView.hidden = NO;
    self.chromeView.mode = OWModeCenter;
    self.chromeView.floatingFrame = self.currentFloatingFrame;
    self.chromeView.handlePill.hidden = NO;
    self.chromeView.hiddenStrip.hidden = YES;
    [self.chromeView setNeedsLayout];
    [self applyFloatingFrameAnimated:YES];
    [self startEnforcingFrame];
}

- (void)enterDockModeFromCurrentFrame {
    self.mode = OWModeDock;
    self.dockAttachedEdge = UIRectEdgeRight;
    self.currentFloatingFrame = [self dockFrameNearEdge:UIRectEdgeRight fromFrame:self.currentFloatingFrame];
    self.chromeView.mode = OWModeDock;
    self.chromeView.floatingFrame = self.currentFloatingFrame;
    self.chromeView.handlePill.hidden = YES;
    self.chromeView.hiddenStrip.hidden = YES;
    [self.chromeView setNeedsLayout];
    [self applyFloatingFrameAnimated:YES];
}

- (void)enterHiddenModeFromDock {
    CGRect screen = self.overlayWindow.bounds;
    BOOL left = self.dockAttachedEdge == UIRectEdgeLeft;
    CGFloat stripW = [OWPrefs hiddenStripWidth];
    CGFloat stripH = MIN(86.0, self.currentFloatingFrame.size.height);
    CGFloat x = left ? 0 : CGRectGetWidth(screen)-stripW;
    CGFloat y = MIN(MAX(CGRectGetMidY(self.currentFloatingFrame)-stripH/2.0, 72.0), CGRectGetHeight(screen)-stripH-72.0);
    self.mode = OWModeHidden;
    self.chromeView.mode = OWModeHidden;
    self.chromeView.handlePill.hidden = YES;
    self.chromeView.hiddenStrip.hidden = NO;
    self.chromeView.hiddenStrip.frame = CGRectMake(x, y, stripW, stripH);

    CGRect hiddenFrame = self.currentFloatingFrame;
    hiddenFrame.origin.x = left ? -hiddenFrame.size.width + 2.0 : CGRectGetWidth(screen) - 2.0;
    self.currentFloatingFrame = hiddenFrame;
    [self applyFloatingFrameAnimated:YES];
}

- (void)restoreDockFromHiddenAtPoint:(CGPoint)p {
    CGRect screen = self.overlayWindow.bounds;
    CGFloat w = CGRectGetWidth(screen) * [OWPrefs dockWidthRatio];
    CGFloat h = MIN(w * 1.78, CGRectGetHeight(screen) * 0.34);
    BOOL left = self.dockAttachedEdge == UIRectEdgeLeft;
    CGFloat x = left ? 10.0 : CGRectGetWidth(screen)-w-10.0;
    CGFloat y = MIN(MAX(p.y-h/2.0, 70.0), CGRectGetHeight(screen)-h-70.0);
    self.currentFloatingFrame = CGRectIntegral(CGRectMake(x, y, w, h));
    self.mode = OWModeDock;
    self.chromeView.mode = OWModeDock;
    self.chromeView.floatingFrame = self.currentFloatingFrame;
    self.chromeView.hiddenStrip.hidden = YES;
    [self applyFloatingFrameAnimated:YES];
}

- (void)restoreCenterFromDock {
    self.mode = OWModeCenter;
    self.currentFloatingFrame = [self centerFrameForScreen:self.overlayWindow.bounds];
    self.chromeView.mode = OWModeCenter;
    self.chromeView.floatingFrame = self.currentFloatingFrame;
    self.chromeView.handlePill.hidden = NO;
    self.chromeView.hiddenStrip.hidden = YES;
    [self.chromeView setNeedsLayout];
    [self applyFloatingFrameAnimated:YES];
}

- (void)applyFloatingFrameAnimated:(BOOL)animated {
    UIView *host = self.hostView;
    UIView *superview = self.hostSuperview ?: host.superview;
    if (!host || !superview || self.mode == OWModeIdle) return;
    CGRect target = [superview convertRect:self.currentFloatingFrame fromView:nil];
    void (^changes)(void) = ^{
        host.transform = CGAffineTransformIdentity;
        host.frame = target;
        host.layer.cornerRadius = (self.mode == OWModeDock || self.mode == OWModeHidden) ? 18.0 : 22.0;
        host.layer.masksToBounds = YES;
        host.layer.borderWidth = 0.5;
        host.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
        host.layer.shadowOpacity = 0.0;
        self.chromeView.floatingFrame = self.currentFloatingFrame;
        [self.chromeView setNeedsLayout];
    };
    if (animated) [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:changes completion:nil];
    else changes();
}

- (void)startEnforcingFrame {
    [self.enforceLink invalidate];
    self.enforceLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(enforceFrameTick)];
    if (@available(iOS 15.0, *)) self.enforceLink.preferredFrameRateRange = CAFrameRateRangeMake(12, 20, 20);
    [self.enforceLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)enforceFrameTick {
    if (self.mode == OWModeIdle || self.mode == OWModeWheel || !self.hostView) return;
    [self applyFloatingFrameAnimated:NO];
}

- (void)restoreHostIfNeeded {
    [self.enforceLink invalidate];
    self.enforceLink = nil;
    UIView *host = self.hostView;
    if (host && self.hostSuperview) {
        [UIView animateWithDuration:0.18 animations:^{
            host.transform = CGAffineTransformIdentity;
            host.frame = self.originalHostFrame;
            host.layer.cornerRadius = 0;
            host.layer.masksToBounds = NO;
            host.layer.borderWidth = 0;
        }];
    }
    self.hostView = nil;
    self.hostSuperview = nil;
}

- (void)closeFloatingWindow {
    OWLog(@"close floating window");
    [self restoreHostIfNeeded];
    self.mode = OWModeIdle;
    self.currentBundleID = nil;
    self.overlayWindow.hidden = YES;
    [self goHomeBestEffort];
}

#pragma mark - Touch handlers

- (void)overlayTapped:(UITapGestureRecognizer *)tap {
    CGPoint p = [tap locationInView:self.overlayWindow];
    if (self.mode == OWModeWheel) {
        if (!CGRectContainsPoint(self.wheelView.frame, p)) [self hideWheel];
        return;
    }
    if (self.mode == OWModeCenter) {
        if (!CGRectContainsPoint(self.currentFloatingFrame, p)) [self closeFloatingWindow];
        return;
    }
    if (self.mode == OWModeDock) {
        if (CGRectContainsPoint(CGRectInset(self.currentFloatingFrame, -14, -14), p)) [self restoreCenterFromDock];
        return;
    }
    if (self.mode == OWModeHidden) {
        if (CGRectContainsPoint(self.chromeView.hiddenStrip.frame, p)) [self restoreDockFromHiddenAtPoint:p];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (self.mode != OWModeCenter) return;
    CGPoint v = [pan velocityInView:self.overlayWindow];
    if (pan.state == UIGestureRecognizerStateEnded && v.y < -120.0) {
        [self enterDockModeFromCurrentFrame];
    }
}

- (void)dockPan:(UIPanGestureRecognizer *)pan {
    CGPoint p = [pan locationInView:self.overlayWindow];
    if (self.mode == OWModeHidden) {
        if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
            [self restoreDockFromHiddenAtPoint:p];
        }
        return;
    }
    if (self.mode != OWModeDock) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.dockPanStartFrame = self.currentFloatingFrame;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint tr = [pan translationInView:self.overlayWindow];
        CGRect f = self.dockPanStartFrame;
        f.origin.x += tr.x;
        f.origin.y += tr.y;
        self.currentFloatingFrame = f;
        self.chromeView.floatingFrame = f;
        [self applyFloatingFrameAnimated:NO];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        [self snapDockOrHideWithVelocity:[pan velocityInView:self.overlayWindow]];
    }
}

- (void)snapDockOrHideWithVelocity:(CGPoint)velocity {
    CGRect screen = self.overlayWindow.bounds;
    CGRect f = self.currentFloatingFrame;
    BOOL attachLeft = CGRectGetMidX(f) < CGRectGetMidX(screen);
    self.dockAttachedEdge = attachLeft ? UIRectEdgeLeft : UIRectEdgeRight;

    CGFloat pushThreshold = 28.0;
    BOOL pushedLeft = CGRectGetMinX(f) < -pushThreshold && velocity.x < -80.0;
    BOOL pushedRight = CGRectGetMaxX(f) > CGRectGetWidth(screen)+pushThreshold && velocity.x > 80.0;
    if ((attachLeft && pushedLeft) || (!attachLeft && pushedRight)) {
        [self enterHiddenModeFromDock];
        return;
    }

    f.origin.x = attachLeft ? 10.0 : CGRectGetWidth(screen)-f.size.width-10.0;
    f.origin.y = MIN(MAX(f.origin.y, 70.0), CGRectGetHeight(screen)-f.size.height-70.0);
    self.currentFloatingFrame = CGRectIntegral(f);
    [self applyFloatingFrameAnimated:YES];
}

#pragma mark - Host view discovery

- (UIView *)findLikelyAppHostView {
    NSArray<UIWindow *> *windows = UIApplication.sharedApplication.windows;
    UIView *best = nil;
    CGFloat bestArea = 0;
    for (UIWindow *window in windows) {
        if ([window isKindOfClass:OWPassThroughWindow.class]) continue;
        UIView *candidate = [self findSceneHostInView:window minArea:&bestArea currentBest:best];
        if (candidate) best = candidate;
    }
    OWLog(@"host candidate=%@ frame=%@", best, NSStringFromCGRect(best.frame));
    return best;
}

- (UIView *)findSceneHostInView:(UIView *)view minArea:(CGFloat *)bestArea currentBest:(UIView *)best {
    NSString *className = NSStringFromClass(view.class);
    BOOL nameMatch = [className containsString:@"SceneHost"] || [className containsString:@"FBScene"] || [className containsString:@"AppContainer"] || [className containsString:@"HostWrapper"] || [className containsString:@"ContextLayer"];
    CGRect rectOnScreen = [view convertRect:view.bounds toView:nil];
    CGFloat area = rectOnScreen.size.width * rectOnScreen.size.height;
    if (nameMatch && area > *bestArea && area > 80000.0) {
        best = view;
        *bestArea = area;
    }
    for (UIView *sub in view.subviews) {
        best = [self findSceneHostInView:sub minArea:bestArea currentBest:best];
    }
    return best;
}

#pragma mark - Best effort private actions

- (void)goHomeBestEffort {
    NSArray<NSString *> *classNames = @[@"SBUIController", @"SBMainWorkspace", @"SpringBoard"];
    NSArray<NSString *> *selectors = @[@"sharedInstance", @"sharedWorkspace", @"sharedApplication"];
    NSArray<NSString *> *actions = @[@"clickedMenuButton", @"handleMenuButtonTap", @"goHome", @"_simulateHomeButtonPress"];

    for (NSUInteger i = 0; i < classNames.count; i++) {
        Class cls = NSClassFromString(classNames[i]);
        if (!cls) continue;
        id obj = nil;
        SEL maker = NSSelectorFromString(selectors[i]);
        if ([cls respondsToSelector:maker]) obj = [cls performSelector:maker];
        if (!obj) continue;
        for (NSString *action in actions) {
            SEL sel = NSSelectorFromString(action);
            if ([obj respondsToSelector:sel]) {
                ((void (*)(id, SEL))objc_msgSend)(obj, sel);
                return;
            }
        }
    }
}

#pragma mark - Gesture delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    CGPoint p = [touch locationInView:self.overlayWindow ?: self.gestureWindow];
    if (self.mode == OWModeDock) return CGRectContainsPoint(CGRectInset(self.currentFloatingFrame, -14, -14), p);
    if (self.mode == OWModeHidden) return CGRectContainsPoint(self.chromeView.hiddenStrip.frame, p);
    return YES;
}

@end
