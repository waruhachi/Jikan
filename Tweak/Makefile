TWEAK_NAME = Jikan

$(TWEAK_NAME)_FILES = $(TWEAK_NAME).x $(wildcard JikanPlatterView/*.m) $(wildcard TT100/*.m) $(wildcard ../Localization/*.m)
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation IOKit
$(TWEAK_NAME)_LIBRARIES += sqlite3
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_RESOURCE_DIRS = Resources

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
