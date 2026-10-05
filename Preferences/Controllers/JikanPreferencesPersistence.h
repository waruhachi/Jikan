#import <Foundation/Foundation.h>

#import "../../Shared/JikanAppearanceSettings.h"
#import "../../Shared/JikanDisplaySettings.h"
#import "../../Shared/JikanEstimateSettings.h"
#import "../../Shared/JikanPositionSettings.h"
#import "../../Shared/JikanPreferences.h"
#import "../../Shared/JikanStackSettings.h"
#import "JikanSliderSettings.h"

@interface JikanPreferencesPersistence : NSObject
// Prepares a value for PSListController to save; NO rejects an invalid Apple
// target. Sync flags and first-use Apple targets are updated before that save.
+ (BOOL)prepareValue:(id *)preparedValue forKey:(NSString *)key preferences:(NSUserDefaults *)prefs;
// Normalization posts a reload only when stored values change. Both resets
// synchronize and post a reload; the controller schedules its own UI refresh.
+ (void)normalizeStoredValuesInPreferences:(NSUserDefaults *)prefs;
+ (void)resetPreferences:(NSUserDefaults *)prefs bundle:(NSBundle *)bundle;
+ (void)resetPillPositionInPreferences:(NSUserDefaults *)prefs;
@end
