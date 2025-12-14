#import "TT100Database.h"

static NSString *const kTT100DBDirectory = @"Library/TT100";
static NSString *const kTT100DBFilename = @"tt100.db";

@interface TT100Database () {
	sqlite3 *_db;
	dispatch_queue_t _queue;
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

#pragma mark - Open

- (NSString *)_dbPath {
	NSString *home = NSHomeDirectory();
	NSString *dir = [home stringByAppendingPathComponent:kTT100DBDirectory];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return [dir stringByAppendingPathComponent:kTT100DBFilename];
}

- (BOOL)openIfNeeded {
	__block BOOL ok = YES;
	dispatch_sync(_queue, ^{
		if (_db) {
			ok = YES;
			return;
		}
		NSString *path = [self _dbPath];
		if (sqlite3_open_v2(path.UTF8String, &_db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
			NSLog(@"[Jikan] (TT100Database) TT100 DB open failed %s", sqlite3_errmsg(_db));
			ok = NO;
			return;
		}
		[self _exec:@"PRAGMA journal_mode=WAL;"];
		[self _exec:@"PRAGMA synchronous=NORMAL;"];
		ok = [self _migrateIfNeeded];
	});
	return ok;
}

- (void)close {
	if (_db) {
		sqlite3_close(_db);
		_db = NULL;
	}
}

- (BOOL)_exec:(NSString *)sql {
	char *err = NULL;
	if (sqlite3_exec(_db, sql.UTF8String, NULL, NULL, &err) != SQLITE_OK) {
		NSLog(@"[Jikan] (TT100Database) SQL exec error: %s", err);
		sqlite3_free(err);
		return NO;
	}
	return YES;
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
	NSInteger v = [self _schemaVersion];
	if (v == 0) {
		NSString *schema =
			@"CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);"
			 "INSERT OR IGNORE INTO meta(key,value) VALUES ('schema_version','1');"
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
			 "sample_count INTEGER DEFAULT 0,"
			 "last_updated_ts REAL,"
			 "PRIMARY KEY (charger_class, percent));";
		return [self _exec:schema];
	}
	return YES;
}

#pragma mark - Sessions

- (NSInteger)beginSessionWithStartSOC:(NSInteger)soc {
	if (![self openIfNeeded]) return -1;
	__block NSInteger newId = -1;
	dispatch_sync(_queue, ^{
		const char *sql = "INSERT INTO sessions(start_ts,start_soc) VALUES(?,?)";
		sqlite3_stmt *stmt;
		if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
			double now = CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970;
			sqlite3_bind_double(stmt, 1, now);
			sqlite3_bind_int(stmt, 2, (int)soc);
			if (sqlite3_step(stmt) == SQLITE_DONE) {
				newId = (NSInteger)sqlite3_last_insert_rowid(_db);
			}
		}
		sqlite3_finalize(stmt);
	});
	return newId;
}

- (void)endSessionId:(NSInteger)sessionId endSOC:(NSInteger)soc {
	if (sessionId < 0) return;
	if (![self openIfNeeded]) return;
	dispatch_async(_queue, ^{
		const char *sql = "UPDATE sessions SET end_ts=?, end_soc=? WHERE id=?";
		sqlite3_stmt *stmt;
		if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
			double now = CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970;
			sqlite3_bind_double(stmt, 1, now);
			sqlite3_bind_int(stmt, 2, (int)soc);
			sqlite3_bind_int(stmt, 3, (int)sessionId);
			sqlite3_step(stmt);
		}
		sqlite3_finalize(stmt);
	});
}

- (void)updateSession:(NSInteger)sessionId chargerClass:(NSString *)chargerClass isWireless:(BOOL)isWireless {
	if (sessionId < 0) return;
	if (![self openIfNeeded]) return;
	dispatch_async(_queue, ^{
		const char *sql = "UPDATE sessions SET charger_class=?, is_wireless=? WHERE id=?";
		sqlite3_stmt *stmt;
		if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
			sqlite3_bind_text(stmt, 1, chargerClass.UTF8String, -1, SQLITE_TRANSIENT);
			sqlite3_bind_int(stmt, 2, isWireless ? 1 : 0);
			sqlite3_bind_int(stmt, 3, (int)sessionId);
			sqlite3_step(stmt);
		}
		sqlite3_finalize(stmt);
	});
}

- (void)markPlateauStartForSession:(NSInteger)sessionId timestamp:(NSTimeInterval)ts {
	if (sessionId < 0) return;
	if (![self openIfNeeded]) return;
	dispatch_async(_queue, ^{
		const char *sql = "UPDATE sessions SET plateau_detected=1, plateau_start_ts=? WHERE id=? AND plateau_detected=0";
		sqlite3_stmt *stmt;
		if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
			sqlite3_bind_double(stmt, 1, ts);
			sqlite3_bind_int(stmt, 2, (int)sessionId);
			sqlite3_step(stmt);
		}
		sqlite3_finalize(stmt);
	});
}

- (void)markPlateauEndForSession:(NSInteger)sessionId timestamp:(NSTimeInterval)ts {
	if (sessionId < 0) return;
	if (![self openIfNeeded]) return;
	dispatch_async(_queue, ^{
		const char *sql = "UPDATE sessions SET plateau_end_ts=? WHERE id=? AND plateau_end_ts IS NULL";
		sqlite3_stmt *stmt;
		if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
			sqlite3_bind_double(stmt, 1, ts);
			sqlite3_bind_int(stmt, 2, (int)sessionId);
			sqlite3_step(stmt);
		}
		sqlite3_finalize(stmt);
	});
}

#pragma mark - Ticks

