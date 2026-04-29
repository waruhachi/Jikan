#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "../../Localization/JikanLocalization.h"
#import "../Views/AnimatedTitleView.h"
#import "../Views/JikanHeaderView.h"

typedef NS_ENUM(NSInteger, JikanDynamicSpecifierOperatorType) {
	JikanEqualToOperatorType,
	JikanNotEqualToOperatorType,
	JikanGreaterThanOperatorType,
	JikanLessThanOperatorType,
};

@interface JikanRootListController : PSListController
@property (nonatomic, assign) BOOL hasDynamicSpecifiers;
@property (nonatomic, retain) NSMutableDictionary *dynamicSpecifiers;

- (void)resetPreferences;
- (void)resetPillPosition;
- (void)openPillBackgroundOpacityEditor;
- (void)openNotificationCenterPreview;
@end
