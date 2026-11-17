import UIKit

enum CADPDFExporter {
    static func export(drawing: CADDrawing, visibleLayers: Set<String>) throws -> URL {
        guard !drawing.entities.isEmpty, drawing.boundingBox.isValid else {
            throw NSError(domain: "CADPDF", code: 1, userInfo: [NSLocalizedDescriptionKey: "Drawing has no visible geometry to export."])
        }
        let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595) // A4 Landscape
        let transform = CADViewportTransform.fitExtents(box: drawing.boundingBox, canvasSize: pageRect.size, padding: 36)

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(drawing.fileName)
            .deletingPathExtension()
            .appendingPathExtension("pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: outURL) { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext
            cg.setLineWidth(0.75)
            cg.setStrokeColor(UIColor.black.cgColor)

            for entity in drawing.entities where visibleLayers.contains(entity.layerName) {
                switch entity.geometry {
                case .line(let start, let end):
                    cg.move(to: transform.worldToScreen(start))
                    cg.addLine(to: transform.worldToScreen(end))
                    cg.strokePath()
                case .polyline(let pts, let closed):
                    guard let first = pts.first else { continue }
                    cg.move(to: transform.worldToScreen(first))
                    for p in pts.dropFirst() { cg.addLine(to: transform.worldToScreen(p)) }
                    if closed { cg.closePath() }
                    cg.strokePath()
                case .circle(let center, let radius):
                    let sc = transform.worldToScreen(center)
                    let sr = CGFloat(radius) * transform.scale
                    cg.strokeEllipse(in: CGRect(x: sc.x - sr, y: sc.y - sr, width: sr * 2, height: sr * 2))
                case .arc(let center, let radius, let startDeg, let endDeg):
                    let sc = transform.worldToScreen(center)
                    let sr = CGFloat(radius) * transform.scale
                    cg.addArc(
                        center: sc,
                        radius: sr,
                        startAngle: CGFloat(-startDeg * .pi / 180.0),
                        endAngle: CGFloat(-endDeg * .pi / 180.0),
                        clockwise: true
                    )
                    cg.strokePath()
                case .dimension(let p1, let p2, let off):
                    let dx = p2.x - p1.x, dy = p2.y - p1.y
                    let len = max(hypot(dx, dy), 1e-6)
                    let nx = -dy / len, ny = dx / len
                    let dp1 = transform.worldToScreen(CADPoint2D(x: p1.x + nx * off, y: p1.y + ny * off))
                    let dp2 = transform.worldToScreen(CADPoint2D(x: p2.x + nx * off, y: p2.y + ny * off))
                    cg.move(to: transform.worldToScreen(p1)); cg.addLine(to: dp1)
                    cg.move(to: transform.worldToScreen(p2)); cg.addLine(to: dp2)
                    cg.move(to: dp1); cg.addLine(to: dp2)
                    cg.strokePath()
                case .text(let pos, let height, let content):
                    let sp = transform.worldToScreen(pos)
                    let fontSize = max(min(CGFloat(height) * transform.scale, 24), 7)
                    (content as NSString).draw(at: sp, withAttributes: [
                        .font: UIFont.systemFont(ofSize: fontSize),
                        .foregroundColor: UIColor.darkGray
                    ])
                }
            }
        }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: outURL.path)
        return outURL
    }
}
