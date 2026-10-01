#import "JikanBatterySnapshot.h"
#import "JikanPresentationSettings.h"

@interface JikanPresentationState : NSObject
@property (nonatomic, strong, readonly) JikanBatterySnapshot *snapshot;
@property (nonatomic, strong, readonly) JikanPresentationSettings *settings;
@property (nonatomic, readonly) BOOL previewActive;
@property (nonatomic, readonly) NSUInteger estimateGeneration;
@property (nonatomic, readonly) BOOL shouldHideQuickActionButtons;
@property (nonatomic, readonly) BOOL shouldShowPlatter;
@property (nonatomic, readonly) BOOL usesPreviewContent;
- (instancetype)initWithSnapshot:(JikanBatterySnapshot *)snapshot settings:(JikanPresentationSettings *)settings previewActive:(BOOL)previewActive estimateGeneration:(NSUInteger)generation;
@end
