import CoreGraphics
import Foundation

enum CADToolMode: String, CaseIterable, Identifiable {
    case pan = "Pan"
    case coordinates = "Coords"
    case distance = "Dist"
    case angleBearing = "Angle/Brg"
    case area = "Area"
    case drawLine = "Line"
    case drawPolyline = "Poly"
    case drawCircle = "Circle"
    case dimension = "Dim"
    case offset = "Offset"
    case align = "Align"
    case color = "Color"
    case explode = "Explode"
    case erase = "Erase"

    var id: String { rawValue }
    var isDrawOrEdit: Bool {
        switch self {
        case .drawLine, .drawPolyline, .drawCircle, .dimension, .offset, .align, .color, .explode, .erase: return true
        default: return false
        }
    }
}

struct CADViewportTransform {
    var scale: CGFloat = 1.0
    var offset: CGSize = .zero

    func worldToScreen(_ pt: CADPoint2D) -> CGPoint {
        CGPoint(
            x: CGFloat(pt.x) * scale + offset.width,
            y: -CGFloat(pt.y) * scale + offset.height
        )
    }

    func screenToWorld(_ pt: CGPoint) -> CADPoint2D {
        CADPoint2D(
            x: Double((pt.x - offset.width) / scale),
            y: Double(-(pt.y - offset.height) / scale)
        )
    }

    func visibleWorldBounds(canvasSize: CGSize) -> CADBoundingBox {
        let topLeft = screenToWorld(.zero)
        let bottomRight = screenToWorld(CGPoint(x: canvasSize.width, y: canvasSize.height))
        return CADBoundingBox(
            minX: min(topLeft.x, bottomRight.x),
            minY: min(topLeft.y, bottomRight.y),
            maxX: max(topLeft.x, bottomRight.x),
            maxY: max(topLeft.y, bottomRight.y)
        )
    }

    static func fitExtents(box: CADBoundingBox, canvasSize: CGSize, padding: CGFloat = 36) -> CADViewportTransform {
        guard box.isValid, canvasSize.width > padding * 2, canvasSize.height > padding * 2 else {
            return CADViewportTransform()
        }
        let availW = canvasSize.width - padding * 2
        let availH = canvasSize.height - padding * 2
        let s = max(0.001, min(availW / CGFloat(box.width), availH / CGFloat(box.height)))
        let c = box.center
        return CADViewportTransform(
            scale: s,
            offset: CGSize(
                width: canvasSize.width * 0.5 - CGFloat(c.x) * s,
                height: canvasSize.height * 0.5 + CGFloat(c.y) * s
            )
        )
    }
}

enum CADGeometryMath {
    static func distance(_ a: CADPoint2D, _ b: CADPoint2D) -> Double {
        hypot(b.x - a.x, b.y - a.y)
    }

    static func slopeDistance3D(_ a: CADPoint2D, _ b: CADPoint2D) -> Double {
        let hd = hypot(b.x - a.x, b.y - a.y)
        return hypot(hd, b.z - a.z)
    }

    static func bearingDegrees(_ a: CADPoint2D, _ b: CADPoint2D) -> Double {
        let deg = atan2(b.x - a.x, b.y - a.y) * 180.0 / .pi
        return deg < 0 ? deg + 360.0 : deg
    }

    static func interiorAngleDegrees(_ p1: CADPoint2D, vertex: CADPoint2D, _ p3: CADPoint2D) -> Double {
        let v1x = p1.x - vertex.x, v1y = p1.y - vertex.y
        let v2x = p3.x - vertex.x, v2y = p3.y - vertex.y
        let m1 = hypot(v1x, v1y), m2 = hypot(v2x, v2y)
        guard m1 > 1e-9, m2 > 1e-9 else { return 0 }
        let cosA = max(-1.0, min(1.0, (v1x * v2x + v1y * v2y) / (m1 * m2)))
        return acos(cosA) * 180.0 / .pi
    }

    static func formatDMS(_ decimalDegrees: Double) -> String {
        let totalSec = Int((abs(decimalDegrees) * 3600.0).rounded())
        let deg = totalSec / 3600
        let min = (totalSec % 3600) / 60
        let sec = totalSec % 60
        return String(format: "%d°%02d'%02d\"", deg, min, sec)
    }

    static func quadrantBearing(_ azimuthDeg: Double) -> String {
        let az = azimuthDeg.truncatingRemainder(dividingBy: 360.0)
        let norm = az < 0 ? az + 360.0 : az
        if norm <= 90.0 {
            return "N \(formatDMS(norm)) E"
        } else if norm <= 180.0 {
            return "S \(formatDMS(180.0 - norm)) E"
        } else if norm <= 270.0 {
            return "S \(formatDMS(norm - 180.0)) W"
        } else {
            return "N \(formatDMS(360.0 - norm)) W"
        }
    }

    static func polygonArea(_ pts: [CADPoint2D]) -> Double {
        guard pts.count >= 3 else { return 0 }
        var sum = 0.0
        for i in 0..<pts.count {
            let j = (i + 1) % pts.count
            sum += pts[i].x * pts[j].y - pts[j].x * pts[i].y
        }
        return abs(sum) * 0.5
    }

