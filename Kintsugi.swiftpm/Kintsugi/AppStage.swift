import SwiftUI
import Observation

enum AppStage {
    case shatter
    case repair
    case reveal
    case share
}

@Observable
@MainActor
final class AppModel {
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
