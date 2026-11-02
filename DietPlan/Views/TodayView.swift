import Charts
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthStore.self) private var health
    @Query(sort: \BehaviorRecord.timestamp) private var records: [BehaviorRecord]

    var body: some View {
        let ledger = Ledger(health: health.days, records: records, settings: settings)
        let today = ledger.row(for: .now)
        let todayRecords = records.filter { Calendar.current.isDateInToday($0.timestamp) }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    pointsHeader(ledger)
                    if let err = health.lastError {
                        Text("健康数据读取失败：\(err)").font(.footnote).foregroundStyle(Theme.warning)
                    }

                    SectionTitle("健康账户")
                    VStack(spacing: 12) {
                        ForEach(AccountKind.allCases) { kind in
                            NavigationLink { AccountDetailView(kind: kind) } label: { AccountCard(kind: kind) }
                                .buttonStyle(.plain)
                        }
                    }

                    SectionTitle("今日行为")
                    todayGrid(today, ledger: ledger)

                    if !todayRecords.isEmpty {
                        SectionTitle("今日记录")
                        VStack(spacing: 8) {
                            ForEach(todayRecords.reversed()) { RecordCard(record: $0) }
                        }
                    }

                    NavigationLink("查看全部记录 →") { RecordListView() }
                        .font(.subheadline)
                        .foregroundStyle(Theme.oliveText)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("橄榄")
            .refreshable { await health.refresh(settings: settings) }
        }
    }

    private func pointsHeader(_ ledger: Ledger) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("累计积分").font(.subheadline).foregroundStyle(Theme.oliveText)
                Text("\(ledger.totalPoints)").font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.oliveDeep)
            }
            Spacer()
            if let s = ledger.daily.last {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("今日 +\(s.total)").font(.headline).foregroundStyle(Theme.oliveDeep)
                    if let w = ledger.currentWeek {
                        Text("本周健身 +\(w.total)").font(.subheadline).foregroundStyle(Theme.oliveText)
                    }
                }
            }
        }
        .padding(20)
        .background(Theme.oliveSoft, in: RoundedRectangle(cornerRadius: 20))
    }

    private func todayGrid(_ row: Ledger.Row?, ledger: Ledger) -> some View {
        let intake = row?.intakeKcal ?? 0
        let target = settings.intakeTargetKcal
        let weekCount = ledger.currentWeek?.workoutCount ?? 0
        return VStack(spacing: 12) {
            // 饮食进度
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("饮食摄入", systemImage: "fork.knife")
                    Spacer()
                    Text("\(intake) / \(target) 千卡").monospacedDigit()
                        .foregroundStyle(intake > target ? Theme.warning : Theme.ink)
                }
                ProgressView(value: min(Double(intake), Double(target)), total: Double(target))
                    .tint(intake > target ? Theme.warning : Theme.olive)
                Text(intake > target ? "已超出 \(intake - target) 千卡，今日饮食未达标"
                                     : "还可摄入 \(target - intake) 千卡")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .card()

            HStack(spacing: 12) {
                MetricTile(title: "睡眠", value: row?.health.sleepHours.map { String(format: "%.1f h", $0) } ?? "—",
                           sub: "目标 \(settings.sleepTargetHours.formatted()) h", symbol: "bed.double")
                MetricTile(title: "本周健身", value: "\(weekCount) 次",
                           sub: "目标 \(settings.weeklyWorkoutTarget) 次", symbol: "figure.strengthtraining.traditional")
            }
            HStack(spacing: 12) {
                MetricTile(title: "步数", value: row?.health.steps.map { $0.formatted() } ?? "—",
                           sub: "来自健康", symbol: "shoeprints.fill")
                MetricTile(title: "活动消耗", value: row?.health.activeKcal.map { "\($0) 千卡" } ?? "—",
                           sub: "来自健康", symbol: "flame")
            }
        }
    }
}

// MARK: - Accounts

