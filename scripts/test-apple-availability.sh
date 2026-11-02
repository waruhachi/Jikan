#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
output=$(mktemp -d "${TMPDIR:-/tmp}/jikan-availability-tests.XXXXXX")
trap 'rm -rf "$output"' EXIT HUP INT TERM
set --
if [ "${JIKAN_TEST_SANITIZERS:-0}" = 1 ]; then set -- -fsanitize=address,undefined; fi
xcrun clang "$@" -fobjc-arc -fblocks -Wall -Werror -Wno-unused-parameter -framework Foundation \
 tests/JikanAppleAvailabilityTests.m Shared/JikanAppleEstimateAvailability.m Shared/JikanEstimateSettings.m Shared/JikanAppleFeatures.m -o "$output/AvailabilityTests"
"$output/AvailabilityTests"
