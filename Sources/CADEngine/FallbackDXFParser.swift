import Foundation

enum FallbackDXFParser {
    static func parse(url: URL) throws -> CADDrawing {
        let content: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            content = utf8
        } else if let cp1252 = try? String(contentsOf: url, encoding: .windowsCP1252) {
            content = cp1252
        } else {
            content = try String(contentsOf: url, encoding: .isoLatin1)
        }
        let lines = content.components(separatedBy: .newlines)

        var layersByName: [String: CADLayer] = [:]
        var entities: [CADEntity] = []
        var totalBox = CADBoundingBox()

        var i = 0
        func nextPair() -> (Int, String)? {
            guard i + 1 < lines.count else { return nil }
            let codeStr = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = lines[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            i += 2
            guard let code = Int(codeStr) else { return (-1, value) }
            return (code, value)
        }

        var currentSection = ""
        var currentTable = ""
        var activeType = ""
        var layerName = "0"
        var colorIndex = 256
        var x1 = 0.0, y1 = 0.0, z1 = 0.0, x2 = 0.0, y2 = 0.0, z2 = 0.0, elev = 0.0
        var radius = 0.0, startAngle = 0.0, endAngle = 360.0
        var textValue = ""
        var polyPoints: [CADPoint2D] = []
        var pendingX: Double?
        var flags = 0

        func flushEntity() {
            guard !activeType.isEmpty else { return }
            var box = CADBoundingBox()
            let geom: CADGeometry?

            switch activeType {
            case "LINE":
                let p1 = CADPoint2D(x: x1, y: y1, z: z1)
                let p2 = CADPoint2D(x: x2, y: y2, z: z2)
                box.expand(to: p1)
                box.expand(to: p2)
                geom = .line(start: p1, end: p2)
            case "LWPOLYLINE":
                guard polyPoints.count >= 2 else { geom = nil; break }
                for p in polyPoints { box.expand(to: p) }
                geom = .polyline(points: polyPoints, closed: (flags & 1) != 0)
            case "CIRCLE":
                let c = CADPoint2D(x: x1, y: y1, z: z1)
                box.expand(to: CADPoint2D(x: c.x - radius, y: c.y - radius))
                box.expand(to: CADPoint2D(x: c.x + radius, y: c.y + radius))
                geom = .circle(center: c, radius: radius)
            case "ARC":
                let c = CADPoint2D(x: x1, y: y1, z: z1)
                box.expand(to: CADPoint2D(x: c.x - radius, y: c.y - radius))
                box.expand(to: CADPoint2D(x: c.x + radius, y: c.y + radius))
                geom = .arc(center: c, radius: radius, startAngleDeg: startAngle, endAngleDeg: endAngle)
            case "TEXT", "MTEXT":
                let p = CADPoint2D(x: x1, y: y1, z: z1)
                box.expand(to: p)
                geom = .text(position: p, height: max(radius, 1.0), content: textValue)
            default:
                geom = nil
            }

            if let geom {
                let resolvedColor = colorIndex == 256 ? (layersByName[layerName]?.colorIndex ?? 7) : colorIndex
                let entity = CADEntity(layerName: layerName, colorIndex: resolvedColor, geometry: geom, boundingBox: box)
                entities.append(entity)
                totalBox.expand(to: box)

                var layer = layersByName[layerName] ?? CADLayer(name: layerName, colorIndex: 7)
                layer.entityCount += 1
                layersByName[layerName] = layer
            }

            activeType = ""
            layerName = "0"
            colorIndex = 256
            x1 = 0; y1 = 0; z1 = 0; x2 = 0; y2 = 0; z2 = 0; elev = 0
            radius = 0; startAngle = 0; endAngle = 360
            textValue = ""
            polyPoints = []
            pendingX = nil
            flags = 0
        }

        while let (code, value) = nextPair() {
            if code == 0 {
                if currentSection == "ENTITIES" {
                    flushEntity()
                } else if currentTable == "LAYER" && activeType == "LAYER" {
                    layersByName[layerName] = CADLayer(name: layerName, colorIndex: colorIndex == 256 ? 7 : colorIndex, isVisible: (flags & 1) == 0)
                    activeType = ""
                    layerName = "0"
                    colorIndex = 7
                    flags = 0
                }

                if value == "SECTION" {
                    if let (_, secName) = nextPair() { currentSection = secName }
                } else if value == "ENDSEC" {
                    currentSection = ""
                } else if value == "TABLE" {
                    if let (_, tblName) = nextPair() { currentTable = tblName }
                } else if value == "ENDTAB" {
                    currentTable = ""
                } else if currentSection == "ENTITIES" || (currentTable == "LAYER" && value == "LAYER") {
                    activeType = value
                }
                continue
            }

            if currentTable == "LAYER" && activeType == "LAYER" {
                switch code {
                case 2: layerName = value
                case 62: colorIndex = abs(Int(value) ?? 7)
                case 70: flags = Int(value) ?? 0
                default: break
                }
            } else if currentSection == "ENTITIES" && !activeType.isEmpty {
                switch code {
                case 8: layerName = value
                case 62: colorIndex = Int(value) ?? 256
                case 70: flags = Int(value) ?? 0
                case 10:
                    let vx = { let v = Double(value) ?? 0; return v.isFinite ? v : 0 }()
                    if activeType == "LWPOLYLINE" {
                        pendingX = vx
                    } else {
                        x1 = vx
                    }
                case 20:
                    let vy = { let v = Double(value) ?? 0; return v.isFinite ? v : 0 }()
                    if activeType == "LWPOLYLINE", let vx = pendingX {
                        polyPoints.append(CADPoint2D(x: vx, y: vy, z: elev))
                        pendingX = nil
                    } else {
                        y1 = vy
                    }
                case 30: z1 = { let v = Double(value) ?? 0; return v.isFinite ? v : 0 }()
                case 38: elev = { let v = Double(value) ?? 0; return v.isFinite ? v : 0 }()
                case 11: x2 = { let v = Double(value) ?? 0; return v.isFinite ? v : 0 }()
                case 21: y2 = { let v = Double(value) ?? 0; return v.isFinite ? v : 0 }()
                case 31: z2 = { let v = Double(value) ?? 0; return v.isFinite ? v : 0 }()
                case 40: radius = { let v = Double(value) ?? 0; return v.isFinite ? v : 0 }()
                case 50: startAngle = { let v = Double(value) ?? 0; return v.isFinite ? v : 0 }()
                case 51: endAngle = Double(value) ?? 360
                case 1: textValue = value
                default: break
                }
            }
        }

        let sortedLayers = layersByName.values.sorted { $0.name < $1.name }
        return CADDrawing(fileName: url.lastPathComponent, layers: sortedLayers, entities: entities, boundingBox: totalBox)
    }
}
