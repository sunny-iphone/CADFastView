import Foundation

enum CADDXFExporter {
    static func export(drawing: CADDrawing) throws -> URL {
        var out = "  0\nSECTION\n  2\nTABLES\n  0\nTABLE\n  2\nLAYER\n"
        for layer in drawing.layers {
            out += "  0\nLAYER\n  2\n\(layer.name)\n 62\n\(layer.colorIndex)\n"
        }
        out += "  0\nENDTAB\n  0\nENDSEC\n  0\nSECTION\n  2\nENTITIES\n"

        for e in drawing.entities {
            switch e.geometry {
            case .line(let s, let end):
                out += "  0\nLINE\n  8\n\(e.layerName)\n 62\n\(e.colorIndex)\n 10\n\(s.x)\n 20\n\(s.y)\n 30\n\(s.z)\n 11\n\(end.x)\n 21\n\(end.y)\n 31\n\(end.z)\n"
            case .polyline(let pts, let closed):
                out += "  0\nLWPOLYLINE\n  8\n\(e.layerName)\n 62\n\(e.colorIndex)\n 90\n\(pts.count)\n 70\n\(closed ? 1 : 0)\n"
                for p in pts {
                    out += " 10\n\(p.x)\n 20\n\(p.y)\n"
                }
            case .circle(let c, let r):
                out += "  0\nCIRCLE\n  8\n\(e.layerName)\n 62\n\(e.colorIndex)\n 10\n\(c.x)\n 20\n\(c.y)\n 40\n\(r)\n"
            case .arc(let c, let r, let sDeg, let eDeg):
                out += "  0\nARC\n  8\n\(e.layerName)\n 62\n\(e.colorIndex)\n 10\n\(c.x)\n 20\n\(c.y)\n 40\n\(r)\n 50\n\(sDeg)\n 51\n\(eDeg)\n"
            case .text(let p, let h, let content):
                out += "  0\nTEXT\n  8\n\(e.layerName)\n 62\n\(e.colorIndex)\n 10\n\(p.x)\n 20\n\(p.y)\n 40\n\(h)\n  1\n\(content)\n"
            case .dimension(let p1, let p2, _):
                out += "  0\nLINE\n  8\n\(e.layerName)\n 62\n\(e.colorIndex)\n 10\n\(p1.x)\n 20\n\(p1.y)\n 11\n\(p2.x)\n 21\n\(p2.y)\n"
            }
        }
        out += "  0\nENDSEC\n  0\nEOF\n"

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let baseName = (drawing.fileName as NSString).deletingPathExtension
        let outURL = docs.appendingPathComponent("\(baseName)_edited.dxf")
        try out.write(to: outURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: outURL.path)
        return outURL
    }
}
