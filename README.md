<div align="center">

<img src="assets/readme-badge.png" alt="TrollTask项目横幅" />

# TrollTask

*面向 TrollStore 用户的本地优先待办与常律应用*

<img src="https://img.shields.io/badge/平台-iOS%2015%2B-blue.svg?style=flat-square" alt="平台：iOS 15以上" />
<img src="https://img.shields.io/badge/语言-Swift-orange.svg?style=flat-square" alt="语言：Swift" />
<img src="https://img.shields.io/badge/界面-UIKit-green.svg?style=flat-square" alt="界面：UIKit" />

</div>

---

面向 TrollStore 用户的本地优先待办与常律应用。任务、常律、归档与提醒保存在设备本机 SQLite 数据库，提醒由独立 HUD 进程按绝对时刻调度。

## 功能特性

| 能力 | 说明 |
| --- | --- |
| 今日律 | 汇总当天常律与到期任务，按实际起止排列，只读查看与原轮次补弹 |
| 常律 | 周期模板按周展示，支持导入周表、时段冲突校验与启停 |
| 清单 | 今日律、常律、星标与普通清单；日期、名称、紧急优先、困难优先四种排序 |
| 新建任务 | 贴键盘的快捷草稿，或进入创建管道填写字段、评估、预计分钟与子任务拆分 |
| 提醒 HUD | 独立进程全屏提醒，支持图片或文件打卡、五分钟延期、有限声振与抬腕静音 |
| 归档 | 完成记录与原附件保存在本机，可在归档内容中恢复或删除 |
| 云端同步 | WebDAV、Google Drive、OneDrive 与百度网盘，按所选顺序上传归档 |
| 设置 | 外观、任务时区、归档内容、归档设置、助手、运行日志与关于 |

## 快速开始

将以下内容发送给AI编程助手。

```text
帮我安装这个仓库并打开TrollTask
https://github.com/yourpapayouknow/TrollTask
```

## 传统开始

### 环境要求

| 设备 | 要求 |
| --- | --- |
| iPhone 或 iPad | iOS 15.0 起，已安装 [TrollStore](https://github.com/opa334/TrollStore#compatibility) |
| Mac | Xcode 命令行工具与 `make`，用于构建安装包 |
| 网络 | 只有局域网安装需要手机与 Mac 连接同一 Wi-Fi；USB 安装不需要 |

### 1. 获取代码并构建

```text
git clone https://github.com/yourpapayouknow/TrollTask.git
cd TrollTask
make check
make package
```

构建完成后生成 `build/TrollTask-<版本>.tipa`。

### 2. 安装应用

- 用 TrollStore 打开生成的 tipa 并覆盖安装；或
- 运行 `make serve`，在手机 Safari 打开终端打印的地址并点「立即安装」。

### 3. 首次启动

覆盖安装后冷启动应用，确保新版本生效。

## 使用指南

### 清单与排序

首页包含今日律、常律、星标与普通清单。普通清单底部左侧切换清单，右侧选择日期、名称、紧急优先或困难优先排序；排序只影响显示，不改变提醒时刻。

### 新建任务

底部中央加号打开贴键盘的快捷草稿，填写总标题与备注；点时钟展开日期窗口。点「下一步」进入创建管道第二页，补充紧急程度、难易程度、预计分钟与子任务拆分。

### 今日律与常律

今日律只读展示当天安排，点击圆圈可补弹原轮次 HUD。常律页签管理周期模板，支持从设置导入周表，导入前会校验时段冲突。

### 提醒 HUD

提醒到达时打开独立全屏 HUD。点「提交」进入打卡，可添加图片或文件附件后确认完成；点「延后5分钟」推迟当前轮次，每个轮次仅允许一次。

### 归档与云端同步

完成的任务与附件进入归档内容。在归档设置中配置 WebDAV、Google Drive、OneDrive 或百度网盘，并按顺序上传。

### 设置与运行日志

设置页可切换外观、任务时区、归档位置、助手连接与后台服务；运行日志保留最近 200 条界面错误、服务启停与调度失败记录，可复制或清空。

## 开发

### 构建与测试

| 命令 | 用途 |
| --- | --- |
| `make package` | 构建可安装的 TrollStore 包 |
| `make check` | 源码分层、布局与宿主测试门禁 |
| `make test` | 完整宿主测试 |
| `make test-ui` | 模拟器 UI 套件，需已启动模拟器 |
| `make icons` | 从 SVG 生成应用图标资源 |

### 目录

- `Sources/App`：应用生命周期、启动与代理。
- `Sources/Core`：SQLite 存储、任务领域、调度与共享配置。
- `Sources/Features`：首页、编辑器、HUD、归档与设置界面。
- `Sources/DesignSystem`：主题、基础控件与通用界面组件。
- `Sources/Support`：伞头、Swift 桥接、递归规则与触摸处理。
- `Tests`：宿主测试、CLI 测试与原生 UI 测试。
- `scripts`：构建、图标、安装与检查脚本。