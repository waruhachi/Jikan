#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "../JikanPresentationStore/JikanPresentationState.h"
#import "JikanInlineWidgetEstimate.h"

@interface JikanInlineEstimateAdapter : NSObject
- (instancetype)initWithRootView:(UIView *)rootView;
// YES only when the native date row is presenting the estimate. Otherwise
// the coordinator keeps the pill available as a fallback.
- (BOOL)updateWithState:(JikanPresentationState *)state;
- (void)invalidate;
+ (NSString *)dateString:(NSString *)dateString forView:(UIView *)dateView;
// LiquidAss compatibility: repairs an estimate discarded by its date-label hooks.
+ (void)applyLiquidAssCompatibilityToDateView:(UIView *)dateView;
@end
