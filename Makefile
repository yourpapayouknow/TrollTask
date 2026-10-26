SHELL := /bin/zsh
.DELETE_ON_ERROR:

APP := TrollTask
BUILD := build
APP_DIR := $(BUILD)/Payload/$(APP).app
TIPA := $(BUILD)/TrollTask-0.18.0.tipa
SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)
CC := xcrun --sdk iphoneos clang
HOST_CC := xcrun --sdk macosx clang
ICON_SOURCE := Resources/AppIcon-source.png
ASSET_FILES := $(shell find Resources/Assets.xcassets -type f)
MING_FILES := $(shell find Resources/MingCute -type f)

SWIFT_SOURCES := $(wildcard Sources/*.swift)
SWIFT_FLAGS := -swift-version 5 -module-name TrollTask -parse-as-library -whole-module-optimization -warnings-as-errors -ISources -IVendor/libical -import-objc-header Sources/SwiftHead.h
M_SOURCES := Sources/main.m Sources/LBShared.m Sources/LBApp.m Sources/LBHud.m Sources/TaskStore.m Sources/TaskRule.m
TOUCH_SOURCES := $(wildcard Vendor/TrollSpeed/*.m)
TOUCH_FILES := $(wildcard Vendor/TrollSpeed/*)
OBJECTS := $(patsubst Sources/%.m,$(BUILD)/%.o,$(M_SOURCES)) $(patsubst Vendor/TrollSpeed/%.m,$(BUILD)/touch/%.o,$(TOUCH_SOURCES)) $(BUILD)/storecli.o $(BUILD)/TaskSwift.o

CFLAGS := -arch arm64 -isysroot $(SDK) -miphoneos-version-min=15.0 -O2 -fvisibility=hidden -Wall -Wextra -Werror -ISources -IVendor/libical
OBJCFLAGS := $(CFLAGS) -fobjc-arc -fmodules
ICAL_SRCS := $(wildcard Vendor/libical/*.c)
ICAL_DEFS := -DHAVE_CONFIG_H -DLIBICAL_ICAL_STATIC_DEFINE -DPACKAGE_DATA_DIR=\".\"
ICAL_IOS := $(patsubst Vendor/libical/%.c,$(BUILD)/ical-ios/%.o,$(ICAL_SRCS))
ICAL_HOST := $(patsubst Vendor/libical/%.c,$(BUILD)/ical-host/%.o,$(ICAL_SRCS))
ICAL_SIM := $(patsubst Vendor/libical/%.c,$(BUILD)/ical-sim/%.o,$(ICAL_SRCS))
SIM_CC := xcrun --sdk iphonesimulator clang
SIM_FLAGS := -target arm64-apple-ios15.0-simulator -O1 -ISources -IVendor/libical
HEADERS := $(wildcard Sources/*.h)
HEADERS += Vendor/TrollSpeed/head.h
CORE_SWIFT := Sources/SwiftHead.swift Sources/ReminderQueue.swift Sources/TaskScheduler.swift Sources/TaskReminder.swift
HOST_FLAGS := -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -ISources -IVendor/libical
HOST_OBJECTS := $(BUILD)/host/TaskStore.o $(BUILD)/host/TaskRule.o $(BUILD)/host/LBShared.o $(BUILD)/host/TaskScheduler.o
ICAL_HEADERS := $(wildcard Vendor/libical/*.h)
ICAL_FILES := $(wildcard Vendor/libical/* Vendor/libical/LICENSES/*)

.PHONY: all package package-debug test test-rule test-queue test-recover test-load test-sched test-reminder test-checkin test-occ test-signal test-ui clean inspect icons serve store

icons: $(ICON_SOURCE)
	python3 scripts/generate_icons.py $(ICON_SOURCE) Resources/Assets.xcassets/AppIcon.appiconset

Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png: $(ICON_SOURCE) scripts/generate_icons.py
	python3 scripts/generate_icons.py $(ICON_SOURCE) Resources/Assets.xcassets/AppIcon.appiconset

all: test package

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: Sources/%.m $(HEADERS) $(ICAL_HEADERS) Makefile | $(BUILD)
	$(CC) $(OBJCFLAGS) -c $< -o $@

$(BUILD)/touch/%.o: Vendor/TrollSpeed/%.m $(HEADERS) Makefile | $(BUILD)
	mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS) -c $< -o $@

$(BUILD)/TaskSwift.o: $(SWIFT_SOURCES) $(HEADERS) $(ICAL_HEADERS) Makefile | $(BUILD)
	xcrun --sdk iphoneos swiftc $(SWIFT_FLAGS) -target arm64-apple-ios15.0 -sdk $(SDK) -O -emit-object $(SWIFT_SOURCES) -o $@

$(BUILD)/storecli.o: cli/storecli.m $(HEADERS) $(ICAL_HEADERS) Makefile | $(BUILD)
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

$(APP_DIR)/$(APP): $(OBJECTS) Resources/Info.plist Resources/entitlements.plist Resources/Reminder.wav $(MING_FILES) $(TOUCH_FILES) $(APP_DIR)/Assets.car $(BUILD)/ical-ios.a $(APP_DIR)/ThirdParty/libical-source.zip
	mkdir -p $(APP_DIR)
	xcrun --sdk iphoneos swiftc -target arm64-apple-ios15.0 -sdk $(SDK) $(OBJECTS) -Xlinker -dead_strip -framework Foundation -framework ImageIO -framework IOKit -framework UIKit -framework CoreGraphics -framework QuartzCore -lsqlite3 $(BUILD)/ical-ios.a -o $@
	cp Resources/Info.plist $(APP_DIR)/Info.plist
	cp -R Resources/MingCute $(APP_DIR)/
	cp Resources/Reminder.wav $(APP_DIR)/
	mkdir -p $(APP_DIR)/ThirdParty/TrollSpeed
	cp Vendor/TrollSpeed/* $(APP_DIR)/ThirdParty/TrollSpeed/
	cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-60@2x.png $(APP_DIR)/AppIcon60x60@2x.png
	cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-60@3x.png $(APP_DIR)/AppIcon60x60@3x.png
	cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-76@2x.png $(APP_DIR)/AppIcon76x76@2x~ipad.png
	cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-60@3x.png $(APP_DIR)/icon.png
	/usr/libexec/PlistBuddy -c "Merge $(BUILD)/asset-info.plist" $(APP_DIR)/Info.plist 2>/dev/null || true
	ldid -SResources/entitlements.plist $@

package: $(APP_DIR)/$(APP)
	cd $(BUILD) && rm -f $(notdir $(TIPA)) && zip -qry $(notdir $(TIPA)) Payload
	@print -r -- "Built $(TIPA)"

# 仅在独立复制目录中标记30秒诊断版，正式包不包含此标记。
package-debug: $(APP_DIR)/$(APP)
	rm -rf $(BUILD)/Debug/Payload
	mkdir -p $(BUILD)/Debug/Payload
	cp -R $(APP_DIR) $(BUILD)/Debug/Payload/
	/usr/libexec/PlistBuddy -c "Add :TTHUDDebug bool true" $(BUILD)/Debug/Payload/$(APP).app/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.10.2" $(BUILD)/Debug/Payload/$(APP).app/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 15" $(BUILD)/Debug/Payload/$(APP).app/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 待办调试" $(BUILD)/Debug/Payload/$(APP).app/Info.plist
	ldid -SResources/entitlements.plist $(BUILD)/Debug/Payload/$(APP).app/$(APP)
	cd $(BUILD)/Debug && rm -f ../TrollTask-0.10.2-debug.tipa && zip -qry ../TrollTask-0.10.2-debug.tipa Payload

test: | $(BUILD)
	$(HOST_CC) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -ISources -IVendor/libical -framework Foundation Tests/test_shared.m Sources/LBShared.m -o $(BUILD)/test_shared
	$(BUILD)/test_shared
	python3 Tests/test_project.py
	$(MAKE) $(BUILD)/ical-host.a
	$(MAKE) test-rule
	$(MAKE) $(BUILD)/test_store $(BUILD)/test_sync
	$(BUILD)/test_store
	$(BUILD)/test_sync
	$(MAKE) test-queue
	$(MAKE) test-recover
	$(MAKE) test-load
	$(MAKE) test-sched
	$(MAKE) test-reminder
	$(MAKE) test-checkin
	$(MAKE) test-occ
	$(MAKE) test-signal
	$(MAKE) store
	PYTHONPATH=scripts python3 -B Tests/test_cli.py
	PYTHONPATH=scripts python3 -B Tests/test_serve.py

test-rule: $(BUILD)/test_rule
	$(BUILD)/test_rule

$(BUILD)/test_rule: Tests/test_rule.m Sources/TaskRule.m $(HEADERS) $(BUILD)/ical-host.a | $(BUILD)
	$(HOST_CC) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -ISources -IVendor/libical -framework Foundation Tests/test_rule.m Sources/TaskRule.m $(BUILD)/ical-host.a -o $@

store: $(BUILD)/taskstore

$(BUILD)/host/%.o: Sources/%.m $(HEADERS) $(ICAL_HEADERS) Makefile
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_FLAGS) -c $< -o $@

$(BUILD)/host/test_%.o: Tests/test_%.m $(HEADERS) Makefile
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_FLAGS) -c $< -o $@

$(BUILD)/host/TaskScheduler.o: $(CORE_SWIFT) $(HEADERS) $(ICAL_HEADERS) Makefile
	mkdir -p $(dir $@)
	xcrun --sdk macosx swiftc $(SWIFT_FLAGS) -Xcc -DLB_HOST_TEST -O -emit-object $(CORE_SWIFT) -o $@

$(BUILD)/test_store $(BUILD)/test_sync $(BUILD)/test_sched $(BUILD)/test_reminder $(BUILD)/test_checkin $(BUILD)/test_occ $(BUILD)/test_signalstore: $(BUILD)/test_%: $(BUILD)/host/test_%.o $(HOST_OBJECTS) $(BUILD)/ical-host.a
	xcrun --sdk macosx swiftc $^ -framework Foundation -framework ImageIO -lsqlite3 -o $@

test-sched: $(BUILD)/test_sched
	$(BUILD)/test_sched

test-queue: $(BUILD)/test_queue
	$(BUILD)/test_queue

test-recover: $(BUILD)/test_recover
	$(BUILD)/test_recover

test-load: $(BUILD)/test_load
	$(BUILD)/test_load

$(BUILD)/test_recover $(BUILD)/test_load: $(BUILD)/test_%: Tests/test_%.swift Tests/TestClock.swift $(CORE_SWIFT) $(filter-out $(BUILD)/host/TaskScheduler.o,$(HOST_OBJECTS)) $(BUILD)/ical-host.a $(HEADERS) Makefile
	xcrun --sdk macosx swiftc $(SWIFT_FLAGS) -Xcc -DLB_HOST_TEST -O Tests/test_$*.swift Tests/TestClock.swift $(CORE_SWIFT) $(filter-out $(BUILD)/host/TaskScheduler.o,$(HOST_OBJECTS)) $(BUILD)/ical-host.a -framework Foundation -framework ImageIO -lsqlite3 -o $@

$(BUILD)/test_queue: Tests/test_queue.swift Sources/ReminderQueue.swift Sources/SwiftHead.swift $(HEADERS) Makefile | $(BUILD)
	xcrun --sdk macosx swiftc $(SWIFT_FLAGS) -Xcc -DLB_HOST_TEST -O Sources/SwiftHead.swift Sources/ReminderQueue.swift Tests/test_queue.swift -o $@

test-reminder: $(BUILD)/test_reminder
	$(BUILD)/test_reminder

test-checkin: $(BUILD)/test_checkin
	$(BUILD)/test_checkin

test-occ: $(BUILD)/test_occ
	$(BUILD)/test_occ

test-signal: $(BUILD)/test_signal $(BUILD)/test_signalstore
	$(BUILD)/test_signal
	$(BUILD)/test_signalstore

$(BUILD)/test_signal: Tests/test_signal.swift Sources/TaskTraits.swift Sources/TaskSignal.swift Sources/SwiftHead.swift $(HEADERS) Makefile | $(BUILD)
	xcrun --sdk macosx swiftc $(SWIFT_FLAGS) -Xcc -DLB_HOST_TEST -O Sources/SwiftHead.swift Sources/TaskTraits.swift Sources/TaskSignal.swift Tests/test_signal.swift -o $@

$(BUILD)/host/storecli.o: cli/storecli.m $(HEADERS) Makefile
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_FLAGS) -DTT_STORE_CLI -c $< -o $@

$(BUILD)/taskstore: $(BUILD)/host/storecli.o $(HOST_OBJECTS) $(BUILD)/ical-host.a
	xcrun --sdk macosx swiftc $^ -framework Foundation -framework ImageIO -lsqlite3 -o $@

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

$(BUILD)/ical-sim/%.o: Vendor/libical/%.c $(ICAL_HEADERS)
	mkdir -p $(dir $@)
	$(SIM_CC) $(SIM_FLAGS) $(ICAL_DEFS) -c $< -o $@

$(BUILD)/ical-sim.a: $(ICAL_SIM)
	xcrun ar rcs $@ $^

UI_M_SOURCES := Sources/LBShared.m Sources/TaskStore.m Sources/TaskRule.m
UI_OBJECTS := $(patsubst Sources/%.m,$(BUILD)/ui/%.o,$(UI_M_SOURCES)) $(patsubst Vendor/TrollSpeed/%.m,$(BUILD)/ui/touch/%.o,$(TOUCH_SOURCES)) $(BUILD)/ui/test_ui.o $(BUILD)/ui/TaskSwift.o
SIM_SDK := $(shell xcrun --sdk iphonesimulator --show-sdk-path)

$(BUILD)/ui/%.o: Sources/%.m $(HEADERS) $(ICAL_HEADERS) Makefile
	mkdir -p $(dir $@)
	$(SIM_CC) $(SIM_FLAGS) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -DLB_UI_TEST -c $< -o $@

$(BUILD)/ui/touch/%.o: Vendor/TrollSpeed/%.m $(HEADERS) Makefile
	mkdir -p $(dir $@)
	$(SIM_CC) $(SIM_FLAGS) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -DLB_UI_TEST -c $< -o $@

$(BUILD)/ui/test_ui.o: Tests/test_ui.m Tests/test_hud.inc Tests/test_signal.inc Tests/test_parity.inc $(HEADERS) Makefile
	mkdir -p $(dir $@)
	$(SIM_CC) $(SIM_FLAGS) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -DLB_UI_TEST -c $< -o $@

$(BUILD)/ui/TaskSwift.o: $(SWIFT_SOURCES) $(HEADERS) $(ICAL_HEADERS) Makefile
	mkdir -p $(dir $@)
	xcrun --sdk iphonesimulator swiftc $(SWIFT_FLAGS) -target arm64-apple-ios15.0-simulator -sdk $(SIM_SDK) -D LB_UI_TEST -Xcc -DLB_HOST_TEST -Xcc -DLB_UI_TEST -O -emit-object $(SWIFT_SOURCES) -o $@

$(BUILD)/MobileUI.app/UItest: $(UI_OBJECTS) Tests/UIInfo.plist Resources/Reminder.wav $(MING_FILES) $(BUILD)/ical-sim.a
	mkdir -p $(dir $@)
	xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios15.0-simulator -sdk $(SIM_SDK) $(UI_OBJECTS) -framework Foundation -framework ImageIO -framework IOKit -framework UIKit -framework CoreGraphics -framework QuartzCore -lsqlite3 $(BUILD)/ical-sim.a -o $@
	cp Tests/UIInfo.plist $(dir $@)/Info.plist
	cp Resources/Reminder.wav $(dir $@)/
	cp -R Resources/MingCute $(dir $@)/
	codesign --force --sign - $(dir $@)

test-ui: $(BUILD)/MobileUI.app/UItest
	/bin/zsh Tests/ui_test.zsh $(UI_DEVICE)

# 同一原生触摸夹具对照UIApplicationMain和手动宿主启动。
$(BUILD)/ui/native_input.o: Tests/native_input.m Tests/test_ui.m $(wildcard Tests/*.inc) $(HEADERS) Makefile
	mkdir -p $(dir $@)
	$(SIM_CC) $(SIM_FLAGS) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -DLB_UI_TEST -c $< -o $@

$(BUILD)/NativeInput.app/NativeInput: $(filter-out $(BUILD)/ui/test_ui.o,$(UI_OBJECTS)) $(BUILD)/ui/native_input.o Tests/UIInfo.plist $(BUILD)/ical-sim.a
	mkdir -p $(dir $@)
	xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios15.0-simulator -sdk $(SIM_SDK) $(filter-out $(BUILD)/ui/test_ui.o,$(UI_OBJECTS)) $(BUILD)/ui/native_input.o -framework Foundation -framework ImageIO -framework IOKit -framework UIKit -framework CoreGraphics -framework QuartzCore -lsqlite3 $(BUILD)/ical-sim.a -o $@
	cp Tests/UIInfo.plist $(dir $@)/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.iwmei.taskforiwmei.nativeinput" $(dir $@)/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable NativeInput" $(dir $@)/Info.plist
	codesign --force --sign - $(dir $@)

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
