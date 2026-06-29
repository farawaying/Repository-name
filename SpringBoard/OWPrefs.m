#import "OWPrefs.h"

@implementation OWPrefs

+ (id)valueForKey:(NSString *)key fallback:(id)fallback {
    CFStringRef domain = (__bridge CFStringRef)OWPrefsDomain;
    CFStringRef k = (__bridge CFStringRef)key;
    CFPreferencesAppSynchronize(domain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(k, domain));
    return value ?: fallback;
}

+ (BOOL)boolForKey:(NSString *)key fallback:(BOOL)fallback {
    id v = [self valueForKey:key fallback:@(fallback)];
    if ([v respondsToSelector:@selector(boolValue)]) return [v boolValue];
    return fallback;
}

+ (CGFloat)floatForKey:(NSString *)key fallback:(CGFloat)fallback {
    id v = [self valueForKey:key fallback:@(fallback)];
    if ([v respondsToSelector:@selector(doubleValue)]) return (CGFloat)[v doubleValue];
    return fallback;
}

+ (BOOL)enabled { return [self boolForKey:@"enabled" fallback:YES]; }
+ (BOOL)enableNotificationFloating { return [self boolForKey:@"enableNotificationFloating" fallback:YES]; }
+ (BOOL)enableAppJumpFloating { return [self boolForKey:@"enableAppJumpFloating" fallback:YES]; }
+ (BOOL)bottomCornersEnabled { return [self boolForKey:@"bottomCornersEnabled" fallback:YES]; }
+ (CGFloat)triggerCornerWidth { return [self floatForKey:@"triggerCornerWidth" fallback:110.0]; }
+ (CGFloat)triggerBottomHeight { return [self floatForKey:@"triggerBottomHeight" fallback:42.0]; }

+ (NSArray<NSString *> *)selectedBundleIDs {
    id raw = [self valueForKey:@"selectedApps" fallback:nil];
    NSMutableArray<NSString *> *out = [NSMutableArray array];

    if ([raw isKindOfClass:[NSArray class]]) {
        for (id v in (NSArray *)raw) if ([v isKindOfClass:[NSString class]]) [out addObject:v];
    } else if ([raw isKindOfClass:[NSDictionary class]]) {
        [(NSDictionary *)raw enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if ([key isKindOfClass:[NSString class]] && [obj respondsToSelector:@selector(boolValue)] && [obj boolValue]) {
                [out addObject:key];
            }
        }];
    } else if ([raw isKindOfClass:[NSString class]]) {
        NSArray *parts = [(NSString *)raw componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",\n "]];
        for (NSString *part in parts) {
            NSString *trim = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trim.length > 0) [out addObject:trim];
        }
    }

    // The wheel is intentionally limited to apps selected in Settings.
    return [out copy];
}

+ (CGFloat)pointsPerCentimeter {
    // iPhone 13 Pro: 460 ppi / 3 native scale / 2.54 = ~60.37 pt/cm.
    // Exposed as a preference because Display Zoom / device model can shift perceived size.
    return [self floatForKey:@"pointsPerCentimeter" fallback:60.37];
}
+ (CGFloat)topMarginPoints { return [self floatForKey:@"topMarginCm" fallback:2.0] * [self pointsPerCentimeter]; }
+ (CGFloat)bottomMarginPoints { return [self floatForKey:@"bottomMarginCm" fallback:4.0] * [self pointsPerCentimeter]; }
+ (CGFloat)sideMarginPoints { return [self floatForKey:@"sideMarginCm" fallback:1.0] * [self pointsPerCentimeter]; }
+ (CGFloat)dockWidthRatio { return [self floatForKey:@"dockWidthRatio" fallback:0.44]; }
+ (CGFloat)dockTopPoints { return [self floatForKey:@"dockTopPt" fallback:92.0]; }
+ (CGFloat)hiddenStripWidth { return [self floatForKey:@"hiddenStripWidth" fallback:18.0]; }
+ (void)reload { CFPreferencesAppSynchronize((__bridge CFStringRef)OWPrefsDomain); }

@end
