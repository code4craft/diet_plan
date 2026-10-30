import Foundation

/// 积分规则。所有数值集中在这里，方便以后调整。
struct ScoreRules: Codable, Equatable {
    var sleepTargetHours: Double = 7
    var intakeTargetKcal: Int = 1800

    /// 日目标（睡眠/饮食）达标基础分
    var dailyBase = 5
    /// 日目标连续达标的额外分上限：第 2 天 +1，第 3 天 +2，第 4 天起 +3
    var dailyStreakCap = 3

    /// 每完成一次健身
    var workoutSessionPoints = 5
    /// 一周健身达到该次数即周达标
    var weeklyWorkoutTarget = 3
    var weeklyBase = 5
    /// 周连击额外分：连续第 2 周 +3，第 3 周 +6，第 4 周起 +9
    var weeklyStreakStep = 3
    var weeklyStreakCap = 9

    func dailyBonus(streak: Int) -> Int { min(max(streak - 1, 0), dailyStreakCap) }
    func weeklyBonus(streak: Int) -> Int { min(max(streak - 1, 0) * weeklyStreakStep, weeklyStreakCap) }
}

/// 某一天的行为输入
struct DayInput: Equatable {
    var day: Date            // 当天 00:00
    var sleepHours: Double?  // nil = 没有睡眠数据
    var intakeKcal: Int
    var mealCount: Int
}

/// 目标状态：pending 表示今天还没结束、暂不判定，不计分也不打断连击
enum GoalStatus: String, Codable { case met, missed, pending }

struct GoalResult: Equatable {
    var status: GoalStatus
    var streak: Int      // 截至当天的连续达标天/周数（未达标为 0）
    var base: Int
    var bonus: Int
    var total: Int { base + bonus }
}

struct DailyScore: Equatable, Identifiable {
    var day: Date
    var sleep: GoalResult
    var diet: GoalResult
    var id: Date { day }
    var total: Int { sleep.total + diet.total }
}

struct WeeklyScore: Equatable, Identifiable {
    var weekStart: Date
    var workoutCount: Int
    var sessionPoints: Int
    var goal: GoalResult
    var id: Date { weekStart }
    var total: Int { sessionPoints + goal.total }
}

enum ScoreEngine {
    static func calendar() -> Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        return cal
    }

    /// 计算每日睡眠/饮食积分。`days` 需覆盖起始日到今天的每一天（缺失的天会按未达标处理）。
    static func daily(days: [DayInput], rules: ScoreRules, now: Date = .now) -> [DailyScore] {
        let cal = calendar()
        let today = cal.startOfDay(for: now)
        let byDay = Dictionary(days.map { (cal.startOfDay(for: $0.day), $0) }, uniquingKeysWith: { a, _ in a })
        guard let first = byDay.keys.min() else { return [] }

        var result: [DailyScore] = []
        var sleepStreak = 0, dietStreak = 0
        var day = first
        while day <= today {
            let input = byDay[day] ?? DayInput(day: day, sleepHours: nil, intakeKcal: 0, mealCount: 0)
            let isToday = day == today

            // 睡眠：以醒来那天计。今天还没同步到数据时暂不判定。
            let sleepStatus: GoalStatus
            if let h = input.sleepHours {
                sleepStatus = h >= rules.sleepTargetHours ? .met : .missed
            } else {
                sleepStatus = isToday ? .pending : .missed
            }
            // 饮食：当天必须有记录且总摄入不超过目标；今天超标可以直接判负，否则等一天结束。
            let dietStatus: GoalStatus
            if input.mealCount > 0 && input.intakeKcal > rules.intakeTargetKcal {
                dietStatus = .missed
            } else if isToday {
                dietStatus = .pending
            } else {
                dietStatus = input.mealCount > 0 ? .met : .missed
            }

            let sleep = dailyResult(sleepStatus, streak: &sleepStreak, rules: rules)
            let diet = dailyResult(dietStatus, streak: &dietStreak, rules: rules)
            result.append(DailyScore(day: day, sleep: sleep, diet: diet))
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    private static func dailyResult(_ status: GoalStatus, streak: inout Int, rules: ScoreRules) -> GoalResult {
        switch status {
        case .met:
            streak += 1
            return GoalResult(status: .met, streak: streak, base: rules.dailyBase, bonus: rules.dailyBonus(streak: streak))
        case .missed:
            streak = 0
            return GoalResult(status: .missed, streak: 0, base: 0, bonus: 0)
        case .pending:
            return GoalResult(status: .pending, streak: streak, base: 0, bonus: 0)
        }
    }

    /// 计算每周健身积分。`workoutDates` 为每次健身的时间点，`start` 为积分起始日。
    static func weekly(workoutDates: [Date], start: Date, rules: ScoreRules, now: Date = .now) -> [WeeklyScore] {
        let cal = calendar()
        guard let firstWeek = cal.dateInterval(of: .weekOfYear, for: start)?.start,
              let currentWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let startDay = cal.startOfDay(for: start)

        var counts: [Date: Int] = [:]
        for d in workoutDates where d >= startDay && d <= now {
            if let w = cal.dateInterval(of: .weekOfYear, for: d)?.start { counts[w, default: 0] += 1 }
        }

        var result: [WeeklyScore] = []
        var streak = 0
        var week = firstWeek
        while week <= currentWeek {
            let count = counts[week] ?? 0
            let goal: GoalResult
            if count >= rules.weeklyWorkoutTarget {
                streak += 1
                goal = GoalResult(status: .met, streak: streak, base: rules.weeklyBase, bonus: rules.weeklyBonus(streak: streak))
            } else if week == currentWeek {
                goal = GoalResult(status: .pending, streak: streak, base: 0, bonus: 0)
            } else {
                streak = 0
                goal = GoalResult(status: .missed, streak: 0, base: 0, bonus: 0)
            }
            result.append(WeeklyScore(weekStart: week, workoutCount: count,
                                      sessionPoints: count * rules.workoutSessionPoints, goal: goal))
            week = cal.date(byAdding: .weekOfYear, value: 1, to: week)!
        }
        return result
    }
}
