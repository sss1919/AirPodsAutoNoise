#import <Foundation/Foundation.h>
#import <MediaRemote/MediaRemote.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <notify.h>

#pragma mark - 常量

static NSString * const kAPANEnabledKey            = @"apan_enabled";
static NSString * const kAPANAutoANCOnConnectKey   = @"apan_auto_anc_on_connect";
static NSString * const kAPANAutoANCOnPlayKey      = @"apan_auto_anc_on_play";
static NSString * const kAPANAutoTransOnStopKey    = @"apan_auto_trans_on_stop";
static NSString * const kAPANCooldownSecondsKey    = @"apan_cooldown_seconds";
static NSString * const kAPANAppBlacklistKey       = @"apan_app_blacklist";

static NSString * const kAPANPrefsChangedNotification = @"com.ayao.airpodsautonoise.prefsChanged";
static NSString * const kAPANNoiseModeChangedNotification = @"AirPodsNoiseControlModeDidChangeNotification";

static const NSInteger kAPANDeviceModeANC         = 2;
static const NSInteger kAPANDeviceModeTransparency = 3;

#pragma mark - 数据模型

@interface APANAirPodsInfo : NSObject
@property (nonatomic, assign) BOOL      isSupported;
@property (nonatomic, assign) BOOL      isPro;
@property (nonatomic, assign) BOOL      isMax;
@property (nonatomic, assign) NSInteger currentMode;
@property (nonatomic,   copy) NSString *address;
@property (nonatomic,   copy) NSString *name;
@end
@implementation APANAirPodsInfo
@end

#pragma mark - 辅助函数 / 私有 API 声明

@interface APANBTManager : NSObject
+ (instancetype)sharedInstance;
- (id)connectedDeviceWithAddress:(NSString *)address;
- (void)setDevice:(id)device modeValue:(NSInteger)mode;
- (NSInteger)modeValueForDevice:(id)device;
@end

@interface APANMRNowPlayingController : NSObject
+ (instancetype)sharedController;
- (NSString *)clientBundleIdentifier;
- (MRPlaybackState)playbackState;
@end

#pragma mark - 主 Tweak 类

@interface AirPodsAutoNoise : NSObject
@property (nonatomic, assign) BOOL         enabled;
@property (nonatomic, assign) BOOL         autoANCOnConnect;
@property (nonatomic, assign) BOOL         autoANCOnPlay;
@property (nonatomic, assign) BOOL         autoTransOnStop;
@property (nonatomic, assign) NSInteger    cooldownSeconds;
@property (nonatomic,   copy) NSArray<NSString *> *appBlacklist;

@property (nonatomic, assign) MRPlaybackState lastPlaybackState;
@property (nonatomic,   copy) NSString        *lastPlayingApp;
@property (nonatomic, assign) NSTimeInterval   lastUserManualSwitchTime;
@property (nonatomic,   copy) NSString        *currentAirPodsAddress;
@property (nonatomic, assign) NSInteger        lastAutoSetMode;

+ (instancetype)sharedInstance;
- (void)loadPreferences;
- (void)startObserving;
- (void)handleRouteChange:(NSNotification *)note;
- (void)handleNowPlayingAppChange:(NSNotification *)note;
- (void)handlePlaybackStateChange:(NSNotification *)note;
- (void)handleNoiseModeChange:(NSNotification *)note;
- (void)evaluateState;
- (BOOL)isInCooldown;
- (void)resetCooldown;
- (APANAirPodsInfo *)currentActiveAirPodsInfo;
- (void)trySetModeForCurrentAirPods:(NSInteger)mode reason:(NSString *)reason;
@end

@implementation AirPodsAutoNoise

+ (instancetype)sharedInstance {
    static AirPodsAutoNoise *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AirPodsAutoNoise alloc] init];
        [instance loadPreferences];
        [instance startObserving];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _enabled = YES;
        _autoANCOnConnect = YES;
        _autoANCOnPlay = YES;
        _autoTransOnStop = YES;
        _cooldownSeconds = 30;
        _appBlacklist = @[
            @"com.ss.iphone.ugc.Aweme",
            @"com.ss.iphone.ugc.Aweme.lite"
        ];
        _lastPlaybackState = MRPlaybackStateStopped;
        _lastPlayingApp = nil;
        _lastUserManualSwitchTime = 0;
        _currentAirPodsAddress = nil;
        _lastAutoSetMode = -1;
    }
    return self;
}

