//
//  AchievementUnlockedView.swift
//  Calisthenics Vision
//
//  The moment after the first set. Shown once, then it's out of the way.
//
//  The claim it's making is the one thing no rival app can make: the number
//  wasn't typed in, it was watched. Everything on this screen came from the
//  same pipeline that drew the skeleton a second earlier.
//

import SwiftUI

struct AchievementUnlockedView: View {
    let achievements: [Achievement]
    let onContinue: () -> Void

    @State private var shown = false

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Image(systemName: achievements.first?.symbol ?? "checkmark.seal.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(Theme.Color.valid)
                    .padding(.bottom, 28)
                    .scaleEffect(shown ? 1 : 0.6)
                    .opacity(shown ? 1 : 0)

                Text(achievements.isEmpty ? "You're all set" : "Nice.")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.Color.primaryText)
                    .padding(.bottom, 12)

                Text(achievements.isEmpty
                     ? "Record a set any time — it'll show up in History."
                     : "That's in your history, and it's your first record to beat.")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.Color.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .padding(.bottom, 30)

                VStack(spacing: 10) {
                    ForEach(Array(achievements.enumerated()), id: \.element.id) { index, item in
                        row(item)
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown ? 0 : 12)
                            .animation(
                                .snappy(duration: 0.3).delay(0.12 * Double(index) + 0.15),
                                value: shown
                            )
                    }
                }
                .padding(.horizontal, Theme.Metric.screenPadding)

                Spacer(minLength: 0)

                PrimaryButton(title: "Start training", action: onContinue)
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.snappy(duration: 0.4)) { shown = true }
            if !achievements.isEmpty { Haptics.sessionComplete() }
        }
    }

    private func row(_ item: Achievement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.valid)
                .frame(width: Theme.Metric.rowIconSize, height: Theme.Metric.rowIconSize)
                .background(Theme.Color.card, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.primaryText)
                Text(item.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.Color.card, in: .rect(cornerRadius: Theme.Metric.cardRadius))
    }
}

#Preview {
    AchievementUnlockedView(
        achievements: [
            Achievement(id: "a", title: "First Rep Counted",
                        detail: "Recorded your first session", symbol: "checkmark.seal.fill"),
            Achievement(id: "b", title: "Ten in a Set",
                        detail: "10 push-ups in one set", symbol: "10.circle.fill"),
        ],
        onContinue: {}
    )
}
