#import <UIKit/UIKit.h>
#import "OWManager.h"
#import "OWPrefs.h"

%ctor {
    @autoreleasepool {
        NSString *proc = NSProcessInfo.processInfo.processName;
        if (![proc isEqualToString:@"SpringBoard"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[OWManager shared] start];
        });
    }
}

// Notification tap support: selectors differ across iOS builds. These hooks are deliberately best-effort.
%hook SBNotificationBannerDestination
- (void)handleTapForNotificationRequest:(id)request {
    NSString *bundleID = nil;
    @try {
        id sectionID = [request valueForKey:@"sectionIdentifier"];
        if ([sectionID isKindOfClass:NSString.class]) bundleID = sectionID;
    } @catch (__unused NSException *e) {}
    if (bundleID.length && [OWPrefs enableNotificationFloating]) {
        [[OWManager shared] openBundleIDFloating:bundleID reason:@"notification-banner"];
        return;
    }
    %orig;
}
%end

%hook NCNotificationShortLookViewController
- (void)_handleDefaultAction:(id)arg1 {
    NSString *bundleID = nil;
    @try {
        id request = [self valueForKey:@"notificationRequest"];
        id sectionID = [request valueForKey:@"sectionIdentifier"];
        if ([sectionID isKindOfClass:NSString.class]) bundleID = sectionID;
    } @catch (__unused NSException *e) {}
    if (bundleID.length && [OWPrefs enableNotificationFloating]) {
        [[OWManager shared] openBundleIDFloating:bundleID reason:@"notification-shortlook"];
        return;
    }
    %orig;
}
%end
