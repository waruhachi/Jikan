#import "TT100LegacyHistory.h"

NSString *TT100PLSQLPath(void) {
	static NSString *cachedPath = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSString *baseDir = jbroot(@"/var/containers/Shared/SystemGroup");
		NSString *relativeSuffix = @"Library/BatteryLife/CurrentPowerlog.PLSQL";
		DIR *dir = opendir([baseDir UTF8String]);
		if (!dir) return;
		struct dirent *entry;
		while ((entry = readdir(dir)) != NULL) {
			if (entry->d_type == DT_DIR) {
				NSString *name = [NSString stringWithUTF8String:entry->d_name];
				if ([name hasPrefix:@"."]) continue;
				NSString *candidate = [baseDir stringByAppendingPathComponent:name];
				candidate = [candidate stringByAppendingPathComponent:relativeSuffix];
				if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
					cachedPath = candidate;
					break;
				}
			}
		}
		closedir(dir);
	});
	return cachedPath;
}

static NSDate *TT100ParseDate(NSString *dateString) {
	static NSDateFormatter *fmt = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		fmt = [[NSDateFormatter alloc] init];
		fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
		fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
	});
	return [fmt dateFromString:dateString];
}

@implementation TT100LegacyHistory

+ (NSDictionary<NSString *, NSNumber *> *)loadHistoryFromPLSQL {
	NSError *err = nil;
	NSString *sql = [NSString stringWithContentsOfFile:TT100PLSQLPath() encoding:NSUTF8StringEncoding error:&err];
	if (!sql.length) {
		NSLog(@"[TT100] Could not read PL/SQL file: %@", err);
		return @{};
	}

	NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"INSERT INTO\\s+battery_history\\s*\\(\\s*pct\\s*,\\s*seconds(?:\\s*,\\s*timestamp)?\\s*\\)\\s*VALUES\\s*\\(\\s*(\\d+)\\s*,\\s*([0-9]+\\.?[0-9]*)(?:\\s*,\\s*'([0-9:\\s-]+)')?\\s*\\)" options:NSRegularExpressionCaseInsensitive error:&err];
	if (!re) {
		NSLog(@"[TT100] Regex error: %@", err);
		return @{};
	}
	NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *perBucket = [NSMutableDictionary new];
	NSArray<NSTextCheckingResult *> *matches = [re matchesInString:sql options:0 range:NSMakeRange(0, sql.length)];
	NSDate *now = [NSDate date];
	NSTimeInterval maxAge = 30 * 24 * 3600;
	for (NSTextCheckingResult *m in matches) {
		NSString *pctStr = [sql substringWithRange:[m rangeAtIndex:1]];
		NSString *secStr = [sql substringWithRange:[m rangeAtIndex:2]];
		double seconds = secStr.doubleValue;

		if (seconds < 10 || seconds > 3600) continue;
		NSDate *ts = nil;
		if ([m numberOfRanges] > 3 && [m rangeAtIndex:3].location != NSNotFound) {
			NSString *dateStr = [sql substringWithRange:[m rangeAtIndex:3]];
			ts = TT100ParseDate(dateStr);
		}

		if (ts && [now timeIntervalSinceDate:ts] > maxAge) continue;
		NSMutableArray *arr = perBucket[pctStr];
		if (!arr) arr = perBucket[pctStr] = [NSMutableArray new];
		[arr addObject:@{@"seconds": @(seconds), @"date": ts ?: [NSNull null]}];
	}

	NSMutableDictionary<NSString *, NSNumber *> *buckets = [NSMutableDictionary new];
	for (NSString *pctStr in perBucket) {
		NSArray *arr = perBucket[pctStr];
		double sum = 0, totalWeight = 0;
		for (NSDictionary *entry in arr) {
			double seconds = [entry[@"seconds"] doubleValue];
			NSDate *ts = entry[@"date"] == [NSNull null] ? nil : entry[@"date"];
			double weight = 1.0;
			if (ts) {
				double daysAgo = [[NSDate date] timeIntervalSinceDate:ts] / (24 * 3600.0);

				weight = fmax(0.5, 1.0 - daysAgo / 60.0);
			}
			sum += seconds * weight;
			totalWeight += weight;
		}
		if (totalWeight > 0) {
			buckets[pctStr] = @(sum / totalWeight);
		}
	}
	return buckets;
}

+ (NSDictionary<NSString *, NSNumber *> *)cachedHistoryBuckets {
	static NSDictionary<NSString *, NSNumber *> *cached = nil;
	static NSDate *cachedMTime = nil;
	static dispatch_queue_t q;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		q = dispatch_queue_create("com.tt100.plsql-cache", DISPATCH_QUEUE_SERIAL);
	});

	__block NSDictionary<NSString *, NSNumber *> *out = nil;
	dispatch_sync(q, ^{
		NSString *path = TT100PLSQLPath();
		NSDate *mtime = nil;
		if (path.length) {
			NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
			mtime = attrs[NSFileModificationDate];
		}

		BOOL needsReload = (cached == nil);
		if (!needsReload && mtime && cachedMTime) {
			needsReload = ([mtime compare:cachedMTime] == NSOrderedDescending);
		}

		if (needsReload) {
			cached = [self loadHistoryFromPLSQL];
			cachedMTime = mtime;
		}
		out = cached ?: @{};
	});
	return out;
}

@end
