import SwiftData
import SwiftUI

struct PointsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthStore.self) private var health
    @Query(sort: \BehaviorRecord.timestamp) private var records: [BehaviorRecord]
    @State private var tab = 0

    var body: some View {
        let ledger = Ledger(health: health.days, records: records, settings: settings)
        NavigationStack {
            List {
                Section {
                    HStack {
                        stat("累计", ledger.totalPoints)
                        stat("睡眠", ledger.daily.reduce(0) { $0 + $1.sleep.total })
                        stat("饮食", ledger.daily.reduce(0) { $0 + $1.diet.total })
                        stat("健身", ledger.weekly.reduce(0) { $0 + $1.total })
                    }
                    HStack {
                        streak("睡眠连续", ledger.daily.last?.sleep.streak ?? 0, unit: "天")
                        streak("饮食连续", ledger.daily.last?.diet.streak ?? 0, unit: "天")
                        streak("健身连击", ledger.weekly.last?.goal.streak ?? 0, unit: "周")
                    }
                }

                Picker("", selection: $tab) {
                    Text("每日").tag(0)
                    Text("每周健身").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if tab == 0 {
                    ForEach(ledger.daily.reversed()) { s in
                        HStack {
                            Text(s.day.formatted(.dateTime.month().day().weekday()))
                            Spacer()
                            goalBadge("睡眠", s.sleep)
                            goalBadge("饮食", s.diet)
                            Text("+\(s.total)").bold().monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }
                } else {
                    ForEach(ledger.weekly.reversed()) { w in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(w.weekStart.formatted(.dateTime.month().day())) 起的一周")
                                Text("健身 \(w.workoutCount) 次 · 单次 +\(w.sessionPoints)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            goalBadge("周目标", w.goal)
                            Text("+\(w.total)").bold().monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                    }
                }

                Section("规则") {
                    Text("睡眠 ≥ \(settings.sleepTargetHours.formatted()) 小时、饮食 ≤ \(settings.intakeTargetKcal) 千卡：达标 +5，连续第 2/3/4+ 天额外 +1/+2/+3")
                    Text("健身每次 +5；一周 ≥ \(settings.weeklyWorkoutTarget) 次周达标 +5，连续第 2/3/4+ 周额外 +3/+6/+9")
                    Text("今天的睡眠/饮食、本周的健身目标在结束前显示为「进行中」，不打断连击。")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("积分")
        }
    }

    private func stat(_ title: String, _ value: Int) -> some View {
        VStack {
            Text("\(value)").font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func streak(_ title: String, _ value: Int, unit: String) -> some View {
        VStack {
            Text("🔥 \(value) \(unit)").font(.subheadline.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func goalBadge(_ title: String, _ g: GoalResult) -> some View {
        let (color, symbol): (Color, String) = switch g.status {
        case .met: (.green, "checkmark.circle.fill")
        case .missed: (.secondary, "xmark.circle")
        case .pending: (.orange, "clock")
        }
        return Label(g.bonus > 0 ? "\(title)+\(g.bonus)" : title, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
    }
}
