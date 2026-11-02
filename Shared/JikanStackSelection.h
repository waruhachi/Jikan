#import "JikanStackSettings.h"

// Owns selection and completed milestones for one charging session. It has no
// views or estimator dependencies, so manual cycling and advancement share it.
@interface JikanStackSelection : NSObject
@property (nonatomic, copy, readonly) NSString *selectedIdentifier;
- (void)updateItems:(NSArray<JikanStackItem *> *)items mainTarget:(NSInteger)mainTarget reachedTargets:(NSSet<NSNumber *> *)reachedTargets connected:(BOOL)connected generation:(NSUInteger)generation;
- (void)selectNextItem;
- (void)selectDefaultItem;
- (BOOL)isTargetCompleted:(NSInteger)target;
@end
