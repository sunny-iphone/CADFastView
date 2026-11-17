import SwiftUI

struct CADCanvasView: View {
    let drawing: CADDrawing
    let spatialIndex: CADSpatialIndex
    let visibleLayers: Set<String>
    let isThermalThrottled: Bool
    @Binding var transform: CADViewportTransform
    @Binding var toolMode: CADToolMode
    @Binding var activePoints: [CADPoint2D]
    @Binding var selectedEntityID: UUID?
    let onTapWorld: (CADPoint2D) -> Void

    @State private var lastDragOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let viewBounds = transform.visibleWorldBounds(canvasSize: size)
                let candidates = spatialIndex.queryIndices(in: viewBounds)

                let maxPerFrame = isThermalThrottled ? 5000 : 12000
                let step = max(1, candidates.count / maxPerFrame)
                for posIdx in stride(from: 0, to: candidates.count, by: step) {
                    let idx = candidates[posIdx]
                    guard idx < drawing.entities.count else { continue }
                    let entity = drawing.entities[idx]
                    guard visibleLayers.contains(entity.layerName),
                          entity.boundingBox.intersects(viewBounds) else { continue }

                    // LOD culling: skip sub-pixel entities to save battery and prevent GPU/CPU heat
                    let screenW = CGFloat(entity.boundingBox.width) * transform.scale
                    let screenH = CGFloat(entity.boundingBox.height) * transform.scale
                    let minDetailPx: CGFloat = isThermalThrottled ? 3.0 : 1.2
                    if max(screenW, screenH) < minDetailPx { continue }

                    let isSelected = (entity.id == selectedEntityID)
                    let strokeColor = isSelected ? Color.orange : ACIColorPalette.color(for: entity.colorIndex)
                    let lineWidth: CGFloat = isSelected ? 2.4 : 1.2

                    switch entity.geometry {
                    case .line(let start, let end):
                        var path = Path()
                        path.move(to: transform.worldToScreen(start))
                        path.addLine(to: transform.worldToScreen(end))
                        context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

                    case .polyline(let pts, let closed):
                        guard let first = pts.first else { continue }
                        var path = Path()
                        path.move(to: transform.worldToScreen(first))
                        for p in pts.dropFirst() { path.addLine(to: transform.worldToScreen(p)) }
                        if closed { path.closeSubpath() }
                        context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

                    case .circle(let center, let radius):
                        let sc = transform.worldToScreen(center)
                        let sr = CGFloat(radius) * transform.scale
                        let rect = CGRect(x: sc.x - sr, y: sc.y - sr, width: sr * 2, height: sr * 2)
                        context.stroke(Path(ellipseIn: rect), with: .color(strokeColor), lineWidth: lineWidth)

                    case .arc(let center, let radius, let startDeg, let endDeg):
                        let sc = transform.worldToScreen(center)
                        let sr = CGFloat(radius) * transform.scale
                        var path = Path()
                        path.addArc(center: sc, radius: sr, startAngle: .degrees(-startDeg), endAngle: .degrees(-endDeg), clockwise: true)
                        context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

                    case .text(let pos, let height, let content):
                        if isThermalThrottled && screenH < 6 { continue }
                        let sp = transform.worldToScreen(pos)
                        let fontSize = max(min(CGFloat(height) * transform.scale, 36), 8)
                        context.draw(Text(content).font(.system(size: fontSize)).foregroundColor(strokeColor), at: sp, anchor: .bottomLeading)

                    case .dimension(let p1, let p2, let off):
                        let sp1 = transform.worldToScreen(p1)
                        let sp2 = transform.worldToScreen(p2)
                        let dx = p2.x - p1.x, dy = p2.y - p1.y
                        let len = max(hypot(dx, dy), 1e-6)
                        let nx = -dy / len, ny = dx / len
                        let dp1 = transform.worldToScreen(CADPoint2D(x: p1.x + nx * off, y: p1.y + ny * off))
                        let dp2 = transform.worldToScreen(CADPoint2D(x: p2.x + nx * off, y: p2.y + ny * off))

                        var ext = Path()
                        ext.move(to: sp1); ext.addLine(to: dp1)
                        ext.move(to: sp2); ext.addLine(to: dp2)
                        context.stroke(ext, with: .color(.cyan.opacity(0.65)), lineWidth: 0.9)

                        var dimLine = Path()
                        dimLine.move(to: dp1); dimLine.addLine(to: dp2)
                        context.stroke(dimLine, with: .color(.cyan), lineWidth: 1.4)

                        let mid = CGPoint(x: (dp1.x + dp2.x) * 0.5, y: (dp1.y + dp2.y) * 0.5 - 10)
                        let label = String(format: "%.3f", len)
                        context.draw(Text(label).font(.caption2.monospaced()).foregroundColor(.cyan), at: mid)
                    }
                }

                // Active tool preview (Measure, Draw, Dimension)
                if !activePoints.isEmpty {
                    var mPath = Path()
                    for (idx, pt) in activePoints.enumerated() {
                        let sp = transform.worldToScreen(pt)
                        if idx == 0 { mPath.move(to: sp) } else { mPath.addLine(to: sp) }
                        context.fill(Path(ellipseIn: CGRect(x: sp.x - 4.5, y: sp.y - 4.5, width: 9, height: 9)), with: .color(.orange))
                    }
                    if toolMode == .area && activePoints.count >= 3 {
                        mPath.closeSubpath()
                        context.fill(mPath, with: .color(.orange.opacity(0.18)))
                    }
                    context.stroke(mPath, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
            }
            .background(Color(red: 0.08, green: 0.09, blue: 0.11))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            lastDragOffset = transform.offset
                        }
                        transform.offset = CGSize(
                            width: lastDragOffset.width + value.translation.width,
                            height: lastDragOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in isDragging = false }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if lastScale == 1.0 && value.magnification != 1.0 {
                            lastScale = transform.scale
                        }
                        let newScale = max(0.01, min(lastScale * value.magnification, 5000))
                        let anchor = value.startLocation
                        let worldAtAnchor = transform.screenToWorld(anchor)
                        transform.scale = newScale
                        let newScreen = transform.worldToScreen(worldAtAnchor)
                        transform.offset.width += anchor.x - newScreen.x
                        transform.offset.height += anchor.y - newScreen.y
                    }
                    .onEnded { _ in lastScale = 1.0 }
            )
            .onTapGesture { location in
                guard toolMode != .pan else { return }
                let viewBounds = transform.visibleWorldBounds(canvasSize: geo.size)
                let candidates = spatialIndex.queryIndices(in: viewBounds)
                let snapped = CADGeometryMath.nearestSnapVertex(
                    to: location,
                    in: drawing.entities,
                    candidateIndices: candidates,
                    visibleLayers: visibleLayers,
                    transform: transform
                )
                let worldPt = snapped ?? transform.screenToWorld(location)
                onTapWorld(worldPt)
            }
            .onAppear {
                transform = CADViewportTransform.fitExtents(box: drawing.boundingBox, canvasSize: geo.size)
            }
            .onChange(of: drawing.fileName) { _ in
                transform = CADViewportTransform.fitExtents(box: drawing.boundingBox, canvasSize: geo.size)
            }
        }
    }
}
