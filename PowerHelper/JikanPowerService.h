#import <Foundation/Foundation.h>
#import <unistd.h>

#import "../Shared/JikanInputPowerProtocol.h"
#import "JikanSMCReader.h"

@interface JikanPowerService : NSObject <NSXPCListenerDelegate, JikanInputPowerProtocol>
- (void)run;
@end
