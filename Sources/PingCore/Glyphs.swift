import CoreGraphics

/// Silhouettes drawn for DotaPing in a unit square (y up). They follow the
/// shapes of the in-game ping icons where those are known (ringed "!", flared
/// X, converging arrows, sword, notched shield, ward eye), redrawn as vectors;
/// no game image is bundled.
public enum Glyphs {
    public struct Glyph {
        public let path: CGPath
        /// Even-odd glyphs use nested contours as cut-outs; the others are unions.
        public let evenOdd: Bool
    }
    public static let all: [PingKind: Glyph] = Dictionary(uniqueKeysWithValues: PingKind.allCases.map { ($0, make($0)) })
    public static func glyph(_ kind: PingKind) -> Glyph { all[kind]! }

    private static func make(_ kind: PingKind) -> Glyph {
        let path = CGMutablePath()
        switch kind {
        case .regular:
            // Ringed exclamation mark: the ordinary ping.
            path.addEllipse(in: circle(0.5, 0.5, 0.47))
            path.addEllipse(in: circle(0.5, 0.5, 0.375))
            path.addPath(polygon([(0.428, 0.80), (0.572, 0.80), (0.536, 0.40), (0.464, 0.40)], radius: 0.03))
            path.addEllipse(in: circle(0.5, 0.275, 0.07))
            return Glyph(path: path, evenOdd: true)
        case .warning:
            // X whose arms flare out towards the tips. Both bars wind the same way,
            // so their overlap stays filled.
            let l: CGFloat = 0.55, tip: CGFloat = 0.125, waist: CGFloat = 0.06
            let bar: [(CGFloat, CGFloat)] = [(-l, -tip), (0, -waist), (l, -tip), (l, tip), (0, waist), (-l, tip)]
            for rotation in [CGFloat.pi/4, -CGFloat.pi/4] { path.addPath(polygon(place(bar, rotation: rotation), radius: 0.015)) }
            return Glyph(path: path, evenOdd: false)
        case .caution:
            // Point-down triangle with a cut-out exclamation mark.
            path.addPath(polygon([(0.03, 0.91), (0.97, 0.91), (0.5, 0.05)], radius: 0.07))
            path.addPath(polygon([(0.452, 0.80), (0.548, 0.80), (0.526, 0.53), (0.474, 0.53)], radius: 0.02))
            path.addEllipse(in: circle(0.5, 0.43, 0.052))
            return Glyph(path: path, evenOdd: true)
        case .attack:
            // Broad sword raised to the upper right.
            let sword: [(CGFloat, CGFloat)] = [(0, 0.64), (0.095, 0.47), (0.095, -0.20), (0.25, -0.20), (0.25, -0.29),
                                               (0.05, -0.29), (0.05, -0.505), (-0.05, -0.505), (-0.05, -0.29),
                                               (-0.25, -0.29), (-0.25, -0.20), (-0.095, -0.20), (-0.095, 0.47)]
            path.addPath(polygon(place(sword, rotation: -.pi/4), radius: 0.012))
            let pommel = place([(0, -0.575)], rotation: -.pi/4)[0]
            path.addPath(polygon(circlePoints(pommel.0, pommel.1, 0.075)))
            return Glyph(path: path, evenOdd: false)
        case .onMyWay:
            // Three arrows converging on the spot: one from above, two from below.
            let arrow: [(CGFloat, CGFloat)] = [(0, 0.07), (0.17, 0.26), (0.068, 0.26), (0.068, 0.50), (-0.068, 0.50), (-0.068, 0.26), (-0.17, 0.26)]
            for rotation in [0, 0.75 * CGFloat.pi, -0.75 * CGFloat.pi] { path.addPath(polygon(place(arrow, rotation: rotation), radius: 0.012)) }
            return Glyph(path: path, evenOdd: true)
        case .assist:
            // Raised open hand. Palm, fingers and thumb share one winding direction.
            func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, rotation: CGFloat = 0) {
                var transform = CGAffineTransform(translationX: x, y: y).rotated(by: rotation)
                path.addPath(CGPath(roundedRect: CGRect(x: -width/2, y: -height/2, width: width, height: height),
                                    cornerWidth: min(width, height)/2, cornerHeight: min(width, height)/2, transform: &transform))
            }
            path.addPath(CGPath(roundedRect: CGRect(x: 0.27, y: 0.04, width: 0.48, height: 0.50), cornerWidth: 0.13, cornerHeight: 0.13, transform: nil))
            for (index, top) in [CGFloat(0.84), 0.93, 0.89, 0.77].enumerated() {
                let x = 0.322 + CGFloat(index)*0.125
                bar(x, (top+0.40)/2, 0.105, top-0.40)
            }
            bar(0.215, 0.40, 0.11, 0.34, rotation: 0.55)
            return Glyph(path: path, evenOdd: false)
        case .defend:
            // Shield with a notched top edge and an inset rim.
            let shield = CGMutablePath()
            shield.move(to: CGPoint(x: 0.5, y: 0.85))
            shield.addQuadCurve(to: CGPoint(x: 0.91, y: 0.96), control: CGPoint(x: 0.72, y: 0.85))
            shield.addLine(to: CGPoint(x: 0.88, y: 0.52))
            shield.addQuadCurve(to: CGPoint(x: 0.5, y: 0.03), control: CGPoint(x: 0.85, y: 0.17))
            shield.addQuadCurve(to: CGPoint(x: 0.12, y: 0.52), control: CGPoint(x: 0.15, y: 0.17))
            shield.addLine(to: CGPoint(x: 0.09, y: 0.96))
            shield.addQuadCurve(to: CGPoint(x: 0.5, y: 0.85), control: CGPoint(x: 0.28, y: 0.85))
            shield.closeSubpath()
            path.addPath(shield)
            for factor: CGFloat in [0.80, 0.64] {
                var inset = CGAffineTransform(translationX: 0.5, y: 0.53).scaledBy(x: factor, y: factor).translatedBy(x: -0.5, y: -0.53)
                path.addPath(shield.copy(using: &inset)!)
            }
            return Glyph(path: path, evenOdd: true)
        case .enemyWard:
            // Solid ward eye, like the Observer Ward map icon.
            path.addPath(almond(left: 0.02, right: 0.98, y: 0.5, lift: 0.58))
            path.addEllipse(in: circle(0.5, 0.5, 0.20))
            path.addEllipse(in: circle(0.5, 0.5, 0.10))
            return Glyph(path: path, evenOdd: true)
        case .friendlyWard:
            // Outlined ward eye, like the Sentry Ward map icon. In game both ward
            // pings share one icon and differ by colour; the outline keeps them
            // apart when the wheel is not highlighted.
            path.addPath(almond(left: 0.02, right: 0.98, y: 0.5, lift: 0.58))
            path.addPath(almond(left: 0.15, right: 0.85, y: 0.5, lift: 0.40))
            path.addEllipse(in: circle(0.5, 0.5, 0.11))
            return Glyph(path: path, evenOdd: true)
        }
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect {
        CGRect(x: x-r, y: y-r, width: r*2, height: r*2)
    }
    private static func circlePoints(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> [(CGFloat, CGFloat)] {
        (0..<28).map { i in
            let a = CGFloat(i) * 2 * .pi/28
            return (x+cos(a)*r, y+sin(a)*r)
        }
    }
    /// Rotates points about the origin, then centres them in the unit square.
    private static func place(_ points: [(CGFloat, CGFloat)], rotation: CGFloat) -> [(CGFloat, CGFloat)] {
        points.map { x, y in (0.5 + x*cos(rotation) - y*sin(rotation), 0.5 + x*sin(rotation) + y*cos(rotation)) }
    }
    /// Counter-clockwise polygon, with optional rounded corners.
    private static func polygon(_ raw: [(CGFloat, CGFloat)], radius: CGFloat = 0) -> CGPath {
        var points = raw.map { CGPoint(x: $0.0, y: $0.1) }
        let area = points.indices.reduce(CGFloat(0)) { sum, i in
            let a = points[i], b = points[(i+1)%points.count]
            return sum + a.x*b.y - b.x*a.y
        }
        if area < 0 { points.reverse() }
        let path = CGMutablePath()
        guard radius > 0 else { path.addLines(between: points); path.closeSubpath(); return path }
        let last = points[points.count-1], first = points[0]
        path.move(to: CGPoint(x: (last.x+first.x)/2, y: (last.y+first.y)/2))
        for i in points.indices {
            path.addArc(tangent1End: points[i], tangent2End: points[(i+1)%points.count], radius: radius)
        }
        path.closeSubpath()
        return path
    }
    private static func almond(left: CGFloat, right: CGFloat, y: CGFloat, lift: CGFloat) -> CGPath {
        let path = CGMutablePath(), mid = (left+right)/2
        path.move(to: CGPoint(x: left, y: y))
        path.addQuadCurve(to: CGPoint(x: right, y: y), control: CGPoint(x: mid, y: y+lift))
        path.addQuadCurve(to: CGPoint(x: left, y: y), control: CGPoint(x: mid, y: y-lift))
        path.closeSubpath()
        return path
    }
}
