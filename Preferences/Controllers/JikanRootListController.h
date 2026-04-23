#include <Preferences/PSListController.h>
#include <Preferences/PSSpecifier.h>
#include <UIKit/UIKit.h>

@interface JikanRootListController : PSListController
- (void)resetPreferences;
- (void)resetPillPosition;
- (void)openPillBackgroundOpacityEditor;
@end
