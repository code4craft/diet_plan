import SwiftUI

/// 静态开屏：深橄榄绿留白 + 居中的橄榄标志与标语。底色与系统启动屏（LaunchBackground）一致，衔接无跳变。
struct SplashView: View {
    var onFinish: () -> Void

    static let background = Color(hex: 0x24330F)

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width * 0.5

            ZStack {
                Self.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()
                    OliveEmblem()
                        .frame(width: side, height: side)
                    Text("橄榄")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .padding(.top, 40)
                    Text("为者常成，行者常至")
                        .font(.system(size: 18, weight: .medium, design: .serif))
                        .tracking(4)
                        .opacity(0.85)
                        .padding(.top, 18)
                    Text("——《晏子春秋》")
                        .font(.system(size: 12, design: .serif))
                        .opacity(0.5)
                        .padding(.top, 10)
                    Spacer()
                    Spacer()
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            onFinish()
        }
    }
}

/// 带两片叶子的橄榄（与 App 图标同一图形，坐标按边长归一化，见 tools/AppIcon.swift）
private struct OliveEmblem: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * w) }

            var stem = Path()
            stem.move(to: p(0.53, 0.36))
            stem.addQuadCurve(to: p(0.64, 0.22), control: p(0.55, 0.26))
            ctx.stroke(stem, with: .color(Color(hex: 0x8A6A3A)), style: StrokeStyle(lineWidth: 0.028 * w, lineCap: .round))

            for (base, tip) in [(p(0.64, 0.22), p(0.27, 0.13)), (p(0.64, 0.22), p(0.88, 0.45))] {
                ctx.fill(leaf(base, tip, width: 0.075 * w),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0xEEF3D6), Color(hex: 0xA9BD73)]),
                                               startPoint: base, endPoint: tip))
                var vein = Path()
                vein.move(to: base)
                vein.addLine(to: tip)
                ctx.stroke(vein, with: .color(Color(hex: 0x7E9450).opacity(0.8)), lineWidth: 0.008 * w)
            }

            var fruitCtx = ctx
            fruitCtx.translateBy(x: 0.47 * w, y: 0.62 * w)
            fruitCtx.rotate(by: .radians(0.38))
            let fruit = Path(ellipseIn: CGRect(x: -0.215 * w, y: -0.275 * w, width: 0.43 * w, height: 0.55 * w))
            fruitCtx.fill(fruit, with: .radialGradient(
                Gradient(stops: [.init(color: Color(hex: 0xE2EC8A), location: 0),
                                 .init(color: Color(hex: 0x9DB534), location: 0.3),
                                 .init(color: Color(hex: 0x5E7A18), location: 0.75),
                                 .init(color: Color(hex: 0x3A4E0E), location: 1)]),
                center: CGPoint(x: -0.08 * w, y: -0.12 * w), startRadius: 0, endRadius: 0.30 * w))
            fruitCtx.fill(Path(ellipseIn: CGRect(x: -0.13 * w, y: -0.19 * w, width: 0.07 * w, height: 0.13 * w)),
                          with: .color(.white.opacity(0.55)))
        }
    }

    /// 柳叶形叶片：base → tip，两侧各一条二次曲线
    private func leaf(_ base: CGPoint, _ tip: CGPoint, width: CGFloat) -> Path {
        let dx = tip.x - base.x, dy = tip.y - base.y
        let len = hypot(dx, dy)
        let nx = -dy / len * width, ny = dx / len * width
        let mid = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
        var path = Path()
        path.move(to: base)
        path.addQuadCurve(to: tip, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
        path.addQuadCurve(to: base, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
        return path
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

#Preview { SplashView {} }
