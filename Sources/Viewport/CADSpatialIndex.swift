import Foundation

/// Uniform 2D spatial grid so pan/zoom and vertex snapping only inspect visible entities,
/// preventing CPU spikes, battery drain, and overheating on large drawings.
struct CADSpatialIndex: Sendable {
    private struct CellKey: Hashable {
        let x: Int
        let y: Int
    }

    private let originX: Double
    private let originY: Double
    private let cellW: Double
    private let cellH: Double
    private var cells: [CellKey: [Int]] = [:]
    private let gridSize = 24

    init(entities: [CADEntity], bounds: CADBoundingBox) {
        self.originX = bounds.isValid ? bounds.minX : 0
        self.originY = bounds.isValid ? bounds.minY : 0
        self.cellW = max((bounds.isValid ? bounds.width : 100) / Double(gridSize), 1e-3)
        self.cellH = max((bounds.isValid ? bounds.height : 100) / Double(gridSize), 1e-3)

        for (idx, e) in entities.enumerated() {
            let b = e.boundingBox
            guard b.isValid else { continue }
            let minCX = max(0, min(gridSize - 1, Int((b.minX - originX) / cellW)))
            let maxCX = max(0, min(gridSize - 1, Int((b.maxX - originX) / cellW)))
            let minCY = max(0, min(gridSize - 1, Int((b.minY - originY) / cellH)))
            let maxCY = max(0, min(gridSize - 1, Int((b.maxY - originY) / cellH)))
            for cx in minCX...maxCX {
                for cy in minCY...maxCY {
                    cells[CellKey(x: cx, y: cy), default: []].append(idx)
                }
            }
        }
    }

    func queryIndices(in box: CADBoundingBox) -> [Int] {
        guard box.isValid else { return [] }
        let minCX = max(0, min(gridSize - 1, Int((box.minX - originX) / cellW)))
        let maxCX = max(0, min(gridSize - 1, Int((box.maxX - originX) / cellW)))
        let minCY = max(0, min(gridSize - 1, Int((box.minY - originY) / cellH)))
        let maxCY = max(0, min(gridSize - 1, Int((box.maxY - originY) / cellH)))

        var seen = Set<Int>()
        var result: [Int] = []
        for cx in minCX...maxCX {
            for cy in minCY...maxCY {
                if let list = cells[CellKey(x: cx, y: cy)] {
                    for idx in list where seen.insert(idx).inserted {
                        result.append(idx)
                    }
                }
            }
        }
        return result
    }
}
