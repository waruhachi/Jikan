#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "../TT100/TT100.h"

@interface JikanPlatterView : UIView {
	UILabel *_staticLabel;
	UILabel *_timeRemainingLabel;
	UIView *_containerView;
	UIView *_backgroundView;
	UIView *_styleOverlayView;
	UIView *_contentTintReplicaView;
	NSTimer *_refreshTimer;
	UIImageView *_boltImageView;
	UITapGestureRecognizer *_tapGesture;
	NSDictionary *_latestBatteryInfo;
	NSString *_latestTimeString;
	BOOL _showingWattage;
}
- (void)setupConstraints;
- (void)updateWithTimeString:(NSString *)timeString;
- (void)applyQuickActionVisualEffect:(UIVisualEffect *)effect;
- (void)applyQuickActionBackgroundStyleFromView:(UIView *)sourceView;
@end

@interface MTMaterialView : UIView
@property (nonatomic, assign, readwrite) BOOL captureOnly;

- (void)setRecipe:(NSInteger)recipe;
+ (MTMaterialView *)materialViewWithRecipe:(NSInteger)recipe options:(NSUInteger)options;
+ (MTMaterialView *)materialViewWithRecipe:(NSInteger)recipe configuration:(NSInteger)configuration;
@end
