#import <UIKit/UIKit.h>

#import "../../Shared/JikanPositionSettings.h"
#import "../../Shared/JikanPreferences.h"
#import "../JikanPlatterView/JikanPlatterView.h"
#import "../JikanQuickActionAdapter/JikanQuickActionAdapter.h"
#import "../TT100/TT100.h"

typedef struct {
	BOOL enabled;
	BOOL hideQuickActionButtons;
	BOOL hideQuickActionButtonsOnlyWhenCharging;
	BOOL showAfterFullCharge;
	BOOL lockPreviewXAxis;
	BOOL lockPreviewYAxis;
	BOOL charging;
	BOOL previewActive;
	JikanPillPosition portraitPosition;
	JikanPillPosition landscapePosition;
} JikanCoverSheetConfiguration;

@interface JikanCoverSheetCoordinator : NSObject
- (instancetype)initWithRootView:(UIView *)rootView
		   configurationProvider:(JikanCoverSheetConfiguration (^)(void))configurationProvider
				snapshotProvider:(NSDictionary * (^)(void))snapshotProvider
				 positionChanged:(void (^)(BOOL landscape, JikanPillPosition position))positionChanged;
- (void)didMoveToWindow;
- (void)layoutSubviews;
- (void)refresh;
@end
