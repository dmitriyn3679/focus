import AppKit

@main
struct MakeIcon {
    static let bolt: [CGPoint] = [
        CGPoint(x: 0.00, y: 0.38),
        CGPoint(x: 0.56, y: 0.82),
        CGPoint(x: 0.56, y: 0.53),
        CGPoint(x: 1.00, y: 0.62),
        CGPoint(x: 0.42, y: 0.18),
        CGPoint(x: 0.42, y: 0.47),
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: MakeIcon <iconset-dir>\n".utf8))
            exit(2)
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            try render(pixels: points).write(to: directory.appendingPathComponent("icon_\(points)x\(points).png"))
            try render(pixels: points * 2).write(to: directory.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
        }
    }

    static func render(pixels: Int) throws -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let side = CGFloat(pixels)
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }

        let scale = side / 1024
        let tile = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * scale, yRadius: 185 * scale)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
        shadow.shadowBlurRadius = 24 * scale
        shadow.set()
        NSColor.black.setFill()
        tilePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.36, green: 0.29, blue: 0.86, alpha: 1),
            NSColor(srgbRed: 0.16, green: 0.12, blue: 0.42, alpha: 1),
        ])!
        gradient.draw(in: tilePath, angle: -90)

        let boltBox = tile.insetBy(dx: tile.width * 0.17, dy: tile.height * 0.17)
        let boltPath = NSBezierPath()
        for (index, point) in bolt.enumerated() {
            let mapped = NSPoint(x: boltBox.minX + point.x * boltBox.width, y: boltBox.minY + point.y * boltBox.height)
            if index == 0 { boltPath.move(to: mapped) } else { boltPath.line(to: mapped) }
        }
        boltPath.close()
        boltPath.lineJoinStyle = .round

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 0.55)
        glow.shadowOffset = .zero
        glow.shadowBlurRadius = 40 * scale
        glow.set()
        NSColor(srgbRed: 1, green: 0.84, blue: 0.25, alpha: 1).setFill()
        boltPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
