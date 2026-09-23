#import <math.h>

#import "TT100Database.h"

static NSString *const kTT100DBDirectory = @"Library/TT100";
static NSString *const kTT100DBFilename = @"tt100.db";

@interface TT100Database () {
	sqlite3 *_db;
	dispatch_queue_t _queue;
	BOOL _ready;
	BOOL _recovered;
	NSUInteger _writesSincePrune;
}
@end

@implementation TT100Database

+ (instancetype)shared {
	static TT100Database *g;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ g = [TT100Database new]; });
	return g;
}

- (instancetype)init {
	if ((self = [super init])) {
		_queue = dispatch_queue_create("com.tt100.db", DISPATCH_QUEUE_SERIAL);
	}
	return self;
}

- (void)dealloc {
	if (_db) sqlite3_close_v2(_db);
}

- (NSString *)_dbPath {
	NSString *home = NSHomeDirectory();
	NSString *dir = [home stringByAppendingPathComponent:kTT100DBDirectory];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
	return [dir stringByAppendingPathComponent:kTT100DBFilename];
}

- (BOOL)_openOnQueue {
	if (_ready && _db) return YES;
	if (_db) {
		sqlite3_close_v2(_db);
		_db = NULL;
	}
	NSString *path = [self _dbPath];
	BOOL opened = path.length && sqlite3_open_v2(path.UTF8String, &_db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) == SQLITE_OK;
	if (!opened) {
		NSLog(@"[Jikan] DB open failed: %s", _db ? sqlite3_errmsg(_db) : "missing path");
	} else {
		sqlite3_busy_timeout(_db, 1000);
		opened = [self _exec:@"PRAGMA journal_mode=WAL;"] &&
			[self _exec:@"PRAGMA synchronous=NORMAL;"] &&
			[self _exec:@"PRAGMA foreign_keys=ON;"] && [self _migrateIfNeeded];
		if (opened && !_recovered) {
			opened = [self _exec:@"BEGIN IMMEDIATE;"];
			if (opened) {
				opened = [self _exec:@"UPDATE sessions SET end_ts=COALESCE((SELECT MAX(ts) FROM ticks WHERE session_id=sessions.id),start_ts), end_soc=COALESCE((SELECT soc FROM ticks WHERE session_id=sessions.id ORDER BY ts DESC,id DESC LIMIT 1),start_soc), notes=CASE WHEN notes IS NULL OR notes='' THEN 'interrupted' ELSE notes || ';interrupted' END WHERE end_ts IS NULL;"] && [self _exec:@"COMMIT;"];
				if (!opened) [self _exec:@"ROLLBACK;"];
			}
		}
		if (opened) opened = [self _pruneOnQueue:128];
	}
	if (!opened) {
		if (_db) sqlite3_close_v2(_db);
		_db = NULL;
		_ready = NO;
		return NO;
	}
	_recovered = YES;
	_ready = YES;
	return YES;
}

- (BOOL)openIfNeeded {
	__block BOOL ok = NO;
	dispatch_sync(_queue, ^{ ok = [self _openOnQueue]; });
	return ok;
}

- (void)close {
	dispatch_sync(_queue, ^{
		_ready = NO;
		if (_db) sqlite3_close_v2(_db);
		_db = NULL;
	});
}

- (BOOL)_exec:(NSString *)sql {
	char *err = NULL;
	if (sqlite3_exec(_db, sql.UTF8String, NULL, NULL, &err) != SQLITE_OK) {
		NSLog(@"[Jikan] (TT100Database) SQL exec error: %s; statement: %@", err, sql);
		sqlite3_free(err);
		return NO;
	}
	return YES;
}

- (BOOL)_prepare:(const char *)sql statement:(sqlite3_stmt **)statement {
	if (sqlite3_prepare_v2(_db, sql, -1, statement, NULL) == SQLITE_OK) return YES;
	NSLog(@"[Jikan] DB prepare failed: %s; statement: %s", sqlite3_errmsg(_db), sql);
	sqlite3_finalize(*statement);
	*statement = NULL;
	return NO;
}

