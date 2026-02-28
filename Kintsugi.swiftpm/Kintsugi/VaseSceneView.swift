@preconcurrency import SceneKit
import SwiftUI

struct VaseSceneView: UIViewRepresentable {
    @Environment(AppModel.self) private var appModel

    func makeCoordinator() -> VaseSceneCoordinator {
        VaseSceneCoordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = UIColor(red: 0.051, green: 0.051, blue: 0.051, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false

        let scene = SCNScene()
        scnView.scene = scene

        let coordinator = context.coordinator
        coordinator.scnView = scnView
        coordinator.scene = scene
        coordinator.appModel = appModel
        coordinator.setupScene()

        scnView.delegate = coordinator

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.appModel = appModel
        coordinator.handleStageChange(appModel.stage)
    }
}

@MainActor
final class VaseSceneCoordinator: NSObject {
    var scnView: SCNView?
    var scene: SCNScene?
    var appModel: AppModel?

    var vaseNode: SCNNode?
    var fragmentNodes: [SCNNode] = []
    var originalTransforms: [SCNMatrix4] = []
    var isShattered = false
    var currentStage: AppStage?

    func setupScene() {
        guard let scene else { return }

        // zero gravity so shattered fragments float visibly outward
        // with gravity they fall off-screen before we can screenshot them
        scene.physicsWorld.gravity = SCNVector3(0, 0, 0)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 45
        cameraNode.position = SCNVector3(0, 0, 6)
        scene.rootNode.addChildNode(cameraNode)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor(white: 0.35, alpha: 1)  // lower ambient = more drama
        scene.rootNode.addChildNode(ambientLight)

        // Strong key light from upper-left — creates smooth ceramic highlight gradient
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.color = UIColor(white: 1.0, alpha: 1)
        keyLight.light?.castsShadow = false
        keyLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 5, 0)
        scene.rootNode.addChildNode(keyLight)

        // Soft fill from right-below to lift shadow side
        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.color = UIColor(white: 0.30, alpha: 1)
        fillLight.eulerAngles = SCNVector3(Float.pi / 6, -Float.pi / 3, 0)
        scene.rootNode.addChildNode(fillLight)

        // Warm rim light from behind-right: gives ceramic a luminous edge for depth
        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light?.type = .directional
        rimLight.light?.color = UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1)  // warm white
        rimLight.light?.intensity = 600
        rimLight.eulerAngles = SCNVector3(Float.pi / 8, -Float.pi * 0.7, 0)  // behind-right
        scene.rootNode.addChildNode(rimLight)

        // Back-fill light: illuminates fragment inner faces during shatter
        let backLight = SCNNode()
        backLight.light = SCNLight()
        backLight.light?.type = .directional
        backLight.light?.color = UIColor(white: 0.50, alpha: 1)
        backLight.eulerAngles = SCNVector3(0, Float.pi, 0)
        scene.rootNode.addChildNode(backLight)

        buildVase()

