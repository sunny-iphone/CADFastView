import SwiftUI

struct LayerSheetView: View {
    @Binding var layers: [CADLayer]
    @Environment(\.dismiss) private var dismiss

    private let quickColors = [1, 2, 3, 4, 5, 6, 7]

    var body: some View {
        NavigationStack {
            List {
                ForEach($layers) { $layer in
                    HStack(spacing: 12) {
                        Button {
                            let idx = quickColors.firstIndex(of: layer.colorIndex) ?? 0
                            layer.colorIndex = quickColors[(idx + 1) % quickColors.count]
                        } label: {
                            Circle()
                                .fill(ACIColorPalette.color(for: layer.colorIndex))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Toggle(isOn: $layer.isVisible) {
                            VStack(alignment: .leading) {
                                Text(layer.name).font(.body.weight(.medium))
                                Text("\(layer.entityCount) entities • Tap swatch for color")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Layers (\(layers.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("All On") {
                        for idx in layers.indices { layers[idx].isVisible = true }
                    }
                    Button("All Off") {
                        for idx in layers.indices { layers[idx].isVisible = false }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
