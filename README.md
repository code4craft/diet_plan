# 橄榄（DietPlan）

橄榄 — 为者常成，行者常至。 精密的计划带来预期的结果。

iOS 17+，SwiftUI + SwiftData + HealthKit；对话/拍照记录用火山方舟豆包解析，按住说话用火山语音识别。

## 结构

| 目录 | 内容 |
|---|---|
| `DietPlan/Scoring/ScoreEngine.swift` | 积分规则与计算（纯函数，有单测） |
| `DietPlan/Services/HealthService.swift` | 从 Apple 健康读体重/去脂体重/体脂/睡眠/步数/活动消耗 |
| `DietPlan/Services/RecordAssistant.swift` | 对话 + 照片 → 豆包 → 健身/饮食记录（支持新增/修改/删除） |
| `DietPlan/Services/HealthStore.swift` | 健康数据缓存 + `Ledger`（每日汇总与积分） |
| `DietPlan/Services/VoiceInput.swift` | 按住说话：录音 + 火山「录音文件识别 2.0」 |
| `DietPlan/Services/ExportService.swift` | 导出 daily.csv / records.csv / weekly.csv |
| `DietPlan/Views/` | 今日、记录（对话）、积分、设置 四个 Tab |

## 跑起来

1. `brew install xcodegen && xcodegen generate`，打开 `DietPlan.xcodeproj`
2. Xcode → Settings → Components 安装 iOS 18.2 平台（或 `xcodebuild -downloadPlatform iOS`）
3. `project.yml` 里的 `DEVELOPMENT_TEAM` 换成自己的 Team（HealthKit 需要真机）
4. 「小米运动健康」里开启同步到 Apple 健康；手环 App 同样打开睡眠同步
5. 密钥：复制 `Config/Secrets.example.xcconfig` 为 `Config/Secrets.xcconfig`（已 gitignore）并填写，首次启动作为默认值；也可以在 App「设置」里填
   - `ARK_API_KEY`：火山方舟 API Key，需开通 `doubao-seed-2-1-pro-260915`
   - `ASR_API_KEY`：豆包语音（新版控制台）API Key，需开通「录音文件识别 2.0」`volc.seedasr.auc`

## 积分规则

- 睡眠（醒来那天计，前一天 18:00 后入睡算当天；没有「睡着」数据时用「卧床」兜底）≥ 7h、饮食当天有记录且总摄入 ≤ 目标：达标 +5；连续第 2/3/4+ 天额外 +1/+2/+3
- 健身每次 +5；一周（周一起）≥ 3 次达标 +5；连续第 2/3/4+ 周额外 +3/+6/+9
- 今天/本周还没结束时显示「进行中」，不计分也不打断连击；今天饮食一旦超标立即判未达标

## 图标

`tools/AppIcon.swift` 用 CoreGraphics 绘制：`xcrun swiftc -o /tmp/icon tools/AppIcon.swift && /tmp/icon DietPlan/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
