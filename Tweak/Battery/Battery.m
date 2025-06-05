@interface BatteryChargerEstimator : NSObject

/// Estimates time (in seconds) until full charge, based on the provided batteryInfo dictionary.
/// Returns -1 if any required data is missing or if charging is infeasible.
+ (NSTimeInterval)estimatedSecondsToFullWithBatteryInfo:(NSDictionary *)batteryInfo;

@end

@implementation BatteryChargerEstimator

+ (NSTimeInterval)estimatedSecondsToFullWithBatteryInfo:(NSDictionary *)batteryInfo {
    if (![batteryInfo isKindOfClass:[NSDictionary class]]) {
        return -1;
    }

    //
    // 1) Determine “raw” capacities (in mAh). Prefer AppleRawCurrentCapacity / AppleRawMaxCapacity.
    //    If either is missing, fall back to percentage values + DesignCapacity.
    //
    double rawCurrent_mAh = -1;
    double rawMax_mAh     = -1;

    NSNumber *rawCurrNum = batteryInfo[@"AppleRawCurrentCapacity"];
    NSNumber *rawMaxNum  = batteryInfo[@"AppleRawMaxCapacity"];
    if (rawCurrNum && rawMaxNum) {
        rawCurrent_mAh = [rawCurrNum doubleValue];
        rawMax_mAh     = [rawMaxNum doubleValue];
    } else {
        // Fallback: use CurrentCapacity (%) and DesignCapacity (mAh)
        NSNumber *percentCurr = batteryInfo[@"CurrentCapacity"];
        NSNumber *percentMax  = batteryInfo[@"MaxCapacity"];
        NSNumber *designCap   = batteryInfo[@"DesignCapacity"];
        if (percentCurr && percentMax && designCap) {
            double pctCurr   = [percentCurr doubleValue] / [percentMax doubleValue]; // e.g. 0.83
            double design_mAh = [designCap doubleValue];
            rawMax_mAh     = design_mAh;
            rawCurrent_mAh = pctCurr * design_mAh;
        }
    }

    // Verify we have valid raw values:
    if (rawCurrent_mAh < 0 || rawMax_mAh <= 0 || rawCurrent_mAh >= rawMax_mAh) {
        return -1;
    }

    double remaining_mAh = rawMax_mAh - rawCurrent_mAh;

    //
    // 2) Determine the instantaneous charging current (in mA).
    //    Priority:
    //      (a) batteryInfo[@"ChargerData"][@"ChargingCurrent"]
    //      (b) batteryInfo[@"Amperage"]
    //      (c) batteryInfo[@"AdapterDetails"][@"Current"]
    //
    double chargingCurrent_mA = 0;
    NSDictionary *chargerData = batteryInfo[@"ChargerData"];
    if ([chargerData isKindOfClass:[NSDictionary class]]) {
        NSNumber *chCurr = chargerData[@"ChargingCurrent"];
        if (chCurr && [chCurr doubleValue] > 0) {
            chargingCurrent_mA = [chCurr doubleValue];
        }
    }

    if (chargingCurrent_mA <= 0) {
        NSNumber *ampNum = batteryInfo[@"Amperage"];
        if (ampNum && [ampNum doubleValue] > 0) {
            chargingCurrent_mA = [ampNum doubleValue];
        }
    }

    if (chargingCurrent_mA <= 0) {
        NSDictionary *adapterDetails = batteryInfo[@"AdapterDetails"];
        if ([adapterDetails isKindOfClass:[NSDictionary class]]) {
            NSNumber *adapterCurr = adapterDetails[@"Current"];
            if (adapterCurr && [adapterCurr doubleValue] > 0) {
                chargingCurrent_mA = [adapterCurr doubleValue];
            }
        }
    }

    if (chargingCurrent_mA <= 0) {
        return -1;
    }

    //
    // 3) Adjust for battery temperature.
    //    iOS reports “Temperature” as an integer. Commonly, that integer is in “0.1 °C” units.
    //    E.g. 3229 → 322.9 °C is impossible, so assume 3229 actually means 32.29 °C (i.e. divide by 100).
    //    We’ll compute tempC = [Temperature] / 100.0. 
    //    If tempC is outside [0 °C, 45 °C], we scale down current by 0.5 (i.e. 50% slower).
    //
    NSNumber *tempNum = batteryInfo[@"Temperature"];
    if (tempNum) {
        double tempC = [tempNum doubleValue] / 100.0;
        if (tempC < 0.0 || tempC > 45.0) {
            chargingCurrent_mA *= 0.5;
        }
    }

    //
    // 4) Adjust for wired vs wireless efficiency.
    //    Look at AdapterDetails[@"IsWireless"] (0 = wired, 1 = wireless).
    //    If wireless, assume ~85% efficiency (i.e. scale current by 0.85).
    //
    NSDictionary *adapterDetails = batteryInfo[@"AdapterDetails"];
    if ([adapterDetails isKindOfClass:[NSDictionary class]]) {
        NSNumber *isWireless = adapterDetails[@"IsWireless"];
        if (isWireless && [isWireless boolValue]) {
            chargingCurrent_mA *= 0.85;
        }
    }

    // If, after adjustments, chargingCurrent_mA is no longer positive, fail:
    if (chargingCurrent_mA <= 0) {
        return -1;
    }

    //
    // 5) Compute time to full (linear approximation, no tapering).
    //    time_hours = remaining_mAh ÷ chargingCurrent_mA
    //    time_seconds = time_hours × 3600
    //
    double hoursToFull   = remaining_mAh / chargingCurrent_mA;
    double secondsToFull = hoursToFull * 3600.0;

    if (!(secondsToFull > 0) || !isfinite(secondsToFull)) {
        return -1;
    }

    return secondsToFull;
}

@end