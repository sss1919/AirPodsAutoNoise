ARCHS = arm64e
TARGET = iphone:clang:17.1:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AirPodsAutoNoisePrefs

AirPodsAutoNoisePrefs_FILES = APANRootListController.m
AirPodsAutoNoisePrefs_INSTALL_PATH = /Library/PreferenceBundles
AirPodsAutoNoisePrefs_FRAMEWORKS = UIKit
# Preferences 框架在少数 CI SDK / Roothide 环境里没有公开头文件或 .tbd，
# 这里不再写 PRIVATE_FRAMEWORKS = Preferences，改用 -undefined dynamic_lookup，
# 让符号推迟到运行时在 SpringBoard/Preferences 进程中解析。
AirPodsAutoNoisePrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
AirPodsAutoNoisePrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/AirPodsAutoNoisePrefs.plist$(ECHO_END)
