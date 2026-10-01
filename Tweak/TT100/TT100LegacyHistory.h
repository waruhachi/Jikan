#import <Foundation/Foundation.h>
#import <dirent.h>
#import <math.h>
#import <roothide.h>

FOUNDATION_EXPORT NSString *TT100PLSQLPath(void);

@interface TT100LegacyHistory : NSObject
+ (NSDictionary<NSString *, NSNumber *> *)loadHistoryFromPLSQL;
+ (NSDictionary<NSString *, NSNumber *> *)cachedHistoryBuckets;
@end
