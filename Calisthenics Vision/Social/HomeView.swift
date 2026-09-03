//
//  HomeView.swift
//  Calisthenics Vision
//
//  The Home tab: what everyone else is doing — design preview.
//
//  Nothing here is connected to anything. There is no account system, no
//  backend and no other users; every name and number below is invented, and
//  the screen says so at the top rather than letting invented figures pass as
//  real. It exists to settle two questions before any of it gets built: what
//  a feed entry should carry, and whether a measured leaderboard is a claim
//  worth defending.
//
//  The order this ships in matters. Sharing a clip needs no account at all
//  and comes first; this comes after, and only if people actually share.
//

import SwiftData
import SwiftUI

struct HomeView: View {

    enum Tab: String, CaseIterable, Hashable {
        case feed = "Following"
        case board = "Leaderboard"
    }

    @State private var tab: Tab = .feed
    @State private var showProfile = false
    @State private var showSearch = false
    @State private var showNotifications = false
    @State private var showMessages = false
    @State private var showComments = false
    @State private var showShare = false

    @Query(sort: \Post.createdAt, order: .reverse) private var posts: [Post]
    @Query private var sessions: [WorkoutSession]
    @State private var movement: Movement = .handstand
    @State private var scope = "Global"

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                // Avatar and search on the left, notifications and messages on
                // the right — the arrangement every feed converges on, because
                // it puts identity and finding people at the thumb end and
                // keeps the incoming stuff out of the way of the scroll.
                HStack(spacing: 10) {
                    Button { showProfile = true } label: {
                        Circle()
                            .fill(Theme.Color.card)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Theme.Color.secondaryText)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Profile")

                    Button { showSearch = true } label: {
                        headerButton("magnifyingglass", label: "Search")
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button { showNotifications = true } label: {
                        headerButton("bell.fill", label: "Notifications", badge: 3)
                    }
                    .buttonStyle(.plain)

                    Button { showMessages = true } label: {
                        headerButton("bubble.left.fill", label: "Messages")
                    }
                    .buttonStyle(.plain)
                }

                PreviewNotice(
                    "No accounts exist yet, so everyone here is invented, and search and messages don't open. This is for deciding what a feed entry should carry."
                )

                SegmentedControl(segments: Tab.allCases, title: \.rawValue, selection: $tab)
            }
            .padding(.horizontal, Theme.Metric.screenPadding)
            .padding(.top, 8)

            ScrollView {
                Group {
                    switch tab {
                    case .feed:  feed
                    case .board: leaderboard
                    }
                }
                .padding(.horizontal, Theme.Metric.screenPadding)
                .padding(.top, 22)
                .padding(.bottom, Theme.Metric.tabBarClearance + 24)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Color.background)
        .navigationDestination(isPresented: $showProfile) { ProfileView() }
        }
        .sheet(isPresented: $showSearch) { PeopleSearchView() }
        .sheet(isPresented: $showNotifications) { NotificationsView() }
        .sheet(isPresented: $showMessages) { MessagesView() }
        .sheet(isPresented: $showComments) { CommentsView() }
        .sheet(isPresented: $showShare) { SharePostView() }
    }

    private func headerButton(_ symbol: String, label: String, badge: Int = 0) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.Color.secondaryText)
            .frame(width: 36, height: 36)
            .background(Theme.Color.card, in: .circle)
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Color.background)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Theme.Color.warning, in: .circle)
                        .offset(x: 3, y: -3)
                }
            }
            .accessibilityLabel(label)
    }

    // MARK: - Feed

    private var feed: some View {
        VStack(spacing: 14) {
            // Yours first — they're the only real ones.
            ForEach(posts) { post in
                PostCard(post: post, sessions: sessions)
            }

            if !posts.isEmpty {
                Text("EVERYTHING BELOW IS INVENTED")
                    .sectionHeaderStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }

            PostCard(
                author: "mila.calis",
                example: .init(
                    title: "Front Lever", when: "22 min ago",
                    caption: "Straddle held for the first time. Hips finally stopped dropping.",
                    headline: "0:09.20", subhead: "straddle · 74% line",
                    hasClip: true, likeCount: 14, commentCount: 3
                ),
                onComment: { showComments = true },
                onShare: { showShare = true }
            )
            PostCard(
                author: "jonas_b",
                example: .init(
                    title: "Pull day", when: "1 h ago",
                    headline: "19 reps", subhead: "3 movements · personal best",
                    likeCount: 8, commentCount: 1
                ),
                onComment: { showComments = true },
                onShare: { showShare = true }
            )
            PostCard(
                author: "rina.hs",
                example: .init(
                    title: "Handstand", when: "3 h ago",
                    headline: "1:12.60", subhead: "4 holds · 88% line",
                    hasClip: true, likeCount: 31, commentCount: 6
                ),
                onComment: { showComments = true },
                onShare: { showShare = true }
            )
        }
    }

    // MARK: - Leaderboard

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach([Movement.handstand, .pullUps, .pushUps], id: \.self) { option in
                        FilterChip(title: option.displayName, isActive: option == movement) {
                            withAnimation(Theme.Motion.selection) { movement = option }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, 12)

            SegmentedControl(segments: ["Friends", "Global"], title: \.self, selection: $scope)
                .padding(.bottom, 22)

            VStack(spacing: 0) {
                standing(1, "rina.hs", "R", "2:41", isYou: false)
                separator
                standing(2, "dmitri_v", "D", "1:58", isYou: false)
                separator
                standing(3, "mila.calis", "M", "1:33", isYou: false)
                separator
                standing(47, "You", "B", "0:24", isYou: true)
            }

            PreviewNotice(
                "Every entry would be measured on-device — but filming a screen would still fool it. Decide what \"verified\" promises before shipping the word."
            )
            .padding(.top, 22)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.Color.rowSeparator)
            .frame(height: 1)
            .padding(.leading, 34)
    }

    private func standing(_ rank: Int, _ handle: String, _ initial: String,
                          _ value: String, isYou: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(isYou ? Theme.Color.valid : Theme.Color.secondaryText)
                .frame(width: 24, alignment: .leading)

            Text(initial)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
                .frame(width: Theme.Metric.rowIconSize, height: Theme.Metric.rowIconSize)
                .background(Theme.Color.elevated, in: .circle)

            Text(handle)
                .font(Theme.Font.body())
                .fontWeight(isYou ? .bold : .medium)
                .foregroundStyle(Theme.Color.primaryText)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Color.primaryText)
        }
        .frame(height: 50)
        .padding(.horizontal, isYou ? 8 : 0)
        .background {
            if isYou {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.Color.valid.opacity(0.07))
            }
        }
    }
}

#Preview {
    HomeView().preferredColorScheme(.dark)
}
