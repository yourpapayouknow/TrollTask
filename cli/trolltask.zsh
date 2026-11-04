#!/bin/zsh
# 调用工程构建入口或设备内核心命令。
set -eu
project_dir=${0:A:h:h}
case "${1:-}" in
    test|test-assist|test-agenda|test-rule|test-queue|test-recover|test-load|test-occ|test-sched|test-reminder|test-checkin|package|inspect|clean|icons|serve)
        exec make -C "$project_dir" "$1"
        ;;
    start|hud|stop|preview)
        if [[ -z "${TROLLTASK_BIN:-}" ]]; then
            print -u2 -r -- '设备命令需要TROLLTASK_BIN指向已安装可执行文件'
            exit 2
        fi
        exec "$TROLLTASK_BIN" "--$1"
        ;;
    store)
        shift
        if [[ -n "${TROLLTASK_BIN:-}" ]]; then
            exec "$TROLLTASK_BIN" --store "$@"
        fi
        make -s -C "$project_dir" store >&2
        exec "$project_dir/build/taskstore" "$@"
        ;;
    *)
        print -r -- '用法：cli/trolltask.zsh test|test-assist|test-agenda|test-rule|test-queue|test-recover|test-load|test-occ|test-sched|test-reminder|test-checkin|package|inspect|clean|icons|serve|start|hud|stop|preview|store'
        exit 2
        ;;
esac
