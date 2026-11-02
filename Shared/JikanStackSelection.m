#import "JikanStackSelection.h"

@interface JikanStackSelection ()
@property (nonatomic, copy) NSArray<JikanStackItem *> *items;
@property (nonatomic, copy, readwrite) NSString *selectedIdentifier;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *completed;
@property (nonatomic) NSInteger mainTarget;
@property (nonatomic) BOOL connected;
@property (nonatomic) NSUInteger generation;
@end

@implementation JikanStackSelection
- (instancetype)init {
	if ((self = [super init])) {
		_selectedIdentifier = JikanStackEstimate;
		_completed = [NSMutableSet set];
	}
	return self;
}
- (JikanStackItem *)_selectedItem {
	for (JikanStackItem *item in self.items) if ([item.identifier isEqual:self.selectedIdentifier]) return item;
	return nil;
}
- (NSString *)_nextUnfinishedEstimateAfter:(NSInteger)target {
	JikanStackItem *candidate = nil;
	for (JikanStackItem *item in self.items) {
		NSInteger value = [item targetForMainTarget:self.mainTarget];
		if (!item.isEstimate || value <= target || [self.completed containsObject:@(value)]) continue;
		if (!candidate || value < [candidate targetForMainTarget:self.mainTarget]) candidate = item;
	}
	return candidate.identifier;
}
- (void)updateItems:(NSArray<JikanStackItem *> *)items mainTarget:(NSInteger)mainTarget reachedTargets:(NSSet<NSNumber *> *)reachedTargets connected:(BOOL)connected generation:(NSUInteger)generation {
	BOOL newSession = connected && !self.connected;
	BOOL disconnected = !connected && self.connected;
	BOOL sameConfiguration = self.generation == generation && self.mainTarget == mainTarget && [self.items isEqualToArray:items];
	NSMutableSet *newlyReached = [reachedTargets mutableCopy];
	[newlyReached minusSet:self.completed];
	if (!connected || newSession) [self.completed removeAllObjects];
	self.items = items;
	self.mainTarget = mainTarget;
	self.generation = generation;
	self.connected = connected;
	if (connected) [self.completed unionSet:reachedTargets];
	JikanStackItem *selected = [self _selectedItem];
	if (newSession || !selected || disconnected) {
		[self selectDefaultItem];
	} else if (connected && sameConfiguration && selected.isEstimate && [newlyReached containsObject:@([selected targetForMainTarget:mainTarget])]) {
		NSString *next = [self _nextUnfinishedEstimateAfter:[selected targetForMainTarget:mainTarget]];
		if (next) self.selectedIdentifier = next;
	}
}
- (void)selectDefaultItem {
	self.selectedIdentifier = JikanStackEstimate;
	if ([self.completed containsObject:@(self.mainTarget)]) {
		NSString *next = [self _nextUnfinishedEstimateAfter:self.mainTarget];
		if (next) self.selectedIdentifier = next;
	}
}
- (void)selectNextItem {
	if (!self.items.count) return;
	NSUInteger index = NSNotFound;
	for (NSUInteger i = 0; i < self.items.count; i++) if ([self.items[i].identifier isEqual:self.selectedIdentifier]) { index = i; break; }
	self.selectedIdentifier = self.items[(index == NSNotFound ? 0 : index + 1) % self.items.count].identifier;
}
- (BOOL)isTargetCompleted:(NSInteger)target { return [self.completed containsObject:@(target)]; }
@end
