#import "../../Shared/JikanPreferences.h"
#import "JikanPresentationState.h"

FOUNDATION_EXPORT NSString *const JikanPresentationStateDidChangeNotification;

@interface JikanPresentationStore : NSObject
@property (nonatomic, strong, readonly) JikanPresentationState *state;
+ (instancetype)sharedInstance;
- (instancetype)initWithPreferences:(NSUserDefaults *)preferences;
- (void)reloadPreferences;
- (BOOL)publishBatteryDictionary:(NSDictionary *)dictionary generation:(NSUInteger)generation publisher:(id)publisher;
- (void)clearBatterySnapshot;
- (void)setPreviewActive:(BOOL)active;
- (void)updatePosition:(JikanPillPosition)position landscape:(BOOL)landscape;
@end
