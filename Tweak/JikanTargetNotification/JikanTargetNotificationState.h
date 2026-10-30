#pragma once
#include <stdbool.h>

typedef struct {
	int targetPercent;
	bool armed;
	bool notified;
} JikanTargetNotificationState;

static inline bool JikanTargetNotificationShouldSend(JikanTargetNotificationState *state, bool hasSnapshot, bool connected, bool enabled, int targetPercent, bool targetReached) {
	if (hasSnapshot && !connected) *state = (JikanTargetNotificationState){0};
	if (!hasSnapshot || !connected || !enabled) {
		state->armed = false;
		state->targetPercent = 0;
		return false;
	}
	if (state->targetPercent != targetPercent) {
		state->targetPercent = targetPercent;
		state->armed = false;
	}
	if (!targetReached) {
		state->armed = true;
		return false;
	}
	if (!state->armed || state->notified) return false;
	state->armed = false;
	state->notified = true;
	return true;
}
