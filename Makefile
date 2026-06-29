ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME ?= rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OrbitWindowSB OrbitWindowAppHook

OrbitWindowSB_FILES = SpringBoard/Tweak.xm SpringBoard/OWManager.mm SpringBoard/OWPassThroughWindow.m SpringBoard/OWWheelView.m SpringBoard/OWPrefs.m
OrbitWindowSB_FRAMEWORKS = UIKit CoreGraphics QuartzCore Foundation
OrbitWindowSB_PRIVATE_FRAMEWORKS = SpringBoardServices FrontBoardServices
OrbitWindowSB_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-arc-performSelector-leaks

OrbitWindowAppHook_FILES = AppHook/Tweak.xm
OrbitWindowAppHook_FRAMEWORKS = UIKit Foundation
OrbitWindowAppHook_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-arc-performSelector-leaks

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
