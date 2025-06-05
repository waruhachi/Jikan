#include "Jikan.h"

BOOL isCharging = NO;
NSString *chargingstate = nil;

static UIImageView *boltImageView = nil;
static UILabel *chargingDetailLabel = nil;
static UIView *chargingContainerView = nil;
static UIStackView *chargingStackView = nil;
static dispatch_source_t _updateTimer = nil;
static UILabel *chargingRemainingLabel = nil;

static NSDictionary* fetchBatteryInfo(void) {
    mach_port_t masterPort;
    io_service_t service;
    CFMutableDictionaryRef matchingDict = IOServiceMatching("IOPMPowerSource");
    CFMutableDictionaryRef properties = NULL;

    IOMasterPort(MACH_PORT_NULL, &masterPort);

    service = IOServiceGetMatchingService(masterPort, matchingDict);

    if (service) {
        IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0);
        IOObjectRelease(service);
    }

    if (properties) {
        NSDictionary *result = [NSDictionary dictionaryWithDictionary:(__bridge NSDictionary *)properties];
        CFRelease(properties);
        // Log to /var/tmp/Jikan.txt
        @try {
            NSString *logPath = @"/var/tmp/Jikan.txt";
            NSString *logString;
            if ([NSJSONSerialization isValidJSONObject:result]) {
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
                logString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            } else {
                logString = [result description];
            }
            [logString writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } @catch (__unused NSException *e) {}
        return result;
    }

    return nil;
}

static void computeTimeToFullCharge(NSDictionary *batteryInfo, int *outHours, int *outMinutes) {
    *outHours = 0;
    *outMinutes = 0;

    NSTimeInterval seconds = [BatteryChargerEstimator estimatedSecondsToFullWithBatteryInfo:batteryInfo];
    if (seconds < 0) {
        return;
    }
    int hours = (int)(seconds / 3600.0);
    int minutes = (int)round((fmod(seconds, 3600.0)) / 60.0);
    if (minutes >= 60) {
        hours += 1;
        minutes -= 60;
    }
    *outHours = hours;
    *outMinutes = minutes;
}

static NSString* buildTimeString(int hours, int minutes) {
    if (hours <= 0 && minutes <= 0) {
        return @"<unavailable>";
    }
    if (hours <= 0) {
        return [NSString stringWithFormat:@"%d minutes", minutes];
    }
    if (hours == 1) {
        return minutes > 0 ? [NSString stringWithFormat:@"1 hour %d minutes", minutes] : @"1 hour";
    }
    return minutes > 0 ? [NSString stringWithFormat:@"%d hours %d minutes", hours, minutes] : [NSString stringWithFormat:@"%d hours", hours];
}

static void asyncGetChargingTime(void (^completion)(NSString *timeString, int hours, int minutes)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *batteryInfo = fetchBatteryInfo();
        BOOL isChargingFlag = [batteryInfo[@"IsCharging"] boolValue];
        if (!isChargingFlag) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@"Not charging", 0, 0);
            });
            return;
        }
        int hours = 0, minutes = 0;
        computeTimeToFullCharge(batteryInfo, &hours, &minutes);
        NSString *finalString = buildTimeString(hours, minutes);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(finalString, hours, minutes);
        });
    });
}