- (void)loadPreferences {
    NSURL *prefsURL = [NSURL fileURLWithPath:@"/var/jb/var/mobile/Library/Preferences/com.ayao.airpodsautonoise.plist"];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfURL:prefsURL];
    if (!prefs) {
        prefsURL = [NSURL fileURLWithPath:@"/User/Library/Preferences/com.ayao.airpodsautonoise.plist"];
        prefs = [NSDictionary dictionaryWithContentsOfURL:prefsURL];
    }
    if (!prefs) return;

    id val;
    val = prefs[kAPANEnabledKey];
    if (val) self.enabled = [val boolValue];

    val = prefs[kAPANAutoANCOnConnectKey];
    if (val) self.autoANCOnConnect = [val boolValue];

    val = prefs[kAPANAutoANCOnPlayKey];
    if (val) self.autoANCOnPlay = [val boolValue];

    val = prefs[kAPANAutoTransOnStopKey];
    if (val) self.autoTransOnStop = [val boolValue];

    val = prefs[kAPANCooldownSecondsKey];
    if (val) self.cooldownSeconds = [val integerValue];

    val = prefs[kAPANAppBlacklistKey];
    if ([val isKindOfClass:[NSArray class]]) {
        self.appBlacklist = val;
    }

    NSLog(@"[AirPodsAutoNoise] prefs loaded: enabled=%d blacklist=%@", self.enabled, self.appBlacklist);
}

- (void)startObserving {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *err = nil;
    [session setActive:YES error:&err];

    [nc addObserver:self selector:@selector(handleRouteChange:)
               name:AVAudioSessionRouteChangeNotification object:session];

    [nc addObserver:self selector:@selector(handleNowPlayingAppChange:)
               name:@"kMRNowPlayingAppDidChangeNotification" object:nil];

    [nc addObserver:self selector:@selector(handlePlaybackStateChange:)
               name:@"kMRPlaybackStateDidChangeNotification" object:nil];

    [nc addObserver:self selector:@selector(handleNoiseModeChange:)
               name:kAPANNoiseModeChangedNotification object:nil];

    [nc addObserver:self selector:@selector(handlePrefsChanged:)
               name:kAPANPrefsChangedNotification object:nil];

    // 启动时立即评估一次
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self evaluateState];
    });
}

#pragma mark - 通知处理

- (void)handlePrefsChanged:(NSNotification *)note {
    [self loadPreferences];
    [self evaluateState];
}

- (void)handleRouteChange:(NSNotification *)note {
    NSNumber *reasonNum = note.userInfo[AVAudioSessionRouteChangeReasonKey];
    AVAudioSessionRouteChangeReason reason = [reasonNum unsignedIntegerValue];
    NSLog(@"[AirPodsAutoNoise] route change reason=%lu", (unsigned long)reason);

    APANAirPodsInfo *info = [self currentActiveAirPodsInfo];
    if (info && info.isSupported) {
        if (reason == AVAudioSessionRouteChangeReasonNewDeviceAvailable ||
            reason == AVAudioSessionRouteChangeReasonCategoryChange) {
            self.currentAirPodsAddress = info.address;
            if (self.autoANCOnConnect && self.enabled) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [self trySetModeForCurrentAirPods:kAPANDeviceModeANC reason:@"connect"];
                });
            }
        }
    } else if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        self.currentAirPodsAddress = nil;
    }
    [self evaluateState];
}

- (void)handleNowPlayingAppChange:(NSNotification *)note {
    NSLog(@"[AirPodsAutoNoise] now playing app changed");
    [self evaluateState];
}

- (void)handlePlaybackStateChange:(NSNotification *)note {
    NSLog(@"[AirPodsAutoNoise] playback state changed");
    [self evaluateState];
}

- (void)handleNoiseModeChange:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    NSNumber *modeNum = info[@"mode"];
    NSNumber *autoNum = info[@"auto"];
    BOOL isAuto = [autoNum boolValue];
    NSInteger newMode = [modeNum integerValue];
    if (!isAuto && newMode != self.lastAutoSetMode) {
        // 用户手动切换
        NSLog(@"[AirPodsAutoNoise] detected manual mode switch -> entering cooldown");
        [self resetCooldown];
    }
}

#pragma mark - 状态评估

