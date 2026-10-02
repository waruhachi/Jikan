#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#import "../../Localization/JikanLocalization.h"

@interface JikanPreferencesPresentation : NSObject
+ (void)localizeSpecifiers:(NSArray<PSSpecifier *> *)specifiers;
+ (void)configureAxisSliderLeftImagesForController:(PSListController *)controller;
+ (BOOL)isSpacerHeaderTitle:(NSString *)title;
+ (UIView *)spacerHeaderView;
+ (UIView *)legendFooterView;
@end
