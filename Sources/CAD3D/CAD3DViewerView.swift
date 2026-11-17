import SwiftUI
import SceneKit

struct CAD3DViewerView: View {
    let scene: SCNScene
    let modelInfo: CAD3DModelInfo
    @State private var renderStyle: CAD3DRenderStyle = .shaded
    @State private var sectionCutY: Double = 1.0
    @State private var selectedViewpoint: String = "Iso"
    @State private var viewpointTrigger = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            SceneKitContainer(scene: scene, renderStyle: renderStyle, sectionCutRatio: sectionCutY, viewpoint: selectedViewpoint, viewpointTrigger: viewpointTrigger)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(["Iso", "Top", "Front", "Right"], id: \.self) { vp in
                        Button(vp) {
                            selectedViewpoint = vp
                            viewpointTrigger += 1
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }

                Text("\(modelInfo.format): \(modelInfo.summary)")
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())

                HStack(spacing: 12) {
                    Picker("Style", selection: $renderStyle) {
                        ForEach(CAD3DRenderStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 6) {
                        Image(systemName: "scissors")
                            .font(.caption)
                        Slider(value: $sectionCutY, in: 0.05...1.0)
                            .frame(width: 90)
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
}

private struct SceneKitContainer: UIViewRepresentable {
    let scene: SCNScene
    let renderStyle: CAD3DRenderStyle
    let sectionCutRatio: Double
    let viewpoint: String
    let viewpointTrigger: Int

    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator { var lastTrigger = 0 }

    private func applyViewpoint(_ vp: String, in view: SCNView, scene: SCNScene) {
        let (minV, maxV) = scene.rootNode.boundingBox
        let cx = (minV.x + maxV.x) * 0.5
        let cy = (minV.y + maxV.y) * 0.5
        let cz = (minV.z + maxV.z) * 0.5
        let span = max(maxV.x - minV.x, max(maxV.y - minV.y, maxV.z - minV.z))
        let d = max(span * 1.6, 10.0)
        let cam = view.pointOfView ?? SCNNode()
        switch vp {
        case "Top":
            cam.position = SCNVector3(cx, cy + d, cz + 0.01)
        case "Front":
            cam.position = SCNVector3(cx, cy, cz + d)
        case "Right":
            cam.position = SCNVector3(cx + d, cy, cz)
        default:
            cam.position = SCNVector3(cx + d * 0.7, cy + d * 0.6, cz + d * 0.7)
        }
        cam.look(at: SCNVector3(cx, cy, cz))
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0)
        // Battery & thermal protection: render only on touch/camera change, never idle 60fps spin
        view.rendersContinuously = false
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if uiView.scene !== scene {
            uiView.scene = scene
        }

        if context.coordinator.lastTrigger != viewpointTrigger {
            context.coordinator.lastTrigger = viewpointTrigger
            applyViewpoint(viewpoint, in: uiView, scene: scene)
        }
        let (minV, maxV) = scene.rootNode.boundingBox
        let cutY = minV.y + (maxV.y - minV.y) * Float(sectionCutRatio)

        scene.rootNode.enumerateChildNodes { node, _ in
            node.isHidden = node.position.y > cutY + 0.01
            guard let geo = node.geometry else { return }
            for mat in geo.materials {
                switch renderStyle {
                case .shaded:
                    mat.fillMode = .fill
                    mat.transparency = 1.0
                case .wireframe:
                    mat.fillMode = .lines
                    mat.transparency = 1.0
                case .xray:
                    mat.fillMode = .fill
                    mat.transparency = 0.35
                }
            }
        }
    }
}