static void setupChargingLabels(UIView *parentView) {
    if (chargingContainerView != nil) {
        return;
    }

	UIView *backgroundView = nil;
	if (@available(iOS 15, *)) {
		backgroundView = [%c(MTMaterialView) materialViewWithRecipe:19 options:2];
	} else {
		backgroundView = [%c(MTMaterialView) materialViewWithRecipe:19 configuration:1];
	}

    chargingContainerView = [[UIView alloc] init];
    chargingContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    chargingContainerView.layer.cornerRadius = 28.0;
    chargingContainerView.clipsToBounds = YES;
    [parentView addSubview:chargingContainerView];

    backgroundView.translatesAutoresizingMaskIntoConstraints = NO;
    backgroundView.layer.cornerRadius = 28.0;
    backgroundView.clipsToBounds = YES;
    [chargingContainerView addSubview:backgroundView];
    [chargingContainerView sendSubviewToBack:backgroundView];
    [NSLayoutConstraint activateConstraints:@[
        [backgroundView.leadingAnchor constraintEqualToAnchor:chargingContainerView.leadingAnchor],
        [backgroundView.trailingAnchor constraintEqualToAnchor:chargingContainerView.trailingAnchor],
        [backgroundView.topAnchor constraintEqualToAnchor:chargingContainerView.topAnchor],
        [backgroundView.bottomAnchor constraintEqualToAnchor:chargingContainerView.bottomAnchor],
    ]];

    boltImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"bolt.fill"]];
    boltImageView.tintColor = [UIColor systemGreenColor];
    boltImageView.contentMode = UIViewContentModeScaleAspectFit;
    boltImageView.translatesAutoresizingMaskIntoConstraints = NO;
    [boltImageView.widthAnchor constraintEqualToConstant:28].active = YES;

    chargingRemainingLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    chargingRemainingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    chargingRemainingLabel.textColor = [UIColor whiteColor];
    chargingRemainingLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    chargingRemainingLabel.textAlignment = NSTextAlignmentLeft;
    chargingRemainingLabel.text = @"-- minutes";

    chargingDetailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    chargingDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    chargingDetailLabel.textColor = [UIColor whiteColor];
    chargingDetailLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    chargingDetailLabel.textAlignment = NSTextAlignmentLeft;
    chargingDetailLabel.text = @"until fully charged";

    UIStackView *labelsStack = [[UIStackView alloc] initWithArrangedSubviews:@[chargingRemainingLabel, chargingDetailLabel]];
    labelsStack.axis = UILayoutConstraintAxisVertical;
    labelsStack.spacing = 2;
    labelsStack.alignment = UIStackViewAlignmentLeading;
    labelsStack.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *mainStack = [[UIStackView alloc] initWithArrangedSubviews:@[boltImageView, labelsStack]];
    mainStack.axis = UILayoutConstraintAxisHorizontal;
    mainStack.spacing = 12;
    mainStack.alignment = UIStackViewAlignmentCenter;
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;

    [chargingContainerView addSubview:mainStack];

    [parentView addConstraint:[NSLayoutConstraint constraintWithItem:chargingContainerView attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:parentView attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0]];
    [parentView addConstraint:[NSLayoutConstraint constraintWithItem:chargingContainerView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:parentView attribute:NSLayoutAttributeBottom multiplier:1.0 constant:-60]];

    [chargingContainerView.widthAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;
    [chargingContainerView.heightAnchor constraintEqualToConstant:56].active = YES;

    [mainStack.leadingAnchor constraintEqualToAnchor:chargingContainerView.leadingAnchor constant:16].active = YES;
    [mainStack.trailingAnchor constraintEqualToAnchor:chargingContainerView.trailingAnchor constant:-16].active = YES;
    [mainStack.centerYAnchor constraintEqualToAnchor:chargingContainerView.centerYAnchor].active = YES;

    [boltImageView.heightAnchor constraintEqualToAnchor:labelsStack.heightAnchor].active = YES;
}

static void loadPrefs(void) {
    asyncGetChargingTime(^(NSString *timeString, int hours, int minutes) {
        chargingstate = timeString ?: @"<error>";
        isCharging = ![timeString isEqualToString:@"Not charging"] && !(hours == 0 && minutes == 0);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"JikanChargingStateChanged" object:nil];
    });
}


%hook _UIBatteryView

- (void)setChargingState:(NSInteger)arg1 {
    isCharging = (arg1 == 1);
    loadPrefs();
    [[NSNotificationCenter defaultCenter] postNotificationName:@"JikanChargingStateChanged" object:nil];
    return %orig;
}

%end

%hook CSCoverSheetView

- (void)didMoveToSuperview {
    loadPrefs();
    UIView *parent = (UIView *)self;
    setupChargingLabels(parent);

    if (chargingContainerView) {
        chargingRemainingLabel.text = chargingstate;
        chargingDetailLabel.text = @"until fully charged";
        chargingContainerView.hidden = !isCharging;
    }

    %orig;

    [[NSNotificationCenter defaultCenter] addObserverForName:@"JikanChargingStateChanged" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
		if (chargingContainerView) {
			chargingRemainingLabel.text = chargingstate;
			chargingDetailLabel.text = @"until fully charged";
			chargingContainerView.hidden = !isCharging;
		}

		[self setNeedsLayout];
		[self setNeedsDisplay];
	}];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"JikanChargingStateChanged" object:nil];
    %orig;
}

%end

%hook NCNotificationListCountIndicatorView

- (void)didMoveToWindow {
    self.hidden = YES;
    %orig;
}

%end

%ctor {
    NSDictionary *batteryInfo = fetchBatteryInfo();
    BOOL initialCharging = [batteryInfo[@"IsCharging"] boolValue];

    if (initialCharging) {
        isCharging = YES;
        loadPrefs();

        dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0);
        _updateTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
        if (_updateTimer) {
            dispatch_source_set_timer(_updateTimer, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), 30 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
            dispatch_source_set_event_handler(_updateTimer, ^{
                loadPrefs();
            });
            dispatch_resume(_updateTimer);
        }
    }
}
