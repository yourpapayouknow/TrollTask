#!/usr/bin/env python3
# 验证工程身份、旧业务移除和系统窗口基础约束。
from pathlib import Path
import plistlib
import re


# 检查独立命名空间及签名身份。
def tstns():
    root = Path(__file__).resolve().parent.parent
    identity = "com.iwmei.taskforiwmei"
    info = plistlib.loads((root / "Resources/Info.plist").read_bytes())
    entitlements = plistlib.loads((root / "Resources/entitlements.plist").read_bytes())
    assert info["CFBundleIdentifier"] == entitlements["application-identifier"] == identity
    assert info["CFBundleDisplayName"] == info["CFBundleExecutable"] == "TrollTask"
    header = (root / "Sources/LBHead.h").read_text()
    assert f'{identity}.plist' in header and f'{identity}.hud.lock' in header
    names = re.findall(r'#define LB_\w+_NOTE "([^"]+)"', header)
    assert len(names) == len(set(names)) == 4
    assert all(name.startswith(identity + ".") for name in names)
    for key in ["com.apple.springboard.accessibility-window-hosting", "com.apple.QuartzCore.displayable-context",
                "com.apple.QuartzCore.secure-mode", "com.apple.private.persona-mgmt",
                "com.apple.private.security.no-sandbox"]:
        assert entitlements[key] is True
    # 平台App的原生导入需要读取所选iCloud源文件。
    assert entitlements["com.apple.private.security.storage.MobileDocuments"] is True
    # 系统采集必须能够写入本应用容器内的临时文件。
    assert entitlements["com.apple.private.security.storage.AppDataContainers"] is True
    # 检查平台应用的系统图像渲染权限。
    clients = entitlements.get("com.apple.security.exception.iokit-user-client-class", [])
    assert isinstance(clients, list) and {"AGXDeviceUserClient", "IOSurfaceRootUserClient", "IOSurfaceAcceleratorClient"} <= set(clients), \
        "Missing GPU access for CoreImage template rendering"
    return root


# 检查旧业务和命名空间没有进入运行工程。
def tstbiz(root):
    # 阶段九允许从绝对时刻显示边栏剩余时间，继续禁止旧业务及累加式NSTimer。
    forbidden = r'lowbatcntdwn|LowBat|LBState|LBMode|lb_(init|cfg|feed|tick|snzdur|chknght|shwnght|setlowpower)\b|UIDeviceBattery|batteryMonitoringEnabled|batteryLevel|CoreDuet|CDBatterySaver|NSTimer|nightLocked|threshold|低电量'
    paths = [path for path in (root / "Sources").glob("*") if path.is_file()]
    paths += list((root / "Resources").glob("*.plist")) + [root / "Makefile"]
    for path in paths:
        assert not re.search(forbidden, path.read_text(), re.I), f"Old business reference in {path}"
    assert not (root / "Sources/LBState.c").exists()
    assert not (root / "Sources/LBState.h").exists()


# 检查窗口安全性和私有框架启动顺序。
def tstarch(root):
    hud = (root / "Sources/LBHud.m").read_text()
    shared = (root / "Sources/LBShared.m").read_text()
    for text in ["SBSAccessibilityWindowHostingController", "registerWindowWithContextID:atLevel:",
                 "window.windowLevel = 10000010.0", "[[window _boundContext] setSecure:YES]",
                 "_isSecure { return YES; }", "_shouldCreateContextAsSecure { return YES; }"]:
        assert text in hud
    for text in ["posix_spawnattr_set_persona_np(&attr, 99", "posix_spawnattr_set_persona_uid_np(&attr, 0)",
                 "posix_spawnattr_set_persona_gid_np(&attr, 0)", "POSIX_SPAWN_SETPGROUP", '"--hud"', "LOCK_EX | LOCK_NB"]:
        assert text in shared
    # 原生入口负责事件源和帧调度，插件完成回调等待运行循环就绪。
    assert "UIApplicationMain(argc, argv, NSStringFromClass(LBHudApp.class), NSStringFromClass(LBHudDel.class))" in hud
    assert "dispatch_async(dispatch_get_main_queue(), ^{ lb_hudrun(self); });" in hud
    assert "[super _run];" in hud
    assert "UIApplicationInstantiateSingleton" not in hud and "GSEventRunModal" not in hud
    order = ["[self _accessibilityInit];", "lb_ldax();", "pBKSHID(lb_onhidevt);", "[app __completeAndRunAsPlugin];"]
    positions = [hud.index(text) for text in order]
    assert positions == sorted(positions)
    reminder = (root / "Sources/TaskReminder.swift").read_text()
    assert '"SBSpringBoardDidLaunchNotification"' in (root / "Sources/LBHead.h").read_text()
    assert "reg(TS_SB_LAUNCH)" in reminder and "halt(true)" in reminder and "DISPATCH_VNODE_DELETE" in hud


# 执行全部工程约束检查。
if __name__ == "__main__":
    project = tstns()
    tstbiz(project)
    tstarch(project)
    print("Namespace, business-removal and preserved HUD architecture checks passed")
