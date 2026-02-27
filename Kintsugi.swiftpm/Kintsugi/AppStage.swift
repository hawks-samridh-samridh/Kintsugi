import SwiftUI
import Observation

enum AppStage {
    case shatter
    case repair
    case reveal
    case share
}

enum ScreenshotMode {
    case intact   // CI: show intact vase, no shatter timer
    case shatter  // CI: show scattered fragments immediately
    case repair   // CI: show reassembled vase + crack overlay
}

@Observable
@MainActor
final class AppModel {
    // Non-nil only in CI screenshot builds; normal experience is unaffected
    var screenshotMode: ScreenshotMode? = {
        let args = CommandLine.arguments
        if args.contains("-screenshot_intact") { return .intact }
        if args.contains("-screenshot_shatter") { return .shatter }
        if args.contains("-screenshot_repair") { return .repair }
        return nil
    }()

    var stage: AppStage = .shatter
    var repairedCracks: Set<Int> = []
    var isRevealing: Bool = false
    var userColorblindOverride: Bool = false

    var isColorblindMode: Bool {
        UIAccessibility.isDarkerSystemColorsEnabled ||
        UIAccessibility.shouldDifferentiateWithoutColor ||
        userColorblindOverride
    }

    var goldColor: Color {
        isColorblindMode ? .white : Color(red: 0.831, green: 0.659, blue: 0.263)
    }

    var allCracksRepaired: Bool {
        repairedCracks.count >= 6
    }
}
