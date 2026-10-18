export TARGET = iphone:latest:14.0
export ARCHS = arm64

ifeq ($(ROOTLESS),1)
	# Procursus-style rootless layout (the classic /var/jb prefix).
	export DEB_ARCH = iphoneos-arm64
	export INSTALL_PREFIX = /var/jb
else ifeq ($(ROOTHIDE),1)
	# RootHide bootstrap: same /var/jb-compatible layout, roothide arch tag.
	export DEB_ARCH = iphoneos-arm64e
	export INSTALL_PREFIX = /var/jb
else
	export DEB_ARCH = iphoneos-arm
endif

INSTALL_TARGET_PROCESSES = NewTerm

include $(THEOS)/makefiles/common.mk

XCODEPROJ_NAME = NewTerm

NewTerm_XCODE_SCHEME = NewTerm (iOS)
NewTerm_XCODEFLAGS = INSTALL_PREFIX=$(INSTALL_PREFIX)
NewTerm_CODESIGN_FLAGS = -SApp/entitlements.plist
NewTerm_INSTALL_PATH = $(INSTALL_PREFIX)/Applications

include $(THEOS_MAKE_PATH)/xcodeproj.mk

before-package::
	perl -i -pe s/iphoneos-arm/$(DEB_ARCH)/ $(THEOS_STAGING_DIR)/DEBIAN/control

after-stage::
	@$(TARGET_CODESIGN) $(NewTerm_CODESIGN_FLAGS) $(THEOS_STAGING_DIR)$(INSTALL_PREFIX)/Applications/NewTerm.app/NewTermLoginHelper
	$(ECHO_NOTHING)node "$(THEOS_PROJECT_DIR)/Tools/fetch-ai-runtime.mjs" "$(THEOS_STAGING_DIR)$(INSTALL_PREFIX)"$(ECHO_END)
	$(ECHO_NOTHING)$(TARGET_CODESIGN) -S"$(THEOS_STAGING_DIR)$(INSTALL_PREFIX)/usr/local/lib/nodejs/entitlements.xml" "$(THEOS_STAGING_DIR)$(INSTALL_PREFIX)/usr/local/lib/nodejs/node"$(ECHO_END)
