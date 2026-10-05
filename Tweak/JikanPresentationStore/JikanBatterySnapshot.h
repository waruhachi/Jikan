#import <Foundation/Foundation.h>
#import <math.h>

#import "../../Localization/JikanLocalization.h"
#import "JikanPresentationSettings.h"

@interface JikanBatterySnapshot : NSObject
@property (nonatomic, copy, readonly) NSDictionary *dictionary;
@property (nonatomic, copy, readonly) NSDictionary *batteryInfo;
@property (nonatomic, copy, readonly) NSString *timeString;
@property (nonatomic, readonly) double remainingSeconds;
@property (nonatomic, copy, readonly) NSString *estimateSource;
@property (nonatomic, copy, readonly) NSString *estimateStatus;
@property (nonatomic, copy, readonly) NSString *chargingSpeed;
@property (nonatomic, readonly) BOOL externalPowerConnected;
@property (nonatomic, readonly) BOOL charging;
@property (nonatomic, readonly) BOOL hasEstimate;
@property (nonatomic, readonly) BOOL targetReached;
@property (nonatomic, readonly) BOOL fullyCharged;
@property (nonatomic, readonly) NSInteger displayPercent;
@property (nonatomic, readonly) NSInteger targetPercent;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary settings:(JikanPresentationSettings *)settings;
- (JikanBatterySnapshot *)snapshotWithoutEstimateForSettings:(JikanPresentationSettings *)settings;
@end
