import Foundation

public struct ChatImage: Equatable, Sendable {
    public var data: Data
    public var mimeType: String
    public init(data: Data, mimeType: String) { self.data = data; self.mimeType = mimeType }
    public var dataURL: String { "data:\(mimeType);base64," + data.base64EncodedString() }
}

public struct ChatMessage: Codable, Sendable, Identifiable {
    public var role: String
    public var content: String
    public var images: [ChatImage]
    public var id: String { role + content }
    public init(role: String, content: String, images: [ChatImage] = []) {
        self.role = role; self.content = content; self.images = images
    }
    private enum Keys: String, CodingKey { case role, content }
    private struct Part: Codable {
        struct ImageURL: Codable { var url: String; var detail: String = "high" }
        var type: String
        var text: String?
        var image_url: ImageURL?
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(role, forKey: .role)
        if images.isEmpty { try container.encode(content, forKey: .content) }
        else {
            guard role == "user" else { throw AppFailure("图片只能附在用户消息中。") }
            let parts = [Part(type: "text", text: content)] + images.map { Part(type: "image_url", image_url: .init(url: $0.dataURL)) }
            try container.encode(parts, forKey: .content)
        }
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        role = try container.decode(String.self, forKey: .role)
        images = []
        if let text = try? container.decode(String.self, forKey: .content) { content = text }
        else {
            let parts = try container.decode([Part].self, forKey: .content)
            content = parts.compactMap(\.text).joined(separator: "\n")
            for part in parts {
                guard let url = part.image_url?.url, url.hasPrefix("data:image/"), let comma = url.firstIndex(of: ","),
                      let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else { continue }
                let mime = String(url[url.index(url.startIndex, offsetBy: 5)..<comma]).replacingOccurrences(of: ";base64", with: "")
                images.append(ChatImage(data: data, mimeType: mime))
            }
        }
    }
}

public struct AIChatRequest: Encodable, Sendable {
    public let model: String
    public let messages: [ChatMessage]
    public let max_tokens: Int
    public let temperature = 0.2
    public let stream = false
    public struct Mode: Encodable, Sendable { public let type: String }
    public let thinking: Mode?
    public let response_format: Mode?
    public static func resolvedModel(_ model: String, endpoint: URL) -> String {
        if endpoint.host?.lowercased() == "api.deepseek.com", ["deepseek-chat", "deepseek-reasoner"].contains(model) { return "deepseek-flash" }
        return model
    }
    public init(model: String, messages: [ChatMessage], maxTokens: Int, endpoint: URL, testing: Bool = false) {
        self.model = Self.resolvedModel(model, endpoint: endpoint)
        self.messages = messages; max_tokens = maxTokens
        let officialDeepSeek = endpoint.host?.lowercased() == "api.deepseek.com"
        thinking = officialDeepSeek ? Mode(type: "disabled") : nil
        response_format = officialDeepSeek && !testing ? Mode(type: "json_object") : nil
    }
}

public enum AITransportFailure: Error { case truncated }

public enum AIChatResponse {
    public static func text(from data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { var content: String? }
                var message: Message
                var finish_reason: String?
            }
            var choices: [Choice]
        }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AppFailure("接口返回的格式不是 Chat Completions 响应，请检查接口地址。") }
        guard let choice = response.choices.first else { throw AppFailure("AI 没有返回回答，请重试。") }
        if choice.finish_reason == "length" { throw AITransportFailure.truncated }
        if choice.finish_reason == "content_filter" { throw AppFailure("本次内容被模型服务拦截，请修改说明后重试。") }
        guard let content = choice.message.content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppFailure("AI 未返回正文，可能只生成了推理内容。请重试或切换非推理模式。")
        }
        return content
    }
}
