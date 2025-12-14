#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "../TT100/TT100.h"

@interface JikanPlatterView : UIView {
	UILabel *_staticLabel;
	UILabel *_timeRemainingLabel;
	UIView *_containerView;
	UIView *_backgroundView;
	NSTimer *_refreshTimer;
	UIImageView *_boltImageView;
}
- (void)setupConstraints;
- (void)updateWithTimeString:(NSString *)timeString;
@end

@interface MTMaterialView : UIView
@property (nonatomic, assign, readwrite) BOOL captureOnly;

- (void)setRecipe:(NSInteger)recipe;
+ (MTMaterialView *)materialViewWithRecipe:(NSInteger)recipe options:(NSUInteger)options;
+ (MTMaterialView *)materialViewWithRecipe:(NSInteger)recipe configuration:(NSInteger)configuration;
@end