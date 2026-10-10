#!/bin/zsh
# 在指定已启动模拟器运行原生界面测试并复制结果。
set -euo pipefail
ui_device=${1:?请指定已启动模拟器UUID}
ui_bundle=com.iwmei.taskforiwmei.uitest
xcrun simctl install "$ui_device" build/MobileUI.app
ui_data=$(xcrun simctl get_app_container "$ui_device" "$ui_bundle" data)
rm -f "$ui_data/Documents/UITestReport.json"
xcrun simctl launch --terminate-running-process --stdout=/tmp/trolltask-ui-stdout.log --stderr=/tmp/trolltask-ui-stderr.log "$ui_device" "$ui_bundle"
# 有界等待报告，不阻塞交互超过一分钟。
for ui_attempt in {1..250}; do
    [[ -f "$ui_data/Documents/UITestReport.json" ]] && break
    sleep 0.2
done
mkdir -p "build/ui-artifacts/$ui_device"
cp -R "$ui_data/Documents/UITestReport.json" "$ui_data/Documents/screens" "build/ui-artifacts/$ui_device/"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(json.dumps(r,ensure_ascii=False)); assert r["passed"], r' "build/ui-artifacts/$ui_device/UITestReport.json"
