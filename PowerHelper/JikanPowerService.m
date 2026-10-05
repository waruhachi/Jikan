#import "JikanPowerService.h"

@interface JikanPowerService ()
@property (nonatomic, strong) dispatch_queue_t samplingQueue;
@property (nonatomic, strong) NSXPCListener *listener;
@property (nonatomic, assign) NSUInteger idleGeneration;
@end

@implementation JikanPowerService

- (void)_scheduleIdleExit {
	NSUInteger generation = ++self.idleGeneration;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), self.samplingQueue, ^{
		if (generation == self.idleGeneration) exit(EXIT_SUCCESS);
	});
}

- (void)run {
	self.samplingQueue = dispatch_queue_create("moe.waru.jikan.input-power.samples", DISPATCH_QUEUE_SERIAL);
	dispatch_async(self.samplingQueue, ^{ [self _scheduleIdleExit]; });
	self.listener = (NSXPCListener *)[(id<JikanMachServiceListener>)[NSXPCListener alloc] initWithMachServiceName:JikanInputPowerServiceName];
	self.listener.delegate = self;
	[self.listener resume];
	dispatch_main();
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
	if (connection.effectiveUserIdentifier != 501 && connection.effectiveUserIdentifier != 0) return NO;
	connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(JikanInputPowerProtocol)];
	connection.exportedObject = self;
	[connection resume];
	return YES;
}

- (void)readInputPowerWithReply:(void (^)(NSDictionary *))reply {
	dispatch_async(self.samplingQueue, ^{
		@autoreleasepool {
			reply([JikanSMCReader readInputPower]);
			[self _scheduleIdleExit];
		}
	});
}

@end
