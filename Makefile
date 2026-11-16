SHELL := /bin/zsh
.DELETE_ON_ERROR:

APP := TrollTask
BUILD := build
APP_DIR := $(BUILD)/Payload/$(APP).app
TIPA := $(BUILD)/TrollTask-0.21.33.tipa
CLOUD_CLIENTS ?=
SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)
CC := xcrun --sdk iphoneos clang
HOST_CC := xcrun --sdk macosx clang
ICON_SOURCE := Resources/AppIcon-source.png
ASSET_FILES := $(shell find Resources/Assets.xcassets -type f)
MING_FILES := $(shell find Resources/MingCute -type f)

SWIFT_SOURCES := $(shell find Sources -name '*.swift' | sort)
SWIFT_FLAGS := -swift-version 5 -module-name TrollTask -parse-as-library -whole-module-optimization -warnings-as-errors -ISources -ISources/Support -ISources/Support/Recurrence -import-objc-header Sources/Support/SwiftHead.h
M_SOURCES := Sources/App/main.m Sources/Core/Infrastructure/LBShared.m Sources/App/LBApp.m Sources/Features/HUD/LBHud.m Sources/Core/Data/TaskStore.m Sources/Core/Domain/TaskRule.m
TOUCH_SOURCES := $(wildcard Sources/Support/Touch/*.m)
OBJECTS := $(patsubst Sources/%.m,$(BUILD)/%.o,$(M_SOURCES)) $(patsubst Sources/Support/Touch/%.m,$(BUILD)/touch/%.o,$(TOUCH_SOURCES)) $(BUILD)/storecli.o $(BUILD)/TaskSwift.o

CFLAGS := -arch arm64 -isysroot $(SDK) -miphoneos-version-min=15.0 -O2 -fvisibility=hidden -Wall -Wextra -Werror -ISources -ISources/Support -ISources/Support/Recurrence
OBJCFLAGS := $(CFLAGS) -fobjc-arc -fmodules
ICAL_SRCS := $(wildcard Sources/Support/Recurrence/*.c)
ICAL_DEFS := -DHAVE_CONFIG_H -DLIBICAL_ICAL_STATIC_DEFINE -DPACKAGE_DATA_DIR=\".\"
ICAL_IOS := $(patsubst Sources/Support/Recurrence/%.c,$(BUILD)/ical-ios/%.o,$(ICAL_SRCS))
ICAL_HOST := $(patsubst Sources/Support/Recurrence/%.c,$(BUILD)/ical-host/%.o,$(ICAL_SRCS))
ICAL_SIM := $(patsubst Sources/Support/Recurrence/%.c,$(BUILD)/ical-sim/%.o,$(ICAL_SRCS))
SIM_CC := xcrun --sdk iphonesimulator clang
SIM_FLAGS := -target arm64-apple-ios15.0-simulator -O1 -ISources -ISources/Support -ISources/Support/Recurrence
HEADERS := $(shell find Sources/App Sources/Core Sources/Features Sources/DesignSystem Sources/Support -name '*.h' -not -path '*/Recurrence/*' | sort)
HEADERS += Sources/Core/Data/TaskStoreAgenda.inc
CORE_SWIFT := Sources/Support/SwiftHead.swift Sources/Core/Domain/ReminderQueue.swift Sources/Core/Domain/TaskScheduler.swift Sources/Core/Domain/TaskReminder.swift Sources/Core/Domain/TaskRoutineImport.swift Sources/Core/Domain/TaskRoutineCheck.swift Sources/Core/Domain/TaskRoutineView.swift Sources/Core/Domain/TaskAI.swift Sources/Core/Domain/TaskIntake.swift Sources/Core/Domain/TaskToday.swift Sources/Core/Domain/TaskDayOrder.swift Sources/Core/Domain/TaskDivision.swift Sources/Core/Domain/TaskTimeMap.swift
HOST_FLAGS := -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -ISources -ISources/Support -ISources/Support/Recurrence
HOST_OBJECTS := $(BUILD)/host/TaskStore.o $(BUILD)/host/TaskRule.o $(BUILD)/host/LBShared.o $(BUILD)/host/TaskScheduler.o
ICAL_HEADERS := $(wildcard Sources/Support/Recurrence/*.h)

.PHONY: all package test test-assist test-agenda test-routine-view test-rule test-queue test-recover test-load test-sched test-reminder test-checkin test-occ test-signal test-ui clean inspect icons serve store

icons: $(ICON_SOURCE)
	python3 scripts/generate_icons.py $(ICON_SOURCE) Resources/Assets.xcassets/AppIcon.appiconset

Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png: $(ICON_SOURCE) scripts/generate_icons.py
	python3 scripts/generate_icons.py $(ICON_SOURCE) Resources/Assets.xcassets/AppIcon.appiconset

all: test package

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/%.o: Sources/%.m $(HEADERS) $(ICAL_HEADERS) Makefile | $(BUILD)
	mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS) -c $< -o $@

$(BUILD)/touch/%.o: Sources/Support/Touch/%.m $(HEADERS) Makefile | $(BUILD)
	mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS) -c $< -o $@

$(BUILD)/TaskSwift.o: $(SWIFT_SOURCES) $(HEADERS) $(ICAL_HEADERS) Makefile | $(BUILD)
	xcrun --sdk iphoneos swiftc $(SWIFT_FLAGS) -target arm64-apple-ios15.0 -sdk $(SDK) -O -emit-object $(SWIFT_SOURCES) -o $@

$(BUILD)/storecli.o: cli/storecli.m $(HEADERS) $(ICAL_HEADERS) Makefile | $(BUILD)
	$(CC) $(OBJCFLAGS) -c $< -o $@

$(APP_DIR)/Assets.car: $(ASSET_FILES)
	mkdir -p $(APP_DIR)
	xcrun actool Resources/Assets.xcassets --compile $(APP_DIR) --platform iphoneos --minimum-deployment-target 15.0 --app-icon AppIcon --output-partial-info-plist $(BUILD)/asset-info.plist --target-device iphone --target-device ipad --output-format human-readable-text

.PHONY: cloud-info
$(BUILD)/AppInfo.plist: Resources/Info.plist scripts/cloud_plist.py scripts/head.py cloud-info | $(BUILD)
	python3 -B scripts/cloud_plist.py "$<" "$@" "$(CLOUD_CLIENTS)"

$(APP_DIR)/$(APP): $(OBJECTS) $(BUILD)/AppInfo.plist Resources/entitlements.plist Resources/Reminder.wav Resources/WeeklyRoutine.json $(MING_FILES) $(APP_DIR)/Assets.car $(BUILD)/ical-ios.a
	mkdir -p $(APP_DIR)
	xcrun --sdk iphoneos swiftc -target arm64-apple-ios15.0 -sdk $(SDK) $(OBJECTS) -Xlinker -dead_strip -framework Foundation -framework ImageIO -framework IOKit -framework UIKit -framework CoreGraphics -framework QuartzCore -lsqlite3 $(BUILD)/ical-ios.a -o $@
	cp $(BUILD)/AppInfo.plist $(APP_DIR)/Info.plist
	cp -R Resources/MingCute $(APP_DIR)/
	cp Resources/Reminder.wav Resources/WeeklyRoutine.json $(APP_DIR)/
	cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-60@2x.png $(APP_DIR)/AppIcon60x60@2x.png
	cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-60@3x.png $(APP_DIR)/AppIcon60x60@3x.png
	cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-76@2x.png $(APP_DIR)/AppIcon76x76@2x~ipad.png
	cp Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-60@3x.png $(APP_DIR)/icon.png
	/usr/libexec/PlistBuddy -c "Merge $(BUILD)/asset-info.plist" $(APP_DIR)/Info.plist 2>/dev/null || true
	ldid -SResources/entitlements.plist $@

package: $(APP_DIR)/$(APP)
	cd $(BUILD) && rm -f $(notdir $(TIPA)) && zip -qry -FS $(notdir $(TIPA)) Payload
	@print -r -- "Built $(TIPA)"

test: store | $(BUILD)
	$(HOST_CC) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -ISources -ISources/Support -ISources/Support/Recurrence -framework Foundation Tests/test_shared.m Sources/Core/Infrastructure/LBShared.m -o $(BUILD)/test_shared
	$(BUILD)/test_shared
	python3 Tests/test_project.py
	$(MAKE) $(BUILD)/ical-host.a
	$(MAKE) test-rule
	$(MAKE) $(BUILD)/test_store $(BUILD)/test_sync
	$(BUILD)/test_store
	$(BUILD)/test_sync
	$(MAKE) test-agenda
	$(MAKE) test-routine-view
	PYTHONPATH=scripts:Tests python3 -B Tests/test_weekly.py
	$(MAKE) test-assist
	PYTHONPATH=scripts python3 -B Tests/test_intake.py
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
	PYTHONPATH=scripts:Tests python3 -B Tests/test_routine_guard.py
	PYTHONPATH=scripts python3 -B Tests/test_serve.py

test-rule: $(BUILD)/test_rule
	$(BUILD)/test_rule

$(BUILD)/test_rule: Tests/test_rule.m Sources/Core/Domain/TaskRule.m $(HEADERS) $(BUILD)/ical-host.a | $(BUILD)
	$(HOST_CC) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -ISources -ISources/Support -ISources/Support/Recurrence -framework Foundation Tests/test_rule.m Sources/Core/Domain/TaskRule.m $(BUILD)/ical-host.a -o $@

store: $(BUILD)/taskstore

$(BUILD)/host/%.o: Sources/%.m $(HEADERS) $(ICAL_HEADERS) Makefile
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_FLAGS) -c $< -o $@

$(BUILD)/host/TaskStore.o: Sources/Core/Data/TaskStore.m $(HEADERS) $(ICAL_HEADERS) Makefile
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_FLAGS) -c $< -o $@

$(BUILD)/host/TaskRule.o: Sources/Core/Domain/TaskRule.m $(HEADERS) $(ICAL_HEADERS) Makefile
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_FLAGS) -c $< -o $@

$(BUILD)/host/LBShared.o: Sources/Core/Infrastructure/LBShared.m $(HEADERS) $(ICAL_HEADERS) Makefile
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_FLAGS) -c $< -o $@

$(BUILD)/host/test_%.o: Tests/test_%.m $(HEADERS) Makefile
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_FLAGS) -c $< -o $@

$(BUILD)/host/TaskScheduler.o: $(CORE_SWIFT) $(HEADERS) $(ICAL_HEADERS) Makefile
	mkdir -p $(dir $@)
	xcrun --sdk macosx swiftc $(SWIFT_FLAGS) -Xcc -DLB_HOST_TEST -O -emit-object $(CORE_SWIFT) -o $@

$(BUILD)/test_store $(BUILD)/test_sync $(BUILD)/test_sched $(BUILD)/test_reminder $(BUILD)/test_checkin $(BUILD)/test_occ $(BUILD)/test_signalstore $(BUILD)/test_agenda $(BUILD)/test_routine_view: $(BUILD)/test_%: $(BUILD)/host/test_%.o $(HOST_OBJECTS) $(BUILD)/ical-host.a
	xcrun --sdk macosx swiftc $^ -framework Foundation -framework ImageIO -lsqlite3 -o $@

test-sched: $(BUILD)/test_sched
	$(BUILD)/test_sched

test-assist: store
	PYTHONPATH=scripts:Tests python3 -B Tests/test_assist.py

test-agenda: $(BUILD)/test_agenda
	$(BUILD)/test_agenda

# 只读常律触发分区及五项分组。
test-routine-view: $(BUILD)/test_routine_view
	$(BUILD)/test_routine_view

test-queue: $(BUILD)/test_queue
	$(BUILD)/test_queue

test-recover: $(BUILD)/test_recover
	$(BUILD)/test_recover

test-load: $(BUILD)/test_load
	$(BUILD)/test_load

$(BUILD)/test_recover $(BUILD)/test_load: $(BUILD)/test_%: Tests/test_%.swift Tests/TestClock.swift $(CORE_SWIFT) $(filter-out $(BUILD)/host/TaskScheduler.o,$(HOST_OBJECTS)) $(BUILD)/ical-host.a $(HEADERS) Makefile
	xcrun --sdk macosx swiftc $(SWIFT_FLAGS) -Xcc -DLB_HOST_TEST -O Tests/test_$*.swift Tests/TestClock.swift $(CORE_SWIFT) $(filter-out $(BUILD)/host/TaskScheduler.o,$(HOST_OBJECTS)) $(BUILD)/ical-host.a -framework Foundation -framework ImageIO -lsqlite3 -o $@

$(BUILD)/test_queue: Tests/test_queue.swift Sources/Core/Domain/ReminderQueue.swift Sources/Support/SwiftHead.swift $(HEADERS) Makefile | $(BUILD)
	xcrun --sdk macosx swiftc $(SWIFT_FLAGS) -Xcc -DLB_HOST_TEST -O Sources/Support/SwiftHead.swift Sources/Core/Domain/ReminderQueue.swift Tests/test_queue.swift -o $@

test-reminder: $(BUILD)/test_reminder
	$(BUILD)/test_reminder

test-checkin: $(BUILD)/test_checkin
	$(BUILD)/test_checkin

test-occ: $(BUILD)/test_occ
	$(BUILD)/test_occ

test-signal: $(BUILD)/test_signal $(BUILD)/test_signalstore
	$(BUILD)/test_signal
	$(BUILD)/test_signalstore

$(BUILD)/test_signal: Tests/test_signal.swift Sources/Core/Domain/TaskTraits.swift Sources/Core/Domain/TaskSignal.swift Sources/Support/SwiftHead.swift $(HEADERS) Makefile | $(BUILD)
	xcrun --sdk macosx swiftc $(SWIFT_FLAGS) -Xcc -DLB_HOST_TEST -O Sources/Support/SwiftHead.swift Sources/Core/Domain/TaskTraits.swift Sources/Core/Domain/TaskSignal.swift Tests/test_signal.swift -o $@

$(BUILD)/host/storecli.o: cli/storecli.m $(HEADERS) Makefile
	mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_FLAGS) -DTT_STORE_CLI -c $< -o $@

$(BUILD)/taskstore: $(BUILD)/host/storecli.o $(HOST_OBJECTS) $(BUILD)/ical-host.a
	xcrun --sdk macosx swiftc $^ -framework Foundation -framework ImageIO -lsqlite3 -o $@

$(BUILD)/ical-ios/%.o: Sources/Support/Recurrence/%.c $(ICAL_HEADERS)
	mkdir -p $(dir $@)
	$(CC) -arch arm64 -isysroot $(SDK) -miphoneos-version-min=15.0 -O2 -fvisibility=hidden -ISources/Support/Recurrence $(ICAL_DEFS) -c $< -o $@

$(BUILD)/ical-host/%.o: Sources/Support/Recurrence/%.c $(ICAL_HEADERS)
	mkdir -p $(dir $@)
	$(HOST_CC) -O2 -ISources/Support/Recurrence $(ICAL_DEFS) -c $< -o $@

$(BUILD)/ical-ios.a: $(ICAL_IOS)
	xcrun ar rcs $@ $^

$(BUILD)/ical-host.a: $(ICAL_HOST)
	xcrun ar rcs $@ $^

$(BUILD)/ical-sim/%.o: Sources/Support/Recurrence/%.c $(ICAL_HEADERS)
	mkdir -p $(dir $@)
	$(SIM_CC) $(SIM_FLAGS) $(ICAL_DEFS) -c $< -o $@

$(BUILD)/ical-sim.a: $(ICAL_SIM)
	xcrun ar rcs $@ $^

UI_M_SOURCES := Sources/Core/Infrastructure/LBShared.m Sources/Core/Data/TaskStore.m Sources/Core/Domain/TaskRule.m
UI_OBJECTS := $(patsubst Sources/%.m,$(BUILD)/ui/%.o,$(UI_M_SOURCES)) $(patsubst Sources/Support/Touch/%.m,$(BUILD)/ui/touch/%.o,$(TOUCH_SOURCES)) $(BUILD)/ui/test_ui.o $(BUILD)/ui/TaskSwift.o
SIM_SDK := $(shell xcrun --sdk iphonesimulator --show-sdk-path)

$(BUILD)/ui/%.o: Sources/%.m $(HEADERS) $(ICAL_HEADERS) Makefile
	mkdir -p $(dir $@)
	$(SIM_CC) $(SIM_FLAGS) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -DLB_UI_TEST -c $< -o $@

$(BUILD)/ui/touch/%.o: Sources/Support/Touch/%.m $(HEADERS) Makefile
	mkdir -p $(dir $@)
	$(SIM_CC) $(SIM_FLAGS) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -DLB_UI_TEST -c $< -o $@

$(BUILD)/ui/test_ui.o: Tests/test_ui.m Tests/test_hud.inc Tests/test_signal.inc Tests/test_parity.inc Tests/test_routine_ui.inc Tests/test_assistant_ui.inc Tests/test_today_ui.inc Tests/test_design_ui.inc Tests/test_weekly_ui.inc Tests/test_create_ui.inc $(HEADERS) Makefile
	mkdir -p $(dir $@)
	$(SIM_CC) $(SIM_FLAGS) -fobjc-arc -fblocks -Wall -Wextra -Werror -DLB_HOST_TEST -DLB_UI_TEST -c $< -o $@

$(BUILD)/ui/TaskSwift.o: $(SWIFT_SOURCES) $(HEADERS) $(ICAL_HEADERS) Makefile
	mkdir -p $(dir $@)
	xcrun --sdk iphonesimulator swiftc $(SWIFT_FLAGS) -target arm64-apple-ios15.0-simulator -sdk $(SIM_SDK) -D LB_UI_TEST -Xcc -DLB_HOST_TEST -Xcc -DLB_UI_TEST -O -emit-object $(SWIFT_SOURCES) -o $@

$(BUILD)/MobileUI.app/UItest: $(UI_OBJECTS) Tests/UIInfo.plist Resources/Reminder.wav Resources/WeeklyRoutine.json $(MING_FILES) $(BUILD)/ical-sim.a
	mkdir -p $(dir $@)
	xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios15.0-simulator -sdk $(SIM_SDK) $(UI_OBJECTS) -framework Foundation -framework ImageIO -framework IOKit -framework UIKit -framework CoreGraphics -framework QuartzCore -lsqlite3 $(BUILD)/ical-sim.a -o $@
	cp Tests/UIInfo.plist $(dir $@)/Info.plist
	cp Resources/Reminder.wav Resources/WeeklyRoutine.json $(dir $@)/
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
