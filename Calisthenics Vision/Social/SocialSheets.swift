//
//  SocialSheets.swift
//  Calisthenics Vision
//
//  The screens behind the feed's buttons — search, notifications, messages,
//  comments and share.
//
//  All design previews. None of them can work without accounts and a backend,
//  and each says so, but a button that opens nothing is worse than one that
//  opens an honest sketch: you can't judge whether the shape is right from a
//  dead control.
//

import SwiftUI

// MARK: - Search

struct PeopleSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""

    private let people: [(handle: String, detail: String)] = [
        ("mila.calis", "Front lever · straddle"),
        ("jonas_b", "19 pull-ups · best set"),
        ("rina.hs", "2:41 handstand"),
        ("dmitri_v", "Planche progression"),
        ("ana.flags", "Human flag · 0:11"),
    ]

    private var results: [(handle: String, detail: String)] {
        let q = term.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? people : people.filter {
            $0.handle.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        SheetScaffold(title: "Find people") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Color.tertiaryText)
                    TextField("Search by handle", text: $term)
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Color.primaryText)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(Theme.Color.card, in: .rect(cornerRadius: 10))

                PreviewNotice("There's no account system, so these people are invented and Follow does nothing.")

                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.offset) { index, person in
                        HStack(spacing: 12) {
                            Text(String(person.handle.prefix(1)).uppercased())
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.Color.primaryText)
                                .frame(width: 34, height: 34)
                                .background(Theme.Color.elevated, in: .circle)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.handle)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.Color.primaryText)
                                Text(person.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.Color.secondaryText)
                            }
                            Spacer(minLength: 8)
                            Text("Follow")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Color.background)
                                .padding(.horizontal, 14)
                                .frame(height: 30)
                                .background(Theme.Color.primaryText, in: .capsule)
                        }
                        .frame(height: 58)

                        if index < results.count - 1 {
                            Rectangle().fill(Theme.Color.rowSeparator).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
            }
        }
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    private let items: [(symbol: String, text: String, when: String, tint: SwiftUI.Color)] = [
        ("heart.fill", "mila.calis liked your handstand set", "12 min ago", Theme.Color.warning),
        ("bubble.right.fill", "jonas_b commented: \"that line is clean\"", "1 h ago", Theme.Color.primaryText),
        ("person.badge.plus", "rina.hs started following you", "3 h ago", Theme.Color.valid),
        ("trophy.fill", "You beat your pull-up record", "Yesterday", Theme.Color.valid),
    ]

    var body: some View {
        SheetScaffold(title: "Notifications") {
            VStack(alignment: .leading, spacing: 16) {
                PreviewNotice("Nothing generates these yet. The last one is the kind we could send today — it needs no account.")

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(item.tint)
                                .frame(width: 34, height: 34)
                                .background(Theme.Color.elevated, in: .circle)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.Color.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.when)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.Color.tertiaryText)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)

                        if index < items.count - 1 {
                            Rectangle().fill(Theme.Color.rowSeparator).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
            }
        }
    }
}

// MARK: - Messages

struct MessagesView: View {
    private let threads: [(handle: String, preview: String, when: String, unread: Bool)] = [
        ("mila.calis", "how long did the straddle take you?", "12 min", true),
        ("jonas_b", "sending you my pull day", "2 h", false),
        ("rina.hs", "the wrist warm-up helped, thanks", "Yesterday", false),
    ]

    var body: some View {
        SheetScaffold(title: "Messages") {
            VStack(alignment: .leading, spacing: 16) {
                PreviewNotice("Messaging needs accounts and a server. This is the shape it would take.")

                VStack(spacing: 0) {
                    ForEach(Array(threads.enumerated()), id: \.offset) { index, thread in
                        HStack(spacing: 12) {
                            Text(String(thread.handle.prefix(1)).uppercased())
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.Color.primaryText)
                                .frame(width: 38, height: 38)
                                .background(Theme.Color.elevated, in: .circle)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(thread.handle)
                                    .font(.system(size: 15, weight: thread.unread ? .bold : .semibold))
                                    .foregroundStyle(Theme.Color.primaryText)
                                Text(thread.preview)
                                    .font(.system(size: 13))
                                    .foregroundStyle(thread.unread
                                                     ? Theme.Color.primaryText : Theme.Color.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 6) {
                                Text(thread.when)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Color.tertiaryText)
                                if thread.unread {
                                    Circle()
                                        .fill(Theme.Color.valid)
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                        .frame(height: 64)

                        if index < threads.count - 1 {
                            Rectangle().fill(Theme.Color.rowSeparator).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
            }
        }
    }
}

// MARK: - Comments

struct CommentsView: View {
    @State private var draft = ""

    private let comments: [(handle: String, text: String, when: String)] = [
        ("jonas_b", "that line is clean", "1 h"),
        ("rina.hs", "shoulders look way more open than last month", "48 min"),
        ("dmitri_v", "what's your warm-up before these?", "20 min"),
    ]

    var body: some View {
        SheetScaffold(title: "Comments") {
            VStack(alignment: .leading, spacing: 16) {
                PreviewNotice("Comments need accounts. Posting one here does nothing yet.")

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(comments.enumerated()), id: \.offset) { _, comment in
                        HStack(alignment: .top, spacing: 10) {
                            Text(String(comment.handle.prefix(1)).uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.Color.primaryText)
                                .frame(width: 28, height: 28)
                                .background(Theme.Color.elevated, in: .circle)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(comment.handle)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.Color.primaryText)
                                    Text(comment.when)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.Color.tertiaryText)
                                }
                                Text(comment.text)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.Color.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                HStack(spacing: 10) {
                    TextField("Add a comment", text: $draft)
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Color.primaryText)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(Theme.Color.card, in: .capsule)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Color.background)
                        .frame(width: 42, height: 42)
                        .background(
                            draft.isEmpty ? Theme.Color.elevated : Theme.Color.primaryText,
                            in: .circle
                        )
                }
            }
        }
    }
}

// MARK: - Share

struct SharePostView: View {
    var body: some View {
        SheetScaffold(title: "Share") {
            VStack(alignment: .leading, spacing: 16) {
                PreviewNotice("Rendering the clip with the skeleton and stats burned in is real work that isn't done. This is the sheet it'll open.")

                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [Theme.Color.elevated, Theme.Color.background],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(height: 260)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("0:24.00")
                                .font(.system(size: 28, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.Color.primaryText)
                            Text("HANDSTAND · 81% LINE")
                                .cardLabelStyle()
                        }
                        .padding(14)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Text("✓ MEASURED")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Color.valid)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(Theme.Color.valid.opacity(0.16), in: .capsule)
                            .padding(14)
                    }

                HStack(spacing: 8) {
                    ForEach(["Skeleton", "Stats", "Measured mark"], id: \.self) { option in
                        Text(option)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Color.background)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(Theme.Color.primaryText, in: .capsule)
                    }
                }

                VStack(spacing: 0) {
                    shareRow("Save to Photos", "square.and.arrow.down")
                    Rectangle().fill(Theme.Color.rowSeparator).frame(height: 1)
                    shareRow("More…", "ellipsis")
                }
                .padding(.horizontal, 14)
                .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
            }
        }
    }

    private func shareRow(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Color.secondaryText)
                .frame(width: 24)
            Text(title)
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Color.primaryText)
            Spacer(minLength: 0)
        }
        .frame(height: 50)
    }
}

// MARK: - Shared chrome

/// One sheet shell, so every preview screen has the same edges and dismiss.
struct SheetScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Color.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview { PeopleSearchView() }
