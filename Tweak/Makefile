TWEAK_NAME = Jikan

$(TWEAK_NAME)_FILES = $(TWEAK_NAME).x $(wildcard JikanCoverSheetCoordinator/*.m) $(wildcard JikanInlineEstimateAdapter/*.m) $(wildcard JikanPresentationStore/*.m) $(wildcard JikanPlatterView/*.m) $(wildcard JikanQuickActionAdapter/*.m) $(wildcard JikanSessionRecorder/*.m) $(wildcard TT100/*.m) $(wildcard ../Localization/*.m) $(wildcard ../Shared/*.m) $(wildcard ../Shared/JikanPillContentView/*.m)
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation IOKit CoreML
$(TWEAK_NAME)_LIBRARIES += sqlite3
$(TWEAK_NAME)_CFLAGS = -fobjc-arc

# Explicitly opt in to the temporary external USB-meter test input.
ifeq ($(JIKAN_APPLE_INPUT_POWER_TEST),1)
$(TWEAK_NAME)_CFLAGS += -DJIKAN_APPLE_INPUT_POWER_TEST=1
endif

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
