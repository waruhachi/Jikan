#import "JikanTargetNotification.h"

@interface JikanTargetNotification () {
	JikanTargetNotificationState _notificationState;
	NSString *_estimateSource;
}
@end

@implementation JikanTargetNotification

- (void)showPreviewWithSettings:(JikanPresentationSettings *)settings {
	NSAssert(NSThread.isMainThread, @"Notification previews must run on the main thread");
	if (!settings.enabled || !settings.notifyWhenTargetReached) return;
	[JikanNotificationPublisher publishTargetReached:settings.targetPercent];
}

- (void)updateWithState:(JikanPresentationState *)state {
	NSAssert(NSThread.isMainThread, @"Charge target notifications must consume state on the main thread");
	JikanBatterySnapshot *snapshot = state.snapshot;
	if (![_estimateSource isEqualToString:state.settings.estimateSource]) {
		_notificationState.armed = false;
		_estimateSource = [state.settings.estimateSource copy];
	}
	BOOL enabled = state.settings.enabled && state.settings.notifyWhenTargetReached;
	JikanTargetNotificationState previousState = _notificationState;
	if (!JikanTargetNotificationShouldSend(&_notificationState, snapshot != nil, snapshot.externalPowerConnected,
			enabled, (int)state.settings.targetPercent, snapshot.targetReached)) return;
	if (![JikanNotificationPublisher publishTargetReached:state.settings.targetPercent]) {
		_notificationState = previousState;
	}
}

@end
