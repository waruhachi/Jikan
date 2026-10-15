#import "../../Shared/JikanPreferences.h"
#import "JikanPresentationState.h"

FOUNDATION_EXPORT NSString *const JikanPresentationStateDidChangeNotification;

@interface JikanPresentationStore : NSObject
@property (nonatomic, strong, readonly) JikanPresentationState *state;
+ (instancetype)sharedInstance;
- (instancetype)initWithPreferences:(NSUserDefaults *)preferences;
- (void)reloadPreferences;
// Update an automatic model default when native readings appear/disappear.
- (void)refreshAutomaticEstimateSelection;
- (BOOL)publishBatteryDictionary:(NSDictionary *)dictionary generation:(NSUInteger)generation publisher:(id)publisher;
- (void)clearBatterySnapshot;
- (void)setPreviewActive:(BOOL)active;
- (void)updatePosition:(JikanPillPosition)position landscape:(BOOL)landscape;
@end
