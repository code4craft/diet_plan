import SwiftUI
import UIKit

/// 「橄榄奶油」配色：奶油绿底 + 暖白卡片 + 橄榄绿主色，与图标、开屏同一套色
enum Theme {
    static let background = Color(hex: 0xF5F3E7)
    static let card = Color(hex: 0xFFFDF6)
    static let cardBorder = Color(hex: 0xECE8D3)
    static let bar = Color(hex: 0xFAF8EE)
    static let barBorder = Color(hex: 0xE4E1CC)

    static let olive = Color(hex: 0x6E7F2A)
    /// 浅底上的橄榄绿文字，比 olive 深一点以保证对比度
    static let oliveText = Color(hex: 0x5E6E22)
    /// 浅橄榄底：积分卡、用户气泡等大面积强调，避免实心深绿看着累
    static let oliveSoft = Color(hex: 0xE4E9C5)
    /// 浅橄榄底上的文字
    static let oliveDeep = Color(hex: 0x46521A)
    static let track = Color(hex: 0xECEAD8)

    static let ink = Color(hex: 0x2B3018)
    static let inkSecondary = Color(hex: 0x66684F)
    static let warning = Color(hex: 0xB0502A)
    static let pending = Color(hex: 0xA0660E)

    /// 导航栏、Tab 栏的 UIKit 外观
    static func applyAppearance() {
        let ink = UIColor(Theme.ink)
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.background)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: ink]
        nav.largeTitleTextAttributes = [.foregroundColor: ink]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.bar)
        tab.shadowColor = UIColor(Theme.barBorder)
        let inactive = UIColor(Color(hex: 0x706F5C))
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = inactive
            item.normal.titleTextAttributes = [.foregroundColor: inactive]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

extension View {
    /// List / Form 换成奶油底 + 暖白行
    func themedList() -> some View {
        scrollContentBackground(.hidden).background(Theme.background)
    }
}
