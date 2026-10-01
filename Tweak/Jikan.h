#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <SpringBoard/SpringBoard.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <spawn.h>

#import "../Shared/JikanEstimateSettings.h"
#import "../Shared/JikanPositionSettings.h"
#import "../Shared/JikanPreferences.h"
#import "JikanCoverSheetCoordinator/JikanCoverSheetCoordinator.h"
#import "JikanPresentationStore/JikanPresentationStore.h"
#import "JikanQuickActionAdapter/JikanQuickActionAdapter.h"
#import "JikanSessionRecorder/JikanSessionRecorder.h"
#import "TT100/TT100.h"

@interface JikanQuickActionControl : UIControl
@end

@interface CSQuickActionsView : UIView
- (void)refreshSupportedButtons;
- (UIEdgeInsets)_buttonOutsets;
- (BOOL)_prototypingAllowsButtons;
@end

@interface CSCoverSheetView : UIView
@end

@interface CSCoverSheetViewController : UIViewController
@end
