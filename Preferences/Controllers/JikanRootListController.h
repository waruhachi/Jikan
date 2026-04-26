#include <Preferences/PSListController.h>
#include <Preferences/PSSpecifier.h>
#include <UIKit/UIKit.h>
#include <objc/runtime.h>

#include "../Views/AnimatedTitleView.h"
#include "../Views/JikanHeaderView.h"

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
