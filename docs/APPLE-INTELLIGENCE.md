# 设备端 Apple Intelligence 调用

Apple 于 2026-10-31 公告首批国行功能自 2026-11-04 的开发者测试版开放。系统功能开放与第三方 Foundation Models 接口可用性需要分别确认，应用不按销售地区或系统版本字符串禁用设备端模式。

## 在 YIClass 中使用

1. 在系统“Apple Intelligence 与 Siri”开启功能并完成模型准备。
2. 设置 → AI 模式与接口配置 → 设备端 Apple Intelligence。
3. 点“重新检测设备端状态”，再点“测试设备端 AI”。测试只生成一条简短文本，不读取课表，不需要 API Key。
4. 保存配置后打开 AI 助手。右上“新对话”保存当前历史、取消旧请求并清空该对话的附件和方案，创建独立上下文。

应用先判断 `SystemLanguageModel.default.availability`，区分设备不支持、未启用和模型未就绪。返回前台时重新检测；可用后通过公开设备端接口生成：

```swift
let session = LanguageModelSession(instructions: "请使用简体中文，简短回答。")
let response = try await session.respond(to: "请只回复：设备端连接成功")
print(response.content)
```

AIService.reply 的设备端分支也使用该 API，传入本轮课表／日程快照并按现有协议校验模型返回；测试成功不代表复杂课表方案必然生成成功。没有自动切换至远程服务。CI 不具备真实国行设备或已准备的系统模型，SDK 编译检查不视为国行模型实测。

官方依据：[国行开放公告](https://www.apple.com.cn/newsroom/2026/10/apple-intelligence-features-are-coming-to-users-in-china/)、[SystemLanguageModel availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)、[LanguageModelSession 生成](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)。
