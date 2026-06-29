#import "OWRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import <spawn.h>

static NSString * const OWPrefsDomain = @"com.openai.orbitwindow";

@implementation OWRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id fallback = [specifier propertyForKey:@"default"];
    if (!key) return fallback;
    CFPreferencesAppSynchronize((__bridge CFStringRef)OWPrefsDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)OWPrefsDomain));
    return value ?: fallback;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFTypeRef)value, (__bridge CFStringRef)OWPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)OWPrefsDomain);
    notify_post("com.openai.orbitwindow.preferences.changed");
}

- (void)respring {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"注销应用插件效果" message:@"这会注销并重新载入桌面 SpringBoard，用来让插件效果重新生效；不是重启手机。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"注销" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        pid_t pid;
        const char *args[] = {"killall", "-9", "SpringBoard", NULL};
        posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char * const *)args, NULL);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clearSelectedApps {
    CFPreferencesSetAppValue(CFSTR("selectedApps"), NULL, (__bridge CFStringRef)OWPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)OWPrefsDomain);
    notify_post("com.openai.orbitwindow.preferences.changed");
    [self reloadSpecifiers];
}

@end
