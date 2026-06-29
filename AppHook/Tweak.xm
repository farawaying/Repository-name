#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <notify.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const OWPrefsDomainApp = @"com.openai.orbitwindow";

static id OWPref(NSString *key, id fallback) {
    CFStringRef domain = (__bridge CFStringRef)OWPrefsDomainApp;
    CFPreferencesAppSynchronize(domain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain));
    return value ?: fallback;
}

static BOOL OWBoolPref(NSString *key, BOOL fallback) {
    id v = OWPref(key, @(fallback));
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : fallback;
}

static NSArray<NSString *> *OWSelectedApps(void) {
    id raw = OWPref(@"selectedApps", nil);
    NSMutableArray *out = [NSMutableArray array];
    if ([raw isKindOfClass:NSArray.class]) {
        for (id v in raw) if ([v isKindOfClass:NSString.class]) [out addObject:v];
    } else if ([raw isKindOfClass:NSDictionary.class]) {
        [(NSDictionary *)raw enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if ([key isKindOfClass:NSString.class] && [obj respondsToSelector:@selector(boolValue)] && [obj boolValue]) [out addObject:key];
        }];
    } else if ([raw isKindOfClass:NSString.class]) {
        for (NSString *part in [(NSString *)raw componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",\n "]]) {
            NSString *trim = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (trim.length) [out addObject:trim];
        }
    }
    return out;
}

static NSString *OWBundleForURL(NSURL *url) {
    if (!url.scheme.length) return nil;
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    id workspace = [workspaceClass respondsToSelector:@selector(defaultWorkspace)] ? [workspaceClass performSelector:@selector(defaultWorkspace)] : nil;
    if (!workspace) return nil;

    SEL sel = NSSelectorFromString(@"applicationsAvailableForHandlingURLScheme:");
    if ([workspace respondsToSelector:sel]) {
        NSArray *apps = ((id (*)(id, SEL, id))objc_msgSend)(workspace, sel, url.scheme);
        for (id proxy in apps) {
            NSString *bid = nil;
            @try { bid = [proxy valueForKey:@"bundleIdentifier"]; } @catch (__unused NSException *e) {}
            if ([bid isKindOfClass:NSString.class] && bid.length) return bid;
        }
    }
    return nil;
}

static BOOL OWRequestSpringBoardOpenFloating(NSURL *url) {
    if (!OWBoolPref(@"enabled", YES) || !OWBoolPref(@"enableAppJumpFloating", YES)) return NO;
    NSString *target = OWBundleForURL(url);
    if (!target.length) return NO;

    // App-to-App jumps are intentionally global by default: any installed target app can be opened floating.
    // Wheel choices remain controlled by selectedApps in Settings.

    CFPreferencesSetAppValue(CFSTR("bundleID"), (__bridge CFStringRef)target, CFSTR("com.openai.orbitwindow.pending"));
    CFPreferencesAppSynchronize(CFSTR("com.openai.orbitwindow.pending"));
    notify_post("com.openai.orbitwindow.open.bundle");
    NSLog(@"[OrbitWindowAppHook] requested floating open for %@ from URL scheme %@", target, url.scheme);
    return YES;
}

%group UserAppHooks

%hook UIApplication

- (BOOL)openURL:(NSURL *)url {
    if (OWRequestSpringBoardOpenFloating(url)) return YES;
    return %orig;
}

- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL success))completion {
    if (OWRequestSpringBoardOpenFloating(url)) {
        if (completion) completion(YES);
        return;
    }
    %orig;
}

%end

%end

%ctor {
    @autoreleasepool {
        NSString *proc = NSProcessInfo.processInfo.processName;
        if ([proc isEqualToString:@"SpringBoard"]) return;
        %init(UserAppHooks);
    }
}
