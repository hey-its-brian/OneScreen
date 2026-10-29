// Renders the OneScreen app icon with plain Core Graphics paths (no fonts or SF Symbols).
// A dark rounded body with two monitors: the main one lit, the second one dimmed.
// Usage: swift render.swift <out.png>                 (1024px preview)
//        swift render.swift --appiconset <dir>        (all macOS sizes plus Contents.json)
import AppKit

let S: CGFloat = 1024
func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let bgTop = hex(0x2B2E36), bgBottom = hex(0x14161B)
let litTop = hex(0x5FA8FF), litBottom = hex(0x2B6FD6)
let dimScreen = hex(0x3A3E48), bezel = hex(0xD9DCE3), dimBezel = hex(0x6B6F7A)

// macOS icon grid: 824pt body centered on a 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

struct Monitor { let frame: CGRect; let lit: Bool }
// The dim monitor sits behind and to the left; the lit one in front and to the right.
let monitors = [
    Monitor(frame: CGRect(x: 190, y: 420, width: 400, height: 270), lit: false),
    Monitor(frame: CGRect(x: 350, y: 330, width: 470, height: 320), lit: true),
]

func drawMonitor(_ m: Monitor) {
    let f = m.frame
    let frameColor = m.lit ? bezel : dimBezel
    // Stand: neck and foot.
    let neck = CGRect(x: f.midX - f.width * 0.06, y: f.minY - f.height * 0.16, width: f.width * 0.12, height: f.height * 0.17)
    let foot = CGRect(x: f.midX - f.width * 0.26, y: f.minY - f.height * 0.22, width: f.width * 0.52, height: f.height * 0.07)
    frameColor.setFill()
    NSBezierPath(rect: neck).fill()
    NSBezierPath(roundedRect: foot, xRadius: foot.height / 2, yRadius: foot.height / 2).fill()

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(m.lit ? 0.45 : 0.3)
    shadow.shadowBlurRadius = m.lit ? 30 : 18
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    let shell = NSBezierPath(roundedRect: f, xRadius: 28, yRadius: 28)
    frameColor.setFill(); shell.fill()
    NSGraphicsContext.restoreGraphicsState()

    let screen = f.insetBy(dx: 18, dy: 18)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: 16, yRadius: 16)
    if m.lit {
        NSGraphicsContext.saveGraphicsState()
        screenPath.addClip()
        NSGradient(starting: litTop, ending: litBottom)!.draw(in: screen, angle: -70)
        // Glossy sweep across the top.
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
            .draw(in: CGRect(x: screen.minX, y: screen.midY, width: screen.width, height: screen.height / 2), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    } else {
        dimScreen.setFill(); screenPath.fill()
    }
}

func draw() {
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(starting: bgTop, ending: bgBottom)!.draw(in: body, angle: -90)
    NSGradient(colors: [litBottom.withAlphaComponent(0.25), litBottom.withAlphaComponent(0)])!
        .draw(fromCenter: CGPoint(x: 585, y: 490), radius: 0, toCenter: CGPoint(x: 585, y: 490), radius: 440, options: [])
    for m in monitors { drawMonitor(m) }
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.08), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: S, height: S)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
if args.count == 3, args[1] == "--appiconset" {
    let dir = URL(fileURLWithPath: args[2])
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var images: [String] = []
    for pt in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
            try render(size: pt * scale).write(to: dir.appendingPathComponent(name))
            images.append(#"    { "idiom" : "mac", "size" : "\#(pt)x\#(pt)", "scale" : "\#(scale)x", "filename" : "\#(name)" }"#)
        }
    }
    let contents = "{\n  \"images\" : [\n\(images.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
    try contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
} else if args.count == 2 {
    try render(size: 1024).write(to: URL(fileURLWithPath: args[1]))
} else {
    print("usage: swift render.swift <out.png> | --appiconset <dir>")
}
