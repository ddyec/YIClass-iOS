# YIClass iOS

面向 **iOS / iPadOS 26+** 的 Swift 6、SwiftUI 原生课表，使用系统 Liquid Glass、WidgetKit 与深色模式。独立于旧 Flutter 仓库，沿用原图标与 Apache 2.0 协议。

## 3.1 更新

3.1.1 修复文件导入选择流程：使用原生文件选择器复制文档，关闭选择器后再读取并打开预览；后台协调读取文件提供器中的文档，读取期间显示进度，错误直接提示。PDF 类型也会按文件头识别。设置中的 JSON 导入使用同一路径。实际 Files 点击行为待用户实机验收。

- **桌面与锁屏小组件**：下一节课、当天课程、开课倒计时。跟随当前选中的课表，课程、时间设置、导入、AI 应用、撤销后同步刷新。
- **紧凑周／日视图**：日视图独立使用前一天／本日／后一天，点击日期展开原生日历。顶部控件合并，行高按可用高度调整，上午／下午／晚上分段。默认 10 节尽量在一屏内显示；小屏、大字号或更多课节时仍可滚动，所有课程可点击。冲突并排显示。
- **统一课节时间**：默认 **4 + 4 + 2**，每段数量可调。每节开始与结束在同一行。修改开始时间保留该节时长并顺移后续课程；修改结束时间联动后续开始／结束。统一时长与课间立即联动，午休与晚间间隔保留。增减分段节数时同步调整全部课表的节次编号；正在使用的课节不能直接删除。
- **完整导入**：设置 → AI 识别课表，支持截图、图片、PDF、TXT／CSV。PDF 保留星期列与跨页关系；可直接预览结构化课表，也可让已配置的 AI 继续整理。截图使用本机 Vision 识字并附带位置，交给 AI 恢复表格结构。识别源可检查、编辑，再生成方案；新建课表导入，不覆盖原有课表。
- **不丢未排课课程**：没有固定星期、节次的网课、军训等保留名称、教师、地点和周次，在列表的“未排时间”中查看、补充安排。导出再导入也会保留。
- **AI 配置精简**：DeepSeek 快捷设置、用当前未保存配置测试 API。自定义模式不显示／查询设备端兼容性；设备模型状态仅在进入对应配置或主动切换时检查。API Key 存入钥匙串。
- **AI 直接修改**：明确的增删／调课指令直接更新并原子保存课表 JSON，完成后说明变化，可以一键撤销。地点、教师可留空，结合设备日期、时区和学期理解“今天／明天／下周一”等表达。只有关键目标无法确定才追问；单纯咨询建议时给候选，导入新文件时仍保留预览。校验节次、周次与过期状态，截断输出不应用。
- 设置页减少卡片留白和说明。默认跟随系统深色，支持浅色／深色切换，启动背景也有深色资源。

## 导入这类教务 PDF

已将用户提供的两页 PDF 制成回归样本，移除学生姓名与学号；核对脱敏前后课程字符与位置一致。验收逐项比对 **21 条排课安排 + 5 门未排时间课程** 的课程名、教师、地点、星期、节次和周次，包含跨页、单双周、周末及同一课程不同教室。

PDF 未提供明确的学期第一周日期。预览中需要确认“开学日期”，默认继承当前学期；不能凭打印日期推断。所有导入默认沿用统一课节时间。

结构化 PDF 可在本机完成导入。AI 路径使用用户选定的本机模型或自定义接口；实际模型可能误读，因此文件导入保留预览；日常明确修改指令直接保存并提供撤销。图片、扫描 PDF 的文字和布局识别也受原文件清晰度影响。不直接解析 XLSX 或教务网页脚本。

测试方法与实际结果见 [验证记录](docs/VALIDATION.md)。构建通过、PDF 导入通过与真实 AI 服务实测是不同检查，未执行的项不会标为通过。

## 下载构建

