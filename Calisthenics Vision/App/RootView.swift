//
//  RootView.swift
//  Calisthenics Vision
//
//  Tab shell. The tab bar is custom rather than a system `TabView` bar so it
//  matches the Figma spec and stays legible over the full-bleed camera
//  preview. On iOS 26 it's a floating Liquid Glass capsule; older systems get
//  the same shape in a material, so the layout never changes shape underneath
//  the screens that reserve room for it.
//
//  Four tabs at 74pt each is 312pt plus padding on a 402pt screen — it fits,
//  but a fifth would not without shrinking the items past a comfortable tap
//  target. Treat four as the ceiling.
//
//  The capture stack lives here, above the tab switch — see CaptureStack for
//  why owning it inside the Train screen crashed.
//

import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case train, history, feed, profile

    var title: String {
        switch self {
        case .train:   "Train"
        case .history: "History"
        case .feed:    "Feed"
        case .profile: "Profile"
        }
    }

    var symbolName: String {
        switch self {
        case .train:   "smallcircle.filled.circle"
        case .history: "clock"
        case .feed:    "person.2.fill"
        case .profile: "person.fill"
        }
    }
}

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab: AppTab = .train
    /// Built once for the life of the app, never per-screen.
    @State private var capture = CaptureStack()

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainInterface
            } else {
                // Onboarding finishes with a real set, so it needs the same
                // capture stack the Train tab uses.
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
                case .train:   TrainIdleView()
                case .history: HistoryView()
                case .feed:    SocialView()
                case .profile: ProfileView()
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
                let isActive = tab == selection

                VStack(spacing: 4) {
                    Image(systemName: tab.symbolName)
                        .font(.system(size: 19, weight: isActive ? .semibold : .regular))
                    Text(tab.title)
                        .font(isActive ? Theme.Font.tabLabelActive() : Theme.Font.tabLabel())
                }
                .foregroundStyle(isActive ? Theme.Color.primaryText : Theme.Color.secondaryText)
                .frame(width: 74, height: 50)
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
        }
        .padding(4)
        .tabBarSurface()
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
