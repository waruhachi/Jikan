#import <Foundation/Foundation.h>
#import <Foundation/NSObjCRuntime.h>
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

@interface TT100Database : NSObject
+ (instancetype)shared;
- (BOOL)openIfNeeded;
- (void)close;
- (NSInteger)beginSessionWithStartSOC:(NSInteger)soc;
- (void)endSessionId:(NSInteger)sessionId endSOC:(NSInteger)soc;
- (void)updateSession:(NSInteger)sessionId chargerClass:(NSString *)chargerClass isWireless:(BOOL)isWireless;
- (void)markPlateauStartForSession:(NSInteger)sessionId timestamp:(NSTimeInterval)ts;
- (void)markPlateauEndForSession:(NSInteger)sessionId timestamp:(NSTimeInterval)ts;
- (void)insertTickForSession:(NSInteger)sessionId
						 soc:(NSInteger)soc
						  ts:(NSTimeInterval)ts
				batteryTempC:(double)temp
	  instantaneousCurrentmA:(NSInteger)current
					screenOn:(BOOL)screenOn
					 cpuLoad:(double)cpuLoad
				thermalLevel:(NSInteger)thermalLevel;
- (void)updatePercentStatsForChargerClass:(NSString *)chargerClass
						 withDurationsSec:(NSDictionary<NSNumber *, NSArray<NSNumber *> *> *)durationsByPercent;
- (BOOL)fetchPercentStatsForChargerClass:(NSString *)chargerClass
							  intoMedian:(double *)median
									 iqr:(double *)iqr
							sampleCounts:(int *)sampleCounts;
- (void)insertUnlockEventAt:(NSTimeInterval)ts wasCharging:(BOOL)charging soc:(NSInteger)soc;
- (void)pruneOldTickDataKeepingRecentSessions:(NSUInteger)recentCount;

@end

NS_ASSUME_NONNULL_END
