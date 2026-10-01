#import <Foundation/Foundation.h>
#import <math.h>

#import "../../Shared/JikanAppearanceSettings.h"
#import "../../Shared/JikanEstimateSettings.h"
#import "../../Shared/JikanPositionSettings.h"
#import "../../Shared/JikanStackSettings.h"

@interface JikanPresentationSettings : NSObject
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL hideQuickActionButtons;
@property (nonatomic, readonly) BOOL hideQuickActionButtonsOnlyWhenCharging;
@property (nonatomic, readonly) BOOL showAfterFullCharge;
@property (nonatomic, readonly) BOOL lockPreviewXAxis;
@property (nonatomic, readonly) BOOL lockPreviewYAxis;
@property (nonatomic, readonly) double backgroundOpacity;
@property (nonatomic, copy, readonly) NSString *appearance;
@property (nonatomic, copy, readonly) NSArray<NSString *> *stackItems;
@property (nonatomic, copy, readonly) NSString *temperatureUnit;
@property (nonatomic, copy, readonly) NSString *estimateSource;
@property (nonatomic, readonly) NSInteger targetPercent;
@property (nonatomic, readonly) JikanPillPosition portraitPosition;
@property (nonatomic, readonly) JikanPillPosition landscapePosition;
- (instancetype)initWithPreferences:(NSUserDefaults *)preferences;
- (JikanPresentationSettings *)settingsByUpdatingPosition:(JikanPillPosition)position landscape:(BOOL)landscape;
@end
