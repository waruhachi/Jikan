#import <UIKit/UIKit.h>

#import "../../Localization/JikanLocalization.h"
#import "../../Shared/JikanAppearanceSettings.h"
#import "../../Shared/JikanPillContentView/JikanPillContentView.h"
#import "../../Shared/JikanPreferences.h"
#import "../../Shared/JikanStackSettings.h"
#import "../JikanPresentationStore/JikanPresentationState.h"
#import "../TT100/TT100.h"
#import "JikanPlatterMaterial.h"

@interface JikanPlatterView : UIView
@property (nonatomic, copy) void (^contentSizeDidChange)(void);
- (CGSize)preferredSizeForMaximumWidth:(CGFloat)width height:(CGFloat)height;
- (void)applyPresentationState:(JikanPresentationState *)state;
- (void)setupConstraints;
- (BOOL)applyQuickActionGlassFromView:(UIView *)sourceView;
- (void)applyQuickActionVisualEffect:(UIVisualEffect *)effect;
- (void)applyQuickActionBackgroundStyleFromView:(UIView *)sourceView;
- (void)setPreviewMode:(BOOL)preview;
- (void)enterEditMode:(BOOL)editing;
@end

@interface MTMaterialView : UIView
@property (nonatomic, assign, readwrite) BOOL captureOnly;

- (void)setRecipe:(NSInteger)recipe;
+ (MTMaterialView *)materialViewWithRecipe:(NSInteger)recipe options:(NSUInteger)options;
+ (MTMaterialView *)materialViewWithRecipe:(NSInteger)recipe configuration:(NSInteger)configuration;
@end
