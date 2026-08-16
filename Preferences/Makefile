ARCHS = arm64e
TARGET = iphone:clang:17.1:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AirPodsAutoNoisePrefs

AirPodsAutoNoisePrefs_FILES = APANRootListController.m
AirPodsAutoNoisePrefs_INSTALL_PATH = /Library/PreferenceBundles
AirPodsAutoNoisePrefs_FRAMEWORKS = UIKit Preferences
AirPodsAutoNoisePrefs_PRIVATE_FRAMEWORKS = Preferences
AirPodsAutoNoisePrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/AirPodsAutoNoisePrefs.plist$(ECHO_END)
