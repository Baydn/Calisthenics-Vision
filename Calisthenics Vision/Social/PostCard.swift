//
//  PostCard.swift
//  Calisthenics Vision
//
//  One post in the feed.
//
//  Ordering follows Hevy's, which is the one that reads cleanly: who and
//  when, then the title, then the caption, the headline number, the clip, and
//  the actions last. A single set and a whole workout are the same card with
//  different contents — modelling them apart would mean writing this twice.
//
//  Actions are Like, Comment and Share rather than an imitation of kudos.
//  Share matters most here because it exports the annotated clip, not a link.
//

import SwiftData
import SwiftUI

struct PostCard: View {
    /// Nil for an example card — the feed shows a few so the shape is visible
    /// before there's anyone to follow.
    var post: Post?
    var sessions: [WorkoutSession] = []
    /// Nil for your own posts; a handle for anyone else's.
    var author: String?

    /// Everything an example card needs, so both kinds render through one
    /// view and the actions row can't exist on one and not the other.
    struct Example {
        var title: String
        var when: String
        var caption: String = ""
        var headline: String
        var subhead: String?
        var hasClip: Bool = false
        var likeCount: Int
        var commentCount: Int
    }
    var example: Example?
    var onComment: (() -> Void)?
    var onShare: (() -> Void)?
    var onOpenAuthor: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var showBreakdown = false
    @State private var exampleLiked = false
    @State private var isFavourite = false
    @State private var notifyOnPost = false
    @State private var isFollowing = true
    @State private var isMuted = false
    @State private var showLikes = false

