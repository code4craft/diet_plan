import SwiftUI

/// 静态开屏：深色留白 + 居中的日出标志与标语。底色与系统启动屏（LaunchBackground）一致，衔接无跳变。
struct SplashView: View {
    var onFinish: () -> Void

    static let night = Color(hex: 0x2A0A2E)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let r = w * 0.12

            ZStack {
                Self.night.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()
                    SunEmblem(radius: r)
                        .frame(width: r * 4, height: r * 2.2)
                    Text("Duly")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .padding(.top, 56)
                    Text("Here for the long run.")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .tracking(1)
                        .opacity(0.85)
                        .padding(.top, 14)
                    Spacer()
                    Spacer()
                    VStack(spacing: 8) {
                        Text("为者常成，行者常至")
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .tracking(4)
                        Text("——《晏子春秋》")
                            .font(.system(size: 11, design: .serif))
                    }
                    .opacity(0.55)
                    .padding(.bottom, 28)
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

/// 地平线上的半轮太阳 + 刻度光芒（与 App 图标同一母题）
private struct SunEmblem: View {
    let radius: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height - 2)

            // 光晕：径向渐变在画布内衰减到 0，避免模糊滤镜被画布边界截出硬边
            ctx.fill(halfDisc(c, radius * 1.95),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0xFF7A1A).opacity(0.55), Color(hex: 0xFF7A1A).opacity(0)]),
                                           center: c, startRadius: radius, endRadius: radius * 1.95))

            ctx.fill(halfDisc(c, radius),
                     with: .linearGradient(Gradient(colors: [.white, Color(hex: 0xFFF2A8), Color(hex: 0xFFD23F)]),
                                           startPoint: CGPoint(x: c.x, y: c.y - radius), endPoint: c))

            for i in 1...17 {
                let a = CGFloat(i) * .pi / 18
                let major = i % 3 == 0
                let inner = radius * 1.22
                let outer = inner + radius * (major ? 0.5 : 0.26)
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y - sin(a) * inner))
                p.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y - sin(a) * outer))
                ctx.stroke(p, with: .color(.white.opacity(major ? 1 : 0.7)),
                           style: StrokeStyle(lineWidth: major ? 4 : 2.5, lineCap: .round))
            }

            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: c.y))
            horizon.addLine(to: CGPoint(x: size.width, y: c.y))
            ctx.stroke(horizon, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    private func halfDisc(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        p.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.closeSubpath()
        return p
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

#Preview { SplashView {} }
