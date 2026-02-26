import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ZStack {
            Color(red: 0.051, green: 0.051, blue: 0.051)
                .ignoresSafeArea()

            switch appModel.stage {
            case .shatter:
                VaseSceneView()
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityLabel("Three-dimensional ceramic vase")
                    .accessibilityHint("Watch as the vase shatters and is repaired with gold")

            case .repair:
                ZStack {
                    VaseSceneView()
                        .ignoresSafeArea()
                    CrackRepairOverlay()
                        .ignoresSafeArea()
                }
                .transition(.opacity)

            case .reveal:
                ZStack {
                    VaseSceneView()
                        .ignoresSafeArea()
                    CrackRepairOverlay()
                        .ignoresSafeArea()
                }
                .transition(.opacity)

            case .share:
                ShareView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: appModel.stage)
    }
}
