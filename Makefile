TARGET := iphone:clang::arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = XCDTweak
XCDTweak_FILES = Tweak.xm XCDTouchInjector.mm XCDVideoEncoder.mm XCDScreenCapture.mm
XCDTweak_CFLAGS = -fobjc-arc -I. -miphoneos-version-min=13.0 -Wno-error -Wno-module-import-in-extern-c
XCDTweak_FRAMEWORKS = UIKit Foundation CoreGraphics CoreVideo VideoToolbox CoreMedia IOKit IOSurface QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
