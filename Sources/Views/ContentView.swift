import SceneKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Binding var externalFileURL: URL?

    @State private var drawing: CADDrawing?
    @State private var scene3D: SCNScene?
    @State private var model3DInfo: CAD3DModelInfo?
    @State private var is3DMode = false
    @State private var spatialIndex = CADSpatialIndex(entities: [], bounds: CADBoundingBox())
    @State private var transform = CADViewportTransform()
    @State private var toolMode: CADToolMode = .pan
    @State private var activePoints: [CADPoint2D] = []
    @State private var selectedEntityID: UUID?

    @State private var undoStack: [[CADEntity]] = []
    @State private var redoStack: [[CADEntity]] = []

    @State private var coordInputText = ""
    @State private var offsetDistanceText = "2.0"
    @State private var alignScaleToFit = false
    @State private var selectedColorIndex = 1
    @State private var savedViewpoints: [CADViewpoint] = []
    @State private var newViewpointName = ""
    @State private var showSaveViewpointAlert = false
    @State private var regenTrigger = 0
    @State private var showCoordEntry = false
    @State private var isThermalThrottled = false

    @State private var localSavedFiles: [URL] = []
    @State private var showImporter = false
    @State private var showLayers = false
    @State private var shareURL: URL?
    @State private var errorMessage: String?

    private let parser = CADParserService()

    private var visibleLayerNames: Set<String> {
        Set((drawing?.layers ?? []).filter(\.isVisible).map(\.name))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if is3DMode, let scene3D, let model3DInfo {
                    CAD3DViewerView(scene: scene3D, modelInfo: model3DInfo)
                } else if let drawing {
                    CADCanvasView(
                        drawing: drawing,
                        spatialIndex: spatialIndex,
                        visibleLayers: visibleLayerNames,
                        isThermalThrottled: isThermalThrottled,
                        transform: $transform,
                        toolMode: $toolMode,
                        activePoints: $activePoints,
                        selectedEntityID: $selectedEntityID,
                        onTapWorld: handleWorldTap
                    )
                    .ignoresSafeArea(edges: .bottom)

                    VStack {
                        if let readout = statusReadout {
                            Text(readout)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.top, 6)
                        }
                        if isThermalThrottled {
                            Text("Eco Mode Active (Thermal Guard)")
                                .font(.caption2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.yellow.opacity(0.25), in: Capsule())
                        }
                        Spacer()
                        if showCoordEntry {
                            coordinateEntryBar
                        }
                        if toolMode == .offset {
                            offsetBar
                        }
                        if toolMode == .align {
                            alignBar
                        }
                        if toolMode == .color {
                            colorBar
                        }
                        bottomToolBar
                    }
                } else {
                    emptyStateView
                }
            }
            .navigationTitle(drawing?.fileName ?? "CADFastView")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    if drawing != nil {
                        Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                            .disabled(undoStack.isEmpty)
                        Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                            .disabled(redoStack.isEmpty)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "folder") }
                    if drawing != nil {
                        Menu {
                            Button("Zoom Extents") { regenDrawing(fitExtents: true) }
                            Button("Save Current Viewpoint") { showSaveViewpointAlert = true }
                            if !savedViewpoints.isEmpty {
                                Divider()
                                ForEach(savedViewpoints) { vp in
                                    Button(vp.name) {
                                        is3DMode = false
                                        transform = CADViewportTransform(
                                            scale: vp.scale,
                                            offset: CGSize(width: vp.offsetWidth, height: vp.offsetHeight)
                                        )
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "eye")
                        }
                        Button { regenDrawing(fitExtents: false) } label: { Image(systemName: "arrow.clockwise") }
                        Button { showCoordEntry.toggle() } label: { Image(systemName: "number") }
                        Button {
                            if is3DMode {
                                is3DMode = false
                            } else if let drawing {
                                let (s, info) = CAD3DLoader.extrude2DDrawing(drawing)
                                scene3D = s; model3DInfo = info; is3DMode = true
                            }
                        } label: {
                            Image(systemName: is3DMode ? "square.2.layers.3d" : "cube")
                        }
                        Button { showLayers = true } label: { Image(systemName: "square.3.layers.3d") }
                        Menu {
                            Button("Export PDF") { exportPDF() }
                            Button("Save / Share DXF") { exportDXF() }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "dwg") ?? .data,
                    UTType(filenameExtension: "dxf") ?? .plainText,
                    UTType(filenameExtension: "step") ?? .data,
                    UTType(filenameExtension: "stp") ?? .data,
                    UTType(filenameExtension: "ifc") ?? .data,
                    UTType(filenameExtension: "obj") ?? .data,
                    UTType(filenameExtension: "stl") ?? .data,
                    UTType(filenameExtension: "usdz") ?? .usdz
                ]
            ) { result in
                if case .success(let url) = result {
                    importLocalCopyAndLoad(url)
                }
            }
            .sheet(isPresented: $showLayers) {
                if let binding = Binding($drawing) {
                    LayerSheetView(layers: binding.layers)
                }
            }
            .sheet(item: Binding(
                get: { shareURL.map { IdentifiableURL(url: $0) } },
                set: { shareURL = $0?.url }
            )) { item in
                ShareSheet(items: [item.url])
            }
            .alert("Save Viewpoint", isPresented: $showSaveViewpointAlert) {
                TextField("Viewpoint name (e.g. Gate A)", text: $newViewpointName)
                Button("Save") {
                    let name = newViewpointName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let vp = CADViewpoint(
                        name: name.isEmpty ? "View \(savedViewpoints.count + 1)" : name,
                        scale: transform.scale,
                        offsetWidth: transform.offset.width,
                        offsetHeight: transform.offset.height
                    )
                    savedViewpoints.append(vp)
                    newViewpointName = ""
                }
                Button("Cancel", role: .cancel) { newViewpointName = "" }
            }
            .alert("Unable to Open Drawing", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                refreshLocalFiles()
                updateThermalState()
            }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                updateThermalState()
            }
            .onChange(of: externalFileURL) { url in
                if let url { importLocalCopyAndLoad(url) }
            }
        }
    }

    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 50))
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
                Text("Offline 2D CAD Viewer & Editor")
                    .font(.title3.weight(.semibold))
                Text("Open downloaded .dxf or .dwg files from the Files app or Safari Downloads—100% offline, zero tracking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                HStack(spacing: 12) {
                    Button("Open Downloads / Files") { showImporter = true }
                        .buttonStyle(.borderedProminent)
                    Button("Load Sample") { loadSample() }
                        .buttonStyle(.bordered)
                }

                if !localSavedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Local Drawings")
                            .font(.headline)
                            .padding(.top, 12)
                        ForEach(localSavedFiles, id: \.self) { url in
                            Button {
                                loadURL(url)
                            } label: {
                                HStack {
                                    Image(systemName: "doc.text")
                                    Text(url.lastPathComponent)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private var coordinateEntryBar: some View {
        HStack(spacing: 8) {
            TextField("X,Y,Z  or  @dX,dY,dZ  or  @Dist<Deg", text: $coordInputText)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .autocorrectionDisabled()
            Button("Apply") {
                if let pt = CADGeometryMath.parseCoordinateInput(coordInputText, lastPoint: activePoints.last) {
                    handleWorldTap(pt)
                    coordInputText = ""
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
    }

    private var colorBar: some View {
        HStack(spacing: 10) {
            Text("Color:")
                .font(.caption.weight(.medium))
            ForEach([1, 2, 3, 4, 5, 6, 7], id: \.self) { aci in
                Button {
                    selectedColorIndex = aci
                } label: {
                    Circle()
                        .fill(ACIColorPalette.color(for: aci))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(selectedColorIndex == aci ? Color.white : Color.clear, lineWidth: 2.5)
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
    }

    private var alignBar: some View {
        HStack(spacing: 10) {
            Toggle("Scale to Fit", isOn: $alignScaleToFit)
                .toggleStyle(.switch)
                .font(.caption.weight(.medium))
                .fixedSize()
            if selectedEntityID != nil && !activePoints.isEmpty {
                Button("Reset") { activePoints = [] }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
    }

    private var offsetBar: some View {
        HStack(spacing: 8) {
            Text("Offset Dist:")
                .font(.caption.weight(.medium))
            TextField("2.0", text: $offsetDistanceText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .frame(width: 80)
            Text(selectedEntityID == nil ? "1. Tap line/poly/circle" : "2. Tap side to offset")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
    }

    private var bottomToolBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CADToolMode.allCases) { mode in
                        Button {
                            toolMode = mode
                            activePoints = []
                            selectedEntityID = nil
                        } label: {
                            Text(mode.rawValue)
                                .font(.caption.weight(toolMode == mode ? .bold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(toolMode == mode ? Color.accentColor : Color.secondary.opacity(0.2), in: Capsule())
                                .foregroundStyle(toolMode == mode ? .white : .primary)
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            if toolMode == .drawPolyline && activePoints.count >= 2 {
                HStack {
                    Button("Finish Polyline") { commitPolyline(closed: false) }.buttonStyle(.bordered).controlSize(.small)
                    Button("Close Polyline") { commitPolyline(closed: true) }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private var statusReadout: String? {
        switch toolMode {
        case .pan:
            return nil
        case .coordinates:
            guard let p = activePoints.last else { return "Tap drawing for X, Y, Z (vertex snap on)" }
            return String(format: "X: %.3f   Y: %.3f   Z: %.3f", p.x, p.y, p.z)
        case .angleBearing:
            if activePoints.isEmpty { return "Angle/Brg: Tap 1st point (back-sight)" }
            if activePoints.count == 1 { return "Tap 2nd point (station/end)" }
            let brg12 = CADGeometryMath.bearingDegrees(activePoints[0], activePoints[1])
            if activePoints.count == 2 {
                return "Brg: \(CADGeometryMath.formatDMS(brg12)) (\(CADGeometryMath.quadrantBearing(brg12))) — tap 3rd pt for angle"
            }
            let ang = CADGeometryMath.interiorAngleDegrees(activePoints[0], vertex: activePoints[1], activePoints[2])
            let brg23 = CADGeometryMath.bearingDegrees(activePoints[1], activePoints[2])
            return "Angle: \(CADGeometryMath.formatDMS(ang)) | Brg 2-3: \(CADGeometryMath.formatDMS(brg23))"
        case .distance:
            if activePoints.isEmpty { return "Tap start point" }
            if activePoints.count == 1 { return "Tap end point" }
            let hd = CADGeometryMath.distance(activePoints[0], activePoints[1])
            let sd = CADGeometryMath.slopeDistance3D(activePoints[0], activePoints[1])
            let dz = activePoints[1].z - activePoints[0].z
            let brg = CADGeometryMath.bearingDegrees(activePoints[0], activePoints[1])
            return abs(dz) > 1e-6 ? String(format: "HD: %.3f  SD: %.3f  dZ: %.3f  Brg: %.2f°", hd, sd, dz, brg) : String(format: "Dist: %.3f   Brg: %.2f°", hd, brg)
        case .area:
            if activePoints.count < 3 { return "Tap \(3 - activePoints.count)+ vertices for area" }
            return String(format: "Area: %.3f sq units (%d pts)", CADGeometryMath.polygonArea(activePoints), activePoints.count)
        case .drawLine:
            return activePoints.isEmpty ? "Draw Line: Tap start or enter X,Y" : "Draw Line: Tap end point"
        case .drawPolyline:
            return "Polyline: \(activePoints.count) pts — tap next or Finish"
        case .drawCircle:
            return activePoints.isEmpty ? "Circle: Tap center" : "Circle: Tap radius point"
        case .dimension:
            return activePoints.isEmpty ? "Dimension: Tap 1st point" : "Dimension: Tap 2nd point"
        case .offset:
            return selectedEntityID == nil ? "Offset: Tap entity to offset" : "Offset: Tap side to place parallel copy"
        case .align:
            if selectedEntityID == nil { return "Align: 1. Tap entity to align" }
            switch activePoints.count {
            case 0: return "Align: Tap Source Pt 1"
            case 1: return "Align: Tap Destination Pt 1"
            case 2: return "Align: Tap Source Pt 2"
            default: return "Align: Tap Destination Pt 2"
            }
        case .color:
            return "Color: Pick swatch below, then tap any entity"
        case .explode:
            return "Explode: Tap any Polyline or Dimension to break into Lines"
        case .erase:
            return "Erase: Tap any entity to delete"
        }
    }

    private func handleWorldTap(_ pt: CADPoint2D) {
        switch toolMode {
        case .pan:
            break
        case .coordinates:
            activePoints = [pt]
        case .angleBearing:
            activePoints = activePoints.count >= 3 ? [pt] : activePoints + [pt]
        case .distance:
            activePoints = activePoints.count >= 2 ? [pt] : activePoints + [pt]
        case .area:
            activePoints.append(pt)
        case .drawLine:
            if let first = activePoints.first {
                addEntity(CADEntity(layerName: "0", colorIndex: 3, geometry: .line(start: first, end: pt)))
                activePoints = []
            } else {
                activePoints = [pt]
            }
        case .drawPolyline:
            activePoints.append(pt)
        case .drawCircle:
            if let center = activePoints.first {
                let r = max(CADGeometryMath.distance(center, pt), 0.1)
                addEntity(CADEntity(layerName: "0", colorIndex: 4, geometry: .circle(center: center, radius: r)))
                activePoints = []
            } else {
                activePoints = [pt]
            }
        case .dimension:
            if let p1 = activePoints.first {
                addEntity(CADEntity(layerName: "DIMENSIONS", colorIndex: 4, geometry: .dimension(p1: p1, p2: pt, offsetDistance: 3.0)))
                activePoints = []
            } else {
                activePoints = [pt]
            }
        case .offset:
            guard let drawing else { return }
            let tol = Double(18.0 / max(transform.scale, 0.001))
            if let selID = selectedEntityID,
               let target = drawing.entities.first(where: { $0.id == selID }),
               let dist = Double(offsetDistanceText), dist > 0,
               let newEntity = CADGeometryMath.offsetEntity(target, by: dist, toward: pt) {
                addEntity(newEntity)
                selectedEntityID = nil
            } else if let idx = CADGeometryMath.nearestEntityIndex(to: pt, in: drawing.entities, visibleLayers: visibleLayerNames, maxWorldDist: tol) {
                selectedEntityID = drawing.entities[idx].id
            }
        case .align:
            guard var d = drawing else { return }
            let tol = Double(18.0 / max(transform.scale, 0.001))
            if selectedEntityID == nil {
                if let idx = CADGeometryMath.nearestEntityIndex(to: pt, in: d.entities, visibleLayers: visibleLayerNames, maxWorldDist: tol) {
                    selectedEntityID = d.entities[idx].id
                    activePoints = []
                }
            } else {
                activePoints.append(pt)
                if activePoints.count == 4,
                   let selID = selectedEntityID,
                   let idx = d.entities.firstIndex(where: { $0.id == selID }) {
                    pushUndo(d.entities)
                    let aligned = CADGeometryMath.alignEntity(
                        d.entities[idx],
                        s1: activePoints[0],
                        d1: activePoints[1],
                        s2: activePoints[2],
                        d2: activePoints[3],
                        scaleToFit: alignScaleToFit
                    )
                    d.entities[idx] = aligned
                    d.boundingBox.expand(to: aligned.boundingBox)
                    updateDrawing(d)
                    activePoints = []
                    selectedEntityID = nil
                }
            }
        case .color:
            guard var d = drawing else { return }
            let tol = Double(18.0 / max(transform.scale, 0.001))
            if let idx = CADGeometryMath.nearestEntityIndex(to: pt, in: d.entities, visibleLayers: visibleLayerNames, maxWorldDist: tol) {
                pushUndo(d.entities)
                d.entities[idx].colorIndex = selectedColorIndex
                updateDrawing(d)
            }
        case .explode:
            guard var d = drawing else { return }
            let tol = Double(18.0 / max(transform.scale, 0.001))
            if let idx = CADGeometryMath.nearestEntityIndex(to: pt, in: d.entities, visibleLayers: visibleLayerNames, maxWorldDist: tol),
               let pieces = CADGeometryMath.explodeEntity(d.entities[idx]) {
                pushUndo(d.entities)
                d.entities.remove(at: idx)
                d.entities.insert(contentsOf: pieces, at: idx)
                updateDrawing(d)
            }
        case .erase:
            guard var d = drawing else { return }
            let tol = Double(18.0 / max(transform.scale, 0.001))
            if let idx = CADGeometryMath.nearestEntityIndex(to: pt, in: d.entities, visibleLayers: visibleLayerNames, maxWorldDist: tol) {
                pushUndo(d.entities)
                d.entities.remove(at: idx)
                updateDrawing(d)
            }
        }
    }

    private func commitPolyline(closed: Bool) {
        guard activePoints.count >= 2 else { return }
        addEntity(CADEntity(layerName: "0", colorIndex: 2, geometry: .polyline(points: activePoints, closed: closed)))
        activePoints = []
    }

    private func addEntity(_ entity: CADEntity) {
        guard var d = drawing else { return }
        pushUndo(d.entities)
        d.entities.append(entity)
        d.boundingBox.expand(to: entity.boundingBox)
        if !d.layers.contains(where: { $0.name == entity.layerName }) {
            d.layers.append(CADLayer(name: entity.layerName, colorIndex: entity.colorIndex, isVisible: true, entityCount: 1))
        }
        updateDrawing(d)
    }

    private func pushUndo(_ snapshot: [CADEntity]) {
        undoStack.append(snapshot)
        if undoStack.count > 30 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func undo() {
        guard var d = drawing, let prev = undoStack.popLast() else { return }
        redoStack.append(d.entities)
        d.entities = prev
        updateDrawing(d)
    }

    private func redo() {
        guard var d = drawing, let next = redoStack.popLast() else { return }
        undoStack.append(d.entities)
        d.entities = next
        updateDrawing(d)
    }

    private func regenDrawing(fitExtents: Bool) {
        guard var d = drawing else { return }
        var box = CADBoundingBox()
        var counts: [String: Int] = [:]
        for e in d.entities {
            box.expand(to: e.boundingBox)
            counts[e.layerName, default: 0] += 1
        }
        d.boundingBox = box
        for i in d.layers.indices {
            d.layers[i].entityCount = counts[d.layers[i].name, default: 0]
        }
        updateDrawing(d)
        if fitExtents {
            transform = CADViewportTransform.fitExtents(box: box, canvasSize: UIScreen.main.bounds.size)
        }
        regenTrigger += 1
    }

    private func updateDrawing(_ updated: CADDrawing) {
        drawing = updated
        spatialIndex = CADSpatialIndex(entities: updated.entities, bounds: updated.boundingBox)
    }

    private func updateThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        isThermalThrottled = (state == .serious || state == .critical)
    }

    private func refreshLocalFiles() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let items = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        localSavedFiles = items.filter { ["dxf", "dwg", "step", "stp", "ifc", "obj", "stl", "usdz"].contains($0.pathExtension.lowercased()) }
    }

    private func importLocalCopyAndLoad(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = docs.appendingPathComponent(url.lastPathComponent)
        if url != dest {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: dest.path)
        }
        refreshLocalFiles()
        loadURL(FileManager.default.fileExists(atPath: dest.path) ? dest : url)
    }

    private func loadSample() {
        if let url = Bundle.main.url(forResource: "SampleSurvey", withExtension: "dxf") {
            loadURL(url)
        }
    }

    private func loadSample3D() {
        let (s, info) = CAD3DLoader.sampleBIMScene()
        scene3D = s; model3DInfo = info; is3DMode = true
    }

    private func loadURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ["obj", "stl", "ply", "usdz", "usda", "usdc", "stp", "step", "ifc"].contains(ext) {
            Task(priority: .userInitiated) {
                do {
                    let (s, info) = try CAD3DLoader.loadScene(from: url)
                    await MainActor.run {
                        scene3D = s; model3DInfo = info; is3DMode = true
                    }
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription }
                }
            }
            return
        }
        Task(priority: .userInitiated) {
            do {
                let parsed = try await parser.loadDrawing(from: url)
                let index = CADSpatialIndex(entities: parsed.entities, bounds: parsed.boundingBox)
                await MainActor.run {
                    activePoints = []
                    undoStack = []
                    redoStack = []
                    selectedEntityID = nil
                    spatialIndex = index
                    is3DMode = false
                    drawing = parsed
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func exportPDF() {
        guard let drawing else { return }
        do {
            shareURL = try CADPDFExporter.export(drawing: drawing, visibleLayers: visibleLayerNames)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportDXF() {
        guard let drawing else { return }
        do {
            shareURL = try CADDXFExporter.export(drawing: drawing)
            refreshLocalFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
