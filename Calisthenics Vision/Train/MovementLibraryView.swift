//
//  MovementLibraryView.swift
//  Calisthenics Vision
//
//  Frame 02b — Movement Library. Free movements are selectable; Pro
//  movements show a lock and route to the paywall (SPEC.md §4).
//

import SwiftUI

struct MovementLibraryView: View {
    @Binding var selected: Movement

    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements
    @State private var showPaywall = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.Color.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Movements")
                    .padding(.top, 72)
                    .padding(.bottom, 24)

                VStack(spacing: 0) {
                    ForEach(Array(Movement.allCases.enumerated()), id: \.element.id) { index, movement in
                        row(for: movement)

                        if index < Movement.allCases.count - 1 {
                            Rectangle()
                                .fill(Theme.Color.rowSeparator)
                                .frame(height: 1)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Metric.screenPadding)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Color.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(Theme.Color.card, in: .circle)
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .padding(.trailing, Theme.Metric.screenPadding)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private func row(for movement: Movement) -> some View {
        let locked = !entitlements.canTrack(movement)

        return Button {
            if locked {
                showPaywall = true
            } else {
                selected = movement
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                MovementIcon(movement: movement)

                Text(movement.displayName)
                    .font(Theme.Font.body())
                    .foregroundStyle(locked ? Theme.Color.secondaryText : Theme.Color.primaryText)

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Color.secondaryText)
                }

                Spacer()

                if movement == selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Color.primaryText)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }
            .frame(height: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MovementLibraryView(selected: .constant(.pushUps))
        .environment(Entitlements())
}
