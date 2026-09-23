#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <SpringBoard/SpringBoard.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <spawn.h>

#import "JikanPlatterView/JikanPlatterView.h"
#import "TT100/TT100.h"
#import "TT100/TT100Database.h"

static BOOL enabled;
static BOOL hideQuickActionButtons;
static BOOL hideQuickActionButtonsOnlyWhenCharging;
static BOOL tapToShowWattage;
static BOOL showAfterFullCharge;
static BOOL lockPreviewXAxis;
static BOOL lockPreviewYAxis;
static CGFloat pillBackgroundOpacity;
static CGFloat platterPosXNorm;
static CGFloat platterPosYNorm;
static BOOL platterHasCustomPosition;
static CGFloat platterPosXNormLandscape;
static CGFloat platterPosYNormLandscape;
static BOOL platterHasCustomPositionLandscape;

extern BOOL isCharging;

@interface JikanQuickActionControl : UIControl
@end

@interface CSProminentButtonControl : UIControl
@property (nonatomic, retain) UIVisualEffectView *backgroundEffectView;
@property (nonatomic, readonly) UIView *backgroundView;
@property (nonatomic) BOOL usesGlassMaterial;
@end

@interface CSProminentButtonsView : UIView
@property (nonatomic, retain) CSProminentButtonControl *leadingButton;
@property (nonatomic, retain) CSProminentButtonControl *trailingButton;
@end

@interface CSQuickActionsView : UIView
@property (nonatomic, retain) CSProminentButtonsView *buttonContainerView;
@property (nonatomic, retain) NSArray *buttons;

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
- (void)_jikanChargingStateChanged:(NSNotification *)notification;
- (void)_jikanHandlePlatterLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@interface CSCoverSheetViewController : UIViewController
@end