- (void)insertTickForSession:(NSInteger)sessionId
						 soc:(NSInteger)soc
						  ts:(NSTimeInterval)ts
				batteryTempC:(double)temp
	  instantaneousCurrentmA:(NSInteger)current
					screenOn:(BOOL)screenOn
					 cpuLoad:(double)cpuLoad
				thermalLevel:(NSInteger)thermalLevel {
	if (sessionId < 0) return;
	if (![self openIfNeeded]) return;
	dispatch_async(_queue, ^{
		const char *sql = "INSERT INTO ticks(session_id,soc,ts,battery_temp_c,instantaneous_current_mA,screen_on,cpu_load,thermal_level) VALUES(?,?,?,?,?,?,?,?)";
		sqlite3_stmt *stmt;
		if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
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
			sqlite3_step(stmt);
		}
		sqlite3_finalize(stmt);
	});
}

#pragma mark - Percent Stats

- (void)updatePercentStatsForChargerClass:(NSString *)chargerClass withDurationsSec:(NSDictionary<NSNumber *, NSArray<NSNumber *> *> *)durationsByPercent {
	if (![self openIfNeeded]) return;
	dispatch_async(_queue, ^{
		const char *upsert = "INSERT INTO percent_stats(charger_class,percent,median_seconds,iqr_seconds,sample_count,last_updated_ts) VALUES(?,?,?,?,?,?) ON CONFLICT(charger_class,percent) DO UPDATE SET median_seconds=excluded.median_seconds, iqr_seconds=excluded.iqr_seconds, sample_count=percent_stats.sample_count + excluded.sample_count, last_updated_ts=excluded.last_updated_ts;";
		sqlite3_stmt *stmt;
		if (sqlite3_prepare_v2(_db, upsert, -1, &stmt, NULL) != SQLITE_OK) return;
		double now = CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970;
		[durationsByPercent enumerateKeysAndObjectsUsingBlock:^(NSNumber *_Nonnull key, NSArray<NSNumber *> *_Nonnull samples, BOOL *_Nonnull stop) {
			if (samples.count == 0) return;
			NSArray<NSNumber *> *sorted = [samples sortedArrayUsingSelector:@selector(compare:)];
			NSUInteger c = sorted.count;
			double median = (c % 2 ? sorted[c / 2].doubleValue : 0.5 * (sorted[c / 2 - 1].doubleValue + sorted[c / 2].doubleValue));
			double q1 = sorted[(NSUInteger)floor(0.25 * (c - 1))].doubleValue;
			double q3 = sorted[(NSUInteger)floor(0.75 * (c - 1))].doubleValue;
			double iqr = q3 - q1;
			sqlite3_reset(stmt);
			sqlite3_clear_bindings(stmt);
			sqlite3_bind_text(stmt, 1, chargerClass.UTF8String, -1, SQLITE_TRANSIENT);
			sqlite3_bind_int(stmt, 2, key.intValue);
			sqlite3_bind_double(stmt, 3, median);
			sqlite3_bind_double(stmt, 4, iqr);
			sqlite3_bind_int(stmt, 5, (int)c);
			sqlite3_bind_double(stmt, 6, now);
			sqlite3_step(stmt);
		}];
		sqlite3_finalize(stmt);
	});
}

- (BOOL)fetchPercentStatsForChargerClass:(NSString *)chargerClass intoMedian:(double *)median iqr:(double *)iqr sampleCounts:(int *)sampleCounts {
	if (![self openIfNeeded]) return NO;
	for (int i = 0; i < 100; i++) {
		median[i] = NAN;
		iqr[i] = NAN;
		sampleCounts[i] = 0;
	}
	const char *q = "SELECT percent, median_seconds, iqr_seconds, sample_count FROM percent_stats WHERE charger_class=?";
	sqlite3_stmt *stmt;
	if (sqlite3_prepare_v2(_db, q, -1, &stmt, NULL) != SQLITE_OK) return NO;
	sqlite3_bind_text(stmt, 1, chargerClass.UTF8String, -1, SQLITE_TRANSIENT);
	BOOL foundAny = NO;
	while (sqlite3_step(stmt) == SQLITE_ROW) {
		int p = sqlite3_column_int(stmt, 0);
		if (p < 0 || p > 99) continue;
		foundAny = YES;
		median[p] = sqlite3_column_double(stmt, 1);
		iqr[p] = sqlite3_column_double(stmt, 2);
		sampleCounts[p] = sqlite3_column_int(stmt, 3);
	}
	sqlite3_finalize(stmt);
	return foundAny;
}

#pragma mark - Unlock events

- (void)insertUnlockEventAt:(NSTimeInterval)ts wasCharging:(BOOL)charging soc:(NSInteger)soc {
	if (![self openIfNeeded]) return;
	dispatch_async(_queue, ^{
		const char *sql = "INSERT INTO unlock_events(ts,was_charging,soc) VALUES(?,?,?)";
		sqlite3_stmt *stmt;
		if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
			sqlite3_bind_double(stmt, 1, ts);
			sqlite3_bind_int(stmt, 2, charging ? 1 : 0);
			sqlite3_bind_int(stmt, 3, (int)soc);
			sqlite3_step(stmt);
		}
		sqlite3_finalize(stmt);
	});
}

#pragma mark - Prune

- (void)pruneOldTickDataKeepingRecentSessions:(NSUInteger)recentCount {
	if (![self openIfNeeded]) return;
	dispatch_async(_queue, ^{
		const char *sql = "DELETE FROM ticks WHERE session_id NOT IN (SELECT id FROM sessions ORDER BY start_ts DESC LIMIT ?)";
		sqlite3_stmt *stmt;
		if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) == SQLITE_OK) {
			sqlite3_bind_int(stmt, 1, (int)recentCount);
			sqlite3_step(stmt);
		}
		sqlite3_finalize(stmt);
	});
}

@end
