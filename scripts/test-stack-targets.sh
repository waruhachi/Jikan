#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output=$(mktemp -d "${TMPDIR:-/tmp}/jikan-stack-tests.XXXXXX")
trap 'rm -rf "$output"' EXIT HUP INT TERM
set --
if [ "${JIKAN_TEST_SANITIZERS:-0}" = 1 ]; then set -- -fsanitize=address,undefined; fi
xcrun clang "$@" -fobjc-arc -fblocks -Wall -Werror -Wno-unused-parameter -Wno-incomplete-implementation -Wno-deprecated-declarations \
  -I tests/Support -framework Foundation -framework CoreML \
  tests/JikanStackTargetsTests.m Shared/JikanStackItem.m Shared/JikanStackSettings.m Shared/JikanStackSelection.m \
  Shared/JikanAppleEstimateAvailability.m Shared/JikanEstimateSettings.m Shared/JikanAppearanceSettings.m Shared/JikanPositionSettings.m Shared/JikanDisplaySettings.m Shared/JikanPreferences.m \
  Tweak/JikanPresentationStore/JikanPresentationSettings.m Tweak/JikanPresentationStore/JikanBatterySnapshot.m \
  Tweak/JikanPresentationStore/JikanTargetEstimate.m Tweak/JikanPresentationStore/JikanPresentationState.m \
  Tweak/JikanPresentationStore/JikanPresentationStore.m Tweak/TT100/TT100AppleEstimator.m Tweak/TT100/TT100HistoryEstimator.m \
  -o "$output/StackTargetsTests"
"$output/StackTargetsTests"
