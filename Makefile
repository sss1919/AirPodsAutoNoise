ARCHS = arm64e
TARGET = iphone:clang:17.1:15.0
INSTALL_TARGET_PROCESSES = mediaremoted

THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AirPodsAutoNoise

AirPodsAutoNoise_FILES = Tweak.xm
AirPodsAutoNoise_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

# MediaRemote / BluetoothManager 都通过运行时反射（NSClassFromString / performSelector）调用，
# 因此不需要链接期强绑定。改为 undefined = dynamic_lookup，避免 CI 环境因缺私有 .tbd 直接 exit 2。
AirPodsAutoNoise_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 mediaremoted || true"
	install.exec "killall -9 Preferences || true"
