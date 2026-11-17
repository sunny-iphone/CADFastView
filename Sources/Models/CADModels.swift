import SwiftUI

struct CADPoint2D: Hashable, Sendable {
    var x: Double
    var y: Double
    var z: Double = 0.0

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct CADBoundingBox: Sendable {
    var minX: Double = .infinity
    var minY: Double = .infinity
    var maxX: Double = -.infinity
    var maxY: Double = -.infinity

    var isValid: Bool {
        minX.isFinite && minY.isFinite && maxX.isFinite && maxY.isFinite && maxX >= minX && maxY >= minY
    }

    var width: Double { max(maxX - minX, 1e-6) }
    var height: Double { max(maxY - minY, 1e-6) }
    var center: CADPoint2D { CADPoint2D(x: (minX + maxX) * 0.5, y: (minY + maxY) * 0.5) }

    mutating func expand(to point: CADPoint2D) {
        minX = min(minX, point.x)
        minY = min(minY, point.y)
        maxX = max(maxX, point.x)
        maxY = max(maxY, point.y)
    }

    mutating func expand(to box: CADBoundingBox) {
        guard box.isValid else { return }
        minX = min(minX, box.minX)
        minY = min(minY, box.minY)
        maxX = max(maxX, box.maxX)
        maxY = max(maxY, box.maxY)
    }

    func intersects(_ other: CADBoundingBox) -> Bool {
        guard isValid && other.isValid else { return true }
        return !(maxX < other.minX || minX > other.maxX || maxY < other.minY || minY > other.maxY)
    }
}

enum CADGeometry: Sendable {
    case line(start: CADPoint2D, end: CADPoint2D)
    case polyline(points: [CADPoint2D], closed: Bool)
    case circle(center: CADPoint2D, radius: Double)
    case arc(center: CADPoint2D, radius: Double, startAngleDeg: Double, endAngleDeg: Double)
    case text(position: CADPoint2D, height: Double, content: String)
    case dimension(p1: CADPoint2D, p2: CADPoint2D, offsetDistance: Double)
}

struct CADEntity: Identifiable, Sendable {
    let id: UUID
    let layerName: String
    var colorIndex: Int
    let geometry: CADGeometry
    let boundingBox: CADBoundingBox

    init(id: UUID = UUID(), layerName: String, colorIndex: Int, geometry: CADGeometry, boundingBox: CADBoundingBox? = nil) {
        self.id = id
        self.layerName = layerName
        self.colorIndex = colorIndex
        self.geometry = geometry
        if let boundingBox {
            self.boundingBox = boundingBox
        } else {
            var box = CADBoundingBox()
            switch geometry {
            case .line(let s, let e):
                box.expand(to: s); box.expand(to: e)
            case .polyline(let pts, _):
                pts.forEach { box.expand(to: $0) }
            case .circle(let c, let r), .arc(let c, let r, _, _):
                box.expand(to: CADPoint2D(x: c.x - r, y: c.y - r))
                box.expand(to: CADPoint2D(x: c.x + r, y: c.y + r))
            case .text(let p, _, _):
                box.expand(to: p)
            case .dimension(let p1, let p2, let off):
                box.expand(to: p1); box.expand(to: p2)
                box.minX -= abs(off); box.minY -= abs(off)
                box.maxX += abs(off); box.maxY += abs(off)
            }
            self.boundingBox = box
        }
    }

    var snapVertices: [CADPoint2D] {
        switch geometry {
        case .line(let start, let end):
            return [start, end, CADPoint2D(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)]
        case .polyline(let points, _):
            return points
        case .circle(let center, _):
            return [center]
        case .arc(let center, let radius, let startDeg, let endDeg):
            let sRad = startDeg * .pi / 180.0
            let eRad = endDeg * .pi / 180.0
            return [
                center,
                CADPoint2D(x: center.x + radius * cos(sRad), y: center.y + radius * sin(sRad)),
                CADPoint2D(x: center.x + radius * cos(eRad), y: center.y + radius * sin(eRad))
            ]
        case .text(let position, _, _):
            return [position]
        case .dimension(let p1, let p2, _):
            return [p1, p2]
        }
    }
}

struct CADLayer: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    var colorIndex: Int
    var isVisible: Bool = true
    var entityCount: Int = 0
}

struct CADDrawing: Sendable {
    var fileName: String
    var layers: [CADLayer]
    var entities: [CADEntity]
    var boundingBox: CADBoundingBox
}

enum ACIColorPalette {
    static func color(for index: Int) -> Color {
        switch index {
        case 1: return .red
        case 2: return .yellow
        case 3: return .green
        case 4: return .cyan
        case 5: return .blue
        case 6: return Color(red: 1.0, green: 0.0, blue: 1.0)
        case 7: return .white
        case 8: return .gray
        case 9: return Color(white: 0.75)
        default:
            if index <= 0 { return .white }
            let hue = Double((index * 37) % 360) / 360.0
            return Color(hue: hue, saturation: 0.75, brightness: 0.95)
        }
    }
}

struct CADViewpoint: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let scale: CGFloat
    let offsetWidth: CGFloat
    let offsetHeight: CGFloat
}
