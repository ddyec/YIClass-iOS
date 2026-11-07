# YIClass iOS

面向 **iOS / iPadOS 26+** 的原生课表与日程应用，使用 Swift 6 与 SwiftUI 从零编写，适配系统 Liquid Glass（液态玻璃）材质、深浅色主题、桌面/锁屏小组件与灵动岛实时活动。

本项目独立于旧版 Flutter 仓库，采用全新设计的书页课表图标，沿用 Apache 2.0 开源协议。

---

## 主要功能

- **多视图课表**：
  - **周视图**：紧凑展示整周课程，自动根据屏幕高度调整行高；当前周无晚课时自动折叠晚间时段，也可手动展开。支持单双周、多课表切换、调休停课与撞课并排展示。
  - **日视图与日程时间轴**：按半小时刻度与实时时间线展示当天的课程与已安排工作时间的待办事项，一眼看清全天节奏。
  - **列表视图**：集中管理所有已排课程与暂未固定时间的课程（如网课、实践周、军训等），导入导出均不会丢失未排课项目。
- **待办事项（To-Do）**：
  - 支持设置截止时间（Deadline）、具体执行时间段与重要程度，按逾期、今日、近三日、远期和无期限自动分组排序。
  - 可直接在 AI 助手中用自然语言添加（例如“帮我记一下下次实验课前交实验报告”），AI 会自动结合当前课表推算下一次上课时间并生成待办。
- **桌面小组件、锁屏组件与灵动岛**：
  - **桌面与锁屏小组件**：展示当前/下一节课、上课地点、倒计时以及待办清单，当天课程结束后自动在晚间切换至明日预览。
  - **实时活动（Live Activities）**：在临近上课及上课期间自动开启锁屏与灵动岛实时活动，展示课程进度、教室与分段倒计时，无需配置远程推送服务器。
- **AI 识表与对话改课**：
  - 支持导入**教务系统 PDF、课表截图、图片、TXT / CSV**。结构化 PDF 可直接在本地解析，图片可结合本机 Vision OCR 或视觉大模型恢复表格结构，预览确认后再导入。
  - 支持通过自然语言直接调课、增删课程或修改时间（例如“把这周五的课搬到周日”），支持一键撤销与最多 30 个历史恢复点。
- **自由配色与统一作息时间**：
  - 支持自定义主题色、背景渐变与单门课程配色。
  - 默认采用 **4 + 4 + 2**（上午/下午/晚上）作息结构，修改单节课时长或开始时间时可自动顺移后续课节。

---

## 下载与安装

最新构建的待重签真机安装包可在 GitHub Actions 中获取：

| 版本 | 说明 | 下载链接 |
| --- | --- | --- |
| **v3.3.0 (29)** | iPhone / iPad 待重签 IPA（含课表与待办小组件） | [Actions 构建页下载](https://github.com/ddyec/YIClass-iOS/actions/runs/41827248978) |
| **v3.1.13 (15)** | main 分支归档版本 | [Actions 构建页下载](https://github.com/ddyec/YIClass-iOS/actions/runs/39745484870) |

你也可以在 [Build Workflow](https://github.com/ddyec/YIClass-iOS/actions/workflows/build.yml) 中随时触发新的构建。

> **签名提示**：下载的 IPA 使用临时签名以保留 App Group 声明。使用自签工具（如全能签、Feather、SideStore 等）或 Xcode 安装到真机时，请确保主程序与扩展都保留同一个 App Group 权限，否则桌面/锁屏小组件将无法读取主程序的课表数据。

---

## 本地构建与开发

环境要求：**Xcode 26+**、**iOS 26 SDK**，无第三方依赖。

```bash
open YIClass.xcodeproj
```

在 Xcode 中选择 `YIClass` Scheme。真机运行时，请为 `YIClass` 和 `YIClassWidget` 两个 Target 配置你自己的 Apple Team 与 Bundle Identifier，并启用相同的 App Group（默认为 `group.com.ddyec.YIClassNative`）。

常用命令行检查与打包脚本：

```bash
python3 scripts/validate_project.py   # 校验工程结构与资源
swift test                            # 运行核心单元测试
bash scripts/test-pdf.sh              # 测试教务 PDF 提取与解析（macOS）
bash scripts/test-store.sh            # 测试 JSON 原子存储与撤销恢复
bash scripts/package-build.sh device  # 归档并打包真机 IPA
```

> 新增或删除源码文件后，可运行 `python3 scripts/generate_project.py` 重新生成确定性的 Xcode 工程文件。

---

## 数据存储与 AI 配置

- **本地数据安全**：所有课表与待办数据均保存在设备本地（支持原子写入与自动备份恢复），通过 App Group 共享快照供小组件读取。
- **AI 接口选择**：在“设置 → AI 模式与接口配置”中可选择：
  - **Apple Intelligence（设备端模型）**：在支持 Foundation Models 的机型与系统上直接本地调用，无需 API Key（详见 [设备端调用说明](docs/APPLE-INTELLIGENCE.md)）。
  - **OpenAI 兼容接口**：内置 DeepSeek 快捷预设（`https://api.deepseek.com/chat/completions`），也可自定义任意支持 Chat Completions 的服务地址。API Key 仅保存在系统钥匙串（Keychain）中。

---

## 目录结构

```text
Sources/Core/     数据模型、作息时间、排课逻辑、PDF 解析、导入导出、AI 工具校验
Sources/App/      SwiftUI 界面、PDFKit、Vision 识字、Foundation Models、钥匙串管理
Sources/Widget/   WidgetKit 桌面/锁屏小组件与灵动岛实时活动
Sources/Shared/   主程序与小组件的数据共享层
Tests/            核心回归测试、脱敏 PDF 样本与 UI 测试
scripts/          工程生成、图标处理、自动化测试与打包脚本
```

更多说明文档：
- [日程与待办数据结构](docs/DAY-AGENDA.md)
- [实时活动与灵动岛说明](docs/LIVE-ACTIVITIES.md)
- [设备端 AI 调用说明](docs/APPLE-INTELLIGENCE.md)
- [测试与验证记录](docs/VALIDATION.md)

---

## 开源协议

本项目基于 [ddyec/YIClass](https://github.com/ddyec/YIClass) 重写，采用 [Apache License 2.0](LICENSE) 开源协议，保留原作者版权声明（详见 [NOTICE](NOTICE)）。