- (BOOL)_stepDone:(sqlite3_stmt *)statement {
	if (sqlite3_step(statement) == SQLITE_DONE) return YES;
	NSLog(@"[Jikan] DB write failed: %s; statement: %s", sqlite3_errmsg(_db), sqlite3_sql(statement));
	return NO;
}

- (NSInteger)_schemaVersion {
	const char *q = "SELECT value FROM meta WHERE key='schema_version'";
	sqlite3_stmt *stmt = NULL;
	NSInteger v = 0;
	if (sqlite3_prepare_v2(_db, q, -1, &stmt, NULL) == SQLITE_OK) {
		if (sqlite3_step(stmt) == SQLITE_ROW) {
			const unsigned char *txt = sqlite3_column_text(stmt, 0);
			if (txt) v = atoi((const char *)txt);
		}
	}
	sqlite3_finalize(stmt);
	return v;
}

- (BOOL)_migrateIfNeeded {
	NSInteger version = [self _schemaVersion];
	if (version > 2) {
		NSLog(@"[Jikan] Unsupported DB schema version: %ld", (long)version);
		return NO;
	}
	if (![self _exec:@"BEGIN IMMEDIATE;"]) return NO;
	NSString *schema =
		@"CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);"
		 "CREATE TABLE IF NOT EXISTS sessions ("
		 "id INTEGER PRIMARY KEY AUTOINCREMENT,"
		 "start_ts REAL NOT NULL,"
		 "end_ts REAL,"
		 "start_soc INTEGER NOT NULL,"
		 "end_soc INTEGER,"
		 "charger_class TEXT DEFAULT 'unknown',"
		 "is_wireless INTEGER DEFAULT 0,"
		 "avg_cc_slope_pct_per_min REAL,"
		 "avg_cv_slope_pct_per_min REAL,"
		 "plateau_detected INTEGER DEFAULT 0,"
		 "plateau_start_ts REAL,"
		 "plateau_end_ts REAL,"
		 "purity_score REAL,"
		 "thermal_flags INTEGER DEFAULT 0,"
		 "notes TEXT);"
		 "CREATE INDEX IF NOT EXISTS idx_sessions_start_ts ON sessions(start_ts);"
		 "CREATE TABLE IF NOT EXISTS ticks ("
		 "id INTEGER PRIMARY KEY AUTOINCREMENT,"
		 "session_id INTEGER NOT NULL,"
		 "soc INTEGER NOT NULL,"
		 "ts REAL NOT NULL,"
		 "battery_temp_c REAL,"
		 "instantaneous_current_mA INTEGER,"
		 "screen_on INTEGER,"
		 "cpu_load REAL,"
		 "thermal_level INTEGER,"
		 "FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE);"
		 "CREATE INDEX IF NOT EXISTS idx_ticks_session_soc ON ticks(session_id, soc);"
		 "CREATE TABLE IF NOT EXISTS unlock_events ("
		 "id INTEGER PRIMARY KEY AUTOINCREMENT,"
		 "ts REAL NOT NULL,"
		 "was_charging INTEGER NOT NULL,"
		 "soc INTEGER NOT NULL);"
		 "CREATE INDEX IF NOT EXISTS idx_unlock_ts ON unlock_events(ts);"
		 "CREATE TABLE IF NOT EXISTS percent_stats ("
		 "charger_class TEXT NOT NULL,"
		 "percent INTEGER NOT NULL,"
		 "median_seconds REAL,"
		 "iqr_seconds REAL,"
		 "mean_seconds REAL,"
		 "m2_seconds REAL,"
		 "sample_count INTEGER DEFAULT 0,"
		 "last_updated_ts REAL,"
		 "PRIMARY KEY (charger_class, percent));";
	BOOL ok = [self _exec:schema];
	NSMutableSet *columns = [NSMutableSet set];
	sqlite3_stmt *stmt = NULL;
	if (ok) {
		ok = sqlite3_prepare_v2(_db, "PRAGMA table_info(percent_stats)", -1, &stmt, NULL) == SQLITE_OK;
		if (ok) {
			int rc;
			while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
				const char *name = (const char *)sqlite3_column_text(stmt, 1);
				if (name) [columns addObject:[NSString stringWithUTF8String:name]];
			}
			ok = rc == SQLITE_DONE;
		}
		sqlite3_finalize(stmt);
	}
	for (NSString *column in @[@"mean_seconds", @"m2_seconds"]) {
		if (ok && ![columns containsObject:column]) {
			ok = [self _exec:[NSString stringWithFormat:@"ALTER TABLE percent_stats ADD COLUMN %@ REAL;", column]];
		}
	}
	if (ok) ok = [self _exec:@"UPDATE percent_stats SET mean_seconds=COALESCE(mean_seconds, median_seconds), m2_seconds=COALESCE(m2_seconds,0.0);"];
	if (ok) ok = [self _exec:@"SELECT id,start_ts,end_ts,start_soc,end_soc,charger_class,is_wireless,plateau_detected,plateau_start_ts,plateau_end_ts,notes FROM sessions LIMIT 0; SELECT id,session_id,soc,ts,battery_temp_c,instantaneous_current_mA,screen_on,cpu_load,thermal_level FROM ticks LIMIT 0; SELECT id,ts,was_charging,soc FROM unlock_events LIMIT 0; SELECT charger_class,percent,median_seconds,iqr_seconds,mean_seconds,m2_seconds,sample_count,last_updated_ts FROM percent_stats LIMIT 0;"];
	if (ok) ok = [self _exec:@"INSERT OR REPLACE INTO meta(key,value) VALUES('schema_version','2');"];
	if (ok) ok = [self _exec:@"COMMIT;"];
	if (!ok) [self _exec:@"ROLLBACK;"];
	return ok;
}

