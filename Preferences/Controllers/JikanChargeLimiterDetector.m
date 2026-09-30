#import "JikanChargeLimiterDetector.h"

static NSNumber *JikanDetectedLimit(id value) {
	double raw = 0;
	if ([value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) raw = [value doubleValue];
	else if (![value isKindOfClass:NSString.class] || !JikanParseNumber(value, [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"], &raw))
		return nil;
	if (!isfinite(raw) || raw < 1 || raw > 100) return nil;
	return @(raw);
}

static BOOL JikanIsChargeLimiterApp(NSString *path) {
	BOOL directory = NO;
	return [path.lastPathComponent isEqualToString:@"ChargeLimiter.app"] &&
		[NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory] && directory;
}

static BOOL JikanChargeLimiterInstalled(NSOperation *operation) {
	if (operation.cancelled) return NO;
	if (JikanIsChargeLimiterApp(jbroot(@"/Applications/ChargeLimiter.app")) || JikanIsChargeLimiterApp(@"/Applications/ChargeLimiter.app")) return YES;
	for (NSString *root in @[@"/var/containers/Bundle/Application", @"/private/var/containers/Bundle/Application"]) {
		if (operation.cancelled) return NO;
		for (NSString *entry in [NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil]) {
			if (operation.cancelled) return NO;
			NSString *path = [[root stringByAppendingPathComponent:entry] stringByAppendingPathComponent:@"ChargeLimiter.app"];
			if (JikanIsChargeLimiterApp(path)) return YES;
		}
	}
	return NO;
}

@interface JikanChargeLimiterDetector ()
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, strong) NSOperation *operation;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, copy) void (^completion)(NSNumber *);
@end

@implementation JikanChargeLimiterDetector

- (void)dealloc {
	[_operation cancel];
	[_task cancel];
}

- (void)cancel {
	self.generation++;
	[self.operation cancel];
	[self.task cancel];
	self.operation = nil;
	self.task = nil;
	self.completion = nil;
}

- (void)_finishWithLimit:(NSNumber *)detected generation:(NSUInteger)generation {
	if (generation != self.generation) return;
	void (^completion)(NSNumber *) = self.completion;
	[self cancel];
	if (completion) completion(detected);
}

- (void)_requestChargeLimiterLimitForGeneration:(NSUInteger)generation {
	if (generation != self.generation) return;
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:1230"]];
	request.HTTPMethod = @"POST";
	request.timeoutInterval = 1.5;
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"api": @"get_conf", @"key": @"charge_above"} options:0 error:nil];
	__weak typeof(self) weakSelf = self;
	self.task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSNumber *detected = nil;
		if (!error && data.length && [response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode == 200) {
			id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
			if ([json isKindOfClass:NSDictionary.class]) {
				id status = json[@"status"];
				double statusValue = NAN;
				if ([status isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)status) != CFBooleanGetTypeID()) statusValue = [status doubleValue];
				else if ([status isKindOfClass:NSString.class])
					JikanParseNumber(status, [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"], &statusValue);
				if (statusValue == 0) detected = JikanDetectedLimit(json[@"data"]);
			}
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			[weakSelf _finishWithLimit:detected generation:generation];
		});
	}];
	[self.task resume];
}

- (void)detectLimitWithCompletion:(void (^)(NSNumber *limit))completion {
	[self cancel];
	self.completion = completion;
	NSUInteger generation = self.generation;
	__weak typeof(self) weakSelf = self;
	NSBlockOperation *operation = [NSBlockOperation new];
	__weak NSBlockOperation *weakOperation = operation;
	[operation addExecutionBlock:^{
		NSBlockOperation *operation = weakOperation;
		if (!operation || operation.cancelled) return;
		BOOL installed = JikanChargeLimiterInstalled(operation);
		if (operation.cancelled) return;
		NSNumber *detected = nil;
		if (installed) {
			NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:@"/var/root/aldente.conf"];
			detected = JikanDetectedLimit(config[@"charge_above"]);
		}
		if (operation.cancelled) return;
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) self = weakSelf;
			if (!self || generation != self.generation || operation.cancelled) return;
			self.operation = nil;
			if (detected || !installed) [self _finishWithLimit:detected generation:generation];
			else
				[self _requestChargeLimiterLimitForGeneration:generation];
		});
	}];
	self.operation = operation;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [operation start]; });
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[weakSelf _finishWithLimit:nil generation:generation];
	});
}

@end
