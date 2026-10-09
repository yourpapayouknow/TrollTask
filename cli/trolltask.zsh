#!/bin/zsh
# 调用工程构建入口或设备内核心命令。
set -eu
project_dir=${0:A:h:h}
case "${1:-}" in
    test|package|inspect|clean|icons|serve)
        exec make -C "$project_dir" "$1"
        ;;
    start|hud|stop|preview)
        if [[ -z "${TROLLTASK_BIN:-}" ]]; then
            print -u2 -r -- '设备命令需要TROLLTASK_BIN指向已安装可执行文件'
            exit 2
        fi
        exec "$TROLLTASK_BIN" "--$1"
        ;;
    *)
        print -r -- '用法：cli/trolltask.zsh test|package|inspect|clean|icons|serve|start|hud|stop|preview'
        exit 2
        ;;
esac
