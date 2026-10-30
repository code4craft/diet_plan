import Foundation

/// 火山方舟 Chat Completions（OpenAI 兼容）客户端
struct DoubaoClient {
    var apiKey: String
    var model: String
    var endpoint = URL(string: "https://ark.cn-beijing.volces.com/api/v3/chat/completions")!

    enum ClientError: LocalizedError {
        case missingKey
        case http(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingKey: "还没有配置火山方舟 API Key，请到「设置」里填写。"
            case .http(let code, let body): "豆包接口错误 \(code)：\(body.prefix(300))"
            case .emptyResponse: "豆包没有返回内容"
            }
        }
    }

    /// messages 为 OpenAI 格式的消息数组；返回 assistant 文本
    func complete(messages: [[String: Any]], jsonMode: Bool = true) async throws -> String {
        guard !apiKey.isEmpty else { throw ClientError.missingKey }
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.2,
            // 记录解析不需要深度思考，关掉以降低延迟
            "thinking": ["type": "disabled"],
        ]
        if jsonMode { body["response_format"] = ["type": "json_object"] }

        var req = URLRequest(url: endpoint, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ClientError.http(code, String(data: data, encoding: .utf8) ?? "") }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String, !content.isEmpty
        else { throw ClientError.emptyResponse }
        return content
    }
}
