#import <Foundation/Foundation.h>
#import "../Shared/JikanAppleEstimateAvailability.h"
#import "../Shared/JikanEstimateSettings.h"
#import "../Shared/JikanAppleFeatures.h"

@interface AvailabilityDefaults : NSUserDefaults
@property NSMutableDictionary *values;
@end
@implementation AvailabilityDefaults
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (BOOL)boolForKey:(NSString *)key { return [self.values[key] boolValue]; }
@end
static NSUInteger checks;
#define CHECK(...) do { checks++; NSCAssert((__VA_ARGS__), @"Check %lu failed: %s", (unsigned long)checks, #__VA_ARGS__); } while (0)
static NSDictionary *Update(NSDictionary *state, NSString *status, NSString *power, BOOL charging, NSInteger target, double time) {
 return JikanAppleAvailabilityByUpdating(state, @{@"ExternalConnected": @(charging), @"IsCharging": @(charging)}, @{@"status": status, @"inputPowerSource": power, @"missingFeatures": @[@"PowerTelemetryData.SystemPowerIn"]}, target, time);
}
int main(void) { @autoreleasepool {
 NSDictionary *state = @{};
 CHECK(JikanAppleRecommendation(state,100)==nil);
 state = Update(state,@"missing_input_power",@"unavailable",NO,100,0);
 CHECK(JikanAppleRecommendation(state,100)==nil);
 state = Update(state,@"waiting_for_first_prediction",@"unavailable",YES,100,1);
 CHECK(JikanAppleRecommendation(state,100)==nil);
 state = Update(state,@"missing_input_power",@"unavailable",YES,100,10);
 CHECK(JikanAppleRecommendation(state,100)==nil);
 state = Update(state,@"missing_input_power",@"unavailable",YES,100,25);
 CHECK(JikanAppleRecommendation(state,100)==nil);
 state = Update(state,@"missing_input_power",@"unavailable",YES,100,40);
 CHECK([JikanAppleRecommendation(state,100) isEqual:@"jikan"]);
 CHECK([state[@"missingFeatures"] isEqual:@[@"PowerTelemetryData.SystemPowerIn"]]);
 state = Update(state,@"available",@"native",YES,100,55);
 CHECK([JikanAppleRecommendation(state,100) isEqual:@"apple"]);
 for (int i=0;i<5;i++) state=Update(state,@"invalid_input_power",@"unavailable",YES,100,70+15*i);
 CHECK([JikanAppleRecommendation(state,100) isEqual:@"apple"]);
 state=Update(state,@"disconnected",@"unavailable",NO,100,150);
 CHECK([JikanAppleRecommendation(state,100) isEqual:@"apple"]);
 CHECK(JikanAppleRecommendation(state,80)==nil); // one target does not prove another's inputs
 state=Update(state,@"available",@"smc",YES,80,170);
 CHECK([JikanAppleRecommendation(state,80) isEqual:@"apple"]);
 state=Update(@{},@"available",@"adapter_estimate",YES,100,0);
 CHECK(JikanAppleRecommendation(state,100)==nil); // approximation is not measured support
 state=@{};
 for (int i=0;i<4;i++) state=Update(state,@"model_load_failed",@"unavailable",YES,100,i*15);
 CHECK(JikanAppleRecommendation(state,100)==nil);
 state=Update(@{},@"missing_input_power",@"unavailable",YES,100,0);
 state=Update(state,@"paused",@"unavailable",NO,100,15);
 state=Update(state,@"missing_input_power",@"unavailable",YES,100,30);
 CHECK(JikanAppleRecommendation(state,100)==nil); // pause breaks the failure run
 for (int i=0;i<5;i++) {
  NSDictionary *cached=@{@"status": @"available", @"inputPowerSource": @"adapter_estimate", @"measuredInputs": @{@"status": @"missing_input_power", @"checkedAt": @0, @"powerSource": @"unavailable"}};
  state=JikanAppleAvailabilityByUpdating(i ? state : @{},@{@"ExternalConnected": @YES,@"IsCharging": @YES},cached,100,i*15);
 }
 CHECK(JikanAppleRecommendation(state,100)==nil); // repeated cached prediction is not three probes
 AvailabilityDefaults *prefs=[AvailabilityDefaults new];
 prefs.values[JikanEstimateSourceKey]=@"apple";
 CHECK([JikanEstimateSource(prefs) isEqual:@"apple"]);
 CHECK(![prefs boolForKey:JikanEstimateAppleEstimatedPowerKey]); // choosing Apple grants no approximation consent
 prefs.values[JikanEstimateSourceKey]=@"jikan";
 prefs.values[JikanEstimateAppleEstimatedPowerKey]=@YES;
 CHECK([JikanEstimateSource(prefs) isEqual:@"jikan"]);
 NSDictionary *unavailable=@{@"unavailableTargets": @[@100]};
 CHECK([JikanEstimateSourceForAvailability(prefs,unavailable) isEqual:@"jikan"]);
 [prefs.values removeAllObjects];
 CHECK([JikanEstimateSourceForAvailability(prefs,@{}) isEqual:@"apple"]); // unknown is not unsupported
 CHECK([JikanEstimateSourceForAvailability(prefs,unavailable) isEqual:@"jikan"]);
 prefs.values[JikanEstimateSourceKey]=@"apple";
 CHECK([JikanEstimateSourceForAvailability(prefs,unavailable) isEqual:@"apple"]);
 CHECK(![prefs boolForKey:JikanEstimateAppleEstimatedPowerKey]);
 [prefs.values removeAllObjects];
 CHECK([JikanEstimateSourceForAvailability(prefs,@{@"supportedTargets": @[@100]}) isEqual:@"apple"]);
 state=@{};
 for (int i=0;i<3;i++) state=Update(state,@"input_power_timeout",@"unavailable",YES,100,i*15);
 CHECK(JikanAppleRecommendation(state,100)==nil); // helper transport errors do not classify hardware
 state=Update(@{},@"missing_input_power",@"unavailable",YES,100,0);
 state=Update(state,@"missing_input_power",@"unavailable",YES,100,100);
 state=Update(state,@"missing_input_power",@"unavailable",YES,100,115);
 CHECK(JikanAppleRecommendation(state,100)==nil); // long gaps break failure continuity
 state=@{};
 for (int i=0;i<3;i++) state=Update(state,@"missing_input_power",@"unavailable",YES,100,i);
 CHECK(JikanAppleRecommendation(state,100)==nil); // three rapid notifications are insufficient
 // Replay the captured iPhone 13 input shape through the production validator.
 NSMutableDictionary *battery=[@{@"AdapterDetails": @{@"Watts": @15, @"FamilyCode": @(-536854518)}, @"BatteryData": @{@"Qmax": @[@2867], @"PresentDOD": @[@2729]}, @"CurrentCapacity": @93, @"NominalChargeCapacity": @2389, @"DesignCapacity": @3208, @"Temperature": @3239, @"CycleCount": @1690, @"InstantAmperage": @463, @"Voltage": @4356, @"PowerTelemetryData": @{@"SystemPowerIn": @2910}} mutableCopy];
 NSString *failure=nil; NSArray *missing=nil;
 for (NSNumber *target in @[@80,@85,@90,@95,@100]) CHECK(JikanAppleFeaturesWithDiagnostics(battery,target.integerValue,50,30,nil,&failure,&missing)!=nil);
 [battery removeObjectForKey:@"InstantAmperage"];
 CHECK(JikanAppleFeaturesWithDiagnostics(battery,80,50,30,nil,&failure,&missing)!=nil);
 CHECK(JikanAppleFeaturesWithDiagnostics(battery,100,50,30,nil,&failure,&missing)==nil);
 CHECK([missing isEqual:@[@"InstantAmperage"]]);
 battery[@"InstantAmperage"]=@463;
 [battery removeObjectForKey:@"PowerTelemetryData"];
 CHECK(JikanAppleFeaturesWithDiagnostics(battery,100,50,30,nil,&failure,&missing)==nil);
 CHECK([missing isEqual:@[@"PowerTelemetryData.SystemPowerIn"]]);
 CHECK(JikanAppleFeaturesWithDiagnostics(battery,100,50,30,@2910,&failure,&missing)!=nil); // measured override
 printf("Passed %lu Apple availability and selection checks.\n",(unsigned long)checks);
} return 0; }
