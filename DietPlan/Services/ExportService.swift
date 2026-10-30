import Foundation

/// 导出 CSV + JSON，供外部 AI 工具做行为与结果的相关性分析
enum ExportService {
    /// 返回导出目录下的文件 URL 列表
    static func export(ledger: Ledger, records: [BehaviorRecord], settings: AppSettings) throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(stamp())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let daily = dir.appendingPathComponent("daily.csv")
        try dailyCSV(ledger).write(to: daily, atomically: true, encoding: .utf8)
        let recs = dir.appendingPathComponent("records.csv")
        try recordsCSV(records).write(to: recs, atomically: true, encoding: .utf8)
        let weekly = dir.appendingPathComponent("weekly.csv")
        try weeklyCSV(ledger).write(to: weekly, atomically: true, encoding: .utf8)
        let readme = dir.appendingPathComponent("README.txt")
        try readmeText(settings).write(to: readme, atomically: true, encoding: .utf8)
        return [daily, recs, weekly, readme]
    }

    static func dailyCSV(_ ledger: Ledger) -> String {
        var lines = ["date,weight_kg,lean_mass_kg,body_fat_pct,sleep_hours,steps,active_kcal,intake_kcal,meal_count,workout_count,workout_minutes,sleep_goal,diet_goal,day_points"]
        for r in ledger.rows {
            let h = r.health
            var cols: [String] = [day(r.day), num(h.weightKg, 2), num(h.leanMassKg, 2), num(h.bodyFatPct, 1),
                                  num(h.sleepHours, 2), int(h.steps), int(h.activeKcal)]
            cols += [String(r.intakeKcal), String(r.mealCount), String(r.workoutCount), String(r.workoutMinutes)]
            cols += [r.score?.sleep.status.rawValue ?? "", r.score?.diet.status.rawValue ?? "", int(r.score?.total)]
            lines.append(cols.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func recordsCSV(_ records: [BehaviorRecord]) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        var lines = ["id,kind,time,duration_min,category,calories,detail,has_photo"]
        for r in records.sorted(by: { $0.timestamp < $1.timestamp }) {
            lines.append([r.shortID, r.kindRaw, f.string(from: r.timestamp), r.durationMinutes.map(String.init) ?? "",
                          csv(r.category), r.calories.map(String.init) ?? "", csv(r.detail),
                          r.photo == nil ? "0" : "1"].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func weeklyCSV(_ ledger: Ledger) -> String {
        var lines = ["week_start,workout_count,goal,streak,session_points,goal_points"]
        for w in ledger.weekly {
            lines.append([day(w.weekStart), String(w.workoutCount), w.goal.status.rawValue, String(w.goal.streak),
                          String(w.sessionPoints), String(w.goal.total)].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func readmeText(_ s: AppSettings) -> String {
        """
        Duly 数据导出 \(stamp())

        daily.csv   每天一行。结果：weight_kg / lean_mass_kg / body_fat_pct（来自体重秤）；
                    行为：sleep_hours（醒来那天计）、steps、active_kcal、intake_kcal、workout_count、workout_minutes。
                    sleep_goal / diet_goal 取值 met / missed / pending。
        records.csv 每条饮食/健身记录明细（detail 为自由文本）。
        weekly.csv  每周健身次数与周目标（周一开始）。

        当前目标：睡眠 ≥ \(s.sleepTargetHours) 小时，饮食 ≤ \(s.intakeTargetKcal) 千卡，每周健身 ≥ \(s.weeklyWorkoutTarget) 次。
        分析建议：体重/去脂体重常有 1-3 天的滞后，可对行为做滚动 7 日均值再与结果求相关。
        """
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: .now)
    }

    private static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private static func num(_ v: Double?, _ digits: Int) -> String {
        v.map { String(format: "%.\(digits)f", $0) } ?? ""
    }

    private static func int(_ v: Int?) -> String { v.map(String.init) ?? "" }

    private static func csv(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
