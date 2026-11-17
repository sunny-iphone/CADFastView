import Foundation
import ModelIO
import SceneKit
import SceneKit.ModelIO

enum CAD3DRenderStyle: String, CaseIterable, Identifiable {
    case shaded = "Shaded"
    case wireframe = "Wireframe"
    case xray = "X-Ray"

    var id: String { rawValue }
}

struct CAD3DModelInfo {
    let fileName: String
    let format: String
    let elementCount: Int
    let summary: String
}

enum CAD3DLoader {
    static func loadScene(from url: URL) throws -> (SCNScene, CAD3DModelInfo) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "obj", "stl", "ply", "usdz", "usda", "usdc":
            let asset = MDLAsset(url: url)
            asset.loadTextures()
            let scene = SCNScene(mdlAsset: asset)
            let count = scene.rootNode.childNodes.count
            return (scene, CAD3DModelInfo(
                fileName: url.lastPathComponent,
                format: ext.uppercased(),
                elementCount: count,
                summary: "Loaded via Apple ModelIO"
            ))

        case "stp", "step":
            return try parseSTEPPreview(url: url)

        case "ifc":
            return try parseIFCPreview(url: url)

        default:
            throw NSError(domain: "CAD3D", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported 3D format: .\(ext). Supported: .obj, .stl, .usdz, .ply, .step/.stp, .ifc"
            ])
        }
    }

    /// Extrudes a 2D CADDrawing into a 3D architectural/survey SceneKit model.
    static func extrude2DDrawing(_ drawing: CADDrawing, height: CGFloat = 4.0) -> (SCNScene, CAD3DModelInfo) {
        let scene = SCNScene()
        let root = SCNNode()
        var count = 0

        for entity in drawing.entities {
            let color = UIColor(ACIColorPalette.color(for: entity.colorIndex))
            switch entity.geometry {
            case .line(let s, let e):
                if let wall = makeWallNode(from: s, to: e, height: height, thickness: 0.25, color: color) {
                    root.addChildNode(wall)
                    count += 1
                }
            case .polyline(let pts, let closed):
                for i in 0..<(pts.count - 1) {
                    if let wall = makeWallNode(from: pts[i], to: pts[i + 1], height: height, thickness: 0.25, color: color) {
                        root.addChildNode(wall)
                        count += 1
                    }
                }
                if closed, let f = pts.first, let l = pts.last,
                   let wall = makeWallNode(from: l, to: f, height: height, thickness: 0.25, color: color) {
                    root.addChildNode(wall)
                    count += 1
                }
            case .circle(let c, let r):
                let cyl = SCNCylinder(radius: CGFloat(r), height: height)
                cyl.firstMaterial?.diffuse.contents = color
                let node = SCNNode(geometry: cyl)
                node.position = SCNVector3(Float(c.x), Float(height * 0.5), Float(-c.y))
                root.addChildNode(node)
                count += 1
            default:
                break
            }
        }

        scene.rootNode.addChildNode(root)
        return (scene, CAD3DModelInfo(
            fileName: "\(drawing.fileName) (3D)",
            format: "3D Extrusion",
            elementCount: count,
            summary: "Extruded \(count) 2D entities (H = \(String(format: "%.1f", height)))"
        ))
    }

    /// Builds a sample 3D BIM structural frame for instant testing.
    static func sampleBIMScene() -> (SCNScene, CAD3DModelInfo) {
        let scene = SCNScene()
        let slabMat = SCNMaterial()
        slabMat.diffuse.contents = UIColor.systemGray3
        let colMat = SCNMaterial()
        colMat.diffuse.contents = UIColor.systemBlue
        let beamMat = SCNMaterial()
        beamMat.diffuse.contents = UIColor.systemTeal

        for floor in 0..<3 {
            let y = Float(floor) * 3.5
            let slab = SCNBox(width: 14, height: 0.3, length: 10, chamferRadius: 0.02)
            slab.materials = [slabMat]
            let slabNode = SCNNode(geometry: slab)
            slabNode.position = SCNVector3(0, y, 0)
            scene.rootNode.addChildNode(slabNode)

            if floor < 2 {
                for x in stride(from: -6.0 as Float, through: 6.0, by: 6.0) {
                    for z in stride(from: -4.0 as Float, through: 4.0, by: 4.0) {
                        let col = SCNBox(width: 0.45, height: 3.5, length: 0.45, chamferRadius: 0.02)
                        col.materials = [colMat]
                        let colNode = SCNNode(geometry: col)
                        colNode.position = SCNVector3(x, y + 1.75, z)
                        scene.rootNode.addChildNode(colNode)
                    }
                }
                let beam = SCNBox(width: 12.4, height: 0.4, length: 0.35, chamferRadius: 0.02)
                beam.materials = [beamMat]
                let bNode = SCNNode(geometry: beam)
                bNode.position = SCNVector3(0, y + 3.3, 0)
                scene.rootNode.addChildNode(bNode)
            }
        }
        return (scene, CAD3DModelInfo(
            fileName: "SampleBIM_Structure",
            format: "3D BIM",
            elementCount: 23,
            summary: "3-Storey Structural Frame (Columns, Beams, Slabs)"
        ))
    }

    private static func makeWallNode(from a: CADPoint2D, to b: CADPoint2D, height: CGFloat, thickness: CGFloat, color: UIColor) -> SCNNode? {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 1e-4 else { return nil }
        let box = SCNBox(width: CGFloat(len), height: height, length: thickness, chamferRadius: 0)
        box.firstMaterial?.diffuse.contents = color
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(Float((a.x + b.x) * 0.5), Float(height * 0.5), Float(-(a.y + b.y) * 0.5))
        node.eulerAngles = SCNVector3(0, Float(atan2(dy, dx)), 0)
        return node
    }

    /// Lightweight ISO 10303-21 STEP parser extracting CARTESIAN_POINT cloud & product count.
    private static func parseSTEPPreview(url: URL) throws -> (SCNScene, CAD3DModelInfo) {
        let text = try String(contentsOf: url, encoding: .utf8)
        let scene = SCNScene()
        var points: [SCNVector3] = []
        var productCount = 0

        let pattern = #"CARTESIAN_POINT\s*\([^,]*,\s*\(([^)]+)\)\s*\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        for line in text.components(separatedBy: .newlines) {
            if line.contains("PRODUCT(") { productCount += 1 }
            let ns = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges >= 2 {
                let coordsStr = ns.substring(with: match.range(at: 1))
                let vals = coordsStr.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
                if vals.count >= 3 {
                    points.append(SCNVector3(vals[0], vals[2], -vals[1]))
                }
            }
        }

        if !points.isEmpty {
            let source = SCNGeometrySource(vertices: points)
            let indices = Array(0..<Int32(points.count))
            let data = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
            let element = SCNGeometryElement(data: data, primitiveType: .point, primitiveCount: points.count, bytesPerIndex: MemoryLayout<Int32>.size)
            element.pointSize = 4.0
            element.minimumPointScreenSpaceRadius = 2.0
            element.maximumPointScreenSpaceRadius = 6.0
            let geo = SCNGeometry(sources: [source], elements: [element])
            geo.firstMaterial?.diffuse.contents = UIColor.systemCyan
            scene.rootNode.addChildNode(SCNNode(geometry: geo))
        }

        return (scene, CAD3DModelInfo(
            fileName: url.lastPathComponent,
            format: "STEP (ISO 10303)",
            elementCount: points.count,
            summary: "\(productCount) products, \(points.count) 3D vertices (point-cloud preview; add OCCT for B-Rep solids)"
        ))
    }

    /// Lightweight IFC parser extracting IFCBUILDINGSTOREY / IFCWALL / IFCBEAM / IFCCOLUMN counts & points.
    private static func parseIFCPreview(url: URL) throws -> (SCNScene, CAD3DModelInfo) {
        let text = try String(contentsOf: url, encoding: .utf8)
        let scene = SCNScene()
        var points: [SCNVector3] = []
        var wallCount = 0, beamCount = 0, colCount = 0

        let pattern = #"IFCCARTESIANPOINT\s*\(\s*\(([^)]+)\)\s*\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        for line in text.components(separatedBy: .newlines) {
            if line.contains("IFCWALL") { wallCount += 1 }
            if line.contains("IFCBEAM") { beamCount += 1 }
            if line.contains("IFCCOLUMN") { colCount += 1 }
            let ns = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges >= 2 {
                let coordsStr = ns.substring(with: match.range(at: 1))
                let vals = coordsStr.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
                if vals.count >= 3 {
                    points.append(SCNVector3(vals[0], vals[2], -vals[1]))
                }
            }
        }

        if !points.isEmpty {
            let source = SCNGeometrySource(vertices: points)
            let indices = Array(0..<Int32(points.count))
            let data = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
            let element = SCNGeometryElement(data: data, primitiveType: .point, primitiveCount: points.count, bytesPerIndex: MemoryLayout<Int32>.size)
            element.pointSize = 4.0
            let geo = SCNGeometry(sources: [source], elements: [element])
            geo.firstMaterial?.diffuse.contents = UIColor.systemGreen
            scene.rootNode.addChildNode(SCNNode(geometry: geo))
        }

        return (scene, CAD3DModelInfo(
            fileName: url.lastPathComponent,
            format: "IFC BIM",
            elementCount: wallCount + beamCount + colCount,
            summary: "\(wallCount) walls, \(beamCount) beams, \(colCount) columns (\(points.count) pts)"
        ))
    }
}
