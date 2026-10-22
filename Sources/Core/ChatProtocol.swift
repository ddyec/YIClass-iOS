import Foundation

public struct ChatImage: Equatable, Sendable {
    public var data: Data
    public var mimeType: String
    public init(data: Data, mimeType: String) { self.data = data; self.mimeType = mimeType }
    public var dataURL: String { "data:\(mimeType);base64," + data.base64EncodedString() }
}

public struct ChatToolCall: Codable, Sendable {
    public struct Function: Codable, Sendable { public var name: String; public var arguments: String }
    public var id: String
    public var type: String
    public var function: Function
}

public struct ChatMessage: Codable, Sendable, Identifiable {
    public var role: String
    public var content: String
    public var images: [ChatImage]
    public var tool_calls: [ChatToolCall]?
    public var tool_call_id: String?
    public var id: String { role + content }
    public init(role: String, content: String, images: [ChatImage] = [], toolCalls: [ChatToolCall]? = nil, toolCallID: String? = nil) {
        self.role = role; self.content = content; self.images = images; tool_calls = toolCalls; tool_call_id = toolCallID
    }
    private enum Keys: String, CodingKey { case role, content, tool_calls, tool_call_id }
    private struct Part: Codable {
        struct ImageURL: Codable { var url: String; var detail: String = "high" }
        var type: String
        var text: String?
        var image_url: ImageURL?
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(tool_calls, forKey: .tool_calls)
        try container.encodeIfPresent(tool_call_id, forKey: .tool_call_id)
        if images.isEmpty {
            if content.isEmpty && !(tool_calls ?? []).isEmpty { try container.encodeNil(forKey: .content) }
            else { try container.encode(content, forKey: .content) }
        }
        else {
            guard role == "user" else { throw AppFailure("图片只能附在用户消息中。") }
            let parts = [Part(type: "text", text: content)] + images.map { Part(type: "image_url", image_url: .init(url: $0.dataURL)) }
            try container.encode(parts, forKey: .content)
        }
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "assistant"
        images = []
        tool_calls = try container.decodeIfPresent([ChatToolCall].self, forKey: .tool_calls)
        tool_call_id = try container.decodeIfPresent(String.self, forKey: .tool_call_id)
        if !container.contains(.content), !(tool_calls ?? []).isEmpty { content = ""; return }
        if container.contains(.content), try container.decodeNil(forKey: .content) { content = ""; return }
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
    public let tools: [AssistantToolDefinition]?
    public let tool_choice: String?
    public static func resolvedModel(_ model: String, endpoint: URL) -> String {
        if endpoint.host?.lowercased() == "api.deepseek.com", ["deepseek-chat", "deepseek-reasoner"].contains(model) { return "deepseek-flash" }
        return model
    }
    public init(model: String, messages: [ChatMessage], maxTokens: Int, endpoint: URL, testing: Bool = false, tools: [AssistantToolDefinition]? = nil, requireTool: Bool = false) {
        self.model = Self.resolvedModel(model, endpoint: endpoint)
        self.messages = messages; max_tokens = maxTokens; self.tools = tools
        tool_choice = tools != nil && requireTool ? "required" : nil
        let officialDeepSeek = endpoint.host?.lowercased() == "api.deepseek.com"
        thinking = officialDeepSeek ? Mode(type: "disabled") : nil
        response_format = officialDeepSeek && !testing ? Mode(type: "json_object") : nil
    }
}

public enum AITransportFailure: Error { case truncated }

public enum AIChatResponse {
    public static func text(from data: Data) throws -> String {
        let message = try turn(from: data)
        guard (message.tool_calls ?? []).isEmpty else { throw AppFailure("AI 返回了工具请求，需先获取课表数据。") }
        return message.content
    }
    public static func turn(from data: Data) throws -> ChatMessage {
        struct Response: Decodable {
            struct Choice: Decodable {
                var message: ChatMessage
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
        if let calls = choice.message.tool_calls, !calls.isEmpty {
            guard calls.count <= 8, Set(calls.map(\.id)).count == calls.count,
                  calls.allSatisfy({ !$0.id.isEmpty && $0.type == "function" && $0.function.arguments.utf8.count <= 50_000 }) else { throw AppFailure("AI 工具调用格式无效。") }
            return choice.message
        }
        guard !choice.message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppFailure("AI 未返回正文，可能只生成了推理内容。请重试或切换非推理模式。")
        }
        return choice.message
    }
}
