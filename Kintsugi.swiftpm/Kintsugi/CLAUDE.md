# Kintsugi — Build Notes

## Project
Swift Student Challenge 2026 submission. A 3-minute interactive emotional experience about resilience, using the Japanese art of kintsugi (金継ぎ) as metaphor.

## Format
`.swiftpm` App Playground — required format. iOS 18+. No third-party packages. No network calls. No external assets (all geometry/particles generated in code).

## Build
Open `Kintsugi.swiftpm` in Xcode 16+ or Swift Playgrounds 4.6+.
Run on iPhone 16 Pro Simulator (iOS 18).

## Architecture
- `AppModel` — @Observable, @MainActor. Source of truth for stage, repairedCracks, colorblind mode.
- `VaseSceneView` — UIViewRepresentable wrapping SCNView. Procedural surface-of-revolution vase geometry (surface of revolution, 12 profile points × 36 angular steps). Voronoi-style fragment generation (12 fragments).
- `CrackRepairOverlay` — SwiftUI Canvas drawn over SCNView. 6 CGPath cracks in normalized coordinates. DragGesture proximity-based tracing (20pt tolerance). Forward-only progress. Gold trail drawn to progress point.
- `HapticsManager` — actor, CHHapticEngine. No-ops gracefully on simulator.
- `ShareView` — SCNView snapshot for ShareLink. Colorblind toggle.

## Key Design Decision
The 2D gold overlay persists through Stage 3 (Reveal). The vase reassembles beneath the overlay; the user's own gold marks remain visible. SCNParticleSystem burst fires through the overlay in 3D. This is more emotionally honest to the kintsugi metaphor.

## Concurrency
- `@preconcurrency import SceneKit` to suppress Sendable warnings
- `HapticsManager` is an `actor`, always `await`ed from `Task {}` blocks
- `Coordinator` is `@MainActor`; renderer delegate is `nonisolated`

## Accessibility
- All elements have `accessibilityLabel`, `accessibilityHint`, `accessibilityValue`
- `UIAccessibility.post(notification: .announcement)` at each stage transition
- Colorblind mode: gold → white (manual toggle + auto-detected from UIAccessibility)
- Reduce Motion: skip/shorten animations, snap instead of animate
- Dynamic Type: zero hardcoded font sizes

## Timing
- 00:00 App launch → vase fade-in (0.8s)
- 00:01 Shatter triggers, fragments settle (~3s)
- 00:04 Repair stage begins (user-paced, ~90s budget)
- ~01:34 All cracks repaired → Reveal (2s reassembly + particles)
- ~01:44 Share stage

## AI Disclosure
This project was built with AI assistance. See Credits.txt.
