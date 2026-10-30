import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthStore.self) private var health
    @Environment(\.modelContext) private var context
    @Query(sort: \BehaviorRecord.timestamp) private var records: [BehaviorRecord]

    @State private var exportFiles: [URL] = []
    @State private var exportError: String?
    @State private var testResult: String?
    @State private var confirmClearChat = false

    var body: some View {
        @Bindable var s = settings
        NavigationStack {
            Form {
                Section("目标") {
                    Stepper(value: $s.sleepTargetHours, in: 5...10, step: 0.5) {
                        LabeledContent("每日睡眠", value: "\(s.sleepTargetHours.formatted()) 小时")
                    }
                    Stepper(value: $s.intakeTargetKcal, in: 1000...3500, step: 50) {
                        LabeledContent("每日摄入上限", value: "\(s.intakeTargetKcal) 千卡")
                    }
                    Stepper(value: $s.weeklyWorkoutTarget, in: 1...7) {
                        LabeledContent("每周健身", value: "\(s.weeklyWorkoutTarget) 次")
                    }
                    DatePicker("积分起始日", selection: $s.scoreStartDate, displayedComponents: .date)
                }

                Section {
                    SecureField("火山方舟 API Key", text: $s.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("模型 ID", text: $s.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("测试连接") { Task { await testConnection() } }
                    if let testResult { Text(testResult).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("豆包（火山方舟）")
                } footer: {
                    Text("在火山方舟控制台「API Key 管理」创建 Key，并在「开通管理」开通所用模型。Key 只保存在本机钥匙串。")
                }

                Section {
                    SecureField("API Key", text: $s.asrToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("语音识别（火山）")
                } footer: {
                    Text("豆包语音控制台开通「录音文件识别 2.0」（volc.seedasr.auc）后，在「API Key 管理」复制 Key 填到这里。")
                }

                Section {
                    Button("重新读取健康数据") { Task { await health.refresh(settings: settings) } }
                    NavigationLink("健康数据诊断") { HealthDiagnosticsView() }
                    Button("导出数据（CSV）") { export() }
                    if !exportFiles.isEmpty {
                        ShareLink(items: exportFiles) {
                            Label("分享 \(exportFiles.count) 个文件", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let exportError { Text(exportError).foregroundStyle(.red) }
                } header: {
                    Text("数据")
                } footer: {
                    Text("导出每日行为与结果（daily.csv）、记录明细（records.csv）、每周健身（weekly.csv），可交给其他 AI 工具做相关性分析。")
                }

                Section {
                    Button("清空对话记录", role: .destructive) { confirmClearChat = true }
                } footer: {
                    Text("只删除聊天气泡，不影响已保存的饮食/健身记录。")
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("清空所有对话？", isPresented: $confirmClearChat) {
                Button("清空", role: .destructive) { try? context.delete(model: ChatMessage.self) }
            }
        }
    }

    private func export() {
        do {
            let ledger = Ledger(health: health.days, records: records, settings: settings)
            exportFiles = try ExportService.export(ledger: ledger, records: records, settings: settings)
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func testConnection() async {
        testResult = "连接中…"
        do {
            let reply = try await DoubaoClient(apiKey: settings.apiKey, model: settings.model)
                .complete(messages: [["role": "user", "content": "回复\"连接成功\"四个字"]], jsonMode: false)
            testResult = "✅ \(reply)"
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
    }
}

/// 列出最近 14 天健康数据的来源与类型，排查睡眠/体重没同步的问题
struct HealthDiagnosticsView: View {
    @State private var lines: [String] = []
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                ProgressView()
            } else {
                ForEach(lines, id: \.self) { Text($0).font(.footnote) }
            }
        }
        .navigationTitle("健康数据诊断")
        .task {
            try? await HealthService.shared.requestAuthorization()
            lines = await HealthService.shared.diagnostics()
            loading = false
        }
    }
}
