import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let W = CGFloat(size)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func linear(_ colors: [CGColor], _ locs: [CGFloat], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

let horizon: CGFloat = 380          // CG 原点在左下
let center = CGPoint(x: W / 2, y: horizon)
let r: CGFloat = 250

// 天空：上方深靛蓝 → 地平线处暖杏色
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: horizon, width: W, height: W - horizon))
linear([rgb(0xC2185B), rgb(0xFF3D3D), rgb(0xFF7A1A), rgb(0xFFC23C)], [0, 0.4, 0.75, 1],
       from: CGPoint(x: 0, y: W), to: CGPoint(x: 0, y: horizon))
// 太阳周围的光晕
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFFF3B0, 0.85), rgb(0xFFE070, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: center, startRadius: r, endCenter: center, endRadius: r * 2.3, options: [])
ctx.restoreGState()

// 地面 / 水面
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: 0, width: W, height: horizon))
linear([rgb(0x5A0F3C), rgb(0x2A0A2E)], [0, 1], from: CGPoint(x: 0, y: horizon), to: CGPoint(x: 0, y: 0))
// 水面倒影：几道逐渐变短变淡的横线
for i in 0..<4 {
    let y = horizon - 70 - CGFloat(i) * 62
    let half = r * (0.95 - CGFloat(i) * 0.2)
    ctx.setStrokeColor(rgb(0xFFC23C, 0.9 - CGFloat(i) * 0.18))
    ctx.setLineWidth(24 - CGFloat(i) * 4)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: W / 2 - half, y: y))
    ctx.addLine(to: CGPoint(x: W / 2 + half, y: y))
    ctx.strokePath()
}
ctx.restoreGState()

// 半轮太阳
ctx.saveGState()
ctx.addArc(center: center, radius: r, startAngle: 0, endAngle: .pi, clockwise: false)
ctx.closePath()
ctx.clip()
linear([rgb(0xFFFFFF), rgb(0xFFF2A8), rgb(0xFFD23F)], [0, 0.45, 1],
       from: CGPoint(x: 0, y: horizon + r), to: CGPoint(x: 0, y: horizon))
ctx.restoreGState()

// 刻度：沿太阳外圈 0°~180°，每 10° 一格，每 30° 长刻度
ctx.setLineCap(.round)
for i in 1...17 {
    let a = CGFloat(i) * .pi / 18
    let major = i % 3 == 0
    let inner = r + 30
    let outer = inner + (major ? 120 : 64)
    ctx.setStrokeColor(rgb(0xFFFFFF, major ? 1 : 0.8))
    ctx.setLineWidth(major ? 26 : 16)
    ctx.move(to: CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner))
    ctx.addLine(to: CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer))
    ctx.strokePath()
}

// 地平线
ctx.setStrokeColor(rgb(0xFFFFFF, 1))
ctx.setLineWidth(12)
ctx.move(to: CGPoint(x: 80, y: horizon))
ctx.addLine(to: CGPoint(x: W - 80, y: horizon))
ctx.strokePath()

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
