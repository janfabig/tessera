// Draws the app icon: nine mosaic stones on dark navy, one of them lit. Run with `make icon`.
import AppKit

let navy = NSColor(srgbRed: 0, green: 3 / 255, blue: 35 / 255, alpha: 1)  // #000323
let glow = NSColor(srgbRed: 27 / 255, green: 36 / 255, blue: 102 / 255, alpha: 1)
let lightBlue = NSColor(srgbRed: 166 / 255, green: 221 / 255, blue: 1, alpha: 1)  // #a6ddff

// Hand-laid look: each stone sits a little askew. Row by row from the top; the top right one is lit.
let tilts: [CGFloat] = [-3, 2, 0, 1.5, -2, 3, 2.5, -1, 1.5]
let shades: [CGFloat] = [0.42, 0.3, 1, 0.3, 0.5, 0.36, 0.5, 0.36, 0.26]

/// Draws on a 1024 by 1024 canvas with the origin at the top left.
func draw() {
    let plate = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    navy.setFill()
    plate.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: glow, ending: navy)!.draw(in: plate, relativeCenterPosition: NSPoint(x: 0.25, y: 0.3))

    let stone: CGFloat = 150, step: CGFloat = 190, origin: CGFloat = 512 - step - stone / 2
    for index in 0..<9 {
        let center = NSPoint(x: origin + CGFloat(index % 3) * step + stone / 2, y: origin + CGFloat(index / 3) * step + stone / 2)
        NSGraphicsContext.saveGraphicsState()
        let turn = NSAffineTransform()
        turn.translateX(by: center.x, yBy: center.y)
        turn.rotate(byDegrees: tilts[index])
        turn.concat()
        let path = NSBezierPath(roundedRect: NSRect(x: -stone / 2, y: -stone / 2, width: stone, height: stone), xRadius: 30, yRadius: 30)
        if shades[index] == 1 {
            let halo = NSShadow()
            halo.shadowColor = lightBlue.withAlphaComponent(0.8)
            halo.shadowBlurRadius = 70
            halo.set()
            lightBlue.setFill()
            path.fill()
            NSGradient(starting: .white, ending: lightBlue)!.draw(in: path, angle: -60)
        } else {
            lightBlue.withAlphaComponent(shades[index]).setFill()
            path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: folder)
try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: CGFloat(pixels))
        flip.scaleX(by: CGFloat(pixels) / 1024, yBy: -CGFloat(pixels) / 1024)
        flip.concat()
        draw()
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
