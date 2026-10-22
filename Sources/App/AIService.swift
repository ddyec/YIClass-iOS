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

struct ChatMessage: Codable, Sendable, Identifiable {
    var role: String
    var content: String
    var id: String { role + content }
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
        let context = try AssistantPrompt.context(table: table, profile: profile)
        let output: String
        switch mode {
        case .onDevice:
            guard case .available = SystemLanguageModel.default.availability else { throw AppFailure(availability) }
            let session = LanguageModelSession(instructions: AssistantPrompt.instructions)
            let conversation = messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
            let response = try await session.respond(to: context + "\n对话：\n" + conversation)
            output = response.content
        case .remote:
            output = try await remote(messages: [ChatMessage(role: "system", content: AssistantPrompt.instructions + "\n" + context)] + messages,
                                      endpoint: endpoint, model: model, key: APIKeyStore.read())
        }
        try Task.checkCancellation()
        return try AssistantReply.parse(output, table: table, profile: profile)
    }
    static func test(endpoint: String, model: String, key: String) async throws -> String {
        let result = try await remote(messages: [ChatMessage(role: "user", content: "请只回复 OK")],
                                      endpoint: endpoint, model: model, key: key, testing: true)
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure("接口返回空内容。") }
        return "连接成功 · \(model)"
    }
    private static func remote(messages: [ChatMessage], endpoint: String, model: String, key: String,
                               testing: Bool = false) async throws -> String {
            guard let components = URLComponents(string: endpoint), components.scheme == "https",
                  components.host != nil, components.user == nil, components.password == nil,
                  let url = components.url, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppFailure("请配置完整的 HTTPS Chat Completions 地址和模型名。")
            }
            guard !key.isEmpty else { throw AppFailure("请先在设置中保存 API Key。") }
            struct Request: Encodable { var model: String; var messages: [ChatMessage]; var temperature = 0.2; var max_tokens: Int }
            let body = Request(model: model, messages: messages, max_tokens: testing ? 32 : 6000)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"; request.timeoutInterval = 60
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(body)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForResource = 65
            let session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AppFailure("AI 请求失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)），请核对接口、额度及模型。")
            }
            guard data.count <= 2_000_000 else { throw AppFailure("AI 返回内容过大。") }
            struct Response: Decodable {
                struct Choice: Decodable { struct Message: Decodable { var content: String }; var message: Message }
                var choices: [Choice]
            }
            guard let content = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content else {
                throw AppFailure("AI 未返回有效内容。")
            }
            return content
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
