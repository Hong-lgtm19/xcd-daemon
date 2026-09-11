# theos Makefile — 编译 XCDDaemon 为后台守护进程（.deb）
# GitHub Actions 的 macOS runner 会用它；本机 (Mac) 也可直接 `make package`

TARGET := iphone:clang:13.6:arm64
INSTALL_TARGET_PROCESSES = XCDDaemon

include $(THEOS)/makefiles/common.mk

TOOL_NAME = XCDDaemon
XCDDaemon_FILES = main.mm XCDTouchInjector.mm XCDVideoEncoder.mm XCDScreenCapture.mm
XCDDaemon_CFLAGS = -fobjc-arc -I.
XCDDaemon_FRAMEWORKS = UIKit Foundation CoreGraphics CoreVideo VideoToolbox CoreMedia IOKit

include $(THEOS_MAKE_PATH)/tool.mk
