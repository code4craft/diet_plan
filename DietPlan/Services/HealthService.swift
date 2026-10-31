import Foundation
import HealthKit

/// 某天的健康数据快照（体重/肌肉取当天最后一次测量）
struct HealthDay: Equatable {
    var day: Date
    var weightKg: Double?
    var leanMassKg: Double?
    var bodyFatPct: Double?
    var sleepHours: Double?
    var steps: Int?
    var activeKcal: Int?
}

/// 从苹果健康读取：体重/体脂/去脂体重（小米体重秤经「小米运动健康」同步）、睡眠（手环）、步数和活动消耗
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.bodyMass), HKQuantityType(.leanBodyMass), HKQuantityType(.bodyFatPercentage),
         HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKCategoryType(.sleepAnalysis)]
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// 读取 [from, to] 每一天的数据，key 为当天 00:00
    func days(from: Date, to: Date = .now) async throws -> [Date: HealthDay] {
        guard isAvailable else { return [:] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: from)
        // 睡眠窗口往前多取半天，覆盖起始日前一晚
        let sleepStart = cal.date(byAdding: .hour, value: -12, to: start)!

        async let weights = lastPerDay(.bodyMass, unit: .gramUnit(with: .kilo), from: start, to: to)
        async let leans = lastPerDay(.leanBodyMass, unit: .gramUnit(with: .kilo), from: start, to: to)
        async let fats = lastPerDay(.bodyFatPercentage, unit: .percent(), from: start, to: to)
        async let steps = dailySum(.stepCount, unit: .count(), from: start, to: to)
        async let active = dailySum(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: to)
        async let sleep = sleepPerDay(from: sleepStart, to: to)

        let (w, l, f, s, a, sl) = try await (weights, leans, fats, steps, active, sleep)

        var result: [Date: HealthDay] = [:]
        var day = start
        while day <= to {
            var h = HealthDay(day: day)
            h.weightKg = w[day]
            h.bodyFatPct = f[day].map { $0 * 100 }
            // 没有去脂体重时用 体重×(1-体脂率) 推算
            h.leanMassKg = l[day] ?? {
                guard let w = w[day], let f = f[day] else { return nil }
                return w * (1 - f)
            }()
            h.steps = s[day].map { Int($0) }
            h.activeKcal = a[day].map { Int($0) }
            h.sleepHours = sl[day]
            result[day] = h
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    // MARK: - Queries

    private func samples(_ type: HKSampleType, from: Date, to: Date) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, s, err in
                if let err { cont.resume(throwing: err) } else { cont.resume(returning: s ?? []) }
            }
            store.execute(q)
        }
    }

    private func lastPerDay(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async throws -> [Date: Double] {
        let cal = Calendar.current
        var out: [Date: Double] = [:]
        for case let s as HKQuantitySample in try await samples(HKQuantityType(id), from: from, to: to) {
            out[cal.startOfDay(for: s.startDate)] = s.quantity.doubleValue(for: unit) // 升序，后者覆盖
        }
        return out
    }

    private func dailySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from: Date, to: Date) async throws -> [Date: Double] {
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let collection: HKStatisticsCollection = try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: predicate,
                                                options: .cumulativeSum, anchorDate: from,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, c, err in
                if let c { cont.resume(returning: c) } else { cont.resume(throwing: err ?? HKError(.errorNoData)) }
            }
            store.execute(q)
        }
        var out: [Date: Double] = [:]
        collection.enumerateStatistics(from: from, to: to) { stat, _ in
            if let v = stat.sumQuantity()?.doubleValue(for: unit) { out[stat.startDate] = v }
        }
        return out
    }

    private static let asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                                 HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                                 HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                                                 HKCategoryValueSleepAnalysis.asleepREM.rawValue]

    /// 每天睡眠时长（小时）。多设备重叠的区间先合并；每段睡眠按 开始时间+6 小时 归到醒来那天，
    /// 即前一天 18:00 到当天 18:00 之间入睡的都算当天。
    /// 有些手环 App 只写「卧床」不写「睡着」，某天没有睡着数据时用卧床时长兜底。
    private func sleepPerDay(from: Date, to: Date) async throws -> [Date: Double] {
        let all = try await samples(HKCategoryType(.sleepAnalysis), from: from, to: to)
            .compactMap { $0 as? HKCategorySample }
        func hours(_ values: Set<Int>) -> [Date: Double] {
            let intervals = all.filter { values.contains($0.value) }
                .map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
            return SleepMath.hoursPerDay(SleepMath.merge(intervals))
        }
        let asleep = hours(Self.asleepValues)
        let inBed = hours([HKCategoryValueSleepAnalysis.inBed.rawValue])
        return inBed.merging(asleep) { _, a in a }
    }

    // MARK: - Diagnostics

    /// 最近 14 天健康数据的来源与类型统计，用于排查「数据没同步过来」
    func diagnostics() async -> [String] {
        guard isAvailable else { return ["此设备不支持 HealthKit"] }
        let from = Calendar.current.date(byAdding: .day, value: -14, to: .now)!
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d HH:mm"
        var lines: [String] = []

        func summarize(_ title: String, _ samples: [HKSample], label: (HKSample) -> String) {
            guard !samples.isEmpty else { lines.append("\(title)：14 天内没有数据"); return }
            let groups = Dictionary(grouping: samples) { "\($0.sourceRevision.source.name) · \(label($0))" }
            for (key, items) in groups.sorted(by: { $0.key < $1.key }) {
                let hours = items.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 3600
                let latest = items.map(\.endDate).max().map { fmt.string(from: $0) } ?? "-"
                var line = "\(title)：\(key) × \(items.count)，最近 \(latest)"
                if title == "睡眠" { line += String(format: "，共 %.1f 小时", hours) }
                lines.append(line)
            }
        }

        do {
            let sleep = try await samples(HKCategoryType(.sleepAnalysis), from: from, to: .now)
            summarize("睡眠", sleep) { s in
                guard let v = (s as? HKCategorySample)?.value,
                      let kind = HKCategoryValueSleepAnalysis(rawValue: v) else { return "未知" }
                switch kind {
                case .inBed: return "卧床"
                case .awake: return "清醒"
                case .asleepCore: return "核心睡眠"
                case .asleepDeep: return "深睡"
                case .asleepREM: return "快速眼动"
                default: return "睡着（未分期）"
                }
            }
            for (title, id) in [("体重", HKQuantityTypeIdentifier.bodyMass), ("去脂体重", .leanBodyMass), ("体脂率", .bodyFatPercentage)] {
                summarize(title, try await samples(HKQuantityType(id), from: from, to: .now)) { _ in "测量" }
            }
        } catch {
            lines.append("读取失败：\(error.localizedDescription)")
        }
        lines.append("没有数据时：请到 iPhone「设置 → 健康 → 数据访问与设备 → 橄榄」确认已打开对应项，并在手环 App 里打开「同步到 Apple 健康」。")
        return lines
    }
}

enum SleepMath {
    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        var merged: [DateInterval] = []
        for i in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, i.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, i.end))
            } else {
                merged.append(i)
            }
        }
        return merged
    }

    static func hoursPerDay(_ merged: [DateInterval], calendar cal: Calendar = .current) -> [Date: Double] {
        var out: [Date: Double] = [:]
        for i in merged {
            let day = cal.startOfDay(for: i.start.addingTimeInterval(6 * 3600))
            out[day, default: 0] += i.duration / 3600
        }
        return out
    }
}
