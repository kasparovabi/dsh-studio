import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
let side = CGFloat(size)

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

context.setFillColor(rgb(0x12, 0x3B, 0x2E))
context.fill(CGRect(x: 0, y: 0, width: side, height: side))

let bars: [CGFloat] = [0.30, 0.58, 0.86, 0.46, 0.72, 0.34, 0.64, 0.42]
let barWidth = side * 0.052
let gap = side * 0.038
let total = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
var x = (side - total) / 2

context.setFillColor(rgb(0xFF, 0xFF, 0xFF))
for bar in bars {
    let height = side * 0.52 * bar
    let rect = CGRect(x: x, y: (side - height) / 2, width: barWidth, height: height)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    context.fillPath()
    x += barWidth + gap
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let url = URL(fileURLWithPath: output)
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("wrote \(output)")
