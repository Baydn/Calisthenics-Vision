//
//  Theme.swift
//  Calisthenics Vision
//
//  Design tokens extracted from the Figma frames. Everything visual should
//  pull from here so the screens stay consistent — don't hardcode colors
//  or sizes in views.
//

import SwiftUI

enum Theme {

    // MARK: - Color

    enum Color {
        /// Screen background.
        static let background = SwiftUI.Color.black
        /// Cards, segmented-control track, row icon circles.
        static let card = SwiftUI.Color(red: 0.110, green: 0.110, blue: 0.118)   // #1C1C1E
        /// Slightly lifted surface, e.g. the lock badge on the Progress chart.
        static let elevated = SwiftUI.Color(red: 0.170, green: 0.170, blue: 0.180)

        static let primaryText = SwiftUI.Color.white
        /// Inactive labels, secondary copy, uppercase card labels.
        static let secondaryText = SwiftUI.Color(red: 0.557, green: 0.557, blue: 0.576) // #8E8E93
        /// Section headers such as "TODAY".
        static let tertiaryText = SwiftUI.Color(red: 0.357, green: 0.357, blue: 0.365)  // #5B5B5D

        /// Tab bar top divider.
        static let divider = SwiftUI.Color(red: 0.227, green: 0.227, blue: 0.235)       // #3A3A3C
        /// Hairline between rows inside a group.
        static let rowSeparator = card

        // Accents. Reserved for the live pose overlay and activity indicators —
        // keep the rest of the app chrome monochrome.
        /// Marks design previews — screens that exist to show the shape of a
        /// planned feature but aren't wired up. Deliberately outside the
        /// app's green/red vocabulary so it never reads as app state.
        static let previewAccent = SwiftUI.Color(red: 1.0, green: 0.69, blue: 0.13)

        static let valid = SwiftUI.Color(red: 0, green: 1, blue: 0.4)                   // #00FF66
        static let warning = SwiftUI.Color(red: 1, green: 0.2, blue: 0.4)               // #FF3366
        /// The middle of a graded measurement — a joint that's neither in the
        /// range you're aiming for nor far enough out to call a fault. Only
        /// for zones on an angle chart, where a three-step scale is the whole
        /// point; it is not a third app-state colour.
        static let caution = SwiftUI.Color(red: 1, green: 0.79, blue: 0.24)             // #FFCA3D
    }

    // MARK: - Typography

    /// The Figma file uses Inter. Until the Inter .ttf files are bundled and
    /// registered in Info.plist, we fall back to the system face, which keeps
    /// the same weights and optical sizes.
    enum Font {
        static func header() -> SwiftUI.Font { .system(size: 28, weight: .bold) }
        static func cardNumber() -> SwiftUI.Font { .system(size: 22, weight: .bold) }
        static func title() -> SwiftUI.Font { .system(size: 17, weight: .semibold) }
        static func body() -> SwiftUI.Font { .system(size: 15, weight: .medium) }
        static func control() -> SwiftUI.Font { .system(size: 13, weight: .medium) }
        static func controlActive() -> SwiftUI.Font { .system(size: 13, weight: .bold) }
        static func sectionHeader() -> SwiftUI.Font { .system(size: 11, weight: .medium) }
        static func cardLabel() -> SwiftUI.Font { .system(size: 9, weight: .medium) }
        static func tabLabel() -> SwiftUI.Font { .system(size: 10, weight: .medium) }
        static func tabLabelActive() -> SwiftUI.Font { .system(size: 10, weight: .bold) }
        /// Glanceable rep counts / hold timers on the live HUD (readable 6–10 ft away).
        static func hudCounter() -> SwiftUI.Font { .system(size: 96, weight: .bold, design: .rounded) }
    }

    // MARK: - Motion

    /// Shared animation curves, so movement feels like one app rather than
    /// like a dozen views each guessing. Reach for these instead of writing
    /// `.snappy(duration:)` inline — anything that changes position or
    /// selection should slide, never pop.
    enum Motion {
        /// Selection sliding between positions — tab bar, zoom pill, chips.
        static var selection: Animation {
            .spring(response: 0.32, dampingFraction: 0.78)
        }
        /// A control expanding or collapsing in place.
        static var expand: Animation {
            .spring(response: 0.34, dampingFraction: 0.82)
        }
        /// Content appearing or changing value.
        static var content: Animation { .snappy(duration: 0.22) }
    }

    // MARK: - Metrics

    enum Metric {
        static let screenPadding: CGFloat = 32
        static let cardRadius: CGFloat = 12
        static let cardHeight: CGFloat = 66
        static let segmentedHeight: CGFloat = 36
        static let rowIconSize: CGFloat = 28
        /// The floating tab bar's own height.
        static let tabBarHeight: CGFloat = 58
        /// What a screen should reserve at the bottom so its content clears
        /// the floating bar — the bar plus the gap beneath it. Screens that
        /// deliberately run underneath the glass (the camera preview) ignore
        /// this for their background and use it only for controls.
        /// The bar now sits inside the home-indicator inset, so screens have
        /// to clear the indicator as well as the bar itself.
        static let tabBarClearance: CGFloat = 100
        static let labelTracking: CGFloat = 0.5
    }
}

extension View {
    /// Uppercase label styling used on stat cards and section headers.
    func cardLabelStyle() -> some View {
        self.font(Theme.Font.cardLabel())
            .tracking(Theme.Metric.labelTracking)
            .foregroundStyle(Theme.Color.secondaryText)
    }

    func sectionHeaderStyle() -> some View {
        self.font(Theme.Font.sectionHeader())
            .tracking(Theme.Metric.labelTracking)
            .foregroundStyle(Theme.Color.tertiaryText)
    }
}
