#import <Foundation/Foundation.h>

#import "../JikanPresentationStore/JikanPresentationState.h"
#import "JikanNotificationPublisher.h"
#import "JikanTargetNotificationState.h"

@class JikanPresentationState, JikanPresentationSettings;

@interface JikanTargetNotification : NSObject
- (void)updateWithState:(JikanPresentationState *)state;
- (void)showPreviewWithSettings:(JikanPresentationSettings *)settings;
@end
