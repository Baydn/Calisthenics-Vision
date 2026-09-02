//
//  RootView.swift
//  Calisthenics Vision
//
//  Tab shell. The tab bar is custom rather than a system `TabView` bar so it
//  matches the Figma spec exactly (88pt tall, hairline divider, bold active
//  label) and stays legible over the full-bleed camera preview.
//

import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case train, history, profile

    var title: String {
        switch self {
        case .train:   "Train"
        case .history: "History"
        case .profile: "Profile"
        }
    }

    var symbolName: String {
        switch self {
        case .train:   "smallcircle.filled.circle"
        case .history: "clock"
        case .profile: "person.fill"
        }
    }
}

struct RootView: View {
    @State private var selectedTab: AppTab = .train

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.Color.background.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .train:   TrainIdleView()
                case .history: HistoryView()
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            AppTabBar(selection: $selectedTab)
        }
        .preferredColorScheme(.dark)
    }
}

struct AppTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Color.divider)
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    let isActive = tab == selection

                    VStack(spacing: 6) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 20, weight: isActive ? .semibold : .regular))
                        Text(tab.title)
                            .font(isActive ? Theme.Font.tabLabelActive() : Theme.Font.tabLabel())
                    }
                    .foregroundStyle(isActive ? Theme.Color.primaryText : Theme.Color.secondaryText)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    .onTapGesture { selection = tab }
                }
            }
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .frame(height: Theme.Metric.tabBarHeight)
        .background(Theme.Color.background)
    }
}

#Preview {
    RootView()
}