    private var sets: [WorkoutSession] { post?.sessions(from: sessions) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
                .contentShape(.rect)
                .onTapGesture { onOpenAuthor?() }
            if !captionText.isEmpty { caption }
            if example?.hasClip == true { clip }
            headline
            if sets.count > 1 { breakdown }
            likedBy
            actions
        }
        .padding(14)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
        .sheet(isPresented: $showLikes) { LikesView(count: likeTotal) }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 10) {
            Text(String((author ?? "You").prefix(1)).uppercased())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
                .frame(width: Theme.Metric.rowIconSize, height: Theme.Metric.rowIconSize)
                .background(Theme.Color.elevated, in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                Text(author ?? "You")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                Text("\(titleText) · \(relativeTime)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.secondaryText)
            }

            Spacer(minLength: 0)

            overflowMenu
        }
    }

    /// Strava's set, which is the right one: the things you want when someone
    /// else's post annoys you or delights you, and nothing else.
    private var overflowMenu: some View {
        Menu {
            Button {
                isFavourite.toggle()
            } label: {
                Label(
                    isFavourite ? "Remove from favourites" : "Add to favourites",
                    systemImage: isFavourite ? "star.slash" : "star"
                )
            }

            Button {
                notifyOnPost.toggle()
            } label: {
                Label(
                    notifyOnPost ? "Turn off notifications" : "Turn on notifications",
                    systemImage: notifyOnPost ? "bell.slash" : "bell"
                )
            }

            if author != nil {
                Divider()
                Button { isFollowing.toggle() } label: {
                    Label(isFollowing ? "Unfollow" : "Follow", systemImage: isFollowing ? "person.badge.minus" : "person.badge.plus")
                }
                Button { isMuted.toggle() } label: {
                    Label(isMuted ? "Unmute activities" : "Mute activities", systemImage: isMuted ? "speaker.wave.2" : "speaker.slash")
                }
                Divider()
                Button(role: .destructive) {} label: {
                    Label("Report activity", systemImage: "flag")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.secondaryText)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .accessibilityLabel("More")
    }

    private var titleText: String {
        example?.title ?? post?.title(from: sessions) ?? "Post"
    }

    private var captionText: String {
        example?.caption ?? post?.caption ?? ""
    }

    private var relativeTime: String {
        if let example { return example.when }
        return post?.createdAt.formatted(.relative(presentation: .numeric)) ?? ""
    }

    private var clip: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [Theme.Color.elevated, Theme.Color.background],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(height: 130)
            .overlay {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.Color.primaryText.opacity(0.65))
            }
    }

    private var caption: some View {
        Text(captionText)
            .font(.system(size: 14.5))
            .foregroundStyle(Theme.Color.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(example?.headline ?? post?.headline(from: sessions) ?? "—")
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.Color.primaryText)
            if let detail = subhead {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            Spacer(minLength: 0)

            // Sits with the number it certifies rather than up in the corner
            // — the claim is about the figure, not about the person.
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("MEASURED")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(Theme.Metric.labelTracking)
            }
            .foregroundStyle(Theme.Color.valid)
        }
    }

    private var subhead: String? {
        if let example { return example.subhead }
        guard let post, let first = sets.first else { return nil }
        if post.isSingleSet {
            if first.movement.isTimedHold, first.holdDurationsSec.count > 1 {
                return "\(first.holdDurationsSec.count) holds · \(first.formQualityLabel ?? "—") line"
            }
            return first.formQualityLabel.map { "\($0) line" }
        }
        return "\(Set(sets.map(\.movement)).count) movements"
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Theme.Motion.expand) { showBreakdown.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(showBreakdown ? "Hide sets" : "Show \(sets.count) sets")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(showBreakdown ? 180 : 0))
                }
                .foregroundStyle(Theme.Color.secondaryText)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if showBreakdown {
                VStack(spacing: 0) {
                    ForEach(sets) { session in
                        HStack(spacing: 10) {
                            DifficultyPill(level: session.movement.difficulty)
                            Text(session.movement.displayName)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.Color.primaryText)
                            Spacer(minLength: 8)
                            Text(session.result.displayValue)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Color.secondaryText)
                        }
                        .frame(height: 40)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var isLiked: Bool { post?.isLikedByMe ?? exampleLiked }

    private var likeTotal: Int {
        let base = post?.likeCount ?? example?.likeCount ?? 0
        return post == nil && exampleLiked ? base + 1 : base
    }

    private var commentTotal: Int { post?.commentCount ?? example?.commentCount ?? 0 }

    /// Faces then a count, the way Strava does it — "who" lands harder than
    /// "how many", and three avatars is enough to recognise a friend.
    @ViewBuilder
    private var likedBy: some View {
        if likeTotal > 0 {
            Button { showLikes = true } label: {
            HStack(spacing: 8) {
                HStack(spacing: -8) {
                    ForEach(Array(likerInitials.enumerated()), id: \.offset) { _, initial in
                        Text(initial)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.primaryText)
                            .frame(width: 24, height: 24)
                            .background(Theme.Color.elevated, in: .circle)
                            .overlay { Circle().strokeBorder(Theme.Color.card, lineWidth: 2) }
                    }
                }
                Text(likedByLabel)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Color.secondaryText)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var likerInitials: [String] {
        // Local likes have no people behind them yet; examples borrow from
        // the same invented cast the feed uses.
        let pool = ["M", "J", "R", "D", "A"]
        return Array(pool.prefix(min(3, likeTotal)))
    }

    private var likedByLabel: String {
        if isLiked && likeTotal == 1 { return "You liked this" }
        if isLiked { return "You and \(likeTotal - 1) other\(likeTotal == 2 ? "" : "s")" }
        return "\(likeTotal) \(likeTotal == 1 ? "person" : "people") liked this"
    }

    private var actions: some View {
        HStack(spacing: 0) {
            action(
                isLiked ? "heart.fill" : "heart",
                label: likeTotal > 0 ? "\(likeTotal)" : "Like",
                tint: isLiked ? Theme.Color.warning : Theme.Color.secondaryText
            ) {
                withAnimation(Theme.Motion.content) { toggleLike() }
            }

            action("bubble.right", label: commentTotal > 0 ? "\(commentTotal)" : "Comment") {
                onComment?()
            }

            action("square.and.arrow.up", label: "Share") { onShare?() }
        }
        .padding(.top, 2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Color.rowSeparator)
                .frame(height: 1)
        }
    }

    private func action(
        _ symbol: String,
        label: String,
        tint: SwiftUI.Color = Theme.Color.secondaryText,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func toggleLike() {
        if let post {
            post.isLikedByMe.toggle()
            post.likeCount += post.isLikedByMe ? 1 : -1
            try? modelContext.save()
        } else {
            exampleLiked.toggle()
        }
        Haptics.repCounted()
    }
}
