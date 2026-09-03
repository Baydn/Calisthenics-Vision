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

    @Environment(\.modelContext) private var modelContext
    @State private var showBreakdown = false
    @State private var exampleLiked = false

    private var sets: [WorkoutSession] { post?.sessions(from: sessions) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !captionText.isEmpty { caption }
            if example?.hasClip == true { clip }
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
                Text("\(titleText) · \(relativeTime)")
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
