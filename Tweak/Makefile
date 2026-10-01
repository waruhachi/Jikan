TWEAK_NAME = Jikan

$(TWEAK_NAME)_FILES = $(TWEAK_NAME).x $(wildcard JikanPlatterView/*.m) $(wildcard JikanSessionRecorder/*.m) $(wildcard TT100/*.m) $(wildcard ../Localization/*.m) $(wildcard ../Shared/*.m)
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation IOKit CoreML
$(TWEAK_NAME)_LIBRARIES += sqlite3
$(TWEAK_NAME)_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
