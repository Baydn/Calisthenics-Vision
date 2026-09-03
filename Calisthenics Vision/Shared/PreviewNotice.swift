//
//  PreviewNotice.swift
//  Calisthenics Vision
//
//  Marks a screen that is designed but not wired up.
//
//  This project's rule is that a control which does nothing is worse than no
//  control — it implies capability the app doesn't have. Design previews are
//  the exception that proves it: they exist so the shape of the finished app
//  can be walked through and argued with, and this badge is the price of
//  admission. Every screen carrying it must say plainly what isn't real.
//
//  When a feature lands, its notice comes out. A stale one is the same lie
//  the rule exists to prevent.
//

import SwiftUI

struct PreviewNotice: View {
    private let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "ruler")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Color.previewAccent)

            VStack(alignment: .leading, spacing: 3) {
                Text("DESIGN PREVIEW")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(Theme.Metric.labelTracking)
                    .foregroundStyle(Theme.Color.previewAccent)
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.Color.previewAccent.opacity(0.08))
                .strokeBorder(Theme.Color.previewAccent.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

#Preview {
    ZStack {
        Theme.Color.background.ignoresSafeArea()
        PreviewNotice("Levels are designed, not wired up. Nothing here is evaluated against your sessions yet.")
            .padding()
    }
    .preferredColorScheme(.dark)
}
