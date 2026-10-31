import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let W = CGFloat(size)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// 翻成 y 向下，坐标与开屏 OliveEmblem 的归一化坐标一致
ctx.translateBy(x: 0, y: W)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
}
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * W, y: y * W) }

/// 柳叶形叶片：base → tip，两侧各一条二次曲线
func leaf(_ base: CGPoint, _ tip: CGPoint, width: CGFloat) -> CGPath {
    let dx = tip.x - base.x, dy = tip.y - base.y
    let len = hypot(dx, dy)
    let nx = -dy / len * width * W, ny = dx / len * width * W
    let mid = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
    let path = CGMutablePath()
    path.move(to: base)
    path.addQuadCurve(to: tip, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
    path.addQuadCurve(to: base, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
    return path
}

// 背景：深橄榄绿，左上略亮
ctx.drawLinearGradient(gradient([rgb(0x4A6421), rgb(0x2B3D14), rgb(0x1A260C)], [0, 0.55, 1]),
                       start: p(0.1, 0), end: p(0.9, 1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// 枝梗
ctx.setStrokeColor(rgb(0x8A6A3A))
ctx.setLineWidth(0.028 * W)
ctx.setLineCap(.round)
ctx.move(to: p(0.53, 0.36))
ctx.addQuadCurve(to: p(0.64, 0.22), control: p(0.55, 0.26))
ctx.strokePath()

// 两片银绿色叶子
for (base, tip) in [(p(0.64, 0.22), p(0.27, 0.13)), (p(0.64, 0.22), p(0.88, 0.45))] {
    ctx.saveGState()
    ctx.addPath(leaf(base, tip, width: 0.075))
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xEEF3D6), rgb(0xA9BD73)], [0, 1]),
                           start: base, end: tip, options: [])
    ctx.restoreGState()
    // 叶脉
    ctx.setStrokeColor(rgb(0x7E9450, 0.8))
    ctx.setLineWidth(0.008 * W)
    ctx.move(to: base)
    ctx.addLine(to: tip)
    ctx.strokePath()
}

// 果实：倾斜的椭圆，径向渐变做出光泽
ctx.saveGState()
ctx.translateBy(x: 0.47 * W, y: 0.62 * W)
ctx.rotate(by: 0.38)
let fruit = CGRect(x: -0.215 * W, y: -0.275 * W, width: 0.43 * W, height: 0.55 * W)
ctx.saveGState()
ctx.addEllipse(in: fruit)
ctx.clip()
ctx.drawRadialGradient(gradient([rgb(0xE2EC8A), rgb(0x9DB534), rgb(0x5E7A18), rgb(0x3A4E0E)], [0, 0.3, 0.75, 1]),
                       startCenter: CGPoint(x: -0.08 * W, y: -0.12 * W), startRadius: 0,
                       endCenter: CGPoint(x: 0, y: 0), endRadius: 0.30 * W, options: [.drawsAfterEndLocation])
ctx.restoreGState()
// 高光
ctx.setFillColor(rgb(0xFFFFFF, 0.55))
ctx.addEllipse(in: CGRect(x: -0.13 * W, y: -0.19 * W, width: 0.07 * W, height: 0.13 * W))
ctx.fillPath()
ctx.restoreGState()

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
