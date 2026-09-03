//
//  OnboardingView.swift
//  Calisthenics Vision
//
//  Frame 01 — first run.
//
//  The original design told people to stand 45°–90° to the camera and tap
//  "I'm in Position". That requirement no longer exists: angles are measured
//  from 3D landmarks, so any camera position works (SPEC.md §1). Onboarding
//  therefore sets expectations and asks for the camera — it never asks the
//  user to get a setup right before they can start.
//
//  It ends on a real set rather than on a permissions screen. Completing an
//  achievement on day one is the single biggest retention lever available,
//  and ours is worth more than a rival's because the camera watched it: the
//  first record in History is something the app measured, not something the
//  user typed.
//

import AVFoundation
import SwiftData
import SwiftUI

struct OnboardingView: View {

    /// Set once completed; the Developer panel can clear it to replay this.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var page = 0
    @State private var cameraDenied = false
    @State private var stage: Stage = .pages
    @State private var unlocked: [Achievement] = []

    /// Onboarding runs pages → a real set → what that set unlocked.
    private enum Stage: Equatable {
        case pages, repTest, celebrate
    }

    private let pages: [Page] = [
        Page(
            symbol: "figure.strengthtraining.functional",
            title: "Count Reps Automatically",
            body: "Prop your phone up and train. Your camera watches your form and counts for you — no wearables, no tapping between sets."
        ),
        Page(
            symbol: "viewfinder",
            title: "Any Angle Works",
            body: "Set the phone wherever it fits. Facing you, off to one side, anywhere between — as long as most of your body is in frame, it works."
        ),
        Page(
            symbol: "camera.fill",
            title: "Camera Access",
            body: "Everything runs on your phone. Your video and workout data stay on this device — nothing is uploaded."
        ),
    ]

    var body: some View {
        switch stage {
        case .pages:
            pageFlow
        case .repTest:
            RepTestView { earned in
                unlocked = earned
                withAnimation(.snappy(duration: 0.3)) { stage = .celebrate }
            }
        case .celebrate:
            AchievementUnlockedView(achievements: unlocked) {
                hasCompletedOnboarding = true
            }
        }
    }

    private var pageFlow: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        pageView(item).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                    .padding(.bottom, 28)

                PrimaryButton(title: buttonTitle) { advance() }
                    .padding(.horizontal, Theme.Metric.screenPadding)

                Button("Skip") { stage = .repTest }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Color.secondaryText)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .opacity(isLastPage ? 0 : 1)
                    .disabled(isLastPage)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Camera access is off", isPresented: $cameraDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            // Without the camera there is no set to record, so skip it
            // rather than showing a screen that can't do anything.
            Button("Continue Anyway", role: .cancel) { hasCompletedOnboarding = true }
        } message: {
            Text("Rep counting needs the camera. You can enable it in Settings at any time.")
        }
    }

    private var isLastPage: Bool { page == pages.count - 1 }
    private var buttonTitle: String { isLastPage ? "Enable Camera" : "Continue" }

    /// Granting the camera leads straight into the set, which is the point of
    /// having asked for it.
    private func beginRepTest() {
        withAnimation(.snappy(duration: 0.3)) { stage = .repTest }
    }

    private func advance() {
        guard isLastPage else {
            withAnimation(.snappy(duration: 0.25)) { page += 1 }
            return
        }

        // Ask at the point the reason is on screen, rather than ambushing
        // them with a system prompt on first launch.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginRepTest()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    beginRepTest()
                } else {
                    cameraDenied = true
                }
            }
        default:
            cameraDenied = true
        }
    }

    // MARK: - Pieces

    private struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    private func pageView(_ item: Page) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: item.symbol)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Theme.Color.primaryText)
                .padding(.bottom, 36)

            Text(item.title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.Color.primaryText)
                .padding(.bottom, 14)

            Text(item.body)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Metric.screenPadding)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { index in
                Circle()
                    .fill(index == page
                          ? Theme.Color.primaryText : Theme.Color.secondaryText.opacity(0.4))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environment(CaptureStack())
        .modelContainer(SampleSessions.previewContainer)
}
