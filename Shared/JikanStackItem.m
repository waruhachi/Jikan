#import "JikanStackItem.h"

@implementation JikanStackItem
- (instancetype)initWithIdentifier:(NSString *)identifier type:(NSString *)type targetPercent:(NSNumber *)targetPercent {
	if ((self = [super init])) {
		_identifier = [identifier copy];
		_type = [type copy];
		_targetPercent = [targetPercent copy];
	}
	return self;
}
+ (instancetype)estimateWithTargetPercent:(NSInteger)targetPercent {
	return [[self alloc] initWithIdentifier:NSUUID.UUID.UUIDString type:@"estimate" targetPercent:@(targetPercent)];
}
- (BOOL)isMainEstimate { return [_identifier isEqualToString:@"estimate"]; }
- (BOOL)isEstimate { return [_type isEqualToString:@"estimate"]; }
- (NSInteger)targetForMainTarget:(NSInteger)mainTarget { return self.isMainEstimate ? mainTarget : _targetPercent.integerValue; }
- (NSDictionary *)propertyList {
	return _targetPercent ? @{@"id": _identifier, @"type": _type, @"target": _targetPercent} : @{@"id": _identifier, @"type": _type};
}
- (id)copyWithZone:(NSZone *)zone { return self; }
- (BOOL)isEqual:(id)object {
	return object == self || ([object isKindOfClass:JikanStackItem.class] && [self.propertyList isEqual:[object propertyList]]);
}
- (NSUInteger)hash { return _identifier.hash; }
@end
