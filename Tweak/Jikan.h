#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <SpringBoard/SpringBoard.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <spawn.h>

#import "JikanPlatterView/JikanPlatterView.h"
#import "TT100/TT100.h"
#import "TT100/TT100Database.h"

static BOOL enabled;
static BOOL hideQuickActionButtons;
static BOOL showRemainingBatteryTime;
static BOOL autoResizeRemainingBatteryTime;

extern BOOL isCharging;

static const void *kTTManagedKey = &kTTManagedKey;
static const void *kTTBaseTextKey = &kTTBaseTextKey;

@interface NCNotificationListCountIndicatorView : UIView
@end

@interface CSQuickActionsButton : UIControl
@end

@interface CSQuickActionsView : UIView
@property (nonatomic, retain) CSQuickActionsButton *cameraButton;
@property (nonatomic, retain) CSQuickActionsButton *flashlightButton;

- (void)refreshSupportedButtons;
- (UIEdgeInsets)_buttonOutsets;
- (BOOL)_prototypingAllowsButtons;
@end

@interface CSCoverSheetView : UIView
@end

@interface CSCoverSheetView (JikanPlatterView)
@property (nonatomic, strong) JikanPlatterView *remainingTimePlatter;

- (void)_configureRemainingTimePlatterConstraints;
- (void)_addOrRemoveRemainingTimePlatterIfNecessary;
- (void)_setRemainingTimePlatterVisible:(BOOL)visible;
@end

@interface CSProminentSubtitleDateView : UIView
@end

@interface _UIAnimatingLabel : UILabel
@end

@interface _UIAnimatingLabel (Jikan)
- (void)_updateBatteryTime:(NSNotification *)notification;
@end