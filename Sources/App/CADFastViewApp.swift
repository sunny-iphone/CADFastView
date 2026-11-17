import SwiftUI

@main
struct CADFastViewApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var incomingFileURL: URL?
    @State private var showCompromisedAlert = false

    init() {
        SecurityHardener.purgeTemporaryExports()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(externalFileURL: $incomingFileURL)
                    .onOpenURL { url in
                        incomingFileURL = url
                    }

                // Privacy shield: hides drawings from iOS app-switcher snapshots
                if scenePhase != .active {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.largeTitle)
                                Text("CADFastView Protected")
                                    .font(.headline)
                            }
                            .foregroundStyle(.secondary)
                        }
                }
            }
            .onAppear {
                if SecurityHardener.isDeviceCompromised() {
                    showCompromisedAlert = true
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    SecurityHardener.purgeTemporaryExports()
                }
            }
            .alert("Security Warning", isPresented: $showCompromisedAlert) {
                Button("Continue Anyway", role: .destructive) {}
            } message: {
                Text("This device appears jailbroken or modified. Local file encryption guarantees may be reduced.")
            }
        }
    }
}
