#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#import "../../Localization/JikanLocalization.h"
#import "../Views/AnimatedTitleView.h"
#import "../Views/JikanHeaderView.h"

@interface JikanPreferencesPresentation : NSObject
+ (void)localizeSpecifiers:(NSArray<PSSpecifier *> *)specifiers;
+ (void)configureAxisSliderLeftImagesForController:(PSListController *)controller;
+ (UIView *)tableHeaderViewForWidth:(CGFloat)width bundle:(NSBundle *)bundle;
+ (AnimatedTitleView *)navigationTitleView;
+ (BOOL)isSpacerHeaderTitle:(NSString *)title;
+ (UIView *)spacerHeaderView;
+ (UIView *)legendFooterView;
@end
