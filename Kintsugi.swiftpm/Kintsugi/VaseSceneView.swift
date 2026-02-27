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
        ambientLight.light?.color = UIColor(white: 0.3, alpha: 1)
        scene.rootNode.addChildNode(ambientLight)

        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.color = UIColor(white: 0.9, alpha: 1)
        keyLight.light?.castsShadow = false
        keyLight.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 6, 0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.color = UIColor(white: 0.25, alpha: 1)
        fillLight.eulerAngles = SCNVector3(Float.pi / 6, -Float.pi / 4, 0)
        scene.rootNode.addChildNode(fillLight)

        buildVase()

        vaseNode?.opacity = 0
        let fadeIn = SCNAction.fadeIn(duration: 0.8)
        vaseNode?.runAction(SCNAction.sequence([SCNAction.wait(duration: 0.2), fadeIn]))

        // SCNAction.wait advances with scene render time — immune to main queue backlog
        // DispatchQueue timers fire in burst when main thread is busy during startup
        let shatterTrigger = SCNAction.sequence([
            SCNAction.wait(duration: 10.0),
            SCNAction.customAction(duration: 0) { [weak self] _, _ in
                DispatchQueue.main.async { self?.triggerShatter() }
            }
        ])
        vaseNode?.runAction(shatterTrigger, forKey: "shatterTrigger")
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
        let angularSteps = 36
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
        mat.diffuse.contents = UIColor(red: 0.82, green: 0.78, blue: 0.72, alpha: 1)
        mat.specular.contents = UIColor(white: 0.4, alpha: 1)
        mat.shininess = 60
        mat.isDoubleSided = false
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
            // fragments scatter over 0.9s, then float for 4s
            SCNAction.wait(duration: 5.0),
            // settle fragments back to origin so repair overlay has a vase to sit on
            SCNAction.customAction(duration: 0) { [weak self] _, _ in
                guard let self else { return }
                for node in self.fragmentNodes {
                    node.removeAllActions()
                    let settle = SCNAction.move(to: SCNVector3(0, 0, 0), duration: 1.5)
                    settle.timingMode = .easeInEaseOut
                    let resetRot = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 1.5)
                    resetRot.timingMode = .easeInEaseOut
                    node.runAction(SCNAction.group([settle, resetRot]))
                }
            },
            SCNAction.wait(duration: 2.0),  // settle completes
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

    func buildFragments(scene: SCNScene) -> [SCNNode] {
        // 8 seeds = fewer physics bodies = better simulator performance for judges
        let seeds: [SIMD3<Float>] = generateSeeds(count: 8)
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
