import Foundation
import SwiftData
import UIKit

/// 大模型返回的结构
struct AssistantResponse: Decodable {
    struct Action: Decodable {
        var op: String                 // create / update / delete
        var id: String?                // update/delete 时引用已有记录的短 id
        var kind: String?              // workout / meal
        var time: String?              // yyyy-MM-dd HH:mm（本地时间）
        var durationMin: Int?
        var category: String?
        var detail: String?
        var calories: Int?

        enum CodingKeys: String, CodingKey {
            case op, id, kind, time, category, detail, calories
            case durationMin = "duration_min"
        }
    }

    var reply: String
    var actions: [Action]

    enum CodingKeys: String, CodingKey { case reply, actions }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reply = (try? c.decode(String.self, forKey: .reply)) ?? ""
        actions = (try? c.decode([Action].self, forKey: .actions)) ?? []
    }

    /// 宽松解析：容忍 ```json 代码块包裹
    static func parse(_ raw: String) throws -> AssistantResponse {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = text.firstIndex(of: "{"), let e = text.lastIndex(of: "}") {
            text = String(text[s...e])
        }
        return try JSONDecoder().decode(AssistantResponse.self, from: Data(text.utf8))
    }

    static func parseTime(_ s: String?, now: Date = .now) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for fmt in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return ISO8601DateFormatter().date(from: s)
    }
}

/// 把对话/照片转成行为记录
@MainActor
struct RecordAssistant {
    let context: ModelContext
    let settings: AppSettings

    /// 处理一条用户消息：保存用户消息、调用豆包、落地记录、保存回复
    func handle(text: String, photo: Data?) async {
        let userMsg = ChatMessage(role: .user, text: text, photo: photo.flatMap(ImageCoder.forStorage))
        context.insert(userMsg)
        try? context.save()

        do {
            let client = DoubaoClient(apiKey: settings.apiKey, model: settings.model)
            let raw = try await client.complete(messages: buildMessages(text: text, photo: photo, current: userMsg))
            let response = try AssistantResponse.parse(raw)
            let ids = apply(response.actions, photo: photo)
            let reply = response.reply.isEmpty ? (ids.isEmpty ? "好的。" : "已记录。") : response.reply
            context.insert(ChatMessage(role: .assistant, text: reply, recordIDs: ids))
        } catch {
            context.insert(ChatMessage(role: .assistant, text: error.localizedDescription, isError: true))
        }
        try? context.save()
    }

    // MARK: - Prompt

