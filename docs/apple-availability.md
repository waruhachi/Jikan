# Shared Apple input availability

SpringBoard owns the assessment in `moe.waru.jikan.estimate-status` under `availability`. Settings reads this record and observes `moe.waru.jikan.apple-availability.changed`; it does not query battery telemetry. The recommendation and automatic algorithm choice use the same target-specific record. Explicit algorithm selection takes precedence, independently of approximation consent.

Only an accepted, current-generation battery refresh publishes an assessment. The probe runs through the Apple estimator even when Jikan is active, using measured inputs only in that case. Apple predictions made with approximation enabled carry the measured-input assessment separately. Cached predictions preserve its sample timestamp, so reusing one prediction cannot establish repeated sensor failures.

A measured success remains known for that target and kernel/device environment. A target with no measured success needs three consistent, fresh input failures spanning at least 30 seconds of active charging before the automatic choice becomes Jikan. A pause, initialization, target completion, model error, helper transport error, or gap over 60 seconds breaks the failure run. Recovery continues to be checked after a fallback. Unknown status initially chooses Apple without asserting a recommendation.

`status`, `missingFeatures`, `powerSource`, and `timestamp` describe the most recent check. `supportedTargets` and `unavailableTargets` determine recommendations. These records contain field names and statuses, not raw battery telemetry. Reset Preferences revokes approximation consent and explicit algorithm selection but preserves observed capability. An OS/kernel change invalidates old capability records.

## Host checks

Run `JIKAN_TEST_SANITIZERS=1 scripts/test-apple-availability.sh` and `JIKAN_TEST_SANITIZERS=1 scripts/test-stack-targets.sh`.

The suites cover decision transitions, explicit selection, target-specific support, measured helper recovery, cached approximation assessments, failure continuity, generation rejection, and the captured iPhone 13 feature shape. They do not verify cross-process notification delivery or the native Preferences UI on a device.

## Device checks

On the iPhone 13 running iOS 16.3.1, and on original Dopamine:

1. With measured power available, open Algorithm and verify the selected value and recommendation agree with SpringBoard's shared record. Confirm availability updates while the page is open.
2. On a device with confirmed measured support, select Jikan and then Apple. Verify Apple is selected without a warning and approximation remains disabled. Verify there is no additional approximation toggle.
3. On a device with confirmed missing measured inputs, select Apple and verify the existing warning appears. Cancel must preserve the previous choice and consent; Proceed explicitly grants approximation consent. Unknown availability and temporary failures after measured success must not trigger this warning. Selecting Jikan or Reset Preferences revokes consent.
4. After measured Apple success, disconnect, reconnect, and pause charging. Verify these transitions do not replace the known Apple recommendation. Predictions may temporarily be unavailable.
5. On a device without measured inputs and without an explicit algorithm choice, verify initial unknown status, sustained charging checks before automatic fallback, and recovery if measured inputs become available. Do not disable live sensors to simulate missing inputs; use a naturally affected device or the host fixtures.
6. Verify added Stack targets, main-target notifications, date-row estimates, and the existing Show Preview behavior still work.

Package/host validation is separate from these device checks. This change does not establish which input caused the earlier iOS 16.3.1 rejection.
