#import <UIKit/UIKit.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "../JikanPlatterView/JikanPlatterView.h"

@class JikanPlatterView;

@interface JikanQuickActionAdapter : NSObject
+ (Class)visibilityControlClass;
+ (BOOL)hiddenValueForControl:(UIView *)control requestedHidden:(BOOL)hidden;
+ (void)setButtonsInView:(UIView *)quickActions hidden:(BOOL)hidden;

- (instancetype)initWithRootView:(UIView *)rootView;
- (void)setButtonsHidden:(BOOL)hidden;
- (UIView *)platterHostView;
- (BOOL)getButtonFramesInView:(UIView *)host leadingRect:(CGRect *)leadingRect trailingRect:(CGRect *)trailingRect;
- (void)applyStyleToPlatter:(JikanPlatterView *)platter;
- (void)invalidateStyle;
@end