- (NSInteger)beginSessionWithStartSOC:(NSInteger)soc {
	__block NSInteger newId = -1;
	dispatch_sync(_queue, ^{
		if (![self _openOnQueue]) return;
		const char *sql = "INSERT INTO sessions(start_ts,start_soc) VALUES(?,?)";
		sqlite3_stmt *stmt = NULL;
		if ([self _prepare:sql statement:&stmt]) {
			double now = CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970;
			sqlite3_bind_double(stmt, 1, now);
			sqlite3_bind_int(stmt, 2, (int)soc);
			if ([self _stepDone:stmt]) {
				newId = (NSInteger)sqlite3_last_insert_rowid(_db);
			}
		}
		sqlite3_finalize(stmt);
		[self _pruneOnQueue:128];
	});
	return newId;
}

- (void)endSessionId:(NSInteger)sessionId endSOC:(NSInteger)soc {
	if (sessionId < 0) return;
	dispatch_async(_queue, ^{
		if (![self _openOnQueue]) return;
		const char *sql = "UPDATE sessions SET end_ts=?, end_soc=? WHERE id=?";
		sqlite3_stmt *stmt = NULL;
		if ([self _prepare:sql statement:&stmt]) {
			double now = CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970;
			sqlite3_bind_double(stmt, 1, now);
			sqlite3_bind_int(stmt, 2, (int)soc);
			sqlite3_bind_int(stmt, 3, (int)sessionId);
			[self _stepDone:stmt];
		}
		sqlite3_finalize(stmt);
		[self _pruneOnQueue:128];
	});
}

- (void)updateSession:(NSInteger)sessionId chargerClass:(NSString *)chargerClass isWireless:(BOOL)isWireless {
	if (sessionId < 0) return;
	dispatch_async(_queue, ^{
		if (![self _openOnQueue]) return;
		const char *sql = "UPDATE sessions SET charger_class=?, is_wireless=? WHERE id=?";
		sqlite3_stmt *stmt = NULL;
		if ([self _prepare:sql statement:&stmt]) {
			sqlite3_bind_text(stmt, 1, chargerClass.UTF8String, -1, SQLITE_TRANSIENT);
			sqlite3_bind_int(stmt, 2, isWireless ? 1 : 0);
			sqlite3_bind_int(stmt, 3, (int)sessionId);
			[self _stepDone:stmt];
		}
		sqlite3_finalize(stmt);
	});
}

