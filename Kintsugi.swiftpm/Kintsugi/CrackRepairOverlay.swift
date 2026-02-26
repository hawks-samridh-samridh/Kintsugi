import SwiftUI

struct CrackPath {
    let id: Int
    // normalized so crack positions scale to any screen size
    let points: [CGPoint]
}

let crackPaths: [CrackPath] = [
    CrackPath(id: 0, points: [  // lower-left
        CGPoint(x: 0.35, y: 0.70),
        CGPoint(x: 0.38, y: 0.64),
        CGPoint(x: 0.34, y: 0.58),
        CGPoint(x: 0.36, y: 0.52),
        CGPoint(x: 0.33, y: 0.48),
    ]),
    CrackPath(id: 1, points: [  // lower-right
        CGPoint(x: 0.62, y: 0.72),
        CGPoint(x: 0.65, y: 0.65),
        CGPoint(x: 0.63, y: 0.59),
        CGPoint(x: 0.67, y: 0.53),
        CGPoint(x: 0.64, y: 0.47),
    ]),
    CrackPath(id: 2, points: [  // center belly
        CGPoint(x: 0.50, y: 0.68),
        CGPoint(x: 0.48, y: 0.62),
        CGPoint(x: 0.52, y: 0.56),
        CGPoint(x: 0.49, y: 0.50),
    ]),
    CrackPath(id: 3, points: [  // upper shoulder left
        CGPoint(x: 0.38, y: 0.42),
        CGPoint(x: 0.40, y: 0.36),
        CGPoint(x: 0.37, y: 0.30),
        CGPoint(x: 0.41, y: 0.25),
    ]),
    CrackPath(id: 4, points: [  // upper shoulder right
        CGPoint(x: 0.60, y: 0.42),
        CGPoint(x: 0.62, y: 0.36),
        CGPoint(x: 0.59, y: 0.30),
        CGPoint(x: 0.63, y: 0.25),
    ]),
    CrackPath(id: 5, points: [  // neck
        CGPoint(x: 0.50, y: 0.26),
        CGPoint(x: 0.48, y: 0.21),
        CGPoint(x: 0.51, y: 0.16),
        CGPoint(x: 0.49, y: 0.12),
    ]),
]

struct CrackRepairOverlay: View {
    @Environment(AppModel.self) private var appModel
    @State private var crackProgress: [Int: Double] = [:]
    @State private var quoteOpacity: [Int: Double] = [:]
    @State private var overlayOpacity: Double = 0
    @State private var glowingCrack: Int? = nil
    @State private var revealGlowPulse: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { ctx, size in
                    drawCracks(ctx: ctx, size: size)
                }
                .opacity(overlayOpacity)

                VStack {
                    Spacer()
                    quotesPanel
                        .padding(.bottom, 40)
                        .padding(.horizontal, 24)
                }

