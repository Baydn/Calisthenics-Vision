//
//  RootView.swift
//  Calisthenics Vision
//
//  Tab shell — Home, Record, You.
//
//  Shaped after Strava, which consolidated its old Profile and Training tabs
//  into a single "You" for exactly the reason we need it: everything about
//  *your* training belongs in one place, which leaves the bar room to grow.
//  Recording sits in the centre and is drawn as a button rather than an icon,
//  because it's the one thing you open the app to do.
//
//  Strava runs five (Home, Maps, Record, Groups, You). Three is the right
//  starting point here — a tab for a feature that doesn't exist yet is worse
//  than a gap — and the bar is built so a fourth and fifth can slot either
//  side of Record when there's something real to put in them.
//
//  The bar is custom rather than a system `TabView` so it stays legible over
//  the full-bleed camera preview. On iOS 26 it's a floating Liquid Glass
//  capsule; older systems get the same shape in a material, so the layout
//  never changes shape underneath the screens that reserve room for it.
//
//  The capture stack lives here, above the tab switch — see CaptureStack for
//  why owning it inside the Record screen crashed.
//

import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case home, record, you

    var title: String {
        switch self {
        case .home:   "Home"
        case .record: "Record"
        case .you:    "You"
        }
    }

    var symbolName: String {
        switch self {
        case .home:   "house.fill"
        case .record: "camera.fill"
        case .you:    "person.fill"
        }
    }

    /// The centre tab is drawn as a button, not an icon in a row.
    var isPrimary: Bool { self == .record }
}

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab: AppTab = .record
    /// Built once for the life of the app, never per-screen.
    @State private var capture = CaptureStack()

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainInterface
            } else {
                // Onboarding finishes with a real set, so it needs the same
                // capture stack the Record tab uses.
                OnboardingView()
            }
        }
        .environment(capture)
    }

    private var mainInterface: some View {
        ZStack(alignment: .bottom) {
            Theme.Color.background.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .home:   HomeView()
                case .record: TrainIdleView()
                case .you:    YouView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            AppTabBar(selection: $selectedTab)
                .padding(.bottom, 6)
        }
        .preferredColorScheme(.dark)
    }
}

struct AppTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                if tab.isPrimary {
                    recordButton(tab)
                } else {
                    item(tab)
                }
            }
        }
        .padding(4)
        .tabBarSurface()
    }

    private func item(_ tab: AppTab) -> some View {
        let isActive = tab == selection
        return VStack(spacing: 4) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 19, weight: isActive ? .semibold : .regular))
            Text(tab.title)
                .font(isActive ? Theme.Font.tabLabelActive() : Theme.Font.tabLabel())
        }
        .foregroundStyle(isActive ? Theme.Color.primaryText : Theme.Color.secondaryText)
        .frame(width: 92, height: 50)
        .background {
            if isActive {
                Capsule()
                    .fill(Theme.Color.primaryText.opacity(0.14))
                    .matchedGeometryEffect(id: "tabPill", in: pill)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(Theme.Motion.selection) { selection = tab }
        }
    }

    /// Borrowed from the shutter on the Record screen, so the two read as the
    /// same action at two scales.
    private func recordButton(_ tab: AppTab) -> some View {
        let isActive = tab == selection
        return ZStack {
            Circle()
                .strokeBorder(Theme.Color.primaryText, lineWidth: isActive ? 3 : 2)
                .frame(width: 46, height: 46)
                .opacity(isActive ? 1 : 0.75)
            Circle()
                .fill(Theme.Color.primaryText)
                .frame(width: isActive ? 34 : 30, height: isActive ? 34 : 30)
                .opacity(isActive ? 1 : 0.75)
        }
        .frame(width: 64, height: 50)
        .contentShape(.rect)
        .accessibilityLabel(tab.title)
        .onTapGesture {
            withAnimation(Theme.Motion.selection) { selection = tab }
        }
    }
}

private extension View {
    /// Liquid Glass where the system has it, a material capsule where it
    /// doesn't. Same size and shape either way, so nothing else has to care.
    @ViewBuilder
    func tabBarSurface() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: .capsule)
                .overlay {
                    Capsule().strokeBorder(Theme.Color.divider.opacity(0.6), lineWidth: 1)
                }
        }
    }
}

#Preview {
    RootView()
        .environment(Entitlements())
        .modelContainer(SampleSessions.previewContainer)
}
