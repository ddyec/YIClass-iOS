import Foundation
import FoundationModels
import Security
import Vision
import ImageIO
import YIClassCore

enum AssistantMode: String, CaseIterable { case onDevice = "设备端 Apple Intelligence", remote = "自定义 AI 接口" }

enum APIKeyStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.ddyec.YIClass.ai",
         kSecAttrAccount as String: "api-key"]
    }
    static func read() throws -> String {
        var request = query
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw AppFailure("无法读取钥匙串中的 API Key（\(status)）。")
        }
        return value
    }
    static func save(_ value: String) throws {
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AppFailure("删除 API Key 失败。") }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppFailure("保存 API Key 失败（\(status)）。") }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor enum AIService {
    static var availability: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "设备端模型可用，课程与对话留在本机。"
        case .unavailable: return "设备端模型暂不可用。请检查机型、Apple Intelligence 开关、语言与模型下载状态，或配置自定义接口。"
        @unknown default: return "请检查设备端模型状态，或配置自定义接口。"
        }
    }
    static func reply(mode: AssistantMode, messages: [ChatMessage], table: Timetable, profile: TimeProfile,
                      endpoint: String, model: String) async throws -> AssistantReply {
        let context = try AssistantPrompt.context(table: table, profile: profile, focusText: messages.suffix(20).map(\.content).joined(separator: "\n"))
        switch mode {
        case .onDevice:
            guard case .available = SystemLanguageModel.default.availability else { throw AppFailure(availability) }
            let session = LanguageModelSession(instructions: AssistantPrompt.instructions)
            let conversation = messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
            let response = try await session.respond(to: "对话：\n" + conversation + "\n以下为本次执行前的权威数据，优先于历史方案：\n" + context)
            try Task.checkCancellation()
            return try AssistantReply.parse(response.content, table: table, profile: profile)
        case .remote:
            var turns = [ChatMessage(role: "system", content: AssistantPrompt.instructions + "\n" + context)] + messages
            var queriedDates = Set<String>()
            var repaired = false
            let requireLookup = AssistantTools.needsLookup(messages.last(where: { $0.role == "user" })?.content ?? "")
            for round in 0..<6 {
                let turn = try await remoteTurn(messages: turns, endpoint: endpoint, model: model, key: APIKeyStore.read(), tools: AssistantTools.definitions, requireTool: round == 0 && requireLookup)
                try Task.checkCancellation()
                if let calls = turn.tool_calls, !calls.isEmpty {
                    turns.append(turn)
                    for call in calls {
                        let content: String
                        do {
                            content = try AssistantTools.execute(call, table: table, profile: profile)
                            if call.function.name == "get_schedule_dates",
                               let args = try? JSONDecoder().decode([String: [String]].self, from: Data(call.function.arguments.utf8)) {
                                queriedDates.formUnion(args["dates"] ?? [])
                            }
                        } catch {
                            let data = try JSONEncoder().encode(["error": error.localizedDescription, "applied": "false"])
                            content = String(decoding: data, as: UTF8.self)
                        }
                        turns.append(ChatMessage(role: "tool", content: content, toolCallID: call.id))
                    }
                    continue
                }
                do {
                    let reply = try AssistantReply.parse(turn.content, table: table, profile: profile)
                    let requiredDates = Set(reply.plans.flatMap { $0.dateMoves ?? [] }.flatMap { [$0.from, $0.to] })
                    guard requiredDates.isSubset(of: queriedDates) else { throw AppFailure("请先调用 get_schedule_dates 查询所有调课源日和目标日，再返回方案。") }
                    return reply
                } catch {
                    guard !repaired else { throw error }
                    repaired = true
                    turns.append(turn)
                    turns.append(ChatMessage(role: "user", content: "方案校验未通过，尚未保存任何修改：" + error.localizedDescription + " 请依据本次权威课表修正；整天调课使用 dateMoves，其他修改保留全部现有课程和 UUID。"))
                }
            }
            throw AppFailure("本次查询次数已达上限，未应用任何修改。请缩小日期范围后重试。")
        }
    }
    static func test(endpoint: String, model: String, key: String) async throws -> String {
        let result = try await remoteTurn(messages: [ChatMessage(role: "user", content: "请只回复 OK")],
                                      endpoint: endpoint, model: model, key: key, testing: true)
        guard !result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure("接口返回空内容。") }
        return "连接成功 · \(model)"
    }
    private static func remoteTurn(messages: [ChatMessage], endpoint: String, model: String, key: String,
                               testing: Bool = false, tools: [AssistantToolDefinition]? = nil, requireTool: Bool = false) async throws -> ChatMessage {
            let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let components = URLComponents(string: endpoint), components.scheme == "https",
                  components.host != nil, components.user == nil, components.password == nil,
                  let url = components.url, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppFailure("请配置完整的 HTTPS Chat Completions 地址和模型名。")
            }
            guard !key.isEmpty else { throw AppFailure("请先在设置中保存 API Key。") }
            guard messages.flatMap(\.images).reduce(0, { $0 + $1.data.count }) <= 30_000_000 else {
                throw AppFailure("本轮对话的原图合计过大，请开始新对话后重试。")
            }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = 190
            let session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            for attempt in 0..<2 {
                try Task.checkCancellation()
                let budget = testing ? 64 : (attempt == 0 ? 16_384 : 32_768)
                let body = AIChatRequest(model: model, messages: messages, maxTokens: budget, endpoint: url, testing: testing, tools: tools, requireTool: requireTool)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"; request.timeoutInterval = 180
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONEncoder().encode(body)
                guard (request.httpBody?.count ?? 0) <= 45_000_000 else { throw AppFailure("图片与对话合计过大，请开始新对话或减少图片。") }
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    struct ServiceError: Decodable { struct Detail: Decodable { var message: String? }; var error: Detail? }
                    let detail = (try? JSONDecoder().decode(ServiceError.self, from: data))?.error?.message ?? "请核对接口、额度及模型。"
                    let safeDetail = String(detail.replacingOccurrences(of: key, with: "[已隐藏]").prefix(350))
                    let imageHint = messages.contains { !$0.images.isEmpty } ? " 请确认所选模型支持图片；DeepSeek 官方可选 deepseek-flash。" : ""
                    throw AppFailure("AI 请求失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）：\(safeDetail)" + imageHint)
                }
                guard data.count <= 4_000_000 else { throw AppFailure("AI 返回内容过大。") }
                do { return try AIChatResponse.turn(from: data) }
                catch AITransportFailure.truncated {
                    if attempt == 1 || testing { throw AppFailure("AI 回答仍达到输出上限，未应用任何更改。请减少本次修改范围后重试。") }
                }
            }
            throw AppFailure("AI 未完成回答，请重试。")
    }

}

enum ImageTextRecognition {
    static func recognize(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard data.count <= 20_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 3000] as CFDictionary) else {
                throw AppFailure("无法读取图片，请选择 20 MB 以下的课表截图。")
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = request.results?.sorted { a, b in
                if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.015 { return a.boundingBox.midY > b.boundingBox.midY }
                return a.boundingBox.minX < b.boundingBox.minX
            }.compactMap { observation -> String? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox
                return String(format: "[x=%.3f y=%.3f w=%.3f h=%.3f] %@", box.minX, 1 - box.maxY, box.width, box.height, text)
            }.joined(separator: "\n") ?? ""
            guard !text.isEmpty else { throw AppFailure("没有识别到文字，请选择更清晰的课表截图。") }
            return text
        }.value
    }
}
