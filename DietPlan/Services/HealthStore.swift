import Foundation
import Observation

/// 缓存健康数据，供首页、积分页、导出共用
@MainActor
@Observable
final class HealthStore {
    var days: [Date: HealthDay] = [:]
    var lastError: String?
    var isLoading = false

    /// 账户趋势至少看 90 天
    static let historyDays = 90

    func refresh(settings: AppSettings) async {
        isLoading = true
        defer { isLoading = false }
        let cal = Calendar.current
        let from = min(settings.scoreStartDate, cal.date(byAdding: .day, value: -Self.historyDays, to: .now)!)
        do {
            try await HealthService.shared.requestAuthorization()
            days = try await HealthService.shared.days(from: from)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    var sortedDays: [HealthDay] { days.values.sorted { $0.day < $1.day } }

    func latest(_ key: KeyPath<HealthDay, Double?>) -> (day: Date, value: Double)? {
        sortedDays.last { $0[keyPath: key] != nil }.map { ($0.day, $0[keyPath: key]!) }
    }
}

/// 把健康数据 + 行为记录汇总成每天一行，并算出积分
struct Ledger {
    struct Row: Identifiable {
        var day: Date
        var health: HealthDay
        var intakeKcal: Int
        var mealCount: Int
        var workoutCount: Int
        var workoutMinutes: Int
        var score: DailyScore?
        var id: Date { day }
    }

    var rows: [Row]
    var daily: [DailyScore]
    var weekly: [WeeklyScore]

    var totalPoints: Int { daily.reduce(0) { $0 + $1.total } + weekly.reduce(0) { $0 + $1.total } }

    init(health: [Date: HealthDay], records: [BehaviorRecord], settings: AppSettings, now: Date = .now) {
        let cal = Calendar.current
        let rules = settings.rules
        let start = cal.startOfDay(for: settings.scoreStartDate)
        let today = cal.startOfDay(for: now)
        let first = min(start, health.keys.min() ?? start, records.map { cal.startOfDay(for: $0.timestamp) }.min() ?? start)

        let byDay = Dictionary(grouping: records) { cal.startOfDay(for: $0.timestamp) }

        var rows: [Row] = []
        var day = first
        while day <= today {
            let recs = byDay[day] ?? []
            let meals = recs.filter { $0.kind == .meal }
            let workouts = recs.filter { $0.kind == .workout }
            rows.append(Row(day: day,
                            health: health[day] ?? HealthDay(day: day),
                            intakeKcal: meals.reduce(0) { $0 + ($1.calories ?? 0) },
                            mealCount: meals.count,
                            workoutCount: workouts.count,
                            workoutMinutes: workouts.reduce(0) { $0 + ($1.durationMinutes ?? 0) }))
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }

        let inputs = rows.filter { $0.day >= start }.map {
            DayInput(day: $0.day, sleepHours: $0.health.sleepHours, intakeKcal: $0.intakeKcal, mealCount: $0.mealCount)
        }
        daily = ScoreEngine.daily(days: inputs, rules: rules, now: now)
        weekly = ScoreEngine.weekly(workoutDates: records.filter { $0.kind == .workout }.map(\.timestamp),
                                    start: start, rules: rules, now: now)
        let scores = Dictionary(daily.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        self.rows = rows.map { var r = $0; r.score = scores[r.day]; return r }
    }

    func row(for day: Date) -> Row? { rows.last { $0.day == Calendar.current.startOfDay(for: day) } }

    var currentWeek: WeeklyScore? { weekly.last }
}
