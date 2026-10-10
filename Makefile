SHELL := /bin/zsh
.DELETE_ON_ERROR:

APP := TrollTask
BUILD := build
APP_DIR := $(BUILD)/Payload/$(APP).app
TIPA := $(BUILD)/TrollTask-0.3.0.tipa
SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)
CC := xcrun --sdk iphoneos clang
HOST_CC := xcrun --sdk macosx clang
ICON_SOURCE := Resources/AppIcon-source.png
ASSET_FILES := $(shell find Resources/Assets.xcassets -type f)

M_SOURCES := Sources/main.m Sources/LBShared.m Sources/LBApp.m Sources/LBHud.m Sources/TaskStore.m Sources/TaskRule.m Sources/TaskSched.m
OBJECTS := $(patsubst Sources/%.m,$(BUILD)/%.o,$(M_SOURCES)) $(BUILD)/storecli.o

CFLAGS := -arch arm64 -isysroot $(SDK) -miphoneos-version-min=15.0 -O2 -fvisibility=hidden -Wall -Wextra -Werror -ISources -IVendor/libical
OBJCFLAGS := $(CFLAGS) -fobjc-arc -fmodules
LDFLAGS := -arch arm64 -isysroot $(SDK) -miphoneos-version-min=15.0 -Wl,-dead_strip -framework Foundation -framework UIKit -framework CoreGraphics -framework QuartzCore -lsqlite3 $(BUILD)/ical-ios.a
ICAL_SRCS := $(wildcard Vendor/libical/*.c)
ICAL_DEFS := -DHAVE_CONFIG_H -DLIBICAL_ICAL_STATIC_DEFINE -DPACKAGE_DATA_DIR=\".\"
ICAL_IOS := $(patsubst Vendor/libical/%.c,$(BUILD)/ical-ios/%.o,$(ICAL_SRCS))
ICAL_HOST := $(patsubst Vendor/libical/%.c,$(BUILD)/ical-host/%.o,$(ICAL_SRCS))
HEADERS := $(wildcard Sources/*.h)
ICAL_HEADERS := $(wildcard Vendor/libical/*.h)
ICAL_FILES := $(wildcard Vendor/libical/* Vendor/libical/LICENSES/*)

.PHONY: all package test clean inspect icons serve store

icons: $(ICON_SOURCE)
	python3 scripts/generate_icons.py $(ICON_SOURCE) Resources/Assets.xcassets/AppIcon.appiconset

Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png: $(ICON_SOURCE) scripts/generate_icons.py
	python3 scripts/generate_icons.py $(ICON_SOURCE) Resources/Assets.xcassets/AppIcon.appiconset

all: test package

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: Sources/%.m $(HEADERS) $(ICAL_HEADERS) | $(BUILD)
	$(CC) $(OBJCFLAGS) -c $< -o $@

$(BUILD)/storecli.o: cli/storecli.m $(HEADERS) $(ICAL_HEADERS) | $(BUILD)
	$(CC) $(OBJCFLAGS) -c $< -o $@

$(APP_DIR)/Assets.car: $(ASSET_FILES)
	mkdir -p $(APP_DIR)
	xcrun actool Resources/Assets.xcassets --compile $(APP_DIR) --platform iphoneos --minimum-deployment-target 15.0 --app-icon AppIcon --output-partial-info-plist $(BUILD)/asset-info.plist --target-device iphone --target-device ipad --output-format human-readable-text

$(BUILD)/libical-source.zip: $(ICAL_FILES) Vendor/LIBICAL.md | $(BUILD)
	cd Vendor && zip -qry ../$(BUILD)/libical-source.zip libical LIBICAL.md

$(APP_DIR)/ThirdParty/libical-source.zip: $(BUILD)/libical-source.zip Vendor/LIBICAL.md
	mkdir -p $(dir $@)
	cp $< $@
	cp Vendor/LIBICAL.md $(APP_DIR)/ThirdParty/NOTICE.md

$(APP_DIR)/$(APP): $(OBJECTS) Resources/Info.plist Resources/entitlements.plist $(APP_DIR)/Assets.car $(BUILD)/ical-ios.a $(APP_DIR)/ThirdParty/libical-source.zip
	mkdir -p $(APP_DIR)
	$(CC) $(OBJECTS) $(LDFLAGS) -o $@
	cp Resources/Info.plist $(APP_DIR)/Info.plist
	cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-60@2x.png $(APP_DIR)/AppIcon60x60@2x.png
	cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-60@3x.png $(APP_DIR)/AppIcon60x60@3x.png
	cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-76@2x.png $(APP_DIR)/AppIcon76x76@2x~ipad.png
	cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-60@3x.png $(APP_DIR)/icon.png
	/usr/libexec/PlistBuddy -c "Merge $(BUILD)/asset-info.plist" $(APP_DIR)/Info.plist 2>/dev/null || true
	ldid -SResources/entitlements.plist $@

package: $(APP_DIR)/$(APP)
	cd $(BUILD) && rm -f $(notdir $(TIPA)) && zip -qry $(notdir $(TIPA)) Payload
	@print -r -- "Built $(TIPA)"

test: | $(BUILD)
	$(HOST_CC) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -ISources -IVendor/libical -framework Foundation Tests/test_shared.m Sources/LBShared.m -o $(BUILD)/test_shared
	$(BUILD)/test_shared
	python3 Tests/test_project.py
	$(MAKE) $(BUILD)/ical-host.a
	$(HOST_CC) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -ISources -IVendor/libical -framework Foundation -lsqlite3 Tests/test_store.m Sources/TaskStore.m Sources/TaskRule.m Sources/TaskSched.m $(BUILD)/ical-host.a -o $(BUILD)/test_store
	$(BUILD)/test_store
	$(HOST_CC) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -ISources -IVendor/libical -framework Foundation -lsqlite3 Tests/test_sync.m Sources/TaskStore.m Sources/TaskRule.m Sources/TaskSched.m $(BUILD)/ical-host.a -o $(BUILD)/test_sync
	$(BUILD)/test_sync
	$(MAKE) store
	PYTHONPATH=scripts python3 -B Tests/test_cli.py

store: $(BUILD)/taskstore

$(BUILD)/taskstore: cli/storecli.m Sources/TaskStore.m Sources/TaskRule.m Sources/TaskSched.m $(HEADERS) $(BUILD)/ical-host.a | $(BUILD)
	$(HOST_CC) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -DTT_STORE_CLI -ISources -IVendor/libical -framework Foundation -lsqlite3 cli/storecli.m Sources/TaskStore.m Sources/TaskRule.m Sources/TaskSched.m $(BUILD)/ical-host.a -o $@

$(BUILD)/ical-ios/%.o: Vendor/libical/%.c $(ICAL_HEADERS)
	mkdir -p $(dir $@)
	$(CC) -arch arm64 -isysroot $(SDK) -miphoneos-version-min=15.0 -O2 -fvisibility=hidden -IVendor/libical $(ICAL_DEFS) -c $< -o $@

$(BUILD)/ical-host/%.o: Vendor/libical/%.c $(ICAL_HEADERS)
	mkdir -p $(dir $@)
	$(HOST_CC) -O2 -IVendor/libical $(ICAL_DEFS) -c $< -o $@

$(BUILD)/ical-ios.a: $(ICAL_IOS)
	xcrun ar rcs $@ $^

$(BUILD)/ical-host.a: $(ICAL_HOST)
	xcrun ar rcs $@ $^

inspect: package
	file $(APP_DIR)/$(APP)
	plutil -lint $(APP_DIR)/Info.plist Resources/entitlements.plist
	plutil -extract CFBundleIcons xml1 -o - $(APP_DIR)/Info.plist
	test -f $(APP_DIR)/Assets.car
	ldid -e $(APP_DIR)/$(APP)
	unzip -l $(TIPA)

serve: package
	python3 -B scripts/serve.py

clean:
	rm -rf $(BUILD)