- (void)evaluateState {
    if (!self.enabled) return;

    APANAirPodsInfo *airPods = [self currentActiveAirPodsInfo];
    if (!airPods || !airPods.isSupported) {
        self.currentAirPodsAddress = nil;
        return;
    }
    self.currentAirPodsAddress = airPods.address;

    // 获取当前播放 App
    NSString *nowPlayingApp = nil;
    MRPlaybackState playbackState = MRPlaybackStateStopped;
    @try {
        Class cls = NSClassFromString(@"MRNowPlayingController");
        id controller = [cls performSelector:@selector(sharedController)];
        if (controller && [controller respondsToSelector:@selector(clientBundleIdentifier)]) {
            nowPlayingApp = [controller performSelector:@selector(clientBundleIdentifier)];
        }
        if (controller && [controller respondsToSelector:@selector(playbackState)]) {
            playbackState = (MRPlaybackState)[controller performSelector:@selector(playbackState)];
        }
    } @catch (NSException *e) {
        NSLog(@"[AirPodsAutoNoise] MRNowPlayingController error: %@", e);
    }

    self.lastPlayingApp = nowPlayingApp;
    self.lastPlaybackState = playbackState;

    // 检查黑名单
    BOOL isBlacklisted = NO;
    if (nowPlayingApp) {
        for (NSString *b in self.appBlacklist) {
            if ([nowPlayingApp isEqualToString:b] ||
                [nowPlayingApp containsString:b]) {
                isBlacklisted = YES;
                break;
            }
        }
    }
    if (isBlacklisted) {
        NSLog(@"[AirPodsAutoNoise] skip: blacklisted app %@", nowPlayingApp);
        return;
    }

    // 检查冷却
    if ([self isInCooldown]) {
        NSLog(@"[AirPodsAutoNoise] skip: in cooldown");
        return;
    }

    BOOL isPlaying = (playbackState == MRPlaybackStatePlaying);

    if (isPlaying) {
        if (self.autoANCOnPlay && airPods.currentMode != kAPANDeviceModeANC) {
            [self trySetModeForCurrentAirPods:kAPANDeviceModeANC reason:@"playing"];
        }
    } else {
        if (self.autoTransOnStop && airPods.currentMode != kAPANDeviceModeTransparency) {
            [self trySetModeForCurrentAirPods:kAPANDeviceModeTransparency reason:@"stopped"];
        }
    }
}

#pragma mark - 设备识别与模式切换

- (APANAirPodsInfo *)currentActiveAirPodsInfo {
    AVAudioSessionRouteDescription *route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription *output in route.outputs) {
        NSString *portType = output.portType;
        if ([portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
            [portType isEqualToString:AVAudioSessionPortBluetoothHFP] ||
            [portType isEqualToString:AVAudioSessionPortBluetoothLE]) {
            NSString *name = output.portName ?: @"";
            NSString *uid = output.UID ?: @"";

            // 通过名称判断 Pro/Max
            BOOL isPro = ([name containsString:@"Pro"] || [name containsString:@"Pro"]);
            BOOL isMax = ([name containsString:@"Max"]);
            BOOL isAirPods = ([name containsString:@"AirPods"] ||
                              [name containsString:@"airpods"] ||
                              [name containsString:@"AirPods"]);

            // 更可靠：查询 BluetoothManager
            BOOL btSupported = NO;
            NSInteger currentMode = -1;
            NSString *btAddr = nil;
            NSString *btName = nil;

            @try {
                Class btMgrCls = NSClassFromString(@"BluetoothManager");
                if (btMgrCls) {
                    id btMgr = [btMgrCls performSelector:@selector(sharedInstance)];
                    if (btMgr && [btMgr respondsToSelector:@selector(connectedDevices)]) {
                        NSArray *devs = [btMgr performSelector:@selector(connectedDevices)];
                        for (id dev in devs) {
                            NSString *dName = nil;
                            NSString *dAddr = nil;
                            if ([dev respondsToSelector:@selector(name)]) dName = [dev performSelector:@selector(name)];
                            if ([dev respondsToSelector:@selector(addressString)]) dAddr = [dev performSelector:@selector(addressString)];
                            if (!dName) continue;

                            BOOL matched = ([name isEqualToString:dName] ||
                                            (dAddr && [uid containsString:dAddr]));
                            if (!matched) continue;

                            btName = dName;
                            btAddr = dAddr;

                            // 检查设备是否支持降噪：通过检查响应或 ANC 相关属性
                            if ([dev respondsToSelector:@selector(noiseControlMode)]) {
                                currentMode = (NSInteger)[dev performSelector:@selector(noiseControlMode)];
                                btSupported = YES;
                            }
                            // 或者支持的模式列表
                            if ([dev respondsToSelector:@selector(supportedNoiseControlModes)]) {
                                NSArray *modes = [dev performSelector:@selector(supportedNoiseControlModes)];
                                if (modes.count > 1) btSupported = YES;
                            }

                            if (btName) {
                                isAirPods = isAirPods || ([btName containsString:@"AirPods"]);
                                isPro = isPro || ([btName containsString:@"Pro"]);
                                isMax = isMax || ([btName containsString:@"Max"]);
                            }
                            if (btSupported) break;
                        }
                    }
                }
            } @catch (NSException *e) {
                NSLog(@"[AirPodsAutoNoise] BluetoothManager error: %@", e);
            }

            APANAirPodsInfo *info = [[APANAirPodsInfo alloc] init];
            info.isPro = isPro;
            info.isMax = isMax;
            // 仅 Pro/Max 支持
            info.isSupported = isAirPods && (isPro || isMax) && btSupported;
            // 如果蓝牙管理器没拿到 currentMode，就 fallback 到 -1
            info.currentMode = currentMode;
            info.address = btAddr ?: uid;
            info.name = btName ?: name;
            return info;
        }
    }
    return nil;
}

