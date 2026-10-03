#import <UIKit/UIKit.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "../../Shared/JikanGlassEffect.h"

@interface JikanPlatterMaterial : NSObject
- (instancetype)initWithContainerView:(UIView *)container;
- (void)setupConstraints;
- (void)layoutMaterialViews;
- (void)applyOpacity:(CGFloat)factor;
- (BOOL)applyQuickActionGlassFromView:(UIView *)sourceView;
- (void)applyQuickActionVisualEffect:(UIVisualEffect *)effect;
- (void)applyQuickActionBackgroundStyleFromView:(UIView *)sourceView opacity:(CGFloat)opacity;
@end
