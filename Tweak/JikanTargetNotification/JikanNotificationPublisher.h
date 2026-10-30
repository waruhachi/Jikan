#import <BulletinBoard/BBBulletinRequest.h>
#import <BulletinBoard/BBDataProvider.h>
#import <BulletinBoard/BBDataProviderIdentity.h>
#import <BulletinBoard/BBSectionIcon.h>
#import <BulletinBoard/BBSectionIconVariant.h>
#import <BulletinBoard/BBSectionInfo.h>
#import <BulletinBoard/BBServer.h>
#import <Foundation/Foundation.h>
#import <roothide.h>

#import "../../Localization/JikanLocalization.h"

@class BBDataProviderConnection;

@interface JikanNotificationPublisher : NSObject
+ (void)setServerQueue:(dispatch_queue_t)queue;
+ (void)setDataProviderConnection:(BBDataProviderConnection *)connection;
+ (BOOL)publishTargetReached:(NSInteger)targetPercent;
@end
