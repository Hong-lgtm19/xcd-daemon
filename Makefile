TARGET := iphone:clang::arm64
INSTALL_TARGET_PROCESSES = XCDDaemon

include $(THEOS)/makefiles/common.mk

TOOL_NAME = XCDDaemon
XCDDaemon_FILES = main.mm XCDTouchInjector.mm XCDVideoEncoder.mm XCDScreenCapture.mm
XCDDaemon_CFLAGS = -fobjc-arc -I. -miphoneos-version-min=13.0
XCDDaemon_FRAMEWORKS = UIKit Foundation CoreGraphics CoreVideo VideoToolbox CoreMedia IOKit

include $(THEOS_MAKE_PATH)/tool.mk
