import Foundation
import Security
import SwiftUI

/// 用户可调的目标和 AI 配置。API Key 单独放 Keychain。
@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    var sleepTargetHours: Double { didSet { defaults.set(sleepTargetHours, forKey: "sleepTargetHours") } }
    var intakeTargetKcal: Int { didSet { defaults.set(intakeTargetKcal, forKey: "intakeTargetKcal") } }
    var weeklyWorkoutTarget: Int { didSet { defaults.set(weeklyWorkoutTarget, forKey: "weeklyWorkoutTarget") } }
    /// 积分从这一天开始累计
    var scoreStartDate: Date { didSet { defaults.set(scoreStartDate, forKey: "scoreStartDate") } }
    var model: String { didSet { defaults.set(model, forKey: "model") } }
    var apiKey: String { didSet { Keychain.set(apiKey, for: "arkApiKey") } }
    /// 火山语音识别 API Key（新版控制台）
    var asrToken: String { didSet { Keychain.set(asrToken, for: "asrToken") } }

    static let defaultModel = "doubao-seed-2-1-pro-260915"

    /// 本地 Config/Secrets.xcconfig 注入到 Info.plist 的预置值（未配置时为 nil）
    private static func bundled(_ key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !v.isEmpty, !v.hasPrefix("$(") else { return nil }
        return v
    }

    private init() {
        defaults.register(defaults: [
            "sleepTargetHours": 7.0,
            "intakeTargetKcal": 1800,
            "weeklyWorkoutTarget": 3,
            "model": Self.defaultModel,
        ])
        sleepTargetHours = defaults.double(forKey: "sleepTargetHours")
        intakeTargetKcal = defaults.integer(forKey: "intakeTargetKcal")
        weeklyWorkoutTarget = defaults.integer(forKey: "weeklyWorkoutTarget")
        model = defaults.string(forKey: "model") ?? Self.defaultModel
        apiKey = Keychain.get("arkApiKey") ?? Self.bundled("DulyArkApiKey") ?? ""
        defaults.removeObject(forKey: "asrAppID") // 旧版设置项，已不再使用
        asrToken = Keychain.get("asrToken") ?? Self.bundled("DulyAsrToken") ?? ""
        if let d = defaults.object(forKey: "scoreStartDate") as? Date {
            scoreStartDate = d
        } else {
            scoreStartDate = Calendar.current.startOfDay(for: .now)
            defaults.set(scoreStartDate, forKey: "scoreStartDate")
        }
    }

    var rules: ScoreRules {
        var r = ScoreRules()
        r.sleepTargetHours = sleepTargetHours
        r.intakeTargetKcal = intakeTargetKcal
        r.weeklyWorkoutTarget = weeklyWorkoutTarget
        return r
    }
}

enum Keychain {
    private static let service = "com.yihua.dietplan"

    static func set(_ value: String, for key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
