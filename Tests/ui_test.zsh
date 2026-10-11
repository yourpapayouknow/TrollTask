#!/bin/zsh
# 在指定已启动模拟器运行原生界面测试并复制结果。
set -euo pipefail
ui_device=${1:?请指定已启动模拟器UUID}
shift
ui_bundle=com.iwmei.taskforiwmei.uitest
xcrun simctl install "$ui_device" build/MobileUI.app
ui_data=$(xcrun simctl get_app_container "$ui_device" "$ui_bundle" data)
rm -f "$ui_data/Documents/UITestReport.json"
xcrun simctl launch --terminate-running-process --stdout=/tmp/trolltask-ui-stdout.log --stderr=/tmp/trolltask-ui-stderr.log "$ui_device" "$ui_bundle" "$@"
# 为原生键盘冷启动和调度集成保留有界等待，由执行工具异步收集。
for ui_attempt in {1..1500}; do
    [[ -f "$ui_data/Documents/UITestReport.json" ]] && break
    sleep 0.2
done
if [[ ! -f "$ui_data/Documents/UITestReport.json" ]]; then
    print -u2 -- "原生界面测试五分钟内未生成报告：$ui_data/Documents"
    exit 1
fi
mkdir -p "build/ui-artifacts/$ui_device"
cp -R "$ui_data/Documents/UITestReport.json" "$ui_data/Documents/screens" "build/ui-artifacts/$ui_device/"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(json.dumps({"passed":r["passed"],"checks":len(r["checks"]),"failure":r["failure"],"device":r["device"],"runtime":r["runtime"]},ensure_ascii=False)); assert r["passed"], r["failure"]' "build/ui-artifacts/$ui_device/UITestReport.json"