        switch appModel?.screenshotMode {
        case .intact:
            // CI: show intact vase immediately, no auto-shatter
            vaseNode?.opacity = 1
        case .shatter:
            // CI: scatter fragments immediately after first frame renders
            vaseNode?.opacity = 0
            DispatchQueue.main.async { self.setupShatterImmediately() }
        case .repair:
            // CI: show reassembled vase + crack overlay
            vaseNode?.opacity = 1
            DispatchQueue.main.async { self.appModel?.stage = .repair }
        case nil:
            // Normal experience
            vaseNode?.opacity = 0
            let fadeIn = SCNAction.fadeIn(duration: 0.8)
            vaseNode?.runAction(SCNAction.sequence([SCNAction.wait(duration: 0.2), fadeIn]))

            // SCNAction.wait advances with scene render time
            let shatterTrigger = SCNAction.sequence([
                SCNAction.wait(duration: 50.0),
                SCNAction.customAction(duration: 0) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.triggerShatter() }
                }
            ])
            vaseNode?.runAction(shatterTrigger, forKey: "shatterTrigger")
        }
    }

    // MARK: - Vase Geometry

    func buildVase() {
        guard let scene else { return }

        let geometry = makeVaseGeometry()
        geometry.materials = [ceramicMaterial()]

        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)
        vaseNode = node
    }

    func makeVaseGeometry() -> SCNGeometry {
        // tokkuri silhouette: narrow neck, wide belly, small base
        let profile: [(r: Float, y: Float)] = [
            (0.12, -1.50),  // base center
            (0.28, -1.40),  // base edge
            (0.50, -1.10),  // lower belly
            (0.62, -0.60),  // widest belly
            (0.58,  0.00),  // mid belly
            (0.45,  0.45),  // upper belly
            (0.28,  0.75),  // shoulder
            (0.18,  0.95),  // neck bottom
            (0.14,  1.15),  // neck mid
            (0.16,  1.30),  // lip flare
            (0.20,  1.42),  // lip
            (0.18,  1.50),  // lip top
        ]

        let verticalSteps = profile.count
        let angularSteps = 72  // 2× resolution: eliminates low-poly faceting on belly
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texCoords: [CGPoint] = []
        var indices: [UInt32] = []

        for (vi, pt) in profile.enumerated() {
            let v = Float(vi) / Float(verticalSteps - 1)
            for ai in 0..<angularSteps {
                let angle = 2 * Float.pi * Float(ai) / Float(angularSteps)
                positions.append(SCNVector3(pt.r * cos(angle), pt.y, pt.r * sin(angle)))
                texCoords.append(CGPoint(x: Double(ai) / Double(angularSteps), y: Double(v)))
            }
        }

        // normal = rotate profile tangent 90° outward: tangent (dr, dy) → normal (dy, -dr)
        for vi in 0..<verticalSteps {
            let prevPt = profile[max(0, vi - 1)]
            let nextPt = profile[min(verticalSteps - 1, vi + 1)]
            let dr = nextPt.r - prevPt.r
            let dy = nextPt.y - prevPt.y
            let nLen = sqrt(dy * dy + dr * dr)
            let nrOutward = nLen > 0 ? dy / nLen : 1.0
            let nyOutward = nLen > 0 ? -dr / nLen : 0.0

            for ai in 0..<angularSteps {
                let angle = 2 * Float.pi * Float(ai) / Float(angularSteps)
                normals.append(SCNVector3(nrOutward * cos(angle), nyOutward, nrOutward * sin(angle)))
            }
        }

        for vi in 0..<(verticalSteps - 1) {
            for ai in 0..<angularSteps {
                let nextAi = (ai + 1) % angularSteps
                let base = UInt32(vi * angularSteps)
                let nextBase = UInt32((vi + 1) * angularSteps)
                let i0 = base + UInt32(ai)
                let i1 = base + UInt32(nextAi)
                let i2 = nextBase + UInt32(ai)
                let i3 = nextBase + UInt32(nextAi)
                indices.append(contentsOf: [i0, i2, i1])
                indices.append(contentsOf: [i1, i2, i3])
            }
        }

        // close the bottom opening so physics convex hull seals correctly
        let baseCenterIdx = UInt32(positions.count)
        positions.append(SCNVector3(0, profile[0].y, 0))
        normals.append(SCNVector3(0, -1, 0))
        texCoords.append(CGPoint(x: 0.5, y: 0.0))
        for ai in 0..<angularSteps {
            let nextAi = (ai + 1) % angularSteps
            indices.append(contentsOf: [baseCenterIdx, UInt32(nextAi), UInt32(ai)])
        }

        let posData = Data(bytes: positions, count: positions.count * MemoryLayout<SCNVector3>.size)
        let normData = Data(bytes: normals, count: normals.count * MemoryLayout<SCNVector3>.size)
        let texData = Data(bytes: texCoords.map { SIMD2<Float>(Float($0.x), Float($0.y)) },
                           count: texCoords.count * MemoryLayout<SIMD2<Float>>.size)
        let idxData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)

        let posSource = SCNGeometrySource(
            data: posData, semantic: .vertex,
            vectorCount: positions.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SCNVector3>.size
        )
        let normSource = SCNGeometrySource(
            data: normData, semantic: .normal,
            vectorCount: normals.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SCNVector3>.size
        )
        let texSource = SCNGeometrySource(
            data: texData, semantic: .texcoord,
            vectorCount: texCoords.count, usesFloatComponents: true,
            componentsPerVector: 2, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD2<Float>>.size
        )
        let element = SCNGeometryElement(
            data: idxData, primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        return SCNGeometry(sources: [posSource, normSource, texSource], elements: [element])
    }

    func ceramicMaterial() -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .phong
        // warm off-white glaze — classic Japanese ceramic tone
        mat.diffuse.contents = UIColor(red: 0.88, green: 0.84, blue: 0.78, alpha: 1)
        mat.specular.contents = UIColor(white: 0.55, alpha: 1)
        mat.shininess = 90
        mat.isDoubleSided = true
        mat.emission.contents = UIColor(red: 0.10, green: 0.08, blue: 0.06, alpha: 1)
        return mat
    }

    // Exposed inner clay face — darker, earthier, more matte than the outer glaze
    func ceramicInnerMaterial() -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .phong
        mat.diffuse.contents = UIColor(red: 0.68, green: 0.60, blue: 0.52, alpha: 1)
        mat.specular.contents = UIColor(white: 0.10, alpha: 1)
        mat.shininess = 15
        mat.isDoubleSided = true
        mat.emission.contents = UIColor(red: 0.09, green: 0.07, blue: 0.05, alpha: 1)
        return mat
    }

    // MARK: - Shatter

    func triggerShatter() {
        guard let scene, let vaseNode, !isShattered else { return }
        isShattered = true

        Task { @MainActor in
            await HapticsManager.shared.playShatter()
        }

        vaseNode.removeFromParentNode()
        fragmentNodes = buildFragments(scene: scene)

        // scatter immediately (0.1s so first frame with fragments renders before they move)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.applyShatterImpulses()
        }

        // use SCNAction for all subsequent stage timing — scene-clock based, not main queue
        let timerNode = SCNNode()
        scene.rootNode.addChildNode(timerNode)

        let sequenceActions = SCNAction.sequence([
            // fragments scatter over 0.9s, then float for 12s (wide window for CI screenshot)
            SCNAction.wait(duration: 12.0),
            // settle fragments back to origin so repair overlay has a vase to sit on
            SCNAction.customAction(duration: 0) { [weak self] _, _ in
                // must dispatch to main — fragmentNodes is @MainActor-isolated
                DispatchQueue.main.async {
                    guard let self else { return }
                    for node in self.fragmentNodes {
                        node.removeAllActions()
                        let settle = SCNAction.move(to: SCNVector3(0, 0, 0), duration: 2.0)
                        settle.timingMode = .easeInEaseOut
                        let resetRot = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 2.0)
                        resetRot.timingMode = .easeInEaseOut
                        node.runAction(SCNAction.group([settle, resetRot]))
                    }
                }
            },
            SCNAction.wait(duration: 3.0),  // settle completes (2s) + 1s buffer
            SCNAction.customAction(duration: 0) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.appModel?.stage = .repair
                    UIAccessibility.post(notification: .announcement, argument: "The vase has shattered. Trace each crack with gold to restore it.")
                }
            },
            SCNAction.removeFromParentNode()
        ])
        timerNode.runAction(sequenceActions)
    }

    // CI screenshot mode: irregular polygon shards via SCNShape — look like real broken ceramic.
    // Explicit world-space positions guarantee: center debris present, even radial spread,
    // mix of glaze (outer) and clay (inner) faces, no off-screen pieces, no center void.
    func setupShatterImmediately() {
        guard let scene, let vaseNode, !isShattered else { return }
        isShattered = true
        vaseNode.removeFromParentNode()

        // Camera at z=6, FOV=45° vertical → visible world: x ±2.5, y ±5.4
        // Each entry: (worldX, worldY, worldZ, tiltX°, tiltY°, tiltZ°, useInnerClay)
        // 3 center-debris pieces + 5 mid-range + 4 far-edge — no void, nothing off-screen
        typealias ShardPos = (x: Float, y: Float, z: Float, tx: Float, ty: Float, tz: Float, inner: Bool)
        let positions: [ShardPos] = [
            // --- 3 near-center debris (small, near origin) ---
            ( 0.30,  0.55,  0.10,  12, -18,   8, true),   // center-right
            (-0.40, -0.35, -0.10, -10,  20, -12, false),  // center-left
            ( 0.10, -0.60,  0.05,   8, -10,  15, true),   // just below center
            // --- 5 mid-range (fill the middle zone) ---
            (-1.30,  1.80, -0.15,  15,  25, -10, false),  // upper-left
            ( 1.40,  1.60,  0.10, -12, -20,   8, true),   // upper-right
            (-1.60, -0.20,  0.20,  18,  15,  12, false),  // left
            ( 1.50, -0.80, -0.10, -20, -15,  -8, true),   // right-lower
            ( 0.20, -2.20,  0.15,  10,  18, -15, false),  // lower-center
            // --- 4 far-edge (dramatic outer scatter) ---
            (-0.50,  3.50, -0.20, -15, -22,  10, true),   // top
            ( 1.80,  3.20,  0.10,  20,  15,  -8, false),  // top-right
            (-1.90, -2.80, -0.10,  -8,  20,  14, true),   // bottom-left
            ( 0.80, -3.80,  0.20,  12, -18,  -6, false),  // bottom
        ]

        // Shard shape templates paired 1:1 with positions above
        // (edges, radius, variance, extrusionDepth, scaleX, scaleY)
        let specs: [(Int, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            // center debris: small, irregular
            (4, 0.22, 0.08, 0.040, 0.9, 1.3),
            (5, 0.20, 0.07, 0.035, 1.1, 0.9),
            (4, 0.18, 0.06, 0.035, 0.7, 1.5),
            // mid-range: medium
            (5, 0.42, 0.14, 0.050, 1.0, 1.3),
            (6, 0.44, 0.16, 0.050, 1.2, 1.0),
            (5, 0.38, 0.13, 0.048, 0.9, 1.2),
            (4, 0.40, 0.14, 0.048, 1.1, 1.1),
            (5, 0.35, 0.12, 0.045, 1.0, 1.4),
            // far-edge: large belly chunks
            (5, 0.56, 0.20, 0.058, 1.0, 1.3),
            (6, 0.52, 0.18, 0.055, 1.2, 1.1),
            (5, 0.50, 0.17, 0.055, 0.9, 1.4),
            (4, 0.48, 0.16, 0.052, 1.1, 1.2),
        ]

        for i in 0..<positions.count {
            let pos = positions[i]
            let spec = specs[i]

            // Build irregular convex polygon path — unique rotation per shard
            let path = UIBezierPath()
            let angleOffset = CGFloat(i) * 0.65
            for e in 0..<spec.0 {
                let theta = angleOffset + CGFloat(e) * (2 * .pi / CGFloat(spec.0))
                let rVar = spec.2 * CGFloat(((i * 7 + e * 13) % 11) - 5) / 5.0
                let r = max(spec.1 * 0.5, spec.1 + rVar)
                let px = cos(theta) * r * spec.4
                let py = sin(theta) * r * spec.5
                if e == 0 { path.move(to: CGPoint(x: px, y: py)) }
                else { path.addLine(to: CGPoint(x: px, y: py)) }
            }
            path.close()

            let shape = SCNShape(path: path, extrusionDepth: spec.3)
            shape.materials = [pos.inner ? ceramicInnerMaterial() : ceramicMaterial()]

            let node = SCNNode(geometry: shape)
            node.position = SCNVector3(pos.x, pos.y, pos.z)
            let toRad = Float.pi / 180
            node.eulerAngles = SCNVector3(pos.tx * toRad, pos.ty * toRad, pos.tz * toRad)

            scene.rootNode.addChildNode(node)
            fragmentNodes.append(node)
        }
    }

    func buildFragments(scene: SCNScene) -> [SCNNode] {
        // 12 seeds: more fragments = more realistic ceramic shard appearance
        let seeds: [SIMD3<Float>] = generateSeeds(count: 12)
        let geometry = makeVaseGeometry()

        guard let posSource = geometry.sources(for: .vertex).first else { return [] }
        let positions = extractPositions(from: posSource)

        guard let element = geometry.elements.first else { return [] }
        let triIndices = extractIndices(from: element)

        var seedTriangles: [[Int]] = Array(repeating: [], count: seeds.count)
        let triCount = triIndices.count / 3
        for tri in 0..<triCount {
            let i0 = Int(triIndices[tri * 3])
            let i1 = Int(triIndices[tri * 3 + 1])
            let i2 = Int(triIndices[tri * 3 + 2])
            let centroid = (positions[i0] + positions[i1] + positions[i2]) / 3
            var nearestSeed = 0
            var minDist: Float = .infinity
            for (si, seed) in seeds.enumerated() {
                let d = simd_distance(centroid, seed)
                if d < minDist {
                    minDist = d
                    nearestSeed = si
                }
            }
            seedTriangles[nearestSeed].append(tri)
        }

        var result: [SCNNode] = []
        for (_, triList) in seedTriangles.enumerated() {
            guard !triList.isEmpty else { continue }

            var fragPositions: [SCNVector3] = []
            var fragNormals: [SCNVector3] = []
            var fragIndices: [UInt32] = []
            var indexMap: [Int: UInt32] = [:]

            let normSource = geometry.sources(for: .normal).first
            let normPositions = normSource.map { extractNormals(from: $0) } ?? []

            for tri in triList {
                for k in 0..<3 {
                    let origIdx = Int(triIndices[tri * 3 + k])
                    if let mapped = indexMap[origIdx] {
                        fragIndices.append(mapped)
                    } else {
                        let newIdx = UInt32(fragPositions.count)
                        indexMap[origIdx] = newIdx
                        let p = positions[origIdx]
                        fragPositions.append(SCNVector3(p.x, p.y, p.z))
                        if origIdx < normPositions.count {
                            let n = normPositions[origIdx]
                            fragNormals.append(SCNVector3(n.x, n.y, n.z))
                        } else {
                            fragNormals.append(SCNVector3(0, 1, 0))
                        }
                        fragIndices.append(newIdx)
                    }
                }
            }

            let fragGeom = buildGeometry(positions: fragPositions, normals: fragNormals, indices: fragIndices)
            fragGeom.materials = [ceramicMaterial()]

            let node = SCNNode(geometry: fragGeom)
            node.opacity = 1
            scene.rootNode.addChildNode(node)
            // no physics body — shatter uses SCNAction for guaranteed visual movement
            // physics impulses are unreliable in the iOS Simulator
            result.append(node)
        }

        return result
    }

    func applyShatterImpulses() {
        // SCNAction guarantees visual movement regardless of physics simulation quality in simulator
        // physics impulses are unreliable in the iOS Simulator; SCNAction.move is deterministic
        for node in fragmentNodes {
            let pos = node.position

            // purely radial outward from vase center — no upward bias so spread is uniform
            var dx = pos.x + Float.random(in: -0.15...0.15)
            var dy = pos.y + Float.random(in: -0.15...0.15)
            var dz = pos.z + Float.random(in: -0.05...0.05)
            let len = sqrt(dx*dx + dy*dy + dz*dz)
            if len > 0.001 { dx /= len; dy /= len; dz /= len }

            let dist = Float.random(in: 0.7...1.4)
            let target = SCNVector3(pos.x + dx*dist, pos.y + dy*dist, pos.z + dz*dist)

            let flyOut = SCNAction.move(to: target, duration: Double.random(in: 0.5...0.9))
            flyOut.timingMode = .easeOut

            // small rotation only — keeps fragment faces visible to camera
            let axis = SCNVector3(0, 0, 1)
            let angle = CGFloat.random(in: -.pi/5 ... .pi/5)
            let tumble = SCNAction.rotate(by: angle, around: axis, duration: Double.random(in: 0.5...0.9))
            tumble.timingMode = .easeOut

            node.runAction(SCNAction.group([flyOut, tumble]))

            // haptic stagger so each fragment sounds individual
            let delay = Double.random(in: 0.1...1.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { await HapticsManager.shared.playFragmentLand(intensity: Float.random(in: 0.3...0.6)) }
            }
        }
    }

    // MARK: - Reveal

    func triggerReveal() {
        guard !fragmentNodes.isEmpty else { return }

        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let duration: TimeInterval = reduceMotion ? 0.3 : 2.0

        // fragments were scattered by SCNAction so no physics type change needed
        for node in fragmentNodes {
            node.removeAllActions()
            let moveAction = SCNAction.move(to: SCNVector3(0, 0, 0), duration: duration)
            moveAction.timingMode = .easeInEaseOut
            let rotAction = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: duration)
            rotAction.timingMode = .easeInEaseOut
            node.runAction(SCNAction.group([moveAction, rotAction]))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
            self.appModel?.isRevealing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.fireRevealParticles()
                Task { await HapticsManager.shared.playRevealPeak() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                    self.appModel?.stage = .share
                    UIAccessibility.post(notification: .announcement, argument: "Your vase has been restored with gold, more beautiful than before.")
                }
            }
        }
    }

    func fireRevealParticles() {
        guard let scene else { return }

        let ps = SCNParticleSystem()
        // additive blend makes overlapping particles glow instead of occlude
        ps.blendMode = .additive
        ps.birthRate = 800
        ps.particleColor = UIColor(red: 0.831, green: 0.659, blue: 0.263, alpha: 1)
        ps.particleLifeSpan = 1.5
        ps.particleLifeSpanVariation = 0.5
        ps.emissionDuration = 2.0
        ps.spreadingAngle = 180
        ps.isAffectedByGravity = false
        ps.particleSize = 0.02
        ps.particleSizeVariation = 0.01

        // size keyframes make particles feel like gold sparks rather than uniform dots
        let sizeController = SCNParticlePropertyController()
        let animation = CAKeyframeAnimation()
        animation.values = [0.02, 0.04, 0.01]
        animation.keyTimes = [0, 0.3, 1.0]
        sizeController.animation = animation
        ps.propertyControllers = [SCNParticleSystem.ParticleProperty.size: sizeController]

        let emitterNode = SCNNode()
        emitterNode.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(emitterNode)
        emitterNode.addParticleSystem(ps)
    }

    func handleStageChange(_ stage: AppStage) {
        guard stage != currentStage else { return }
        currentStage = stage

        switch stage {
        case .reveal:
            triggerReveal()
        case .shatter, .repair, .share:
            break
        }
    }

    // MARK: - Geometry Helpers

    func generateSeeds(count: Int) -> [SIMD3<Float>] {
        var seeds: [SIMD3<Float>] = []
        let profile: [(r: Float, y: Float)] = [
            (0.28, -1.40), (0.50, -1.10), (0.62, -0.60),
            (0.58, 0.00), (0.45, 0.45), (0.28, 0.75),
            (0.18, 0.95), (0.14, 1.15)
        ]

        for i in 0..<count {
            let t = Float(i) / Float(count)
            let profileIdx = Int(t * Float(profile.count - 1))
            let pt = profile[min(profileIdx, profile.count - 1)]
            let angle = 2 * Float.pi * Float(i) / Float(count) + Float.random(in: -0.3...0.3)
            let r = pt.r * Float.random(in: 0.7...1.0)
            seeds.append(SIMD3<Float>(r * cos(angle), pt.y + Float.random(in: -0.2...0.2), r * sin(angle)))
        }
        return seeds
    }

    func extractPositions(from source: SCNGeometrySource) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        let stride = source.dataStride
        let offset = source.dataOffset
        let count = source.vectorCount
        source.data.withUnsafeBytes { ptr in
            for i in 0..<count {
                let base = offset + i * stride
                let x = ptr.load(fromByteOffset: base, as: Float.self)
                let y = ptr.load(fromByteOffset: base + 4, as: Float.self)
                let z = ptr.load(fromByteOffset: base + 8, as: Float.self)
                result.append(SIMD3<Float>(x, y, z))
            }
        }
        return result
    }

    // same memory layout as positions — just a typed alias
    func extractNormals(from source: SCNGeometrySource) -> [SIMD3<Float>] {
        extractPositions(from: source)
    }

    func extractIndices(from element: SCNGeometryElement) -> [UInt32] {
        var result: [UInt32] = []
        let count = element.primitiveCount * 3
        let bpi = element.bytesPerIndex
        element.data.withUnsafeBytes { ptr in
            for i in 0..<count {
                let base = i * bpi
                let idx: UInt32
                if bpi == 2 {
                    idx = UInt32(ptr.load(fromByteOffset: base, as: UInt16.self))
                } else {
                    idx = ptr.load(fromByteOffset: base, as: UInt32.self)
                }
                result.append(idx)
            }
        }
        return result
    }

    func buildGeometry(positions: [SCNVector3], normals: [SCNVector3], indices: [UInt32]) -> SCNGeometry {
        let posData = Data(bytes: positions, count: positions.count * MemoryLayout<SCNVector3>.size)
        let normData = Data(bytes: normals, count: normals.count * MemoryLayout<SCNVector3>.size)
        let idxData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)

        let posSource = SCNGeometrySource(
            data: posData, semantic: .vertex,
            vectorCount: positions.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4,
            dataOffset: 0, dataStride: MemoryLayout<SCNVector3>.size
        )
        let normSource = SCNGeometrySource(
            data: normData, semantic: .normal,
            vectorCount: normals.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: 4,
            dataOffset: 0, dataStride: MemoryLayout<SCNVector3>.size
        )
        let element = SCNGeometryElement(
            data: idxData, primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        return SCNGeometry(sources: [posSource, normSource], elements: [element])
    }
}

extension VaseSceneCoordinator: SCNSceneRendererDelegate {
    nonisolated func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {}
}
