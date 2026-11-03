// Renders the OpenMount app icon (1024×1024 PNG) with Core Graphics.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)   // top-left origin

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// macOS icon grid: 824pt body centred in a 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = rounded(body, 186)

// Drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: rgb(0x000000, 0.45))
ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x15171C)); ctx.fillPath()
ctx.restoreGState()

// Background: deep graphite
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x2B2F38), rgb(0x16181D)], [0, 1]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

// Light bar along the top with a warm glow spilling down
let bar = CGRect(x: 190, y: 214, width: 644, height: 34)
let barColors = [rgb(0xFF7A18), rgb(0xFF3D6E), rgb(0xB14DFF), rgb(0x3D8BFF)]
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: rgb(0xFF5A3C, 0.9))
ctx.addPath(rounded(bar, 17)); ctx.setFillColor(rgb(0xFF5A3C)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(rounded(bar, 17)); ctx.clip()
ctx.drawLinearGradient(gradient(barColors, [0, 0.4, 0.72, 1]), start: CGPoint(x: bar.minX, y: 0), end: CGPoint(x: bar.maxX, y: 0), options: [])
ctx.restoreGState()
// soft wash under the bar
ctx.drawRadialGradient(gradient([rgb(0xFF6A3D, 0.35), rgb(0xFF6A3D, 0)], [0, 1]),
                       startCenter: CGPoint(x: 512, y: 250), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 250), endRadius: 430, options: [])

// Keycap: side (skirt) then top face
let cap = CGRect(x: 302, y: 352, width: 420, height: 420)
let skirt = rounded(cap, 92)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 30), blur: 50, color: rgb(0x000000, 0.55))
ctx.addPath(skirt); ctx.setFillColor(rgb(0x0E0F12)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(skirt); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x4A4F5A), rgb(0x2A2D34)], [0, 1]),
                       start: CGPoint(x: 512, y: cap.minY), end: CGPoint(x: 512, y: cap.maxY), options: [])
ctx.restoreGState()

let top = CGRect(x: cap.minX + 44, y: cap.minY + 30, width: cap.width - 88, height: cap.height - 112)
let topPath = rounded(top, 64)
ctx.saveGState()
ctx.addPath(topPath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x6A707C), rgb(0x434852)], [0, 1]),
                       start: CGPoint(x: 512, y: top.minY), end: CGPoint(x: 512, y: top.maxY), options: [])
// warm reflection of the light bar on the cap's upper edge
ctx.drawLinearGradient(gradient([rgb(0xFF8A4C, 0.45), rgb(0xFF8A4C, 0)], [0, 1]),
                       start: CGPoint(x: 512, y: top.minY), end: CGPoint(x: 512, y: top.minY + 90), options: [])
ctx.restoreGState()
ctx.addPath(topPath); ctx.setStrokeColor(rgb(0xFFFFFF, 0.12)); ctx.setLineWidth(3); ctx.strokePath()

// Legend: ⌘ with an orange glow (the Mac key on a keyboard made for Windows)
let legend = NSAttributedString(string: "⌘", attributes: [
    .font: NSFont.systemFont(ofSize: 200, weight: .semibold),
    .foregroundColor: NSColor(srgbRed: 1, green: 0.93, blue: 0.88, alpha: 1),
])
let lsize = legend.size()
NSGraphicsContext.saveGraphicsState()
let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
NSGraphicsContext.current = ns
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 36, color: rgb(0xFF6A2B, 0.95))
legend.draw(at: CGPoint(x: top.midX - lsize.width / 2, y: top.midY - lsize.height / 2 - 4))
ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()

// Glass highlight on the top half of the body
ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.08), rgb(0xFFFFFF, 0)], [0, 1]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 520), options: [])
ctx.restoreGState()

// Hairline edge
ctx.addPath(rounded(body.insetBy(dx: 1.5, dy: 1.5), 185)); ctx.setStrokeColor(rgb(0xFFFFFF, 0.10)); ctx.setLineWidth(3); ctx.strokePath()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
