#import "JikanNotificationPublisher.h"

@interface BBDataProviderConnection : NSObject
- (id)addDataProvider:(id)provider;
@end

static NSString *const JikanNotificationSection = @"moe.waru.jikan";
static __weak BBDataProviderConnection *JikanNotificationConnection;
static dispatch_queue_t JikanNotificationQueue;

@interface BBSectionInfo (JikanNotification)
@property (nonatomic, copy) NSString *appName;
@property (nonatomic) BOOL enabled;
@property (nonatomic, strong) BBSectionIcon *icon;
@end

@interface JikanNotificationProvider : BBDataProvider
@end

@implementation JikanNotificationProvider

- (instancetype)init {
	self = [super init];
	if (self) {
		BBDataProviderIdentity *identity = [BBDataProviderIdentity identityForDataProvider:self];
		identity.sectionIdentifier = JikanNotificationSection;
		identity.sectionDisplayName = @"Jikan";
		identity.defaultSectionInfo = [self defaultSectionInfo];
		self.identity = identity;
	}
	return self;
}

- (NSString *)sectionIdentifier {
	return JikanNotificationSection;
}
- (NSString *)sectionDisplayName {
	return @"Jikan";
}
- (NSArray *)sortDescriptors {
	return @[[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO]];
}
- (NSSet *)bulletinsFilteredBy:(NSUInteger)filter count:(NSUInteger)count lastCleared:(NSDate *)lastCleared {
	return [NSSet set];
}

- (NSData *)sectionIconData {
	return [NSData dataWithContentsOfFile:jbroot(@"/Library/PreferenceBundles/JikanPreferences.bundle/icon@3x.png")];
}

- (BBSectionIcon *)sectionIcon {
	NSData *data = [self sectionIconData];
	if (!data.length) return nil;
	BBSectionIcon *icon = [BBSectionIcon new];
	[icon addVariant:[BBSectionIconVariant variantWithFormat:0 imageData:data]];
	return icon;
}

- (BBSectionInfo *)defaultSectionInfo {
	BBSectionInfo *info = [BBSectionInfo defaultSectionInfoForType:0];
	info.sectionID = JikanNotificationSection;
	info.allowsNotifications = YES;
	info.showsInLockScreen = YES;
	info.showsInNotificationCenter = YES;
	info.showsMessagePreview = YES;
	info.alertType = BBSectionInfoAlertTypeBanner;
	info.pushSettings = BBSectionInfoPushSettingsAlerts;
	info.notificationCenterLimit = 1;
	if ([info respondsToSelector:@selector(setAppName:)]) info.appName = @"Jikan";
	if ([info respondsToSelector:@selector(setEnabled:)]) info.enabled = YES;
	if ([info respondsToSelector:@selector(setIcon:)]) info.icon = [self sectionIcon];
	return info;
}

@end

@implementation JikanNotificationPublisher

+ (void)setServerQueue:(dispatch_queue_t)queue {
	if (!queue) return;
	@synchronized(self) {
		JikanNotificationQueue = queue;
	}
}

+ (void)setDataProviderConnection:(BBDataProviderConnection *)connection {
	if (!connection) return;
	@synchronized(self) {
		JikanNotificationConnection = connection;
	}
}

+ (BOOL)publishTargetReached:(NSInteger)targetPercent {
	BBDataProviderConnection *connection;
	dispatch_queue_t queue;
	@synchronized(self) {
		connection = JikanNotificationConnection;
		queue = JikanNotificationQueue;
	}
	if (!queue || ![connection respondsToSelector:@selector(addDataProvider:)]) return NO;
	NSString *message = [NSString stringWithFormat:JikanLocalizedString(@"jikan.notification.target_reached.message", @"Your battery has reached the %ld%% charge target."), (long)targetPercent];
	dispatch_async(queue, ^{
		// All provider registration and publication stays on BBServer's own queue.
		static JikanNotificationProvider *provider;
		static __weak BBDataProviderConnection *registeredConnection;
		if (registeredConnection != connection) {
			provider = [JikanNotificationProvider new];
			[connection addDataProvider:provider];
			registeredConnection = connection;
		}
		BBBulletinRequest *bulletin = [BBBulletinRequest new];
		bulletin.sectionID = JikanNotificationSection;
		bulletin.header = @"Jikan";
		bulletin.message = message;
		bulletin.bulletinID = NSUUID.UUID.UUIDString;
		bulletin.recordID = bulletin.bulletinID;
		bulletin.publisherBulletinID = bulletin.bulletinID;
		bulletin.date = [NSDate date];
		bulletin.publicationDate = bulletin.date;
		bulletin.lastInterruptDate = bulletin.date;
		bulletin.clearable = YES;
		bulletin.turnsOnDisplay = YES;
		bulletin.icon = [provider sectionIcon];
		BBDataProviderAddBulletin(provider, bulletin);
	});
	return YES;
}

@end
