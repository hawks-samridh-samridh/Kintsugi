import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            Color(red: 0.051, green: 0.051, blue: 0.051)
                .ignoresSafeArea()

            // single persistent VaseSceneView — never recreated across stage changes
            // recreating it would restart triggerShatter() and lose fragment state
            VaseSceneView()
                .ignoresSafeArea()
                .accessibilityLabel("Three-dimensional ceramic vase")
                .accessibilityHint("Watch as the vase shatters and is repaired with gold")
                .opacity(appModel.stage == .share ? 0 : 1)

            // crack overlay persists through repair and reveal so gold marks remain
            if appModel.stage == .repair || appModel.stage == .reveal {
                CrackRepairOverlay()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // share view slides in on top when all cracks are repaired and reveal finishes
            if appModel.stage == .share {
                ShareView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: appModel.stage)
    }
}
