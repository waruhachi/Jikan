#import <Foundation/Foundation.h>

#define JikanInputPowerServiceName @"moe.waru.jikan.input-power"

// The helper exposes no key selection or SMC write operation.
@protocol JikanInputPowerProtocol
- (void)readInputPowerWithReply:(void (^)(NSDictionary *sample))reply;
@end

// Available at runtime on iOS, but omitted from the public iOS SDK interface.
@protocol JikanMachServiceListener
- (instancetype)initWithMachServiceName:(NSString *)name;
@end

@protocol JikanMachServiceConnection
- (instancetype)initWithMachServiceName:(NSString *)name options:(NSXPCConnectionOptions)options;
@end
