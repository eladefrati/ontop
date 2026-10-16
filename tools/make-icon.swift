// Renders the app icon as an .iconset directory: a pushpin on a rounded square, drawn
// with paths so no licensed symbol artwork is embedded. Usage: swift make-icon.swift <out.iconset>
import AppKit

let outDir = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // Apple's macOS icon grid: 824 pt square centered on a 1024 pt canvas.
    let square = NSRect(x: 100, y: 100, width: 824, height: 824)
    let plate = NSBezierPath(roundedRect: square, xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.36, alpha: 1),
                        NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.18, alpha: 1)])!
        .draw(in: plate, angle: -90)

    // Pushpin, drawn upright around the canvas center and tilted.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512)
    ctx.rotate(by: -.pi / 5)
    ctx.translateBy(x: 0, y: 40)
    let pin = NSBezierPath()
    pin.append(NSBezierPath(roundedRect: NSRect(x: -150, y: 150, width: 300, height: 120), xRadius: 40, yRadius: 40))
    pin.append(NSBezierPath(rect: NSRect(x: -60, y: 70, width: 120, height: 90)))
    pin.append(NSBezierPath(roundedRect: NSRect(x: -200, y: 0, width: 400, height: 80), xRadius: 30, yRadius: 30))
    let needle = NSBezierPath()
    needle.move(to: NSPoint(x: -28, y: 10))
    needle.line(to: NSPoint(x: 28, y: 10))
    needle.line(to: NSPoint(x: 0, y: -300))
    needle.close()
    pin.append(needle)
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor.white.setFill()
    pin.fill()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let rep = render(points * scale)
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
