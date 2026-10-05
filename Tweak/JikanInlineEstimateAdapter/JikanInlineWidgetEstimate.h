#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdlib.h>

// Accessory-inline widgets render their date in another process. Keep the
// widget intact and reserve space for a suffix in its existing native row.
@interface JikanInlineWidgetEstimate : NSObject
- (BOOL)updateWithController:(UIViewController *)controller rootView:(UIView *)rootView dateView:(UIView *)dateView text:(NSString *)text;
- (void)invalidate;
+ (void)layoutInController:(UIViewController *)controller;
+ (void)nativeContentDidChangeForHost:(UIViewController *)host;
@end
