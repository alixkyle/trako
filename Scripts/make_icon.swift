import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appending(path: "Resources", directoryHint: .isDirectory)
let iconset = resources.appending(path: "Trako.iconset", directoryHint: .isDirectory)
let output = resources.appending(path: "Trako.icns")

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(name: String, points: CGFloat, scale: CGFloat)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2)
]

extension NSColor {
    static func trako(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }
}

func drawRoundedLine(from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: end)
    path.lineWidth = width
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    bounds.fill()

    let tileRect = bounds.insetBy(dx: size * 0.04, dy: size * 0.04)
    let tile = NSBezierPath(
        roundedRect: tileRect,
        xRadius: size * 0.22,
        yRadius: size * 0.22
    )

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = size * 0.045
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)
    shadow.set()
    NSColor.black.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        .trako(24, 188, 165),
        .trako(40, 126, 224)
    ])?.draw(in: tile, angle: 35)

    let innerStroke = NSBezierPath(
        roundedRect: tileRect.insetBy(dx: size * 0.018, dy: size * 0.018),
        xRadius: size * 0.195,
        yRadius: size * 0.195
    )
    NSColor.white.withAlphaComponent(0.2).setStroke()
    innerStroke.lineWidth = max(1, size * 0.012)
    innerStroke.stroke()

    let center = CGPoint(x: size * 0.5, y: size * 0.51)
    let radius = size * 0.255
    let ring = NSBezierPath()
    ring.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: 118,
        endAngle: -54,
        clockwise: true
    )
    ring.lineWidth = size * 0.082
    ring.lineCapStyle = .round
    NSColor.white.setStroke()
    ring.stroke()

    let accent = NSBezierPath()
    accent.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: 118,
        endAngle: 44,
        clockwise: true
    )
    accent.lineWidth = size * 0.084
    accent.lineCapStyle = .round
    NSColor.trako(133, 255, 222).setStroke()
    accent.stroke()

    drawRoundedLine(
        from: center,
        to: CGPoint(x: center.x, y: center.y + size * 0.16),
        width: size * 0.036,
        color: .white
    )
    drawRoundedLine(
        from: center,
        to: CGPoint(x: center.x + size * 0.118, y: center.y - size * 0.06),
        width: size * 0.036,
        color: .white
    )

    let hub = NSBezierPath(ovalIn: NSRect(
        x: center.x - size * 0.052,
        y: center.y - size * 0.052,
        width: size * 0.104,
        height: size * 0.104
    ))
    NSColor.white.setFill()
    hub.fill()

    image.unlockFocus()
    image.isTemplate = false
    return image
}

for entry in sizes {
    let pixelSize = entry.points * entry.scale
    let image = drawIcon(size: pixelSize / 2)
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "TrakoIcon", code: 1)
    }

    try data.write(to: iconset.appending(path: entry.name), options: [.atomic])
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "TrakoIcon", code: Int(process.terminationStatus))
}

print(output.path)
