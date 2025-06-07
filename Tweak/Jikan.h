#import <spawn.h>
#import <UIKit/UIKit.h>
#import <IOKit/IOKitLib.h>
#import <Foundation/Foundation.h>
#import <SpringBoard/SpringBoard.h>

#import "TT100/TT100.h"
#import "JikanPlatterView/JikanPlatterView.h"

@interface NCNotificationListCountIndicatorView : UIView
@end

@interface CSQuickActionsButton : UIControl
@end

@interface CSQuickActionsView : UIView
	@property (nonatomic,retain) CSQuickActionsButton *cameraButton;
	@property (nonatomic,retain) CSQuickActionsButton *flashlightButton;
	
	- (void)refreshSupportedButtons;
	- (UIEdgeInsets)_buttonOutsets;
	- (BOOL)_prototypingAllowsButtons;
@end

@interface CSQuickActionsView (JikanPlatterView)
	@property (nonatomic, strong) JikanPlatterView *remainingTimePlatter;
	
	- (void)_configureRemainingTimePlatterConstraints;
	- (void)_addOrRemoveRemainingTimePlatterIfNecessary;
@end

extern BOOL isCharging;