- (void)markPlateauStartForSession:(NSInteger)sessionId timestamp:(NSTimeInterval)ts {
	if (sessionId < 0) return;
	dispatch_async(_queue, ^{
		if (![self _openOnQueue]) return;
		const char *sql = "UPDATE sessions SET plateau_detected=1, plateau_start_ts=? WHERE id=? AND plateau_detected=0";
		sqlite3_stmt *stmt = NULL;
		if ([self _prepare:sql statement:&stmt]) {
			sqlite3_bind_double(stmt, 1, ts);
			sqlite3_bind_int(stmt, 2, (int)sessionId);
			[self _stepDone:stmt];
		}
		sqlite3_finalize(stmt);
	});
}

- (void)markPlateauEndForSession:(NSInteger)sessionId timestamp:(NSTimeInterval)ts {
	if (sessionId < 0) return;
	dispatch_async(_queue, ^{
		if (![self _openOnQueue]) return;
		const char *sql = "UPDATE sessions SET plateau_end_ts=? WHERE id=? AND plateau_end_ts IS NULL";
		sqlite3_stmt *stmt = NULL;
		if ([self _prepare:sql statement:&stmt]) {
			sqlite3_bind_double(stmt, 1, ts);
			sqlite3_bind_int(stmt, 2, (int)sessionId);
			[self _stepDone:stmt];
		}
		sqlite3_finalize(stmt);
	});
}

- (void)insertTickForSession:(NSInteger)sessionId
						 soc:(NSInteger)soc
						  ts:(NSTimeInterval)ts
				batteryTempC:(double)temp
	  instantaneousCurrentmA:(NSInteger)current
					screenOn:(BOOL)screenOn
					 cpuLoad:(double)cpuLoad
				thermalLevel:(NSInteger)thermalLevel {
	if (sessionId < 0) return;
	dispatch_async(_queue, ^{
		if (![self _openOnQueue]) return;
		const char *sql = "INSERT INTO ticks(session_id,soc,ts,battery_temp_c,instantaneous_current_mA,screen_on,cpu_load,thermal_level) VALUES(?,?,?,?,?,?,?,?)";
		sqlite3_stmt *stmt = NULL;
		if ([self _prepare:sql statement:&stmt]) {
			sqlite3_bind_int(stmt, 1, (int)sessionId);
			sqlite3_bind_int(stmt, 2, (int)soc);
			sqlite3_bind_double(stmt, 3, ts);
			if (isnan(temp)) sqlite3_bind_null(stmt, 4);
			else
				sqlite3_bind_double(stmt, 4, temp);
			sqlite3_bind_int(stmt, 5, (int)current);
			sqlite3_bind_int(stmt, 6, screenOn ? 1 : 0);
			if (isnan(cpuLoad)) sqlite3_bind_null(stmt, 7);
			else
				sqlite3_bind_double(stmt, 7, cpuLoad);
			sqlite3_bind_int(stmt, 8, (int)thermalLevel);
			[self _stepDone:stmt];
		}
		sqlite3_finalize(stmt);
		if (++_writesSincePrune >= 128) [self _pruneOnQueue:128];
	});
}

