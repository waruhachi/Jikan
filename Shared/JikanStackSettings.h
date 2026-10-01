#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <math.h>

FOUNDATION_EXPORT NSString *const JikanStackItemsKey;
FOUNDATION_EXPORT NSString *const JikanTemperatureUnitKey;
FOUNDATION_EXPORT NSString *const JikanStackEstimate;
FOUNDATION_EXPORT NSString *const JikanStackWattage;
FOUNDATION_EXPORT NSString *const JikanStackTemperature;
FOUNDATION_EXPORT NSString *const JikanStackVoltage;

FOUNDATION_EXPORT NSArray<NSString *> *JikanStackItems(NSUserDefaults *preferences);
FOUNDATION_EXPORT NSArray<NSString *> *JikanNormalizeStackItems(id value);
FOUNDATION_EXPORT NSString *JikanTemperatureUnit(NSUserDefaults *preferences);
FOUNDATION_EXPORT NSString *JikanResolvedTemperatureUnit(NSUserDefaults *preferences);
FOUNDATION_EXPORT NSString *JikanResolveTemperatureUnit(NSString *choice);
FOUNDATION_EXPORT NSString *JikanFormattedBatteryTemperature(NSDictionary *batteryInfo, NSString *unit);
FOUNDATION_EXPORT NSString *JikanFormattedBatteryVoltage(NSDictionary *batteryInfo);
