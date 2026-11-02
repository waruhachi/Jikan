#import <Preferences/PSViewController.h>
#import "../../Shared/JikanStackSettings.h"

@interface JikanStackEstimateController : PSViewController
- (instancetype)initWithItem:(JikanStackItem *)item items:(NSArray<JikanStackItem *> *)items saveHandler:(void (^)(JikanStackItem *item))saveHandler;
@end
