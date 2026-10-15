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
	// Keep the pill visible in Apple mode when the selected model cannot
	// produce an estimate. Its content already renders "N/A" in this case.
	// Wait for the initial prediction before showing that unavailable state.
	BOOL showUnavailableAppleEstimate = [_settings.estimateSource isEqualToString:@"apple"] &&
		!_snapshot.targetReached && ![_snapshot.estimateStatus isEqualToString:@"waiting_for_first_prediction"];
	return _settings.enabled && (_previewActive || (_snapshot.externalPowerConnected &&
		(_snapshot.hasEstimate || showUnavailableAppleEstimate || (_settings.showAfterFullCharge && _snapshot.targetReached))));
}

- (BOOL)usesPreviewContent {
	return _previewActive && (!_snapshot.externalPowerConnected || (!_snapshot.hasEstimate && !(_settings.showAfterFullCharge && _snapshot.targetReached)));
}

@end
