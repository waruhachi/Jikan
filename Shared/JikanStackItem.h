#import <Foundation/Foundation.h>

@interface JikanStackItem : NSObject <NSCopying>
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *type;
@property (nonatomic, copy, readonly) NSNumber *targetPercent;
@property (nonatomic, readonly) BOOL isMainEstimate;
@property (nonatomic, readonly) BOOL isEstimate;
@property (nonatomic, copy, readonly) NSDictionary *propertyList;
- (instancetype)initWithIdentifier:(NSString *)identifier type:(NSString *)type targetPercent:(NSNumber *)targetPercent;
+ (instancetype)estimateWithTargetPercent:(NSInteger)targetPercent;
- (NSInteger)targetForMainTarget:(NSInteger)mainTarget;
@end
