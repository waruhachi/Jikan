export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:14.5

INSTALL_TARGET_PROCESSES = SpringBoard

SUBPROJECTS += Tweak Preferences

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk