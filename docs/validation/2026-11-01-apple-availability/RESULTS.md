# Apple availability device validation — November 1, 2026

**Historical test build:** this run included an added approximation toggle that was subsequently removed at the user's request. These captures preserve that test run and the helper-path finding; they do not represent the final Algorithm UI.

The updated Jikan 1.0.3 release packages were installed on the four SSH test devices. All four passed the native Algorithm UI checks and the Settings/SpringBoard shared-state checks. This is device-runtime evidence, separate from the 39 availability and 96 Stack/estimator host checks, which also passed with AddressSanitizer and UndefinedBehaviorSanitizer.

## Device results

| Device | Package | Native Algorithm UI | Shared state and live updates | Prediction evidence |
| --- | --- | --- | --- | --- |
| iPad7,5, iOS 14.8 | Rootful | Passed | Passed; full charge remained unknown instead of being classified as unsupported | Stayed at 100% with `IsCharging = false` during an approximately eight-minute observation; active-charging prediction and sustained-failure fallback remain unverified |
| iPhone 13, iOS 16.3.1 | RootHide | Passed | Passed; native support remembered | Positive Apple prediction captured using native input power |
| iPhone 8, iOS 16.7.16 | Rootless | Passed | Passed; measured helper support remembered | Positive Apple prediction captured using SMC helper power after enabling through the native Enable switch |
| iPhone 11, iOS 26.0 | Rootless | Passed in the existing TweakSettings host | Passed; confirmed support remained recommended during later charging pauses | Measured support was confirmed during the run; the dedicated prediction capture encountered `paused`, so no positive prediction is claimed for that capture |

The iOS 26 main Settings app did not expose the Jikan entry through the attempted deep link. The existing TweakSettings app loaded the actual Jikan Preferences controllers and native controls; this run does not establish main-Settings entry integration on iOS 26.

## UI and cross-process checks

On each device, the tests used native UIKit cell selection and switch value-change events, not calls directly to Jikan's approximation setter:

- Disable approximation and verify persistence.
- Enable it and verify the confirmation appears.
- Cancel and verify consent remains disabled.
- Confirm Proceed and verify consent is enabled.
- Select Jikan, then Apple; verify the saved algorithm and selected checkmark.
- Verify selecting Apple does not grant approximation consent.

Settings' actual `readPreferenceValue:` result matched SpringBoard's published algorithm. While each Algorithm controller remained mounted, the test temporarily changed Jikan's Apple target from 100% to an already-completed 80%, then back to 100%. SpringBoard published each assessment and the displayed footer converged without leaving the page. Existing confirmed support was retained; the iPad's classification correctly stayed unknown. Notifications were disabled during this target-change check to avoid publishing a test target-reached bulletin. No battery sensors or live power inputs were overridden.

The captures in this directory show only the native Algorithm view. They exclude unrelated Settings sidebar contents. Test control events are not proof of physical finger input or of a complete charging cycle.

## Helper launch-path failure found and fixed

The first real check on iOS 16.7.16 found launchd attempting `/usr/libexec/JikanPowerd`, although the rootless helper was installed under the jailbreak bootstrap. The job reported `EX_CONFIG` (78), and Jikan's availability remained unknown with `input_power_timeout`. That was a helper transport failure, not evidence of missing Apple-model support.

[PowerHelper/main.m](../../../PowerHelper/main.m) now writes `rootfs(jbroot(@"/usr/libexec/JikanPowerd"))` to `ProgramArguments`. All three schemes were rebuilt and the corrected packages installed on all four devices. Actual read-only XPC requests received helper replies on every device, including requests as UID 501. The iPhone 13 and iPhone 8 returned SMC readings; the full/paused devices returned honest unavailable statuses where appropriate. The iPhone 8's real estimator then confirmed measured support and produced an Apple prediction using `smc`.

The helper probe used the existing `JikanInputPowerProtocol` and privileged Mach-service connection. It requested only `readInputPowerWithReply:` and reported status/source/power/time; it exposed no sensor write operation. These checks verify connection and existing validator behavior, not independent external-meter calibration or future charging-time accuracy.

## Restoration and cleanup

All four original Jikan preference domains were compared with the in-process backups and restored exactly, with no differing keys. The iPhone 8's originally disabled state was restored. Existing capability observations were retained; charging history was not reset. Each SpringBoard process remained healthy and kept the same generation during testing, apart from the deliberate installation reloads.

The temporary iOS 14 inspection package was removed after testing, with Settings closed and SpringBoard deliberately reloaded to unload it. Existing inspection installations on the other devices were retained. Temporary helper executables and transferred installers were removed after verification.

No commits were made. [results.json](results.json) contains sanitized assertions, state samples, and final package hashes. Original preference contents and unrelated app data are not included.

## Captures

- [iOS 14.8](14.8-algorithm.png)
- [iOS 16.3.1](16.3.1-algorithm.png)
- [iOS 16.7.16](16.7.16-algorithm.png)
- [iOS 26.0](26.0-algorithm.png)
