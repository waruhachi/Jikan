#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "../../Localization/JikanLocalization.h"
#import "../../Shared/JikanEstimateSettings.h"
#import "../../Shared/JikanPreferences.h"
#import "JikanSliderSettings.h"

@interface JikanSliderEditor : NSObject
- (instancetype)initWithController:(PSListController *)controller
						   canEdit:(BOOL (^)(void))canEdit
						  willEdit:(void (^)(void))willEdit
						   didEdit:(void (^)(void))didEdit;
- (void)configureCell:(UITableViewCell *)cell specifier:(PSSpecifier *)specifier;
- (void)dismiss;
@end
