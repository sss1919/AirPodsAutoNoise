ARCHS = arm64e
TARGET = iphone:clang:17.1:15.0
INSTALL_TARGET_PROCESSES = mediaremoted

THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AirPodsAutoNoise

AirPodsAutoNoise_FILES = Tweak.xm
AirPodsAutoNoise_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

# MediaRemote / BluetoothManager 通过 NSClassFromString 运行时反射调用，CI 上
# 不需要存在对应 .tbd，直接用 -undefined dynamic_lookup 在运行时解析。
AirPodsAutoNoise_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

package::
	@echo "[make-post-package] packages dir listing:"
	@ls -la packages || echo "[make-post-package] packages dir MISSING"

after-install::
	install.exec "killall -9 mediaremoted || true"
	install.exec "killall -9 Preferences || true"
