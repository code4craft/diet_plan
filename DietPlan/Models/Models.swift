import Foundation
import SwiftData

enum RecordKind: String, Codable, CaseIterable {
    case workout, meal

    var title: String { self == .workout ? "健身" : "饮食" }
    var symbol: String { self == .workout ? "figure.run" : "fork.knife" }
}

/// 一条行为记录（健身或饮食）。由对话/拍照经豆包解析生成。
@Model
final class BehaviorRecord {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    /// 健身：开始时间点；饮食：用餐时间
    var timestamp: Date
    /// 健身持续分钟数
    var durationMinutes: Int?
    /// 健身类型（跑步/力量…）或餐次（早餐/午餐…）
    var category: String
    /// 非结构描述：动作、食物明细等
    var detail: String
    /// 饮食摄入卡路里；健身为估算消耗（可空）
    var calories: Int?
    @Attribute(.externalStorage) var photo: Data?
    var createdAt: Date

    init(kind: RecordKind, timestamp: Date, durationMinutes: Int? = nil, category: String,
         detail: String, calories: Int? = nil, photo: Data? = nil) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.timestamp = timestamp
        self.durationMinutes = durationMinutes
        self.category = category
        self.detail = detail
        self.calories = calories
        self.photo = photo
        self.createdAt = .now
    }

    var kind: RecordKind { RecordKind(rawValue: kindRaw) ?? .meal }
    /// 给大模型引用的短 id
    var shortID: String { String(id.uuidString.prefix(6)).lowercased() }
}

enum ChatRole: String, Codable { case user, assistant }

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var text: String
    @Attribute(.externalStorage) var photo: Data?
    var createdAt: Date
    /// 这条回复创建/修改过的记录
    var recordIDs: [UUID]
    var isError: Bool

    init(role: ChatRole, text: String, photo: Data? = nil, recordIDs: [UUID] = [], isError: Bool = false) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.text = text
        self.photo = photo
        self.createdAt = .now
        self.recordIDs = recordIDs
        self.isError = isError
    }

    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .user }
}
