#import <Foundation/Foundation.h>
#import <math.h>

#import "../../Localization/JikanLocalization.h"

@interface JikanPillContent : NSObject
@property (nonatomic, copy, readonly) NSString *primaryText;
@property (nonatomic, copy, readonly) NSString *secondaryText;
@property (nonatomic, copy, readonly) NSString *chargingSpeed;
@property (nonatomic, readonly) double progress;
- (instancetype)initWithPrimaryText:(NSString *)primaryText secondaryText:(NSString *)secondaryText progress:(double)progress chargingSpeed:(NSString *)chargingSpeed;
+ (NSString *)estimateSubtitleForTargetPercent:(NSInteger)target;
+ (NSString *)formattedWattage:(double)watts;
+ (instancetype)previewContentForTargetPercent:(NSInteger)target;
@end
