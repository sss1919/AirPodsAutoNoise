ARCHS = arm64e
TARGET = iphone:clang:17.1:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AirPodsAutoNoisePrefs

AirPodsAutoNoisePrefs_FILES = APANRootListController.m
AirPodsAutoNoisePrefs_INSTALL_PATH = /Library/PreferenceBundles
AirPodsAutoNoisePrefs_FRAMEWORKS = UIKit
AirPodsAutoNoisePrefs_CFLAGS = -fobjc-arc
# Preferences 是私有框架，CI 环境没有对应的 .tbd；
# 通过运行时反射 + dynamic_lookup 让链接阶段允许未解析符号，到 SpringBoard/Preferences 进程里再解析。
AirPodsAutoNoisePrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/AirPodsAutoNoisePrefs.plist$(ECHO_END)
