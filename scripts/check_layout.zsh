#!/bin/zsh
# 检查源码分层、根目录文件与 Apple Design skill 是否就位。
set -euo pipefail
cd "${0:A:h:h}"

typeset -a required=(
    App
    Core/Data
    Core/Domain
    Core/Infrastructure
    Features
    DesignSystem
    Support
    Support/Recurrence
    Support/Touch
)
for directory in "${required[@]}"; do
    if [[ ! -d "Sources/$directory" ]]; then
        print -u2 -- "缺少 Sources/$directory"
        exit 1
    fi
done

typeset -a root_files
root_files=("${(@f)$(find Sources -maxdepth 1 -type f)}")
root_files=(${root_files:#})
if (( ${#root_files} )); then
    print -u2 -- "Sources 根目录只允许目录：${(j:, :)root_files}"
    exit 1
fi

typeset -a stray_swift
stray_swift=("${(@f)$(find Sources -name '*.swift' -not -path 'Sources/App/*' -not -path 'Sources/Core/*' -not -path 'Sources/Features/*' -not -path 'Sources/DesignSystem/*' -not -path 'Sources/Support/*')}")
stray_swift=(${stray_swift:#})
if (( ${#stray_swift} )); then
    print -u2 -- "Swift 文件未落在分层目录：${(j:, :)stray_swift}"
    exit 1
fi

if [[ -d Vendor ]]; then
    print -u2 -- "Vendor 目录应归入 Sources/Support"
    exit 1
fi

if [[ ! -f "$HOME/.local/skills/apple-design/SKILL.md" ]]; then
    print -u2 -- "apple-design skill 未安装：~/.local/skills/apple-design/SKILL.md"
    exit 1
fi

[[ -f Resources/AppIcon-source.svg ]] || {
    print -u2 -- "缺少 Resources/AppIcon-source.svg"
    exit 1
}
iconset=Resources/Assets.xcassets/AppIcon.appiconset
[[ -f "$iconset/AppIcon-1024.png" ]] || {
    print -u2 -- "缺少 $iconset/AppIcon-1024.png"
    exit 1
}
grep -q '"platform" : "ios"' "$iconset/Contents.json" || {
    print -u2 -- "AppIcon 必须使用单尺寸 iOS 图标"
    exit 1
}
for icon in "$iconset"/*.png; do
    alpha=$(sips -g hasAlpha "$icon" 2>/dev/null | awk '/hasAlpha/{print $2}')
    [[ "$alpha" == "no" ]] || {
        print -u2 -- "$icon 仍带 alpha 通道"
        exit 1
    }
done

print "布局检查通过"