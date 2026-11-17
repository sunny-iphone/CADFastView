import Foundation

enum CADParserError: LocalizedError {
    case unsupportedDWGWithoutLibdxfrw
    case bridgeFailure(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedDWGWithoutLibdxfrw:
            return "Binary .dwg requires libdxfrw. Run scripts/fetch_libdxfrw.sh and enable USE_LIBDXFRW=1 in Xcode, or open an ASCII .dxf file."
        case .bridgeFailure(let message):
            return message
        }
    }
}

actor CADParserService {
    func loadDrawing(from url: URL) throws -> CADDrawing {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let ext = url.pathExtension.lowercased()
        if CADParserBridge.isLibdxfrwAvailable() {
            return try parseViaBridge(url: url)
        } else if ext == "dwg" {
            throw CADParserError.unsupportedDWGWithoutLibdxfrw
        } else {
            return try FallbackDXFParser.parse(url: url)
        }
    }

    private func parseViaBridge(url: URL) throws -> CADDrawing {
        let result = CADParserBridge.parseFile(atPath: url.path)
        if let err = result.errorMessage, result.entities.isEmpty {
            throw CADParserError.bridgeFailure(err)
        }

        var layerMap: [String: CADLayer] = [:]
        for l in result.layers {
            layerMap[l.name] = CADLayer(name: l.name, colorIndex: l.colorIndex, isVisible: l.visible, entityCount: 0)
        }

        var entities: [CADEntity] = []
        var totalBox = CADBoundingBox()

        for b in result.entities {
            var box = CADBoundingBox()
            let coords = b.coordinates.map { $0.doubleValue }
            let geom: CADGeometry?

            switch b.type {
            case .line where coords.count >= 6:
                let p1 = CADPoint2D(x: coords[0], y: coords[1], z: coords[2])
                let p2 = CADPoint2D(x: coords[3], y: coords[4], z: coords[5])
                box.expand(to: p1); box.expand(to: p2)
                geom = .line(start: p1, end: p2)
            case .polyline where coords.count >= 6:
                var pts: [CADPoint2D] = []
                for idx in stride(from: 0, to: coords.count - 2, by: 3) {
                    let pt = CADPoint2D(x: coords[idx], y: coords[idx + 1], z: coords[idx + 2])
                    pts.append(pt)
                    box.expand(to: pt)
                }
                geom = .polyline(points: pts, closed: b.closed)
            case .circle where coords.count >= 2:
                let c = CADPoint2D(x: coords[0], y: coords[1], z: coords.count >= 3 ? coords[2] : 0)
                let r = b.radiusOrHeight
                box.expand(to: CADPoint2D(x: c.x - r, y: c.y - r))
                box.expand(to: CADPoint2D(x: c.x + r, y: c.y + r))
                geom = .circle(center: c, radius: r)
            case .arc where coords.count >= 2:
                let c = CADPoint2D(x: coords[0], y: coords[1], z: coords.count >= 3 ? coords[2] : 0)
                let r = b.radiusOrHeight
                box.expand(to: CADPoint2D(x: c.x - r, y: c.y - r))
                box.expand(to: CADPoint2D(x: c.x + r, y: c.y + r))
                geom = .arc(center: c, radius: r, startAngleDeg: b.startAngleDeg, endAngleDeg: b.endAngleDeg)
            case .text where coords.count >= 2:
                let p = CADPoint2D(x: coords[0], y: coords[1], z: coords.count >= 3 ? coords[2] : 0)
                box.expand(to: p)
                geom = .text(position: p, height: max(b.radiusOrHeight, 1.0), content: b.textContent ?? "")
            default:
                geom = nil
            }

            if let geom {
                let resolvedColor = b.colorIndex == 256 ? (layerMap[b.layerName]?.colorIndex ?? 7) : b.colorIndex
                entities.append(CADEntity(layerName: b.layerName, colorIndex: resolvedColor, geometry: geom, boundingBox: box))
                totalBox.expand(to: box)

                var layer = layerMap[b.layerName] ?? CADLayer(name: b.layerName, colorIndex: 7)
                layer.entityCount += 1
                layerMap[b.layerName] = layer
            }
        }

        return CADDrawing(
            fileName: url.lastPathComponent,
            layers: layerMap.values.sorted { $0.name < $1.name },
            entities: entities,
            boundingBox: totalBox
        )
    }
}
