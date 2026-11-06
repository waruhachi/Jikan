#import <UIKit/UIKit.h>

#import "../JikanPresentationStore/JikanPresentationStore.h"

// Hides the Lock Screen Focus/notification-count indicator (NCNotificationListCountIndicatorView),
// which sits where the Jikan pill is usually placed.
@interface JikanFocusIndicatorVisibility : NSObject
+ (BOOL)hiddenValueForView:(UIView *)view requested:(BOOL)hidden;
+ (void)updateView:(UIView *)view;
+ (void)refreshTrackedViews;
@end
