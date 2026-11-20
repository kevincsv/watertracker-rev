import SwiftUI
import UIKit

/// The "Noche deportiva" look: a dark, blue-black background, a bright cyan
/// accent and condensed numbers. The app always runs in dark mode.
enum Theme {
    /// #0A0F13, behind every list and form.
    static let background = Color(red: 0.039, green: 0.059, blue: 0.075)
    /// #3FD0E8, the same colour as the AccentColor asset.
    static let accent = Color(red: 0.247, green: 0.816, blue: 0.910)
    /// #3DDC84, goal reached.
    static let good = Color(red: 0.239, green: 0.863, blue: 0.518)
    /// #FFB020, first place in the ranking.
    static let gold = Color(red: 1.0, green: 0.690, blue: 0.125)
    /// #FF8A3D, calories.
    static let food = Color(red: 1.0, green: 0.541, blue: 0.239)

    /// Big condensed numbers, for totals and the water gauge.
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold).width(.condensed)
    }

    /// Condensed navigation titles and an accent-coloured segmented control.
    @MainActor static func applyAppearance() {
        let navigationBar = UINavigationBar.appearance()
        navigationBar.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 38, weight: .heavy, width: .condensed)
        ]
        navigationBar.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold, width: .condensed)
        ]

        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = UIColor(accent)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
    }
}

extension View {
    /// Shows the theme's background behind a List or Form instead of the
    /// system's grouped background.
    func themedBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}
