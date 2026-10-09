import AppKit

// Original app icon: a dark ping wheel with one lit sector and a ringed "!".
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let red = NSColor(srgbRed: 0.86, green: 0.25, blue: 0.16, alpha: 1)
let steel = NSColor(srgbRed: 0.64, green: 0.68, blue: 0.72, alpha: 1)
for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = size*factor
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let s = CGFloat(pixels), inset = s*0.04, c = CGPoint(x: s/2, y: s/2)
        let tile = NSBezierPath(roundedRect: CGRect(x: inset, y: inset, width: s-inset*2, height: s-inset*2), xRadius: s*0.22, yRadius: s*0.22)
        NSGradient(colors: [NSColor(srgbRed: 0.13, green: 0.07, blue: 0.065, alpha: 1), NSColor(srgbRed: 0.035, green: 0.038, blue: 0.045, alpha: 1)])!.draw(in: tile, angle: -90)
        // Lit north sector of the wheel.
        let outer = s*0.36, inner = s*0.205
        let sector = NSBezierPath()
        sector.appendArc(withCenter: c, radius: outer, startAngle: 112.5, endAngle: 67.5, clockwise: true)
        sector.appendArc(withCenter: c, radius: inner, startAngle: 67.5, endAngle: 112.5, clockwise: false)
        sector.close()
        red.withAlphaComponent(0.55).setFill(); sector.fill()
        let wheel = NSBezierPath(ovalIn: CGRect(x: c.x-outer, y: c.y-outer, width: outer*2, height: outer*2))
        steel.withAlphaComponent(0.55).setStroke(); wheel.lineWidth = max(1, s*0.014); wheel.stroke()
        for i in 0..<8 where size >= 32 {
            let a = (CGFloat(i)*45+22.5) * .pi/180
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: c.x+cos(a)*inner*1.08, y: c.y+sin(a)*inner*1.08))
            tick.line(to: CGPoint(x: c.x+cos(a)*outer*0.94, y: c.y+sin(a)*outer*0.94))
            steel.withAlphaComponent(0.30).setStroke(); tick.lineWidth = max(1, s*0.008); tick.stroke()
        }
        // Centre: ringed exclamation mark.
        let ring = NSBezierPath(ovalIn: CGRect(x: c.x-inner, y: c.y-inner, width: inner*2, height: inner*2))
        NSColor(srgbRed: 0.04, green: 0.042, blue: 0.05, alpha: 1).setFill(); ring.fill()
        red.setStroke(); ring.lineWidth = s*0.03; ring.stroke()
        let bar = NSBezierPath(roundedRect: CGRect(x: c.x-s*0.028, y: c.y-s*0.035, width: s*0.056, height: s*0.17), xRadius: s*0.02, yRadius: s*0.02)
        NSColor.white.setFill(); bar.fill()
        NSBezierPath(ovalIn: CGRect(x: c.x-s*0.033, y: c.y-s*0.13, width: s*0.066, height: s*0.066)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(factor == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
    }
}
