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
    let post: Post
    let sessions: [WorkoutSession]
    /// Nil for your own posts; a handle for anyone else's.
    var author: String?

    @Environment(\.modelContext) private var modelContext
    @State private var showBreakdown = false

    private var sets: [WorkoutSession] { post.sessions(from: sessions) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !post.caption.isEmpty { caption }
            headline
            if sets.count > 1 { breakdown }
            actions
        }
        .padding(14)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
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
                Text("\(post.title(from: sessions)) · \(relativeTime)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.secondaryText)
            }

            Spacer(minLength: 0)

            // The claim the whole feature rests on: this number came from a
            // camera, not a text field.
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Color.valid)
                .accessibilityLabel("Measured by camera")
        }
    }

    private var relativeTime: String {
        post.createdAt.formatted(.relative(presentation: .numeric))
    }

    private var caption: some View {
        Text(post.caption)
            .font(.system(size: 14.5))
            .foregroundStyle(Theme.Color.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(post.headline(from: sessions))
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.Color.primaryText)
            if let detail = subhead {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private var subhead: String? {
        guard let first = sets.first else { return nil }
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

    private var actions: some View {
        HStack(spacing: 0) {
            action(
                post.isLikedByMe ? "heart.fill" : "heart",
                label: post.likeCount > 0 ? "\(post.likeCount)" : "Like",
                tint: post.isLikedByMe ? Theme.Color.warning : Theme.Color.secondaryText
            ) {
                withAnimation(Theme.Motion.content) { toggleLike() }
            }

            action("bubble.right", label: post.commentCount > 0 ? "\(post.commentCount)" : "Comment") {}

            action("square.and.arrow.up", label: "Share") {}
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
        post.isLikedByMe.toggle()
        post.likeCount += post.isLikedByMe ? 1 : -1
        try? modelContext.save()
        Haptics.repCounted()
    }
}
