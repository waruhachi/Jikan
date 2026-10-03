#import <Preferences/PSListController.h>
#import <Preferences/PSListItemsController.h>
#import <Preferences/PSSpecifier.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <objc/runtime.h>

#import "../../Localization/JikanLocalization.h"
#import "../../Shared/JikanAppearanceSettings.h"
#import "../../Shared/JikanEstimateSettings.h"
#import "../../Shared/JikanPositionSettings.h"
#import "../../Shared/JikanPreferences.h"
#import "../../Shared/JikanStackSettings.h"
#import "JikanChargeLimiterDetector.h"
#import "JikanDeviceCapabilities.h"
#import "JikanPreferencesPersistence.h"
#import "JikanPreferencesPresentation.h"
#import "JikanSliderEditor.h"
#import "JikanSliderSettings.h"

@interface JikanRootListController : PSListController
- (void)resetPreferences;
- (void)resetPillPosition;
- (void)openNotificationCenterPreview;
- (void)showBatteryLimitSourceInfo;
- (void)detectBatteryLimit;
@end
