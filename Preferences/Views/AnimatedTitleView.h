#import <UIKit/UIKit.h>

@interface AnimatedTitleView : UIView
- (instancetype)initWithTitle:(NSString *)title minimumScrollOffsetRequired:(CGFloat)minimumOffset;
- (void)adjustLabelPositionToScrollOffset:(CGFloat)offset;
@end