    private func buildMessages(text: String, photo: Data?, current: ChatMessage) throws -> [[String: Any]] {
        var messages: [[String: Any]] = [["role": "system", "content": try systemPrompt()]]

        // 最近几轮对话，只带文字，帮助理解"刚才那个"之类的指代
        var history = FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        history.fetchLimit = 11
        let recent = try context.fetch(history).filter { $0.id != current.id && !$0.isError }.prefix(10).reversed()
        for m in recent where !m.text.isEmpty {
            messages.append(["role": m.role.rawValue, "content": m.text])
        }

        var content: [[String: Any]] = []
        if let photo, let jpeg = ImageCoder.forUpload(photo) {
            content.append(["type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]])
        }
        content.append(["type": "text", "text": text.isEmpty ? "（用户只发了一张照片，请识别并记录）" : text])
        messages.append(["role": "user", "content": content])
        return messages
    }

    private func systemPrompt() throws -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.dateFormat = "yyyy-MM-dd HH:mm EEEE"
        let now = fmt.string(from: .now)

        // 最近 3 天的记录，供修改/删除时引用
        let since = Calendar.current.date(byAdding: .day, value: -3, to: .now)!
        let desc = FetchDescriptor<BehaviorRecord>(predicate: #Predicate { $0.timestamp >= since },
                                                   sortBy: [SortDescriptor(\.timestamp)])
        let records = try context.fetch(desc)
        let t = DateFormatter()
        t.dateFormat = "yyyy-MM-dd HH:mm"
        let recordLines = records.map { r in
            var s = "- id=\(r.shortID) kind=\(r.kindRaw) time=\(t.string(from: r.timestamp)) category=\(r.category)"
            if let d = r.durationMinutes { s += " duration_min=\(d)" }
            if let c = r.calories { s += " calories=\(c)" }
            return s + " detail=\(r.detail)"
        }.joined(separator: "\n")

        return """
        你是一个减脂记录助手，把用户的口语描述或照片转成结构化记录。只记录两类行为：
        1. workout（健身）：开始时间点、持续分钟数、类型（如 跑步/力量训练/游泳/骑行/瑜伽/HIIT/散步），detail 写动作、组数、强度等补充信息，calories 为估算消耗（可省略）。
        2. meal（饮食）：用餐时间、餐次 category（早餐/午餐/晚餐/加餐/饮品），detail 写识别到的食物和分量，calories 为整餐总摄入千卡（必须给出估算整数）。

        当前本地时间：\(now)。用户没说时间就用当前时间；说"中午""昨晚"等请换算成具体时间。
        照片如果是食物，估算份量和热量；如果是健身相关（器械、运动 App 截图、手表截图），提取类型、时长、时间。
        一条消息里可以有多条记录。用户要求修改或删除已有记录时，用下面列表里的 id。
        如果用户只是闲聊或提问，actions 为空，正常简短回答。
        今日饮食摄入目标：\(settings.intakeTargetKcal) 千卡。

        最近 3 天已有记录：
        \(recordLines.isEmpty ? "（无）" : recordLines)

        只输出一个 JSON 对象，格式：
        {"reply":"给用户的一两句中文回复，可以包含估算依据","actions":[
          {"op":"create","kind":"meal","time":"2026-01-01 12:30","category":"午餐","detail":"牛肉面一碗(约400g)","calories":650},
          {"op":"create","kind":"workout","time":"2026-01-01 19:00","duration_min":40,"category":"跑步","detail":"5公里 配速7分"},
          {"op":"update","id":"ab12cd","calories":500},
          {"op":"delete","id":"ab12cd"}
        ]}
        """
    }

    // MARK: - Apply

    private func apply(_ actions: [AssistantResponse.Action], photo: Data?) -> [UUID] {
        let all = (try? context.fetch(FetchDescriptor<BehaviorRecord>())) ?? []
        func find(_ short: String?) -> BehaviorRecord? {
            guard let short = short?.lowercased(), !short.isEmpty else { return nil }
            return all.first { $0.shortID == short }
        }
        let thumb = photo.flatMap(ImageCoder.forStorage)
        var touched: [UUID] = []

        for a in actions {
            switch a.op.lowercased() {
            case "create":
                guard let kind = RecordKind(rawValue: a.kind?.lowercased() ?? "") else { continue }
                let r = BehaviorRecord(kind: kind,
                                       timestamp: AssistantResponse.parseTime(a.time) ?? .now,
                                       durationMinutes: kind == .workout ? a.durationMin : nil,
                                       category: a.category ?? kind.title,
                                       detail: a.detail ?? "",
                                       calories: a.calories,
                                       photo: thumb)
                context.insert(r)
                touched.append(r.id)
            case "update":
                guard let r = find(a.id) else { continue }
                if let t = AssistantResponse.parseTime(a.time) { r.timestamp = t }
                if let v = a.durationMin { r.durationMinutes = v }
                if let v = a.category { r.category = v }
                if let v = a.detail { r.detail = v }
                if let v = a.calories { r.calories = v }
                if let thumb, r.photo == nil { r.photo = thumb }
                touched.append(r.id)
            case "delete":
                guard let r = find(a.id) else { continue }
                context.delete(r)
            default:
                continue
            }
        }
        return touched
    }
}

enum ImageCoder {
    /// 上传给模型：长边 1024
    static func forUpload(_ data: Data) -> Data? { resized(data, maxSide: 1024, quality: 0.7) }
    /// 本地保存：长边 1600
    static func forStorage(_ data: Data) -> Data? { resized(data, maxSide: 1600, quality: 0.8) }

    private static func resized(_ data: Data, maxSide: CGFloat, quality: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return out.jpegData(compressionQuality: quality)
    }
}