                if appModel.stage == .repair && appModel.repairedCracks.count == 0 {
                    VStack {
                        Spacer().frame(height: 60)
                        Text("Trace each crack with gold")
                            .font(.system(.subheadline, design: .default, weight: .thin))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(size: geo.size))
        }
        .onAppear {
            if appModel.stage == .repair {
                withAnimation(.easeIn(duration: 0.8)) {
                    overlayOpacity = 1.0
                }
            } else if appModel.stage == .reveal {
                overlayOpacity = 1.0
            }
        }
        .onChange(of: appModel.stage) { _, newStage in
            if newStage == .repair {
                withAnimation(.easeIn(duration: 0.8)) {
                    overlayOpacity = 1.0
                }
            } else if newStage == .reveal {
                // overlay persists — the user's own marks become the seams
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    revealGlowPulse = true
                }
            }
        }
        .onChange(of: appModel.isRevealing) { _, isRevealing in
            if isRevealing {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    revealGlowPulse = true
                }
            }
        }
    }

    func drawCracks(ctx: GraphicsContext, size: CGSize) {
        for crack in crackPaths {
            let pts = crack.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            guard pts.count >= 2 else { continue }

            let progress = crackProgress[crack.id] ?? 0.0
            let isRepaired = appModel.repairedCracks.contains(crack.id)
            let isGlowing = glowingCrack == crack.id

            var path = Path()
            path.move(to: pts[0])
            for i in 1..<pts.count {
                path.addLine(to: pts[i])
            }

            // faint guide so users know where to trace without making it trivial
            if !isRepaired {
                ctx.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: 1.5)
            }

            // proximity affordance pulls the finger onto the crack
            if isGlowing && !isRepaired {
                ctx.stroke(path, with: .color(Color(red: 0.831, green: 0.659, blue: 0.263).opacity(0.25)), lineWidth: 12)
            }

            if progress > 0 || isRepaired {
                let fillProgress = isRepaired ? 1.0 : progress
                let goldPath = subpath(pts: pts, progress: fillProgress)
                let goldColor: Color = appModel.isColorblindMode ? .white : Color(red: 0.831, green: 0.659, blue: 0.263)

                if appModel.isRevealing || appModel.stage == .reveal {
                    // animate glow in reveal so the user's marks feel like they're coming alive
                    let glowWidth: CGFloat = revealGlowPulse ? 14 : 8
                    let glowOpacity: Double = revealGlowPulse ? 1.0 : 0.7
                    ctx.stroke(goldPath, with: .color(goldColor.opacity(glowOpacity * 0.4)), lineWidth: glowWidth)
                    ctx.stroke(goldPath, with: .color(goldColor.opacity(glowOpacity)), lineWidth: 3.0)
                } else {
                    ctx.stroke(goldPath, with: .color(goldColor.opacity(0.4)), lineWidth: 8)
                    ctx.stroke(goldPath, with: .color(goldColor), lineWidth: 2.5)
                }
            }
        }
    }

    func subpath(pts: [CGPoint], progress: Double) -> Path {
        guard pts.count >= 2 else { return Path() }

        var segLengths: [CGFloat] = []
        var totalLen: CGFloat = 0
        for i in 1..<pts.count {
            let d = hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y)
            segLengths.append(d)
            totalLen += d
        }

        let targetLen = totalLen * CGFloat(progress)
        var path = Path()
        path.move(to: pts[0])
        var accum: CGFloat = 0
        for i in 1..<pts.count {
            let seg = segLengths[i - 1]
            if accum + seg >= targetLen {
                let t = (targetLen - accum) / seg
                let end = CGPoint(
                    x: pts[i-1].x + t * (pts[i].x - pts[i-1].x),
                    y: pts[i-1].y + t * (pts[i].y - pts[i-1].y)
                )
                path.addLine(to: end)
                break
            }
            path.addLine(to: pts[i])
            accum += seg
        }
        return path
    }

    func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard appModel.stage == .repair else { return }
                updateTracing(at: value.location, size: size, velocity: value.velocity)
            }
            .onEnded { _ in
                glowingCrack = nil
            }
    }

    func updateTracing(at location: CGPoint, size: CGSize, velocity: CGSize) {
        let tolerance: CGFloat = 20
        let guideRadius: CGFloat = 35

        for crack in crackPaths {
            guard !appModel.repairedCracks.contains(crack.id) else { continue }

            let pts = crack.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            let densePts = densify(pts: pts, count: 50)

            var nearestIdx = 0
            var nearestDist: CGFloat = .infinity
            for (i, pt) in densePts.enumerated() {
                let d = hypot(location.x - pt.x, location.y - pt.y)
                if d < nearestDist {
                    nearestDist = d
                    nearestIdx = i
                }
            }

            if nearestDist < guideRadius {
                glowingCrack = crack.id
            }

            if nearestDist < tolerance {
                // forward-only so users can't accidentally unpaint a crack
                let newProgress = Double(nearestIdx + 1) / Double(densePts.count)
                let current = crackProgress[crack.id] ?? 0.0
                if newProgress > current {
                    crackProgress[crack.id] = newProgress

                    let speed = sqrt(velocity.width * velocity.width + velocity.height * velocity.height)
                    let intensity = Float(min(max(speed / 500.0, 0.2), 0.6))
                    Task { @MainActor in
                        await HapticsManager.shared.playTracing(velocity: intensity)
                    }
                }

                if newProgress >= 0.95 && !appModel.repairedCracks.contains(crack.id) {
                    crackProgress[crack.id] = 1.0
                    appModel.repairedCracks.insert(crack.id)
                    glowingCrack = nil

                    withAnimation(.easeIn(duration: 0.8)) {
                        quoteOpacity[crack.id] = 1.0
                    }

                    Task { @MainActor in
                        await HapticsManager.shared.playCrackComplete()
                    }

                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "Crack \(crack.id + 1) repaired. \(crackReflections[crack.id].quote)"
                    )

                    if appModel.allCracksRepaired {
                        Task { @MainActor in
                            await HapticsManager.shared.playAllRepaired()
                            try? await Task.sleep(for: .milliseconds(500))
                            appModel.stage = .reveal
                        }
                    }
                }
            }
        }
    }

    func densify(pts: [CGPoint], count: Int) -> [CGPoint] {
        guard pts.count >= 2 else { return pts }
        var totalLen: CGFloat = 0
        for i in 1..<pts.count {
            totalLen += hypot(pts[i].x - pts[i-1].x, pts[i].y - pts[i-1].y)
        }

        var result: [CGPoint] = []
        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(count - 1) * totalLen
            var accum: CGFloat = 0
            for j in 1..<pts.count {
                let seg = hypot(pts[j].x - pts[j-1].x, pts[j].y - pts[j-1].y)
                if accum + seg >= t || j == pts.count - 1 {
                    let frac = seg > 0 ? (t - accum) / seg : 0
                    result.append(CGPoint(
                        x: pts[j-1].x + frac * (pts[j].x - pts[j-1].x),
                        y: pts[j-1].y + frac * (pts[j].y - pts[j-1].y)
                    ))
                    break
                }
                accum += seg
            }
        }
        return result
    }

    var quotesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(crackReflections) { reflection in
                if appModel.repairedCracks.contains(reflection.id) {
                    Text(reflection.quote)
                        .font(.system(.caption, design: .default, weight: .thin))
                        .foregroundStyle(appModel.goldColor.opacity(quoteOpacity[reflection.id] ?? 0))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Reflection: \(reflection.quote)")
                        .transition(.opacity)
                }
            }
        }
    }
}
