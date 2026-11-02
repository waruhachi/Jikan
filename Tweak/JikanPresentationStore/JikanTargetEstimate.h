#import <Foundation/Foundation.h>

@interface JikanTargetEstimate : NSObject
@property (nonatomic, readonly) NSInteger targetPercent;
@property (nonatomic, copy, readonly) NSString *timeString;
@property (nonatomic, copy, readonly) NSString *status;
@property (nonatomic, readonly) double remainingSeconds;
@property (nonatomic, readonly) BOOL hasEstimate;
@property (nonatomic, readonly) BOOL targetReached;
- (instancetype)initWithDictionary:(NSDictionary *)dictionary targetPercent:(NSInteger)targetPercent;
@end
