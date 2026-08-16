#import "APANRootListController.h"
#import <notify.h>

static NSString * const kAPANBundleID = @"com.ayao.airpodsautonoise";
static NSString * const kAPANEnabledKey            = @"apan_enabled";
static NSString * const kAPANAutoANCOnConnectKey   = @"apan_auto_anc_on_connect";
static NSString * const kAPANAutoANCOnPlayKey      = @"apan_auto_anc_on_play";
static NSString * const kAPANAutoTransOnStopKey    = @"apan_auto_trans_on_stop";
static NSString * const kAPANCooldownSecondsKey    = @"apan_cooldown_seconds";
static NSString * const kAPANAppBlacklistKey       = @"apan_app_blacklist";

static NSString * const kAPANPrefsChangedNotification = @"com.ayao.airpodsautonoise.prefsChanged";

@implementation APANRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        // 总开关组
        PSSpecifier *masterGroup = [PSSpecifier emptyGroupSpecifier];
        [masterGroup setProperty:@"AirPods 自动降噪" forKey:@"header"];
        [masterGroup setProperty:@"识别支持降噪的 AirPods Pro/Max 后，根据播放状态自动切换主动降噪与通透模式。" forKey:@"footer"];
        [specs addObject:masterGroup];

        PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"启用插件"
                                                             target:self
                                                                set:@selector(setPreferenceValue:specifier:)
                                                                get:@selector(readPreferenceValue:)
                                                             detail:nil
                                                               cell:PSSwitchCell
                                                               edit:nil];
        [enabled setProperty:kAPANEnabledKey forKey:@"key"];
        [enabled setProperty:@(YES) forKey:@"default"];
        [specs addObject:enabled];

        // 触发条件组
        PSSpecifier *triggersGroup = [PSSpecifier emptyGroupSpecifier];
        [triggersGroup setProperty:@"自动化条件" forKey:@"header"];
        [specs addObject:triggersGroup];

        PSSpecifier *onConnect = [PSSpecifier preferenceSpecifierNamed:@"连接时自动降噪"
                                                               target:self
                                                                  set:@selector(setPreferenceValue:specifier:)
                                                                  get:@selector(readPreferenceValue:)
                                                               detail:nil
                                                                 cell:PSSwitchCell
                                                                 edit:nil];
        [onConnect setProperty:kAPANAutoANCOnConnectKey forKey:@"key"];
        [onConnect setProperty:@(YES) forKey:@"default"];
        [specs addObject:onConnect];

        PSSpecifier *onPlay = [PSSpecifier preferenceSpecifierNamed:@"播放时切降噪"
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSSwitchCell
                                                              edit:nil];
        [onPlay setProperty:kAPANAutoANCOnPlayKey forKey:@"key"];
        [onPlay setProperty:@(YES) forKey:@"default"];
        [specs addObject:onPlay];

        PSSpecifier *onStop = [PSSpecifier preferenceSpecifierNamed:@"停止时切通透"
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSSwitchCell
                                                              edit:nil];
        [onStop setProperty:kAPANAutoTransOnStopKey forKey:@"key"];
        [onStop setProperty:@(YES) forKey:@"default"];
        [specs addObject:onStop];

        // 冷却时间
        PSSpecifier *advancedGroup = [PSSpecifier emptyGroupSpecifier];
        [advancedGroup setProperty:@"高级" forKey:@"header"];
        [advancedGroup setProperty:@"手动切换降噪模式后，插件将在冷却时间内暂不自动接管，避免干扰。" forKey:@"footer"];
        [specs addObject:advancedGroup];

        PSSpecifier *cooldown = [PSSpecifier preferenceSpecifierNamed:@"手动冷却（秒）"
                                                              target:self
                                                                 set:@selector(setPreferenceValue:specifier:)
                                                                 get:@selector(readPreferenceValue:)
                                                              detail:nil
                                                                cell:PSSliderCell
                                                                edit:nil];
        [cooldown setProperty:kAPANCooldownSecondsKey forKey:@"key"];
        [cooldown setProperty:@(0) forKey:@"min"];
        [cooldown setProperty:@(120) forKey:@"max"];
        [cooldown setProperty:@(30) forKey:@"default"];
        [specs addObject:cooldown];

        // 黑名单说明
        PSSpecifier *blGroup = [PSSpecifier emptyGroupSpecifier];
        [blGroup setProperty:@"应用黑名单" forKey:@"header"];
        [blGroup setProperty:@"黑名单内应用的播放状态将不会触发自动切换，用于过滤短视频等常驻媒体进程。\n默认已包含：抖音 (com.ss.iphone.ugc.Aweme)、抖音极速版 (com.ss.iphone.ugc.Aweme.lite)" forKey:@"footer"];
        [specs addObject:blGroup];

        _specifiers = specs;
    }
    return _specifiers;
}

#pragma mark - 读写

- (id)readPreferenceValue:(PSSpecifier *)spec {
    NSString *key = [spec propertyForKey:@"key"];
    if (!key) return nil;
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key inDomain:kAPANBundleID];
    if (!value) value = [spec propertyForKey:@"default"];
    return value;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)spec {
    NSString *key = [spec propertyForKey:@"key"];
    if (!key) return;
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:key inDomain:kAPANBundleID];
    [[NSUserDefaults standardUserDefaults] synchronize];

    // 广播通知，让 mediaremoted 端刷新
    notify_post("com.ayao.airpodsautonoise.prefsChanged");
    [[NSNotificationCenter defaultCenter]
        postNotificationName:kAPANPrefsChangedNotification object:nil];
}

#pragma mark - 生命周期

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

@end