enum AccountKind: String, CaseIterable, Identifiable {
    case weight, muscle, sleep
    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: "体重"
        case .muscle: "肌肉（去脂体重）"
        case .sleep: "睡眠"
        }
    }
    var unit: String { self == .sleep ? "小时" : "斤" }
    var symbol: String {
        switch self {
        case .weight: "scalemass"
        case .muscle: "figure.arms.open"
        case .sleep: "moon.zzz"
        }
    }
    var keyPath: KeyPath<HealthDay, Double?> {
        switch self {
        case .weight: \.weightKg
        case .muscle: \.leanMassKg
        case .sleep: \.sleepHours
        }
    }
    /// 用于展示的数值：健康数据内部存公斤，这里换算成斤（1 公斤 = 2 斤）
    func displayValue(of day: HealthDay) -> Double? {
        guard let value = day[keyPath: keyPath] else { return nil }
        return self == .sleep ? value : value * 2
    }
    /// 数值上升是否是好事（用于涨跌着色）
    var higherIsBetter: Bool { self != .weight }
}

struct AccountCard: View {
    let kind: AccountKind
    @Environment(HealthStore.self) private var health

    var body: some View {
        let points = health.sortedDays.compactMap { d in kind.displayValue(of: d).map { (d.day, $0) } }
        let recent = points.filter { $0.0 >= Calendar.current.date(byAdding: .day, value: -30, to: .now)! }
        let latest = points.last
        // 与 7 天前（或之前最近一次）对比
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let base = points.last { $0.0 <= weekAgo }

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label(kind.title, systemImage: kind.symbol).font(.subheadline).foregroundStyle(.secondary)
                Text(latest.map { String(format: "%.1f", $0.1) } ?? "—")
                    .font(.title.bold()).monospacedDigit()
                + Text(" \(kind.unit)").font(.footnote).foregroundStyle(.secondary)
                if let latest, let base {
                    let delta = latest.1 - base.1
                    let good = kind.higherIsBetter ? delta >= 0 : delta <= 0
                    Text(String(format: "较 7 天前 %+.1f", delta)).font(.caption)
                        .foregroundStyle(abs(delta) < 0.05 ? Theme.inkSecondary : (good ? Theme.oliveText : Theme.warning))
                } else if let latest {
                    Text(latest.0.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Chart(recent, id: \.0) { p in
                LineMark(x: .value("日期", p.0), y: .value(kind.title, p.1))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.olive)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(width: 120, height: 50)
        }
        .card()
    }
}

struct AccountDetailView: View {
    let kind: AccountKind
    @Environment(HealthStore.self) private var health
    @Environment(AppSettings.self) private var settings
    @State private var range = 30

    var body: some View {
        let from = Calendar.current.date(byAdding: .day, value: -range, to: .now)!
        let points = health.sortedDays.filter { $0.day >= from }.compactMap { d in kind.displayValue(of: d).map { (d.day, $0) } }

        List {
            Section {
                Picker("范围", selection: $range) {
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                }
                .pickerStyle(.segmented)

                Chart {
                    ForEach(points, id: \.0) { p in
                        if kind == .sleep {
                            BarMark(x: .value("日期", p.0, unit: .day), y: .value("小时", p.1))
                                .foregroundStyle(p.1 >= settings.sleepTargetHours ? Theme.olive : Theme.pending)
                        } else {
                            LineMark(x: .value("日期", p.0, unit: .day), y: .value(kind.unit, p.1))
                                .foregroundStyle(Theme.olive)
                            PointMark(x: .value("日期", p.0, unit: .day), y: .value(kind.unit, p.1))
                                .foregroundStyle(Theme.olive)
                        }
                    }
                    if kind == .sleep {
                        RuleMark(y: .value("目标", settings.sleepTargetHours))
                            .lineStyle(StrokeStyle(dash: [4]))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: kind == .sleep))
                .frame(height: 220)
            }
            .listRowBackground(Theme.card)

            Section("明细") {
                ForEach(points.reversed(), id: \.0) { p in
                    HStack {
                        Text(p.0.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text(String(format: "%.1f %@", p.1, kind.unit)).monospacedDigit()
                    }
                }
                if points.isEmpty {
                    Text(kind == .sleep ? "没有睡眠数据：请确认手环 App 已同步到「健康」"
                                        : "没有数据：请在「小米运动健康」里开启同步到 Apple 健康")
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedList()
        .navigationTitle(kind.title)
    }
}

// MARK: - Small components

struct MetricTile: View {
    let title: String, value: String, sub: String, symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.title3.bold()).foregroundStyle(Theme.ink).padding(.top, 4) }
}

extension View {
    func card() -> some View {
        padding()
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder, lineWidth: 1))
    }
}
