import SwiftData
import SwiftUI

@main
struct DietPlanApp: App {
    @State private var settings = AppSettings.shared
    @State private var health = HealthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(health)
        }
        .modelContainer(for: [BehaviorRecord.self, ChatMessage.self])
    }
}

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthStore.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = !UserDefaults.standard.bool(forKey: "debugSkipSplash")
    /// 调试用：启动参数 `-debugInitialTab 1` 可直接打开指定 Tab
    @State private var tab = UserDefaults.standard.integer(forKey: "debugInitialTab")

    var body: some View {
        ZStack {
            tabs
            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.5)) { showSplash = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        // 开屏结束后再请求健康授权，避免授权弹窗盖住动画
        .task(id: showSplash) {
            if !showSplash { await health.refresh(settings: settings) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !showSplash { Task { await health.refresh(settings: settings) } }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("今日", systemImage: "chart.bar.doc.horizontal") }
                .tag(0)
            ChatView()
                .tabItem { Label("记录", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(1)
            PointsView()
                .tabItem { Label("积分", systemImage: "star.circle") }
                .tag(2)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(3)
        }
    }
}