    /// Parses AutoCAD-style coordinate input:
    /// - Absolute: "100.5, 250.0"
    /// - Relative: "@15.0, -5.0"
    /// - Polar: "@25.0<45"
    static func parseCoordinateInput(_ input: String, lastPoint: CADPoint2D?) -> CADPoint2D? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") {
            let base = lastPoint ?? CADPoint2D(x: 0, y: 0)
            let body = String(trimmed.dropFirst())
            if body.contains("<") {
                let parts = body.split(separator: "<").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, let dist = Double(parts[0]), let angleDeg = Double(parts[1]) else { return nil }
                let rad = angleDeg * .pi / 180.0
                return CADPoint2D(x: base.x + dist * cos(rad), y: base.y + dist * sin(rad))
            } else {
                let parts = body.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count >= 2, let dx = Double(parts[0]), let dy = Double(parts[1]) else { return nil }
                let dz = parts.count >= 3 ? (Double(parts[2]) ?? 0) : 0
                return CADPoint2D(x: base.x + dx, y: base.y + dy, z: base.z + dz)
            }
        } else {
            let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
            let z = parts.count >= 3 ? (Double(parts[2]) ?? 0) : 0
            return CADPoint2D(x: x, y: y, z: z)
        }
    }

    static func pointToSegmentDistance(_ p: CADPoint2D, _ a: CADPoint2D, _ b: CADPoint2D) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 1e-12 else { return distance(p, a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return distance(p, CADPoint2D(x: a.x + t * dx, y: a.y + t * dy))
    }

    static func nearestEntityIndex(
        to worldPoint: CADPoint2D,
        in entities: [CADEntity],
        visibleLayers: Set<String>,
        maxWorldDist: Double
    ) -> Int? {
        var bestIdx: Int?
        var bestD = maxWorldDist
        for (idx, e) in entities.enumerated() where visibleLayers.contains(e.layerName) {
            let d: Double
            switch e.geometry {
            case .line(let a, let b):
                d = pointToSegmentDistance(worldPoint, a, b)
            case .polyline(let pts, let closed):
                guard pts.count >= 2 else { continue }
                var minSeg = Double.infinity
                for i in 0..<(pts.count - 1) {
                    minSeg = min(minSeg, pointToSegmentDistance(worldPoint, pts[i], pts[i + 1]))
                }
                if closed, let f = pts.first, let l = pts.last {
                    minSeg = min(minSeg, pointToSegmentDistance(worldPoint, l, f))
                }
                d = minSeg
            case .circle(let c, let r), .arc(let c, let r, _, _):
                d = abs(distance(worldPoint, c) - r)
            case .text(let p, _, _):
                d = distance(worldPoint, p)
            case .dimension(let p1, let p2, _):
                d = pointToSegmentDistance(worldPoint, p1, p2)
            }
            if d < bestD {
                bestD = d
                bestIdx = idx
            }
        }
        return bestIdx
    }

    /// Offsets a Line, Polyline, or Circle toward the side of `sidePoint` by `distance`.
    static func offsetEntity(_ entity: CADEntity, by dist: Double, toward sidePoint: CADPoint2D) -> CADEntity? {
        switch entity.geometry {
        case .line(let a, let b):
            let dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            guard len > 1e-9 else { return nil }
            let nx = -dy / len, ny = dx / len
            let side = (sidePoint.x - a.x) * nx + (sidePoint.y - a.y) * ny >= 0 ? 1.0 : -1.0
            let ox = nx * dist * side, oy = ny * dist * side
            return CADEntity(
                layerName: entity.layerName,
                colorIndex: entity.colorIndex,
                geometry: .line(
                    start: CADPoint2D(x: a.x + ox, y: a.y + oy),
                    end: CADPoint2D(x: b.x + ox, y: b.y + oy)
                )
            )
        case .circle(let c, let r):
            let dCenter = distance(c, sidePoint)
            let newR = dCenter >= r ? (r + dist) : max(0.1, r - dist)
            return CADEntity(
                layerName: entity.layerName,
                colorIndex: entity.colorIndex,
                geometry: .circle(center: c, radius: newR)
            )
        case .polyline(let pts, let closed):
            guard pts.count >= 2 else { return nil }
            let a = pts[0], b = pts[1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(hypot(dx, dy), 1e-9)
            let nx = -dy / len, ny = dx / len
            let side = (sidePoint.x - a.x) * nx + (sidePoint.y - a.y) * ny >= 0 ? 1.0 : -1.0
            var newPts: [CADPoint2D] = []
            for i in 0..<pts.count {
                let pPrev = i > 0 ? pts[i - 1] : (closed ? pts[pts.count - 1] : pts[i])
                let pNext = i < pts.count - 1 ? pts[i + 1] : (closed ? pts[0] : pts[i])
                let segDx = pNext.x - pPrev.x, segDy = pNext.y - pPrev.y
                let segLen = max(hypot(segDx, segDy), 1e-9)
                let pnx = (-segDy / segLen) * dist * side
                let pny = (segDx / segLen) * dist * side
                newPts.append(CADPoint2D(x: pts[i].x + pnx, y: pts[i].y + pny))
            }
            return CADEntity(
                layerName: entity.layerName,
                colorIndex: entity.colorIndex,
                geometry: .polyline(points: newPts, closed: closed)
            )
        default:
            return nil
        }
    }

    /// Aligns an entity using 2 source points (s1, s2) and 2 destination points (d1, d2).
    static func alignEntity(
        _ entity: CADEntity,
        s1: CADPoint2D,
        d1: CADPoint2D,
        s2: CADPoint2D,
        d2: CADPoint2D,
        scaleToFit: Bool
    ) -> CADEntity {
        let srcAngle = atan2(s2.y - s1.y, s2.x - s1.x)
        let dstAngle = atan2(d2.y - d1.y, d2.x - d1.x)
        let theta = dstAngle - srcAngle
        let cosT = cos(theta), sinT = sin(theta)

        let srcLen = max(distance(s1, s2), 1e-9)
        let dstLen = distance(d1, d2)
        let k = scaleToFit ? max(dstLen / srcLen, 1e-4) : 1.0
        let dz = d1.z - s1.z

        func xform(_ p: CADPoint2D) -> CADPoint2D {
            let rx = (p.x - s1.x) * k
            let ry = (p.y - s1.y) * k
            return CADPoint2D(
                x: d1.x + rx * cosT - ry * sinT,
                y: d1.y + rx * sinT + ry * cosT,
                z: p.z + dz
            )
        }

        let newGeom: CADGeometry
        switch entity.geometry {
        case .line(let a, let b):
            newGeom = .line(start: xform(a), end: xform(b))
        case .polyline(let pts, let closed):
            newGeom = .polyline(points: pts.map(xform), closed: closed)
        case .circle(let c, let r):
            newGeom = .circle(center: xform(c), radius: r * k)
        case .arc(let c, let r, let sDeg, let eDeg):
            let rotDeg = theta * 180.0 / .pi
            newGeom = .arc(center: xform(c), radius: r * k, startAngleDeg: sDeg + rotDeg, endAngleDeg: eDeg + rotDeg)
        case .text(let p, let h, let content):
            newGeom = .text(position: xform(p), height: h * k, content: content)
        case .dimension(let p1, let p2, let off):
            newGeom = .dimension(p1: xform(p1), p2: xform(p2), offsetDistance: off * k)
        }

        return CADEntity(
            id: entity.id,
            layerName: entity.layerName,
            colorIndex: entity.colorIndex,
            geometry: newGeom
        )
    }

    /// Explodes a Polyline or Dimension into individual Line entities.
    static func explodeEntity(_ entity: CADEntity) -> [CADEntity]? {
        switch entity.geometry {
        case .polyline(let pts, let closed):
            guard pts.count >= 2 else { return nil }
            var lines: [CADEntity] = []
            for i in 0..<(pts.count - 1) {
                lines.append(CADEntity(layerName: entity.layerName, colorIndex: entity.colorIndex, geometry: .line(start: pts[i], end: pts[i + 1])))
            }
            if closed, let f = pts.first, let l = pts.last {
                lines.append(CADEntity(layerName: entity.layerName, colorIndex: entity.colorIndex, geometry: .line(start: l, end: f)))
            }
            return lines
        case .dimension(let p1, let p2, let off):
            let dx = p2.x - p1.x, dy = p2.y - p1.y
            let len = max(hypot(dx, dy), 1e-6)
            let nx = -dy / len, ny = dx / len
            let dp1 = CADPoint2D(x: p1.x + nx * off, y: p1.y + ny * off, z: p1.z)
            let dp2 = CADPoint2D(x: p2.x + nx * off, y: p2.y + ny * off, z: p2.z)
            return [
                CADEntity(layerName: entity.layerName, colorIndex: entity.colorIndex, geometry: .line(start: p1, end: dp1)),
                CADEntity(layerName: entity.layerName, colorIndex: entity.colorIndex, geometry: .line(start: p2, end: dp2)),
                CADEntity(layerName: entity.layerName, colorIndex: entity.colorIndex, geometry: .line(start: dp1, end: dp2))
            ]
        default:
            return nil
        }
    }

    static func nearestSnapVertex(
        to screenPoint: CGPoint,
        in entities: [CADEntity],
        candidateIndices: [Int],
        visibleLayers: Set<String>,
        transform: CADViewportTransform,
        maxScreenRadius: CGFloat = 24
    ) -> CADPoint2D? {
        var best: CADPoint2D?
        var bestDist = maxScreenRadius
        for idx in candidateIndices {
            let entity = entities[idx]
            guard visibleLayers.contains(entity.layerName) else { continue }
            for v in entity.snapVertices {
                let sv = transform.worldToScreen(v)
                let d = hypot(sv.x - screenPoint.x, sv.y - screenPoint.y)
                if d < bestDist {
                    bestDist = d
                    best = v
                }
            }
        }
        return best
    }
}
