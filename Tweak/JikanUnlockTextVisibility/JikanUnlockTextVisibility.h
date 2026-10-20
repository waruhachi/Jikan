#import <UIKit/UIKit.h>

#import "../JikanPresentationStore/JikanPresentationStore.h"

@interface JikanUnlockTextVisibility : NSObject
+ (void)updateModernContainer:(UIView *)container;
+ (void)updateLegacyLabel:(UIView *)label;
+ (void)refreshTrackedLabels;
@end
