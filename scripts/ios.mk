SHIRO_TC ?= $(THEOS)/toolchain/linux/iphone/bin
SHIRO_SDK_V7 ?= $(error set SHIRO_SDK_V7 to the legacy armv7 sdk)
SHIRO_SDK_V64 ?= $(error set SHIRO_SDK_V64 to the arm64 sdk)
SHIRO_OPENSSL_V7 ?= $(error set SHIRO_OPENSSL_V7 to the armv7 openssl prefix)
SHIRO_OPENSSL_VE ?= $(error set SHIRO_OPENSSL_VE to the arm64e openssl prefix)
SHIRO_OPENSSL_V64 ?= $(error set SHIRO_OPENSSL_V64 to the arm64 openssl prefix)
SHIRO_CRT_V7 ?=
SHIRO_PYTHON ?= python3
SHIRO_SDK_VE ?= $(SHIRO_SDK_V64)
SHIRO_MODERN_CC ?= clang
B := build/ios
.DELETE_ON_ERROR:
INC := $(addprefix -I,$(wildcard core/*)) -Icommon -Idaemon -Iapp/controllers -Iapp/support -Iapp/appearance -Iapp/views -Iapp/theme
CFLAGS := -std=c99 -O2 -g -Wall -Wextra -Werror -Wshadow -Wstrict-prototypes -Wmissing-prototypes -Wconversion -Wno-sign-conversion $(INC) -MMD -MP
MFLAGS := -std=gnu99 -O2 -g -fno-objc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter $(INC) -MMD -MP
CORE := $(wildcard core/*/*.c)
DAEMON := $(wildcard daemon/*.c daemon/*.m) common/ShiroControl.m
APP := $(wildcard app/*/*.m) common/ShiroControl.m core/net/shiro_control_io.c core/base/shiro_clock.c core/base/shiro_log.c
STATUS := status/shiro_status.m
V7 := -target armv7-apple-ios5.0 -isysroot $(SHIRO_SDK_V7) -I$(SHIRO_OPENSSL_V7)/include
VE := -target arm64e-apple-ios14.0 -isysroot $(SHIRO_SDK_VE) -I$(SHIRO_OPENSSL_VE)/include
V64 := -target arm64-apple-ios7.0 -isysroot $(SHIRO_SDK_V64) -I$(SHIRO_OPENSSL_V64)/include
LIBS := -framework Foundation -framework CoreFoundation
UI_LIBS := $(LIBS) -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreText -framework CFNetwork
DAEMON_LIBS := $(LIBS) -framework SystemConfiguration
obj = $(addprefix $(B)/$(1)/,$(addsuffix .o,$(2)))
.PHONY: all app inputs inspect force
app: $(B)/Shiro.app/Shiro
all: $(B)/Shiro.app/Shiro $(B)/shirod $(B)/shirostatus.dylib $(B)/shirostatus-modern.dylib
inputs:
	@test -x '$(SHIRO_TC)/clang' -a -x '$(SHIRO_TC)/lipo' || { echo 'missing SHIRO_TC toolchain' >&2; exit 1; }
	@test -f '$(SHIRO_SDK_V7)/usr/include/stdlib.h' -a -f '$(SHIRO_SDK_V64)/usr/include/stdlib.h' || { echo 'missing SHIRO_SDK_V7 or SHIRO_SDK_V64' >&2; exit 1; }
	@test -x '$(SHIRO_MODERN_CC)' -a -f '$(SHIRO_OPENSSL_VE)/lib/libssl.a' -a -f '$(SHIRO_OPENSSL_VE)/lib/libcrypto.a' || { echo 'missing SHIRO_MODERN_CC or SHIRO_OPENSSL_VE inputs' >&2; exit 1; }
	@test -f '$(SHIRO_OPENSSL_V7)/lib/libssl.a' -a -f '$(SHIRO_OPENSSL_V64)/lib/libssl.a' || { echo 'missing SHIRO_OPENSSL_V7 or SHIRO_OPENSSL_V64' >&2; exit 1; }
force:
$(B)/flags: force | inputs
	@mkdir -p $(B)
	@echo '$(SHIRO_TC) $(SHIRO_MODERN_CC) $(SHIRO_SDK_VE) $(V7) $(V64) $(VE) $(SHIRO_CRT_V7) $(CFLAGS) $(MFLAGS)' | cmp -s - $@ || echo '$(SHIRO_TC) $(SHIRO_MODERN_CC) $(SHIRO_SDK_VE) $(V7) $(V64) $(VE) $(SHIRO_CRT_V7) $(CFLAGS) $(MFLAGS)' > $@
define rules
$(B)/$(1)/%.c.o: %.c $(B)/flags
	@mkdir -p $$(dir $$@)
	'$(if $(5),$(5),$(SHIRO_TC)/clang)' -B'$(SHIRO_TC)' $$(CFLAGS) $(2) -c $$< -o $$@
$(B)/$(1)/%.m.o: %.m $(B)/flags
	@mkdir -p $$(dir $$@)
	'$(if $(5),$(5),$(SHIRO_TC)/clang)' -B'$(SHIRO_TC)' $$(MFLAGS) $(if $(filter arm64e-modern,$(1)),-Wno-error=deprecated-declarations) $(2) -c $$< -o $$@
$(B)/$(1)/Shiro: $(call obj,$(1),$(APP))
	'$(if $(5),$(5),$(SHIRO_TC)/clang)' -B'$(SHIRO_TC)' $(2) $$^ $$(UI_LIBS) $(3) -o $$@
$(B)/$(1)/shirod: $(call obj,$(1),$(CORE) $(DAEMON))
	'$(if $(5),$(5),$(SHIRO_TC)/clang)' -B'$(SHIRO_TC)' $(2) $$^ $(4)/lib/libssl.a $(4)/lib/libcrypto.a $$(DAEMON_LIBS) $(3) -o $$@
$(B)/$(1)/shirostatus.dylib: $(call obj,$(1),$(STATUS))
	'$(if $(5),$(5),$(SHIRO_TC)/clang)' -B'$(SHIRO_TC)' $(2) -dynamiclib $$^ $$(UI_LIBS) -install_name /var/jb/usr/lib/shirostatus.dylib -o $$@
endef
$(eval $(call rules,armv7,$(V7),$(if $(SHIRO_CRT_V7),-nostartfiles $(SHIRO_CRT_V7),),$(SHIRO_OPENSSL_V7)))
$(eval $(call rules,arm64,$(V64),,$(SHIRO_OPENSSL_V64)))
$(eval $(call rules,arm64e-modern,$(VE),,$(SHIRO_OPENSSL_VE),$(SHIRO_MODERN_CC)))
$(B)/Shiro.app/Shiro: $(B)/arm64e-modern/Shiro $(B)/armv7/Shiro $(B)/arm64/Shiro packaging/Info.plist scripts/icons.py $(wildcard assets/*.png assets/*.jpg resources/shiro/*.pem)
	rm -rf $(B)/Shiro.app
	mkdir -p $(B)/Shiro.app
	'$(SHIRO_TC)/lipo' -create $(B)/armv7/Shiro $(B)/arm64/Shiro $(B)/arm64e-modern/Shiro -output $@
	cp packaging/Info.plist $(B)/Shiro.app/
	cp resources/shiro/*.pem assets/shiro_fox.png LICENSE $(B)/Shiro.app/
	cp assets/glyph-*.png assets/sqmrak.jpg assets/qwertyu1opz.png assets/cloudflare.png $(B)/Shiro.app/
	$(SHIRO_PYTHON) scripts/icons.py
$(B)/shirod: $(B)/armv7/shirod $(B)/arm64/shirod $(B)/arm64e-modern/shirod
	'$(SHIRO_TC)/lipo' -create $^ -output $@
$(B)/arm64e/status/shiro_status.m.o: status/shiro_status.m $(B)/flags
	@mkdir -p $(dir $@)
	'$(SHIRO_TC)/clang' -B'$(SHIRO_TC)' $(MFLAGS) -target arm64e-apple-ios12.0 -isysroot $(SHIRO_SDK_VE) -c $< -o $@
$(B)/arm64e/shirostatus.dylib: $(B)/arm64e/status/shiro_status.m.o
	'$(SHIRO_TC)/clang' -B'$(SHIRO_TC)' -target arm64e-apple-ios12.0 -isysroot $(SHIRO_SDK_VE) -dynamiclib $^ $(UI_LIBS) -install_name /var/jb/usr/lib/shirostatus.dylib -o $@
$(B)/shirostatus-modern.dylib: $(B)/arm64/shirostatus.dylib $(B)/arm64e-modern/shirostatus.dylib
	'$(SHIRO_TC)/lipo' -create $^ -output $@
$(B)/shirostatus.dylib: $(B)/armv7/shirostatus.dylib $(B)/arm64/shirostatus.dylib $(B)/arm64e/shirostatus.dylib
	'$(SHIRO_TC)/lipo' -create $^ -output $@
inspect: all
	@set -e; for binary in $(B)/Shiro.app/Shiro $(B)/shirod $(B)/shirostatus.dylib $(B)/shirostatus-modern.dylib; do \
	  '$(SHIRO_TC)/lipo' -info $$binary; \
	  '$(SHIRO_TC)/otool' -L $$binary; \
	  '$(SHIRO_TC)/otool' -l $$binary | sed -n '/LC_VERSION_MIN_IPHONEOS/,+4p; /LC_BUILD_VERSION/,+5p'; \
	done
-include $(patsubst %.o,%.d,$(foreach arch,armv7 arm64 arm64e-modern,$(call obj,$(arch),$(CORE) $(DAEMON) $(APP) $(STATUS))))
