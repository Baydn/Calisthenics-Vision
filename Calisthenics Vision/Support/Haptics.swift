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

    /// Call shortly before an expected event so the Taptic engine is warm —
    /// otherwise the first tap of a set lags noticeably.
    static func prepare() {
        impact.prepare()
        notice.prepare()
    }

    static func repCounted() {
        impact.impactOccurred()
        impact.prepare()
    }

    static func formBreak() {
        notice.notificationOccurred(.warning)
        notice.prepare()
    }

    /// Each countdown beat, so you can look away from the phone and still
    /// know when the set begins.
    static func countdownTick() {
        let light = UIImpactFeedbackGenerator(style: .light)
        light.impactOccurred()
    }

    static func sessionStart() {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.impactOccurred()
    }

    static func sessionComplete() {
        notice.notificationOccurred(.success)
    }
}
