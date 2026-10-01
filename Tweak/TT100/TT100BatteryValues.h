#import <Foundation/Foundation.h>
#import <math.h>

static inline NSNumber *TT100Number(NSDictionary *dict, NSString *key) {
	if (![dict isKindOfClass:[NSDictionary class]]) return nil;
	id v = dict[key];
	return [v isKindOfClass:[NSNumber class]] ? (NSNumber *)v : nil;
}

static inline BOOL TT100Bool(NSDictionary *dict, NSString *key, BOOL *outHasValue) {
	NSNumber *n = TT100Number(dict, key);
	if (n) {
		if (outHasValue) *outHasValue = YES;
		return n.boolValue;
	}
	if (outHasValue) *outHasValue = NO;
	return NO;
}
