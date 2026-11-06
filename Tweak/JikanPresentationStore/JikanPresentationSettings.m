#import "JikanPresentationSettings.h"

@implementation JikanPresentationSettings

- (instancetype)initWithPreferences:(NSUserDefaults *)preferences {
	self = [super init];
	if (self) {
		_enabled = [preferences objectForKey:@"enabled"] ? [preferences boolForKey:@"enabled"] : YES;
		_hideQuickActionButtons = [preferences boolForKey:@"hideQuickActionButtons"];
		_hideQuickActionButtonsOnlyWhenCharging = [preferences boolForKey:@"hideQuickActionButtonsOnlyWhenCharging"];
		_hideSwipeToUnlockText = [preferences boolForKey:@"hideSwipeToUnlockText"];
		_hideFocusIndicator = [preferences objectForKey:@"hideFocusIndicator"] ? [preferences boolForKey:@"hideFocusIndicator"] : YES;
		_hideFocusIndicatorOnlyWhenCharging = [preferences boolForKey:@"hideFocusIndicatorOnlyWhenCharging"];
		_showAfterFullCharge = [preferences boolForKey:@"showAfterFullCharge"];
		_notifyWhenTargetReached = [preferences boolForKey:@"notifyWhenTargetReached"];
		_showEstimateBesideDate = [preferences boolForKey:JikanEstimateBesideDateKey];
		_lockPreviewXAxis = [preferences boolForKey:JikanPreviewXAxisLockKey];
		_lockPreviewYAxis = [preferences boolForKey:JikanPreviewYAxisLockKey];
		id opacity = [preferences objectForKey:@"pillBackgroundOpacityPercent"];
		double percent = [opacity respondsToSelector:@selector(doubleValue)] ? [opacity doubleValue] : 100.0;
		_backgroundOpacity = isfinite(percent) ? MAX(0.0, MIN(100.0, percent)) / 100.0 : 1.0;
		_appearance = [JikanPillAppearance(preferences) copy];
		_temperatureUnit = [JikanTemperatureUnit(preferences) copy];
		_estimateSource = [JikanEstimateSource(preferences) copy];
		_allowEstimatedAppleInputPower = [preferences boolForKey:JikanEstimateAppleEstimatedPowerKey];
		_appleTargetPercent = JikanEstimateTarget(preferences, @"apple");
		_targetPercent = JikanEstimateTarget(preferences, _estimateSource);
		_stackItems = JikanEffectiveStackItems(JikanStackItems(preferences), _targetPercent);
		_estimateTargets = JikanStackTargets(_stackItems, _targetPercent);
		_portraitPosition = JikanReadPillPosition(preferences, NO);
		_landscapePosition = JikanReadPillPosition(preferences, YES);
	}
	return self;
}

- (JikanPresentationSettings *)settingsByUpdatingPosition:(JikanPillPosition)position landscape:(BOOL)landscape {
	JikanPresentationSettings *settings = [JikanPresentationSettings new];
	settings->_enabled = _enabled;
	settings->_hideQuickActionButtons = _hideQuickActionButtons;
	settings->_hideQuickActionButtonsOnlyWhenCharging = _hideQuickActionButtonsOnlyWhenCharging;
	settings->_hideSwipeToUnlockText = _hideSwipeToUnlockText;
	settings->_hideFocusIndicator = _hideFocusIndicator;
	settings->_hideFocusIndicatorOnlyWhenCharging = _hideFocusIndicatorOnlyWhenCharging;
	settings->_showAfterFullCharge = _showAfterFullCharge;
	settings->_notifyWhenTargetReached = _notifyWhenTargetReached;
	settings->_showEstimateBesideDate = _showEstimateBesideDate;
	settings->_lockPreviewXAxis = _lockPreviewXAxis;
	settings->_lockPreviewYAxis = _lockPreviewYAxis;
	settings->_backgroundOpacity = _backgroundOpacity;
	settings->_appearance = _appearance;
	settings->_stackItems = _stackItems;
	settings->_estimateTargets = _estimateTargets;
	settings->_temperatureUnit = _temperatureUnit;
	settings->_estimateSource = _estimateSource;
	settings->_allowEstimatedAppleInputPower = _allowEstimatedAppleInputPower;
	settings->_targetPercent = _targetPercent;
	settings->_appleTargetPercent = _appleTargetPercent;
	settings->_portraitPosition = landscape ? _portraitPosition : position;
	settings->_landscapePosition = landscape ? position : _landscapePosition;
	return settings;
}

@end
