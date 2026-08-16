ARCHS = arm64e
TARGET = iphone:clang:17.1:15.0
INSTALL_TARGET_PROCESSES = mediaremoted

THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AirPodsAutoNoise

AirPodsAutoNoise_FILES = Tweak.xm
AirPodsAutoNoise_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AirPodsAutoNoise_PRIVATE_FRAMEWORKS = MediaRemote BluetoothManager

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 mediaremoted || true"
	install.exec "killall -9 Preferences || true"
