#!/bin/zsh
# 构建并控制复用生产界面的独立模拟器调试入口。
set -euo pipefail
project_dir=${0:A:h:h}
debug_action=${1:-start}
debug_device=${2:-${UI_DEVICE:-}}
debug_bundle=com.iwmei.taskforiwmei.uitest
case "$debug_action" in
    start|stop) ;;
    *) print -u2 -r -- '用法：cli/huddebug.zsh [start|stop] [模拟器UUID]'; exit 2 ;;
esac
if [[ -z "$debug_device" ]]; then
    debug_device=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; devices=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d["name"].startswith("iPhone")]; devices.sort(key=lambda d:d["state"]!="Booted"); print(devices[0]["udid"] if devices else "")')
fi
if [[ -z "$debug_device" ]]; then
    print -u2 -r -- '没有可用iPhone模拟器，请先在Xcode安装运行时'
    exit 1
fi
if [[ "$debug_action" == stop ]]; then
    exec xcrun simctl terminate "$debug_device" "$debug_bundle"
fi
make -C "$project_dir" build/MobileUI.app/UItest
xcrun simctl bootstatus "$debug_device" -b
/usr/bin/open -a Simulator
xcrun simctl install "$debug_device" "$project_dir/build/MobileUI.app"
xcrun simctl launch --terminate-running-process --stdout="$project_dir/build/hud-debug-stdout.log" --stderr="$project_dir/build/hud-debug-stderr.log" "$debug_device" "$debug_bundle" --hud-inspect
debug_data=$(xcrun simctl get_app_container "$debug_device" "$debug_bundle" data)
print -r -- "模拟器：$debug_device" "独立数据库：$debug_data/Documents/HUDInspect.sqlite3" "日志：$project_dir/build/hud-debug-stderr.log"
