// Renders the Dooodle app icon: a hand-drawn "ooo" loop scribble
// (the three o's of dooodle) in red pen on a soft paper background.
// Usage: swift Scripts/make_icon.swift <output.png>

import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// --- Background: macOS-style rounded rect (icon grid: 824x824 inset) ---
let inset: CGFloat = 100
let bgRect = NSRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let radius: CGFloat = bgRect.width * 0.2237 // Big Sur squircle approximation
let bg = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)

let gradient = NSGradient(
    starting: NSColor(srgbRed: 1.00, green: 1.00, blue: 0.99, alpha: 1),
    ending: NSColor(srgbRed: 0.94, green: 0.93, blue: 0.90, alpha: 1))!
gradient.draw(in: bg, angle: -90)

// subtle edge
NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.06).setStroke()
bg.lineWidth = 4
bg.stroke()

// --- The "ooo" scribble: prolate cycloid (three loops) ---
// x = a*t - b*sin(t), y = -b*cos(t); loops appear when b > a
let a: CGFloat = 46
let b: CGFloat = 118
let loops = 3
var pts: [NSPoint] = []
let steps = 600
let t0 = -CGFloat.pi * 0.55
// loops form around t = 0, 2π, 4π, ... so N loops span (N-1) full periods
// extend past the last loop so the stroke flicks out instead of ending on the circle
let t1 = CGFloat(loops - 1) * 2 * .pi + CGFloat.pi * 0.85
for i in 0...steps {
    let t = t0 + (t1 - t0) * CGFloat(i) / CGFloat(steps)
    let x = a * t - b * sin(t)
    let y = -b * cos(t)
    pts.append(NSPoint(x: x, y: y))
}

// normalize + center, with a slight hand-drawn tilt
let xs = pts.map(\.x), ys = pts.map(\.y)
let w = xs.max()! - xs.min()!, h = ys.max()! - ys.min()!
let targetW: CGFloat = 560
let scale = targetW / w
let cx = (xs.max()! + xs.min()!) / 2, cy = (ys.max()! + ys.min()!) / 2

let tilt: CGFloat = -6 * .pi / 180
let path = NSBezierPath()
for (i, p) in pts.enumerated() {
    var x = (p.x - cx) * scale
    var y = (p.y - cy) * scale
    (x, y) = (x * cos(tilt) - y * sin(tilt), x * sin(tilt) + y * cos(tilt))
    let pt = NSPoint(x: S / 2 + x, y: S / 2 + y + 10)
    i == 0 ? path.move(to: pt) : path.line(to: pt)
}
path.lineWidth = 58
path.lineCapStyle = .round
path.lineJoinStyle = .round

// soft shadow under the ink
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(srgbRed: 0.8, green: 0.1, blue: 0.05, alpha: 0.25)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
shadow.set()

NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1).setStroke() // #FF3B30
path.stroke()
NSGraphicsContext.current?.restoreGraphicsState()

let _ = h // silence unused warning

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
