#import "JikanPresentationState.h"

@implementation JikanPresentationState

- (instancetype)initWithSnapshot:(JikanBatterySnapshot *)snapshot settings:(JikanPresentationSettings *)settings previewActive:(BOOL)previewActive estimateGeneration:(NSUInteger)generation {
	self = [super init];
	if (self) {
		_snapshot = snapshot;
		_settings = settings;
		_previewActive = previewActive && settings.enabled;
		_estimateGeneration = generation;
	}
	return self;
}

- (BOOL)shouldHideQuickActionButtons {
	return _settings.enabled && _settings.hideQuickActionButtons && (!_settings.hideQuickActionButtonsOnlyWhenCharging || _snapshot.externalPowerConnected);
}

- (BOOL)shouldShowPlatter {
	return _settings.enabled && (_previewActive || (_snapshot.externalPowerConnected &&
		(_snapshot.hasAnyEstimate || (_snapshot.targetReached && _snapshot.hasUnfinishedTarget) || _snapshot.hasUnavailableAppleTarget || (_settings.showAfterFullCharge && !_snapshot.hasUnfinishedTarget))));
}

- (BOOL)usesPreviewContent {
	return _previewActive && (!_snapshot.externalPowerConnected || (!_snapshot.hasAnyEstimate && !(_settings.showAfterFullCharge && !_snapshot.hasUnfinishedTarget)));
}

@end