- (void)trySetModeForCurrentAirPods:(NSInteger)mode reason:(NSString *)reason {
    if ([self isInCooldown]) {
        NSLog(@"[AirPodsAutoNoise] skip set mode in cooldown");
        return;
    }

    @try {
        Class btMgrCls = NSClassFromString(@"BluetoothManager");
        if (!btMgrCls) return;
        id btMgr = [btMgrCls performSelector:@selector(sharedInstance)];
        if (!btMgr) return;

        id targetDev = nil;
        if (self.currentAirPodsAddress &&
            [btMgr respondsToSelector:@selector(connectedDeviceWithAddress:)]) {
            targetDev = [btMgr performSelector:@selector(connectedDeviceWithAddress:)
                                    withObject:self.currentAirPodsAddress];
        }
        if (!targetDev && [btMgr respondsToSelector:@selector(connectedDevices)]) {
            NSArray *devs = [btMgr performSelector:@selector(connectedDevices)];
            for (id dev in devs) {
                NSString *dName = nil;
                if ([dev respondsToSelector:@selector(name)]) dName = [dev performSelector:@selector(name)];
                if (dName && ([dName containsString:@"Pro"] || [dName containsString:@"Max"])) {
                    targetDev = dev;
                    break;
                }
            }
        }
        if (!targetDev) {
            NSLog(@"[AirPodsAutoNoise] no target device for mode switch");
            return;
        }

        SEL setModeSel = NSSelectorFromString(@"setNoiseControlMode:");
        if (!setModeSel) setModeSel = NSSelectorFromString(@"setModeValue:");

        if ([targetDev respondsToSelector:setModeSel]) {
            // 发送通知用于冷却检测
            [[NSNotificationCenter defaultCenter]
                postNotificationName:kAPANNoiseModeChangedNotification
                object:nil
                userInfo:@{
                    @"mode": @(mode),
                    @"auto": @(YES),
                    @"reason": reason ?: @""
                }];

            void (*imp)(id, SEL, NSInteger) = (void(*)(id,SEL,NSInteger))[targetDev methodForSelector:setModeSel];
            if (imp) {
                imp(targetDev, setModeSel, mode);
                self.lastAutoSetMode = mode;
                NSLog(@"[AirPodsAutoNoise] set mode %ld reason=%@", (long)mode, reason);
            }
        } else if ([btMgr respondsToSelector:@selector(setDevice:modeValue:)]) {
            void (*imp)(id, SEL, id, NSInteger) = (void(*)(id,SEL,id,NSInteger))[btMgr methodForSelector:@selector(setDevice:modeValue:)];
            if (imp) {
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:kAPANNoiseModeChangedNotification
                    object:nil
                    userInfo:@{
                        @"mode": @(mode),
                        @"auto": @(YES),
                        @"reason": reason ?: @""
                    }];
                imp(btMgr, @selector(setDevice:modeValue:), targetDev, mode);
                self.lastAutoSetMode = mode;
                NSLog(@"[AirPodsAutoNoise] btMgr set mode %ld reason=%@", (long)mode, reason);
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[AirPodsAutoNoise] set mode error: %@", e);
    }
}

#pragma mark - 冷却机制

- (BOOL)isInCooldown {
    if (self.cooldownSeconds <= 0) return NO;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    return (now - self.lastUserManualSwitchTime) < (NSTimeInterval)self.cooldownSeconds;
}

- (void)resetCooldown {
    self.lastUserManualSwitchTime = [[NSDate date] timeIntervalSince1970];
    self.lastAutoSetMode = -1;
}

@end

#pragma mark - 构造器

__attribute__((constructor))
static void apan_initialize() {
    @autoreleasepool {
        NSLog(@"[AirPodsAutoNoise] constructor: loaded in %@",
              [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown");
        // 仅在 mediaremoted 中初始化
        NSString *procName = [[NSProcessInfo processInfo] processName];
        if ([procName isEqualToString:@"mediaremoted"]) {
            [AirPodsAutoNoise sharedInstance];
        }
    }
}
