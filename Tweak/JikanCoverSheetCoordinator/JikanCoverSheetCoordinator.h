#import <UIKit/UIKit.h>

#import "../../Shared/JikanPositionSettings.h"
#import "../../Shared/JikanPreferences.h"
#import "../JikanInlineEstimateAdapter/JikanInlineEstimateAdapter.h"
#import "../JikanPlatterView/JikanPlatterView.h"
#import "../JikanPresentationStore/JikanPresentationStore.h"
#import "../JikanQuickActionAdapter/JikanQuickActionAdapter.h"
#import "../TT100/TT100.h"

@interface JikanCoverSheetCoordinator : NSObject
- (instancetype)initWithRootView:(UIView *)rootView presentationStore:(JikanPresentationStore *)presentationStore;
- (void)didMoveToWindow;
- (void)layoutSubviews;
- (void)refresh;
@end
