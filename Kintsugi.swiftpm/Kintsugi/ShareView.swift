import SwiftUI
@preconcurrency import SceneKit

struct ShareView: View {
    @Environment(AppModel.self) private var appModel
    @State private var shareImage: UIImage? = nil
    @State private var showShareSheet = false
    @State private var isCapturing = false

    var body: some View {
        @Bindable var model = appModel
        ZStack {
            Color(red: 0.051, green: 0.051, blue: 0.051)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Your vase, made whole")
                    .font(.system(.title2, design: .default, weight: .thin))
                    .foregroundStyle(.white)
                    .padding(.top, 60)
                    .padding(.bottom, 24)
                    .accessibilityAddTraits(.isHeader)

                RotatingVaseView()
                    .frame(height: 260)
                    .accessibilityLabel("Three-dimensional ceramic vase, restored with gold")
                    .accessibilityHint("Your repaired vase, rotating slowly")

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(crackReflections) { reflection in
                            Text(reflection.quote)
                                .font(.system(.caption, design: .default, weight: .thin))
                                .foregroundStyle(appModel.goldColor)
                                .multilineTextAlignment(.leading)
                                .accessibilityLabel("Reflection: \(reflection.quote)")
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                }
                .frame(maxHeight: 200)

                Spacer()

                Button {
                    Task { await captureAndShare() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                            .font(.system(.body, design: .default, weight: .regular))
                    }
                    .foregroundStyle(Color(red: 0.051, green: 0.051, blue: 0.051))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(appModel.goldColor)
                    .clipShape(Capsule())
                }
                .padding(.bottom, 20)
                .accessibilityLabel("Share your restored vase")
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showShareSheet)

                Button {
                    model.userColorblindOverride.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: appModel.isColorblindMode ? "eye.slash" : "eye")
                            .font(.caption)
                        Text(appModel.isColorblindMode ? "High contrast: on" : "High contrast: off")
                            .font(.system(.caption2, design: .default, weight: .thin))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 40)
                .accessibilityLabel(appModel.isColorblindMode
                    ? "High contrast mode enabled. Tap to disable."
                    : "High contrast mode disabled. Tap to enable.")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let img = shareImage {
                ShareSheet(image: img)
            }
        }
    }

    func captureAndShare() async {
        guard !isCapturing else { return }
        isCapturing = true

        await MainActor.run {
            // snapshot only captures scenekit — composite the 2d crack overlay manually
            let size = CGSize(width: 1080, height: 1080)
            let tempView = SCNView(frame: CGRect(origin: .zero, size: size))
            tempView.backgroundColor = UIColor(red: 0.051, green: 0.051, blue: 0.051, alpha: 1)
            tempView.antialiasingMode = .multisampling4X

            let scene = SCNScene()
            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 45
            camera.position = SCNVector3(0, 0, 6)
            scene.rootNode.addChildNode(camera)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.color = UIColor(white: 0.3, alpha: 1)
            scene.rootNode.addChildNode(ambient)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.color = UIColor(white: 0.9, alpha: 1)
            key.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 6, 0)
            scene.rootNode.addChildNode(key)

            let coord = VaseSceneCoordinator()
            coord.scene = scene
            coord.scnView = tempView
            let geo = coord.makeVaseGeometry()
            geo.materials = [coord.ceramicMaterial()]
            scene.rootNode.addChildNode(SCNNode(geometry: geo))

            tempView.scene = scene
            tempView.autoenablesDefaultLighting = false

            let scnImage = tempView.snapshot()

            // draw gold crack paths over the scenekit snapshot since snapshot() misses swiftui layers
            let goldColor = appModel.isColorblindMode
                ? UIColor.white
                : UIColor(red: 0.831, green: 0.659, blue: 0.263, alpha: 1)

            let renderer = UIGraphicsImageRenderer(size: size)
            let composite = renderer.image { ctx in
                scnImage.draw(at: .zero)

                let cgCtx = ctx.cgContext
                cgCtx.setLineCap(.round)
                cgCtx.setLineJoin(.round)

                // glow pass — wide soft stroke beneath the crisp line
                cgCtx.setStrokeColor(goldColor.withAlphaComponent(0.35).cgColor)
                cgCtx.setLineWidth(12)
                for crack in crackPaths {
                    let pts = crack.points.map {
                        CGPoint(x: $0.x * size.width, y: $0.y * size.height)
                    }
                    guard pts.count >= 2 else { continue }
                    cgCtx.move(to: pts[0])
                    pts.dropFirst().forEach { cgCtx.addLine(to: $0) }
                    cgCtx.strokePath()
                }

                // crisp gold line on top
                cgCtx.setStrokeColor(goldColor.cgColor)
                cgCtx.setLineWidth(4)
                for crack in crackPaths {
                    let pts = crack.points.map {
                        CGPoint(x: $0.x * size.width, y: $0.y * size.height)
                    }
                    guard pts.count >= 2 else { continue }
                    cgCtx.move(to: pts[0])
                    pts.dropFirst().forEach { cgCtx.addLine(to: $0) }
                    cgCtx.strokePath()
                }
            }

            shareImage = composite
            showShareSheet = true
        }

        isCapturing = false
    }
}

struct RotatingVaseView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = false

        let scene = SCNScene()
        scnView.scene = scene

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 45
        camera.position = SCNVector3(0, 0, 6)
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(white: 0.3, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = UIColor(white: 0.9, alpha: 1)
        key.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 6, 0)
        scene.rootNode.addChildNode(key)

        let coord = VaseSceneCoordinator()
        coord.scene = scene
        coord.scnView = scnView
        let geo = coord.makeVaseGeometry()
        geo.materials = [coord.ceramicMaterial()]

        let vaseNode = SCNNode(geometry: geo)
        scene.rootNode.addChildNode(vaseNode)

        vaseNode.runAction(SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 8)
        ))

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