- (void)updatePercentStatsForChargerClass:(NSString *)chargerClass withDurationsSec:(NSDictionary<NSNumber *, NSArray<NSNumber *> *> *)durationsByPercent {
	NSMutableDictionary *batch = [NSMutableDictionary dictionaryWithCapacity:durationsByPercent.count];
	for (NSNumber *percent in durationsByPercent) batch[percent] = [durationsByPercent[percent] copy];
	chargerClass = [chargerClass copy];
	dispatch_async(_queue, ^{
		if (![self _openOnQueue]) return;
		const char *upsert = "INSERT INTO percent_stats(charger_class,percent,median_seconds,iqr_seconds,mean_seconds,m2_seconds,sample_count,last_updated_ts) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(charger_class,percent) DO UPDATE SET median_seconds=excluded.median_seconds, iqr_seconds=excluded.iqr_seconds, mean_seconds=((percent_stats.mean_seconds*percent_stats.sample_count)+(excluded.mean_seconds*excluded.sample_count))/NULLIF(percent_stats.sample_count+excluded.sample_count,0), m2_seconds=(percent_stats.m2_seconds + excluded.m2_seconds + ((excluded.mean_seconds-percent_stats.mean_seconds)*(excluded.mean_seconds-percent_stats.mean_seconds))*percent_stats.sample_count*excluded.sample_count/NULLIF(percent_stats.sample_count+excluded.sample_count,0)), sample_count=percent_stats.sample_count + excluded.sample_count, last_updated_ts=excluded.last_updated_ts;";
		sqlite3_stmt *stmt = NULL;
		if (![self _prepare:upsert statement:&stmt]) return;
		double now = CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970;
		[batch enumerateKeysAndObjectsUsingBlock:^(NSNumber *_Nonnull key, NSArray<NSNumber *> *_Nonnull samples, BOOL *_Nonnull stop) {
			if (key.integerValue < 0 || key.integerValue > 99 || samples.count == 0) return;
			NSMutableArray<NSNumber *> *clean = [NSMutableArray arrayWithCapacity:samples.count];
			for (NSNumber *n in samples) {
				double v = n.doubleValue;
				if (!isfinite(v)) continue;
				if (v <= 0.5 || v > 3600.0) continue;
				[clean addObject:@(v)];
			}
			if (clean.count == 0) return;

			NSArray<NSNumber *> *sorted = [clean sortedArrayUsingSelector:@selector(compare:)];
			NSUInteger c = sorted.count;
			if (c == 0) return;
			double median = (c % 2 ? sorted[c / 2].doubleValue : 0.5 * (sorted[c / 2 - 1].doubleValue + sorted[c / 2].doubleValue));
			double q1 = sorted[(NSUInteger)floor(0.25 * (c - 1))].doubleValue;
			double q3 = sorted[(NSUInteger)floor(0.75 * (c - 1))].doubleValue;
			double iqr = q3 - q1;
			double lowFence = q1 - 1.5 * iqr;
			double highFence = q3 + 1.5 * iqr;
			if (!isfinite(lowFence)) lowFence = 0.5;
			if (!isfinite(highFence)) highFence = 3600.0;

			double mean = 0;
			double m2 = 0;
			int n = 0;
			for (NSNumber *nObj in sorted) {
				double x = nObj.doubleValue;
				x = MIN(MAX(x, lowFence), highFence);
				n += 1;
				double delta = x - mean;
				mean += delta / n;
				double delta2 = x - mean;
				m2 += delta * delta2;
			}
			if (n <= 0) return;

			sqlite3_reset(stmt);
			sqlite3_clear_bindings(stmt);
			sqlite3_bind_text(stmt, 1, chargerClass.UTF8String, -1, SQLITE_TRANSIENT);
			sqlite3_bind_int(stmt, 2, key.intValue);
			sqlite3_bind_double(stmt, 3, median);
			sqlite3_bind_double(stmt, 4, iqr);
			sqlite3_bind_double(stmt, 5, mean);
			sqlite3_bind_double(stmt, 6, m2);
			sqlite3_bind_int(stmt, 7, n);
			sqlite3_bind_double(stmt, 8, now);
			[self _stepDone:stmt];
		}];
		sqlite3_finalize(stmt);
		if (++_writesSincePrune >= 128) [self _pruneOnQueue:128];
	});
}

