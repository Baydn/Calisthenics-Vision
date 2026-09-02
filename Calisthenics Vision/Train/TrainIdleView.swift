//
//  TrainIdleView.swift
//  Calisthenics Vision
//
//  Frame 02 — Train · Idle. The dark backdrop stands in for the live camera
//  preview until the AVCaptureSession pipeline lands; the ghost figure and
//  framing hint sit on top of it.
//

import SwiftUI

struct TrainIdleView: View {
    @Environment(Entitlements.self) private var entitlements

    @State private var selected: Movement = .pushUps
    @State private var showLibrary = false
    @State private var showPaywall = false

    /// Quick-pick movements; the rest live behind "+ Library".
    private let quickPicks: [Movement] = [.pushUps, .handstand, .lSit]

    var body: some View {
        ZStack {
            // Stand-in for the camera preview.
            Color(red: 0.09, green: 0.09, blue: 0.09)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                movementPicker
                    .padding(.top, 8)

                Spacer()

                framingHint

                Spacer()

                recordButton
                    .padding(.bottom, Theme.Metric.tabBarHeight + 8)
            }
        }
        .sheet(isPresented: $showLibrary) {
            MovementLibraryView(selected: $selected)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Pieces

    private var movementPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(quickPicks) { movement in
                    FilterChip(
                        title: movement.displayName,
                        isActive: movement == selected,
                        horizontalPadding: 14
                    ) {
                        select(movement)
                    }
                }

                Button { showLibrary = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Library")
                            .font(Theme.Font.control())
                    }
                    .foregroundStyle(Theme.Color.primaryText)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                Theme.Color.secondaryText,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                            )
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private var framingHint: some View {
        VStack(spacing: 28) {
            GhostFigure()
                .frame(width: 120, height: 160)

            Text("Step into frame to begin")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.Color.secondaryText)
        }
    }

    private var recordButton: some View {
        Button {
            // Session start is wired once the camera + pose layers exist.
        } label: {
            Circle()
                .fill(Theme.Color.primaryText)
                .frame(width: 68, height: 68)
                .overlay {
                    Circle()
                        .strokeBorder(Theme.Color.primaryText, lineWidth: 4)
                        .frame(width: 82, height: 82)
                }
        }
        .buttonStyle(.plain)
    }

    private func select(_ movement: Movement) {
        guard entitlements.canTrack(movement) else {
            showPaywall = true
            return
        }
        withAnimation(.snappy(duration: 0.2)) { selected = movement }
    }
}

// MARK: - Ghost figure

/// The faint standing figure used as a framing guide.
private struct GhostFigure: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let stroke = Theme.Color.secondaryText.opacity(0.55)

            ZStack {
                Circle()
                    .fill(Theme.Color.secondaryText.opacity(0.45))
                    .frame(width: w * 0.36, height: w * 0.36)
                    .position(x: w / 2, y: h * 0.14)

                Path { path in
                    // Torso
                    path.move(to: CGPoint(x: w / 2, y: h * 0.30))
                    path.addLine(to: CGPoint(x: w / 2, y: h * 0.72))
                    // Arms
                    path.move(to: CGPoint(x: w * 0.14, y: h * 0.46))
                    path.addLine(to: CGPoint(x: w / 2, y: h * 0.30))
                    path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.46))
                    // Legs
                    path.move(to: CGPoint(x: w * 0.22, y: h * 0.94))
                    path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.94))
                }
                .stroke(stroke, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

#Preview {
    TrainIdleView()
        .environment(Entitlements())
        .preferredColorScheme(.dark)
}
