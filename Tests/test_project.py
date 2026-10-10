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
    # 检查平台应用的系统图像渲染权限。
    clients = entitlements.get("com.apple.security.exception.iokit-user-client-class", [])
    assert isinstance(clients, list) and {"AGXDeviceUserClient", "IOSurfaceRootUserClient"} <= set(clients), \
        "Missing GPU access for CoreImage template rendering"
    return root


# 检查旧业务和命名空间没有进入运行工程。
def tstbiz(root):
    forbidden = r'lowbatcntdwn|LowBat|LBState|LBMode|lb_(init|cfg|feed|tick|snzdur|chknght|shwnght|setlowpower)\b|UIDeviceBattery|batteryMonitoringEnabled|batteryLevel|CoreDuet|CDBatterySaver|NSTimer|nightLocked|threshold|countdown|倒计时|低电量'
    paths = list((root / "Sources").glob("*")) + list((root / "Resources").glob("*.plist")) + [root / "Makefile"]
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
    order = ["gsInit();", "bksStart();", "uiInit();", "uiSingle([LBHudApp class]);", "[app _accessibilityInit];",
             "lb_ldax();", "if (pBKSHID) pBKSHID(lb_onhidevt);", "gsEvtInit(0);", "[app __completeAndRunAsPlugin];"]
    positions = [hud.index(text) for text in order]
    assert positions == sorted(positions)
    assert "SBSpringBoardDidLaunchNotification" in hud and "DISPATCH_VNODE_DELETE" in hud


# 执行全部工程约束检查。
if __name__ == "__main__":
    project = tstns()
    tstbiz(project)
    tstarch(project)
    print("Namespace, business-removal and preserved HUD architecture checks passed")