- (BOOL)fetchPercentStatsForChargerClass:(NSString *)chargerClass intoEstimate:(double *)estimate uncertainty:(double *)uncertainty sampleCounts:(int *)sampleCounts lastUpdated:(double *)lastUpdated {
	for (int i = 0; i < 100; i++) {
		estimate[i] = NAN;
		uncertainty[i] = NAN;
		sampleCounts[i] = 0;
		lastUpdated[i] = 0;
	}
	__block BOOL foundAny = NO;
	dispatch_sync(_queue, ^{
		if (![self _openOnQueue]) return;

		const char *q = "SELECT percent, mean_seconds, m2_seconds, sample_count, median_seconds, iqr_seconds, last_updated_ts FROM percent_stats WHERE charger_class=?";
		sqlite3_stmt *stmt = NULL;
		if (![self _prepare:q statement:&stmt]) return;
		sqlite3_bind_text(stmt, 1, chargerClass.UTF8String, -1, SQLITE_TRANSIENT);
		while (sqlite3_step(stmt) == SQLITE_ROW) {
			int p = sqlite3_column_int(stmt, 0);
			if (p < 0 || p > 99) continue;
			foundAny = YES;
			double mean = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? NAN : sqlite3_column_double(stmt, 1);
			double m2 = sqlite3_column_double(stmt, 2);
			int n = sqlite3_column_int(stmt, 3);
			double median = sqlite3_column_double(stmt, 4);
			double iqr = sqlite3_column_double(stmt, 5);
			double updated = sqlite3_column_double(stmt, 6);

			double est = isfinite(mean) && n > 0 ? mean : median;
			double var = (n > 1 && isfinite(m2)) ? (m2 / (double)(n - 1)) : NAN;
			double sd = isfinite(var) && var > 0 ? sqrt(var) : NAN;
			double u = isfinite(sd) ? sd : iqr;

			estimate[p] = est;
			uncertainty[p] = u;
			sampleCounts[p] = n;
			lastUpdated[p] = updated;
		}
		sqlite3_finalize(stmt);
	});
	return foundAny;
}

- (void)insertUnlockEventAt:(NSTimeInterval)ts wasCharging:(BOOL)charging soc:(NSInteger)soc {
	dispatch_async(_queue, ^{
		if (![self _openOnQueue]) return;
		const char *sql = "INSERT INTO unlock_events(ts,was_charging,soc) VALUES(?,?,?)";
		sqlite3_stmt *stmt = NULL;
		if ([self _prepare:sql statement:&stmt]) {
			sqlite3_bind_double(stmt, 1, ts);
			sqlite3_bind_int(stmt, 2, charging ? 1 : 0);
			sqlite3_bind_int(stmt, 3, (int)soc);
			[self _stepDone:stmt];
		}
		sqlite3_finalize(stmt);
		if (++_writesSincePrune >= 128) [self _pruneOnQueue:128];
	});
}

- (BOOL)_pruneOnQueue:(NSUInteger)recentCount {
	recentCount = MIN(recentCount, (NSUInteger)128);
	if (![self _exec:@"BEGIN IMMEDIATE;"]) return NO;
	NSString *sql = [NSString stringWithFormat:
			@"DELETE FROM sessions WHERE end_ts IS NOT NULL AND id NOT IN (SELECT id FROM sessions WHERE end_ts IS NOT NULL ORDER BY start_ts DESC,id DESC LIMIT %lu);"
			 "DELETE FROM ticks WHERE session_id NOT IN (SELECT id FROM sessions);"
			 "DELETE FROM ticks WHERE id NOT IN (SELECT id FROM ticks ORDER BY ts DESC,id DESC LIMIT 32768);"
			 "DELETE FROM unlock_events WHERE id NOT IN (SELECT id FROM unlock_events ORDER BY ts DESC,id DESC LIMIT 2048);"
			 "DELETE FROM percent_stats WHERE charger_class NOT IN (SELECT charger_class FROM percent_stats GROUP BY charger_class ORDER BY MAX(last_updated_ts) DESC,charger_class LIMIT 64);",
		(unsigned long)recentCount];
	BOOL ok = [self _exec:sql] && [self _exec:@"COMMIT;"];
	if (!ok) [self _exec:@"ROLLBACK;"];
	else
		_writesSincePrune = 0;
	return ok;
}

- (void)pruneOldTickDataKeepingRecentSessions:(NSUInteger)recentCount {
	dispatch_async(_queue, ^{
		if (![self _openOnQueue]) return;
		[self _pruneOnQueue:recentCount];
	});
}

@end