**3.1.1 (3) iPhone 包已实际归档并校验**，源码 `c5e9716b5657cd5809355f8469422e94a662708a`，[构建记录](https://github.com/ddyec/YIClass-iOS/actions/runs/39704828963)。

| 产物 | 下载 |
| --- | --- |
| iPhone／iPad 未签名 IPA（含小组件） | [下载安装包](https://github.com/ddyec/YIClass-iOS/actions/runs/39704828963/artifacts/12393864999) |

后续可在 [Downloadable iOS builds](https://github.com/ddyec/YIClass-iOS/actions/workflows/build.yml) 运行新的构建：

- `YIClass-iOS26-unsigned-ipa`：iPhone／iPad arm64 IPA，**未签名**，安装前需用自己的 Apple 签名身份和描述文件签名。
- `YIClass-iOS26-simulator`：Mac 上的 iOS 26 模拟器 App，包含 arm64／x86_64。
- `YIClass-build-logs`：完整构建日志。构建包带清单和 SHA-256 校验文件，Artifacts 保存 30 天。

```bash
tar -xzf YIClass-iOS26-simulator.tar.gz
xcrun simctl install booted YIClass.app
xcrun simctl launch booted com.ddyec.YIClassNative
```

## Xcode 构建与签名

需要 Xcode 26+、iOS 26 SDK，无第三方依赖。

```bash
open YIClass.xcodeproj
```

选择 `YIClass` scheme。真机签名需要为 **YIClass 与 YIClassWidget 两个目标**配置自己的 Team、Bundle Identifier，并在两个目标启用同一个 App Group。默认共享组为 `group.com.ddyec.YIClassNative`，如需更改，同时修改两个 entitlements 与 `Sources/Shared/SharedLibrary.swift`。重新签名时必须保留小组件扩展和 App Group 权限，否则主程序与小组件无法共享数据。

本地完整课表仍保存在应用支持目录，WidgetKit 使用同一数据的共享快照；共享快照原子写入，在设备首次解锁后可供锁屏小组件读取。共享容器不可用时，设置会显示实际同步错误。

```bash
python3 scripts/validate_project.py
swift test
bash scripts/test-pdf.sh       # macOS：真实 PDFKit 提取与完整导入核对
bash scripts/test-store.sh     # 实际 JSON 文件保存、重启读取与撤销
bash scripts/package-build.sh device
bash scripts/package-build.sh simulator
```

工程由 `scripts/generate_project.py` 确定性生成，新增源文件后需重新生成。`Import and layout review` 工作流在 iOS 模拟器里操作 PDF 预览、导入、紧凑设置与周视图，并保存实际截图。

## 数据与 AI

所有课表共享一个 `TimeProfile`，新建继承当前学期，切换、普通导入、AI 方案均不会回退默认时间。旧 JSON 如果没有时间字段，缺失的信息无法恢复；补设一次后会持续沿用。导出包含统一时间；只有主动采用文件内时间才会更新全局设置。

数据采用原子保存与上一版备份，加载损坏数据时保留原文件并提供恢复。支持课程、日／周／列表、多课表、停课日、单双周、一次撤销。原 Isar 数据库不能直接读取。

“设置 → AI 模式与接口配置”可选择 Apple Intelligence 或 HTTPS OpenAI 兼容接口。DeepSeek 快捷配置为 `https://api.deepseek.com/chat/completions` / `deepseek-chat`。测试 API 仅发送连接检查，不上传课表；识别或对话时，会把相关资料和课表发送到所选远程服务。没有自动云端回退；请求拒绝重定向。Claude／Gemini 原生协议不在本版范围内。设备端需要兼容的机型、地区、语言和已下载模型；iOS 26 本身不保证可用。

## 代码与边界

```text
Sources/Core/    模型、统一时间、排课、PDF 解析、导入导出、AI 校验
Sources/App/     SwiftUI、PDFKit、Vision、Foundation Models、Keychain
Sources/Widget/  WidgetKit 桌面与锁屏扩展
Sources/Shared/  主程序与小组件共享数据
Tests/Core/     核心回归与人工核对的 PDF 期望数据
Tests/UI/       原生操作与截图
Tests/Fixtures/ 移除学生身份信息的原 PDF 样本
scripts/        工程生成、PDF 实测、产物校验与构建
```

真机签名安装、TestFlight、实际 Apple Intelligence 与自定义 AI 服务需要对应设备／凭证验收。旧版教务脚本仓库、直接网页导入与本地上课通知尚未迁移，不声称与旧版所有功能等价。

基于 [ddyec/YIClass](https://github.com/ddyec/YIClass) `c8f857828c236706afa745b7aea6435f9a428396` 重写，原仓库未修改。Apache License 2.0，保留 `Copyright 2025 wykwey`、原始图标与 Logo，见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。
