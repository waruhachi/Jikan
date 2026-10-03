#import <UIKit/UIKit.h>

#import "../JikanAppearanceSettings.h"
#import "JikanPillContent.h"

@interface JikanPillContentView : UIView
@property (nonatomic, copy) NSString *appearance;
@property (nonatomic, assign) BOOL adaptsToSystemAppearance;
@property (nonatomic, strong, readonly) JikanPillContent *content;
@property (nonatomic, copy) void (^contentSizeDidChange)(void);
- (void)applyContent:(JikanPillContent *)content;
- (CGSize)preferredSizeForMaximumWidth:(CGFloat)width height:(CGFloat)height;
@end
