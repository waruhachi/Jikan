# Additional Stack targets

The main Estimated Time item follows the target in Jikan's main settings and stays first. Additional estimates have their own percentage and can be edited, reordered, or removed in Stack. Apple mode supports 80/85/90/95/100%; Jikan mode supports 1–100%. Existing saved values are preserved across algorithm changes, with unsupported Apple percentages shown as unavailable. Duplicate effective percentages are omitted from the pill without deleting the saved entry.

Manual taps follow Stack order. Automatic advancement follows percentage order, only when the displayed estimate newly reaches its target. Other readings remain selected. Completed milestones stay completed for the charging session, and a manual visit to one does not immediately advance again. Once all targets are completed, Show after full charge controls visibility. There is no scheduling or charging-limit control.

## Implementation

- `Shared/JikanStackItem` supplies immutable items, stable identifiers, and property-list serialization. `JikanStackSettings` reads legacy string arrays and normalizes new records. Settings are written in the new format when the Stack is edited.
- `TT100` computes configured targets from one refresh. Apple's per-target prediction caches share session/model state and one helper sample per refresh. Jikan's history estimator loads history once and computes cumulative durations.
- `JikanBatterySnapshot` exposes immutable per-target results. The presentation store latches completed milestones and rejects results from obsolete settings generations. Existing consumers still receive one snapshot per refresh. Main-target fields remain available to the date row and notification.
- `JikanStackSelection` owns manual selection and advancement. Both pill styles use the selected estimate's target for text and progress.

## Host checks

Run `scripts/test-stack-targets.sh`. To check array access and undefined behavior too, run `JIKAN_TEST_SANITIZERS=1 scripts/test-stack-targets.sh`.

The tests use production settings, selection, presentation-store, and estimator control flow with deterministic battery/model/history doubles. They check migration, validation, stable identity, duplicate handling, progression, manual selection, completed milestones, invalidation, unavailable targets, independent prediction caches, shared helper reads, and batched history. They do not prove model accuracy, private-framework UI behavior, or real charging transitions.

## Device acceptance checks

Run on original Dopamine and RootHide Dopamine after installing the matching release package and respringing:

1. Open an existing Stack and verify its order and temperature setting are preserved. Add 90% and 100% estimates to a lower main target. Edit, reorder, and remove entries, including numeric entry and slider/VoiceOver adjustments. Confirm duplicate targets cannot be saved and unsupported percentages survive algorithm changes.
2. While charging, tap through estimates and other readings in both Classic and Progress Ring. Verify each estimate's caption and progress use its own target. Check preview while unplugged and with unavailable battery inputs.
3. Let the displayed lower target be reached: verify advancement to the next higher unfinished target, including a reading that skips multiple percentages. Check that Wattage, Temperature, or Voltage stays selected during the same transition.
4. Manually revisit a completed target; wait for another battery refresh and confirm it stays selected. Verify minor fluctuations do not repeat advancement. Disconnect/reconnect and confirm session milestones reset.
5. Verify the pill stays available after the main target while a higher target is pending. After all targets are reached, check both values of Show after full charge.
6. Check that the date-row estimate, main-target notification and its preview, still follow the main target, and charging history still records a single session/sample stream.

Host test and package validation results must be reported separately from these device checks.
