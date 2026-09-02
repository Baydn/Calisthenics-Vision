//
//  Haptics.swift
//  Calisthenics Vision
//
//  Physical feedback for workout events (SPEC.md §5).
//
//  The HUD is meant to be glanceable from 6–10 feet, but mid-set you often
//  can't look at it at all. Haptics carry the confirmation the screen can't.
//

import UIKit

enum Haptics {

    private static let impact = UIImpactFeedbackGenerator(style: .medium)
    private static let notice = UINotificationFeedbackGenerator()

    /// Checked here rather than at every call site, so a new feedback point
    /// can't accidentally ignore the user's preference.
    private static var isEnabled: Bool { AppSettings.shared.hapticsEnabled }

    /// Call shortly before an expected event so the Taptic engine is warm —
    /// otherwise the first tap of a set lags noticeably.
    static func prepare() {
        impact.prepare()
        notice.prepare()
    }

    static func repCounted() {
        guard isEnabled else { return }
        impact.impactOccurred()
        impact.prepare()
    }

    static func formBreak() {
        guard isEnabled else { return }
        notice.notificationOccurred(.warning)
        notice.prepare()
    }

    /// Each countdown beat, so you can look away from the phone and still
    /// know when the set begins.
    static func countdownTick() {
        guard isEnabled else { return }
        let light = UIImpactFeedbackGenerator(style: .light)
        light.impactOccurred()
    }

    /// One quiet pulse per second of a valid hold. Upside down you can't see
    /// the screen at all, so this is the only feedback that reaches you.
    static func holdTick() {
        guard isEnabled else { return }
        let soft = UIImpactFeedbackGenerator(style: .rigid)
        soft.impactOccurred(intensity: 0.5)
    }

    static func sessionStart() {
        guard isEnabled else { return }
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.impactOccurred()
    }

    static func sessionComplete() {
        guard isEnabled else { return }
        notice.notificationOccurred(.success)
    }
}
