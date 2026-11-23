![TrollTask](assets/readme-badge.png)

# TrollTask

<div align="center">
  <img alt="平台-iOS15" src="https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-iOS%2015-111111?logo=apple&logoColor=white">
  <img alt="界面-UIKit" src="https://img.shields.io/badge/%E7%95%8C%E9%9D%A2-UIKit-2396F3">
  <img alt="语言-Swift" src="https://img.shields.io/badge/%E8%AF%AD%E8%A8%80-Swift-F05138?logo=swift&logoColor=white">
  <img alt="存储-SQLite" src="https://img.shields.io/badge/%E5%AD%98%E5%82%A8-SQLite-003B57?logo=sqlite&logoColor=white">
  <img alt="安装-TrollStore" src="https://img.shields.io/badge/%E5%AE%89%E8%A3%85-TrollStore-FF6B35">
</div>

TrollTask 是运行于 iOS 15+ 的本地优先待办与常律应用，通过 TrollStore 安装。任务、常律、归档与提醒保存在设备本机 SQLite 数据库，提醒由独立 HUD 进程按绝对时刻调度。

## 功能

- 今日律、常律、星标与普通清单，支持日期、名称、紧急程度、难易程度四种显示排序。
- 快捷新建与创建管道：标题、备注、日期窗口、评估、预计分钟与子任务拆分。
- 独立提醒 HUD：图片或文件打卡、五分钟延期、声振与抬腕静音。
- 归档与云端同步：WebDAV、Google Drive、OneDrive 与百度网盘。
- 常律周表导入、时段冲突校验与今日安排。
- 设置：外观、任务时区、归档内容、归档设置、助手、运行日志与关于。

## 环境要求

- macOS 与 Xcode 命令行工具。
- iOS 15.0 及以上，设备已安装 TrollStore。
- 构建只依赖系统 SDK 与仓库内源码，无需包管理器。

## 快速开始

将以下内容发送给AI编程助手。

```text
帮我安装这个仓库并打开TrollTask
https://github.com/yourpapayouknow/TrollTask
```

## 传统开始

1. 克隆仓库并进入项目目录。
2. 运行 `make check` 验证源码分层、图标资源与宿主测试。
3. 运行 `make package`，生成 `build/TrollTask-<版本>.tipa`。
4. 安装到设备：
   - 用 TrollStore 打开生成的 tipa；或
   - 运行 `make serve`，在手机 Safari 打开终端打印的地址并点「立即安装」。
5. 覆盖安装后冷启动应用，确保新版本生效。

## 构建与测试

| 命令 | 用途 |
| --- | --- |
| `make package` | 构建可安装的 TrollStore 包 |
| `make check` | 源码分层、布局与宿主测试门禁 |
| `make test` | 完整宿主测试 |
| `make test-ui` | 模拟器 UI 套件，需已启动模拟器 |
| `make icons` | 从 SVG 生成 1024 母图与图标资源 |

## 目录

- `Sources/App`：应用生命周期、启动与代理。
- `Sources/Core`：SQLite 存储、任务领域、调度与共享配置。
- `Sources/Features`：首页、编辑器、HUD、归档与设置界面。
- `Sources/DesignSystem`：主题、基础控件与通用界面组件。
- `Sources/Support`：伞头、Swift 桥接、递归规则与触摸处理。
- `Tests`：宿主测试、CLI 测试与原生 UI 测试。
- `scripts`：构建、图标、安装与检查脚本。

## 第三方组件

- MingCute 图标，Apache-2.0。
- libical，LGPL-2.1 / MPL-2.0。