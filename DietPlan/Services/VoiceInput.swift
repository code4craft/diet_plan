import AVFoundation
import Foundation
import Observation

/// 按住说话的录音器：录 16kHz 单声道 16bit WAV，并提供实时音量电平给波形动画
@MainActor
@Observable
final class VoiceRecorder {
    private(set) var isRecording = false
    /// 最近一段时间的音量（0...1），用于画波形
    private(set) var levels: [CGFloat] = Array(repeating: 0.05, count: 24)

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var startedAt = Date.now

    enum RecordError: LocalizedError {
        case permissionDenied, tooShort

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "没有麦克风权限，请在「设置 → 橄榄」里打开麦克风。"
            case .tooShort: "说话时间太短"
            }
        }
    }

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw RecordError.permissionDenied }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        r.record()
        recorder = r
        startedAt = .now
        isRecording = true

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleLevel() }
        }
    }

    /// 停止录音。`keep` 为 false 时丢弃录音（上滑取消）
    func stop(keep: Bool) throws -> Data? {
        meterTimer?.invalidate()
        meterTimer = nil
        guard let r = recorder else { return nil }
        let duration = r.currentTime
        r.stop()
        recorder = nil
        isRecording = false
        levels = Array(repeating: 0.05, count: levels.count)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { try? FileManager.default.removeItem(at: r.url) }

        guard keep else { return nil }
        guard duration >= 0.6 else { throw RecordError.tooShort }
        return try Data(contentsOf: r.url)
    }

    private func sampleLevel() {
        guard let r = recorder else { return }
        r.updateMeters()
        // averagePower 为 -160...0 dB，映射到 0...1
        let db = max(r.averagePower(forChannel: 0), -50)
        let level = CGFloat((db + 50) / 50)
        levels.removeFirst()
        levels.append(max(0.05, level))
    }
}

/// 火山引擎「大模型录音文件识别 2.0 标准版」：提交音频（base64）后轮询查询结果，短语音通常 1 秒内返回
struct VolcASRClient {
    var apiKey: String
    var resourceID = "volc.seedasr.auc"
    var base = URL(string: "https://openspeech.bytedance.com/api/v3/auc/bigmodel")!

    enum ASRError: LocalizedError {
        case missingCredentials
        case server(String, String)
        case empty
        case timeout

        var errorDescription: String? {
            switch self {
            case .missingCredentials: "还没有配置火山语音识别的 API Key，请到「设置」里填写。"
            case .server(let code, let msg): "语音识别失败（\(code)）：\(msg)"
            case .empty: "没有识别到说话内容"
            case .timeout: "语音识别超时，请重试"
            }
        }
    }

    func recognize(wav: Data) async throws -> String {
        guard !apiKey.isEmpty else { throw ASRError.missingCredentials }
        let requestID = UUID().uuidString
        let body: [String: Any] = [
            "user": ["uid": "duly"],
            "audio": ["data": wav.base64EncodedString(), "format": "wav"],
            "request": ["model_name": "bigmodel", "enable_itn": true, "enable_punc": true],
        ]
        let (_, submitStatus, submitMsg) = try await call("submit", requestID: requestID, body: body)
        guard submitStatus == "20000000" else { throw ASRError.server(submitStatus, submitMsg) }

        // 20000001 处理中 / 20000002 排队中 / 20000000 完成 / 20000003 静音
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(400))
            let (data, status, msg) = try await call("query", requestID: requestID, body: [:])
            switch status {
            case "20000001", "20000002":
                continue
            case "20000003":
                throw ASRError.empty
            case "20000000":
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let text = ((json?["result"] as? [String: Any])?["text"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { throw ASRError.empty }
                return text
            default:
                throw ASRError.server(status, msg)
            }
        }
        throw ASRError.timeout
    }

    private func call(_ path: String, requestID: String, body: [String: Any]) async throws -> (Data, String, String) {
        var req = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        req.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        req.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        req.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let status = http?.value(forHTTPHeaderField: "X-Api-Status-Code") ?? "\(http?.statusCode ?? 0)"
        let msg = http?.value(forHTTPHeaderField: "X-Api-Message") ?? String(data: data, encoding: .utf8) ?? ""
        return (data, status, msg)
    }
}
