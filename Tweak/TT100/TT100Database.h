#import <Foundation/Foundation.h>
#import <math.h>
#import <sqlite3.h>

@interface TT100Database : NSObject
+ (instancetype)shared;
- (NSInteger)beginSessionWithStartSOC:(NSInteger)soc timestamp:(NSTimeInterval)ts;
- (void)endSessionId:(NSInteger)sessionId endSOC:(NSInteger)soc timestamp:(NSTimeInterval)ts;
- (void)updateSession:(NSInteger)sessionId chargerClass:(NSString *)chargerClass isWireless:(BOOL)isWireless;
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
							intoEstimate:(double *)estimate
							 uncertainty:(double *)uncertainty
							sampleCounts:(int *)sampleCounts
							 lastUpdated:(double *)lastUpdated;

@end
