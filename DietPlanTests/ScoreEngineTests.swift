import XCTest
@testable import DietPlan

final class ScoreEngineTests: XCTestCase {
    let cal = ScoreEngine.calendar()
    let rules = ScoreRules()

    func date(_ s: String, _ hour: Int = 12) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH"
        return f.date(from: "\(s) \(hour)")!
    }

    func day(_ offset: Int, from s: String) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: date(s)))!
    }

    func testDailyStreakBonusCapsAtThree() {
        // 6 天睡眠全部达标，第 7 天（今天）没数据
        let days = (0..<7).map { i in
            DayInput(day: day(i, from: "2026-10-01"), sleepHours: i < 6 ? 7.5 : nil, intakeKcal: 0, mealCount: 0)
        }
        let scores = ScoreEngine.daily(days: days, rules: rules, now: date("2026-10-07", 9))
        XCTAssertEqual(scores.map(\.sleep.total), [5, 6, 7, 8, 8, 8, 0])
        XCTAssertEqual(scores.last?.sleep.status, .pending)
        XCTAssertEqual(scores.last?.sleep.streak, 6)
    }

    func testMissResetsStreak() {
        let hours: [Double?] = [8, 8, 6, 8, nil]
        let days = hours.enumerated().map { i, h in
            DayInput(day: day(i, from: "2026-10-01"), sleepHours: h, intakeKcal: 0, mealCount: 0)
        }
        let scores = ScoreEngine.daily(days: days, rules: rules, now: date("2026-10-06"))
        // 第 5 天无数据且不是今天 → missed
        XCTAssertEqual(scores.prefix(5).map(\.sleep.total), [5, 6, 0, 5, 0])
        XCTAssertEqual(scores[4].sleep.status, .missed)
    }

    func testDietRequiresRecordsAndUnderTarget() {
        let days = [
            DayInput(day: day(0, from: "2026-10-01"), sleepHours: nil, intakeKcal: 1700, mealCount: 3),
            DayInput(day: day(1, from: "2026-10-01"), sleepHours: nil, intakeKcal: 1750, mealCount: 3),
            DayInput(day: day(2, from: "2026-10-01"), sleepHours: nil, intakeKcal: 0, mealCount: 0),
            DayInput(day: day(3, from: "2026-10-01"), sleepHours: nil, intakeKcal: 2500, mealCount: 2),
            DayInput(day: day(4, from: "2026-10-01"), sleepHours: nil, intakeKcal: 900, mealCount: 1),
        ]
        let scores = ScoreEngine.daily(days: days, rules: rules, now: date("2026-10-05", 15))
        XCTAssertEqual(scores.map(\.diet.status), [.met, .met, .missed, .missed, .pending])
        XCTAssertEqual(scores.map(\.diet.total), [5, 6, 0, 0, 0])
    }

    func testTodayOverTargetIsMissedImmediately() {
        let days = [DayInput(day: day(0, from: "2026-10-01"), sleepHours: nil, intakeKcal: 2000, mealCount: 2)]
        let scores = ScoreEngine.daily(days: days, rules: rules, now: date("2026-10-01", 20))
        XCTAssertEqual(scores.first?.diet.status, .missed)
    }

    func testWeeklyStreak() {
        // 2026-10-05 是周一。前 4 周每周 3 次，第 5 周 2 次（已结束），第 6 周进行中 1 次
        var workouts: [Date] = []
        for w in 0..<4 { for d in 0..<3 { workouts.append(day(w * 7 + d, from: "2026-10-05")) } }
        workouts += [day(28, from: "2026-10-05"), day(29, from: "2026-10-05")]
        workouts += [day(35, from: "2026-10-05")]
        let weeks = ScoreEngine.weekly(workoutDates: workouts, start: date("2026-10-05"), rules: rules,
                                       now: day(36, from: "2026-10-05").addingTimeInterval(3600))
        XCTAssertEqual(weeks.map(\.workoutCount), [3, 3, 3, 3, 2, 1])
        XCTAssertEqual(weeks.map(\.goal.total), [5, 8, 11, 14, 0, 0])
        XCTAssertEqual(weeks.map(\.sessionPoints), [15, 15, 15, 15, 10, 5])
        XCTAssertEqual(weeks.last?.goal.status, .pending)
    }

    func testWeeklyBonusCap() {
        XCTAssertEqual((1...6).map { rules.weeklyBonus(streak: $0) }, [0, 3, 6, 9, 9, 9])
        XCTAssertEqual((1...6).map { rules.dailyBonus(streak: $0) }, [0, 1, 2, 3, 3, 3])
    }

    func testSleepMergeAndAttribution() {
        // 手环和手表重叠记录同一晚：23:00-07:00 与 23:30-06:30，外加次日午睡 13:00-13:30
        let a = DateInterval(start: date("2026-10-01", 23), end: date("2026-10-02", 7))
        let b = DateInterval(start: date("2026-10-01", 23).addingTimeInterval(1800), end: date("2026-10-02", 6).addingTimeInterval(1800))
        let nap = DateInterval(start: date("2026-10-02", 13), duration: 1800)
        let hours = SleepMath.hoursPerDay(SleepMath.merge([a, b, nap]))
        XCTAssertEqual(hours[Calendar.current.startOfDay(for: date("2026-10-02"))] ?? 0, 8.5, accuracy: 0.001)
        XCTAssertEqual(hours.count, 1)
    }

    func testAssistantResponseParsing() throws {
        let raw = """
        ```json
        {"reply":"记好了","actions":[{"op":"create","kind":"workout","time":"2026-10-30 19:00","duration_min":40,"category":"跑步","detail":"5公里"}]}
        ```
        """
        let r = try AssistantResponse.parse(raw)
        XCTAssertEqual(r.reply, "记好了")
        XCTAssertEqual(r.actions.first?.durationMin, 40)
        XCTAssertEqual(AssistantResponse.parseTime("2026-10-30 19:00"), date("2026-10-30", 19))
        XCTAssertEqual(AssistantResponse.parseTime("2026-10-30T19:00"), date("2026-10-30", 19))
    }
}
