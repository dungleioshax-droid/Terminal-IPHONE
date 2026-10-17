TARGET := iphone:clang:16.5:14.0
# arm64, not arm64e: the Linux toolchain (clang 11) can only emit the old arm64e
# ABI v1 (cpusubtype 0x2, no 0x80 capability bit), which is what gets killed on
# launch on iOS 17. A plain arm64 slice runs natively on every arm64e device and
# a standalone app has no reason to carry the private arm64e ABI.
ARCHS := arm64

# Every built .deb lands in ./dist (the requested output folder).
# `?=` in Theos' common.mk will not override this assignment.
THEOS_PACKAGE_DIR := dist

INSTALL_TARGET_PROCESSES = TerminalIPHONE

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TerminalIPHONE

TerminalIPHONE_FILES = \
	native/main.m \
	native/TITerminalAppDelegate.m \
	native/TITerminalViewController.m \
	native/TIPTYSession.m \
	native/TITerminalBuffer.m \
	native/TITerminalParser.m \
	native/TITerminalView.m \
	native/TILaunchLog.m \
	native/TIKeyboardInput.m

TerminalIPHONE_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
TerminalIPHONE_CFLAGS = -fobjc-arc -Wall
TerminalIPHONE_CODESIGN_FLAGS = -Snative/entitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

# Theos only rsyncs layout/ into the staging dir during `stage`, so stage the
# shared bootstrap script (single source of truth: scripts/bootstrap-iphone.sh)
# with explicit permissions here.
after-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/usr/share/terminal-iphone"$(ECHO_END)
	$(ECHO_NOTHING)install -m 755 scripts/bootstrap-iphone.sh "$(THEOS_STAGING_DIR)/usr/share/terminal-iphone/bootstrap-iphone.sh"$(ECHO_END)