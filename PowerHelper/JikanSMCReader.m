#import "JikanSMCReader.h"

typedef struct {
	uint8_t major, minor, build;
	uint16_t release;
} JikanSMCVersion;
typedef struct {
	uint16_t version, length;
	uint32_t cpu, gpu, memory;
} JikanSMCLimits;
typedef struct {
	uint32_t size, type;
	uint8_t attributes;
} JikanSMCKeyInfo;
typedef struct {
	uint32_t key;
	JikanSMCVersion version;
	JikanSMCLimits limits;
	JikanSMCKeyInfo info;
	uint8_t result, status, command;
	uint32_t index;
	uint8_t bytes[120];
} JikanSMCRequest;
_Static_assert(sizeof(JikanSMCRequest) == 168, "Unexpected AppleSMC request layout");

static uint32_t JikanSMCKey(const char *name) {
	return (uint32_t)name[0] << 24 | (uint32_t)name[1] << 16 | (uint32_t)name[2] << 8 | (uint32_t)name[3];
}

static BOOL JikanSMCRead(io_connect_t connection, const char *name, const char *type, uint32_t length, void *bytes) {
	JikanSMCRequest request = {0}, response = {0};
	request.key = JikanSMCKey(name);
	request.command = 9;  // Read key information.
	size_t size = sizeof(response);
	kern_return_t result = IOConnectCallStructMethod(connection, 2, &request, sizeof(request), &response, &size);
	if (result || size != sizeof(response) || response.result || response.info.size != length || response.info.type != JikanSMCKey(type)) return NO;
	request.info = response.info;
	request.command = 5;  // Read value; no write commands are supported.
	memset(&response, 0, sizeof(response));
	size = sizeof(response);
	result = IOConnectCallStructMethod(connection, 2, &request, sizeof(request), &response, &size);
	if (result || size != sizeof(response) || response.result || length > sizeof(response.bytes)) return NO;
	memcpy(bytes, response.bytes, length);
	return YES;
}

static double JikanSMCSensor(io_connect_t connection, const char *name) {
	int64_t value = 0;
	return JikanSMCRead(connection, name, "ioft", sizeof(value), &value) ? (double)value / 65536.0 : NAN;
}

static NSDictionary *JikanPowerState(void) {
	io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPMPowerSource"));
	if (!service) return nil;
	CFMutableDictionaryRef properties = NULL;
	IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0);
	IOObjectRelease(service);
	return CFBridgingRelease(properties);
}

static NSDictionary *JikanWiredIdentity(NSDictionary *state) {
	NSDictionary *adapter = state[@"AdapterDetails"];
	if (![adapter isKindOfClass:NSDictionary.class] || ![state[@"ExternalConnected"] boolValue] || ![state[@"IsCharging"] boolValue]) return nil;
	NSNumber *wireless = adapter[@"IsWireless"];
	if (![wireless isKindOfClass:NSNumber.class] || wireless.boolValue || [state[@"IsWirelessCharging"] boolValue]) return nil;
	// Compare the complete adapter description across the sampling window.
	return adapter;
}

@implementation JikanSMCReader

+ (NSDictionary *)readInputPower {
	NSDictionary *identity = JikanWiredIdentity(JikanPowerState());
	if (!identity) return @{@"status": @"input_power_unavailable"};
	io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSMC"));
	io_connect_t connection = IO_OBJECT_NULL;
	kern_return_t result = service ? IOServiceOpen(service, mach_task_self(), 0, &connection) : kIOReturnNotFound;
	if (service) IOObjectRelease(service);
	if (result) return @{@"status": @"input_power_access_denied"};
	double total = 0;
	BOOL valid = YES;
	for (NSUInteger i = 0; i < 3; i++) {
		uint32_t port = 0;
		// Only CHPS=1 / VQ0u has been verified for the missing-telemetry path.
		if (!JikanSMCRead(connection, "CHPS", "ui32", sizeof(port), &port) || port != 1) {
			valid = NO;
			break;
		}
		double current = JikanSMCSensor(connection, "IQ0u");
		double voltage = JikanSMCSensor(connection, "VQ0u");
		if (!isfinite(current) || !isfinite(voltage) || current <= 0 || current > 12 || voltage < 2.5 || voltage > 30 || current * voltage > 240) {
			valid = NO;
			break;
		}
		total += current * voltage * 1000.0;
		if (i < 2) usleep(250000);
	}
	uint32_t finalPort = 0;
	valid = valid && JikanSMCRead(connection, "CHPS", "ui32", sizeof(finalPort), &finalPort) && finalPort == 1;
	IOServiceClose(connection);
	if (!valid) return @{@"status": @"input_power_unsupported_path"};
	if (![identity isEqual:JikanWiredIdentity(JikanPowerState())]) return @{@"status": @"input_power_state_changed"};
	return @{@"status": @"available", @"milliwatts": @(total / 3.0), @"timestamp": @([NSDate date].timeIntervalSince1970), @"adapter": identity, @"source": @"smc"};
}

@end
