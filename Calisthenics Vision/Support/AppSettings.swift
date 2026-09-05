//
//  AppSettings.swift
//  Calisthenics Vision
//
//  User preferences, backed by UserDefaults.
//
//  Everything here changes real behaviour. A settings screen full of switches
//  that do nothing is worse than no settings screen — it implies control the
//  app doesn't actually offer.
//

import AVFoundation
import Foundation
import Observation

@Observable
final class AppSettings {

    static let shared = AppSettings()

    /// Seconds of countdown before a set begins. 0 starts immediately.
    /// Set from the Train screen, where it's decided.
    var countdownSeconds: Int {
        didSet { defaults.set(countdownSeconds, forKey: Keys.countdown) }
    }

    /// Haptic feedback for reps, holds, and form breaks.
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }

    /// Keep the display on during a workout. On by default, because a screen
    /// dimming mid-set is the most disruptive thing this app can do.
    var keepsScreenAwake: Bool {
        didSet { defaults.set(keepsScreenAwake, forKey: Keys.screenAwake) }
    }

    /// Save a video alongside each session. Off means telemetry only, which
    /// costs a few hundred KB instead of ~150 MB per ten minutes.
    var recordsVideo: Bool {
        didSet { defaults.set(recordsVideo, forKey: Keys.recordsVideo) }
    }

    // MARK: - Coaching

    /// Short confirmation tones for rep, hold-second, form-break and
    /// countdown events. On by default, unlike speech — a tone isn't the
    /// social nuisance a voice announcing your rep count is.
    var soundCues: Bool {
        didSet { defaults.set(soundCues, forKey: Keys.soundCues) }
    }

    /// Spoken coaching. Off by default and turned on from the Train screen —
    /// an app that starts talking unprompted in a gym is worse than a silent
    /// one, and this is the kind of thing you enable when you're about to
    /// train, not while poking through Settings.
    var audioCoaching: Bool {
        didSet { defaults.set(audioCoaching, forKey: Keys.audioCoaching) }
    }

    var speaksReps: Bool {
        didSet { defaults.set(speaksReps, forKey: Keys.speaksReps) }
    }

    var speaksHoldTime: Bool {
        didSet { defaults.set(speaksHoldTime, forKey: Keys.speaksHoldTime) }
    }

    var speaksFormCues: Bool {
        didSet { defaults.set(speaksFormCues, forKey: Keys.speaksFormCues) }
    }

    var speaksCountdown: Bool {
        didSet { defaults.set(speaksCountdown, forKey: Keys.speaksCountdown) }
    }

    /// Seconds between spoken hold announcements. Every second is exhausting;
    /// landmarks are what you actually want upside down.
    var holdAnnounceInterval: Int {
        didSet { defaults.set(holdAnnounceInterval, forKey: Keys.holdInterval) }
    }

    // MARK: - Overlay

    /// How the skeleton is drawn over the camera and over a recording.
    /// One preference for both, because they're the same picture of the same
    /// thing — a skeleton that changes appearance between live and review
    /// makes review harder to read against what you remember seeing.
    var overlayStyle: PoseOverlayStyle {
        didSet { defaults.set(overlayStyle.rawValue, forKey: Keys.overlayStyle) }
    }

    /// Which overlay Session Review draws — the skeleton, the line you were
    /// holding, or the angle the movement is judged at. Remembered because
    /// it's a way of looking at your training, not a per-session decision:
    /// someone working on their line wants the line every time.
    var reviewOverlayMode: ReviewOverlayMode {
        didSet { defaults.set(reviewOverlayMode.rawValue, forKey: Keys.reviewOverlay) }
    }

    // MARK: - Movement tuning

    /// How deep a push-up has to go before it counts, as a share of the
    /// person's own observed range (POSE.md Law 3).
    ///
    /// The default stays lenient on purpose: an uncounted rep reads as a
    /// broken app, not as coaching (Law 4). This exists for people who
    /// *choose* to hold themselves to more, never as a default.
    enum RepDepth: String, CaseIterable, Identifiable {
        case lenient, standard, strict

        var id: String { rawValue }
        var title: String {
            switch self {
            case .lenient:  "Lenient"
            case .standard: "Standard"
            case .strict:   "Strict"
            }
        }
        var detail: String {
            switch self {
            case .lenient:  "Counts partial reps — good while you're building up"
            case .standard: "Counts most of the way down"
            case .strict:   "Only counts near-full depth"
            }
        }
        /// Fraction into the observed range the bottom gate sits at.
        var bottomGateFraction: Double {
            switch self {
            case .lenient:  0.32
            case .standard: 0.42
            case .strict:   0.58
            }
        }
    }

    var repDepth: RepDepth {
        didSet { defaults.set(repDepth.rawValue, forKey: Keys.repDepth) }
    }

    // MARK: - Train quick picks

    /// Which movements show as one-tap chips on Train, in the order chosen.
    /// Chosen from the library rather than hardcoded, because the library
    /// only grows — a fixed list stops being "the ones you actually use"
    /// the moment a new tracker ships.
    var pinnedMovements: [Movement] {
        didSet {
            defaults.set(pinnedMovements.map(\.rawValue), forKey: Keys.pinnedMovements)
        }
    }

    /// Always opens on the front camera: while setting up you're looking at
    /// the phone, and seeing your own skeleton is how you know it's working.
    /// Flipping is a control on the Train screen, not a stored preference.
    var cameraPosition: AVCaptureDevice.Position { .front }

    private let defaults: UserDefaults

    private enum Keys {
        static let countdown = "settings.countdownSeconds"
        static let haptics = "settings.haptics"
        static let screenAwake = "settings.keepScreenAwake"
        static let recordsVideo = "settings.recordsVideo"
        static let soundCues = "settings.soundCues"
        static let audioCoaching = "settings.audioCoaching"
        static let speaksReps = "settings.speaksReps"
        static let speaksHoldTime = "settings.speaksHoldTime"
        static let speaksFormCues = "settings.speaksFormCues"
        static let speaksCountdown = "settings.speaksCountdown"
        static let holdInterval = "settings.holdAnnounceInterval"
        static let repDepth = "settings.repDepth"
        static let pinnedMovements = "settings.pinnedMovements"
        static let overlayStyle = "settings.overlayStyle"
        static let reviewOverlay = "settings.reviewOverlayMode"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` distinguishes "never set" from "set to false", so
        // defaults land on sensible values rather than everything off.
        countdownSeconds = defaults.object(forKey: Keys.countdown) as? Int ?? 3
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        keepsScreenAwake = defaults.object(forKey: Keys.screenAwake) as? Bool ?? true
        recordsVideo = defaults.object(forKey: Keys.recordsVideo) as? Bool ?? true
        soundCues = defaults.object(forKey: Keys.soundCues) as? Bool ?? true
        audioCoaching = defaults.object(forKey: Keys.audioCoaching) as? Bool ?? false
        speaksReps = defaults.object(forKey: Keys.speaksReps) as? Bool ?? true
        speaksHoldTime = defaults.object(forKey: Keys.speaksHoldTime) as? Bool ?? true
        speaksFormCues = defaults.object(forKey: Keys.speaksFormCues) as? Bool ?? true
        speaksCountdown = defaults.object(forKey: Keys.speaksCountdown) as? Bool ?? true
        holdAnnounceInterval = defaults.object(forKey: Keys.holdInterval) as? Int ?? 5
        repDepth = (defaults.string(forKey: Keys.repDepth))
            .flatMap(RepDepth.init(rawValue:)) ?? .standard
        overlayStyle = (defaults.string(forKey: Keys.overlayStyle))
            .flatMap(PoseOverlayStyle.init(rawValue:)) ?? .outline
        reviewOverlayMode = (defaults.string(forKey: Keys.reviewOverlay))
            .flatMap(ReviewOverlayMode.init(rawValue:)) ?? .skeleton

        if let stored = defaults.array(forKey: Keys.pinnedMovements) as? [String] {
            pinnedMovements = stored.compactMap(Movement.init(rawValue:))
        } else {
            // First run: every movement that already has a real tracker.
            // Once pinning is used at all, the user's own choice takes over
            // completely rather than merging with this default.
            pinnedMovements = Movement.allCases.filter(\.isTrackingSupported)
        }
    }

    #if DEBUG
    func resetToDefaults() {
        for key in [Keys.countdown,
                    Keys.haptics, Keys.screenAwake, Keys.recordsVideo,
                    Keys.soundCues,
                    Keys.audioCoaching, Keys.speaksReps, Keys.speaksHoldTime,
                    Keys.speaksFormCues, Keys.speaksCountdown,
                    Keys.holdInterval, Keys.repDepth, Keys.pinnedMovements,
                    Keys.overlayStyle, Keys.reviewOverlay] {
            defaults.removeObject(forKey: key)
        }
        countdownSeconds = 3
        hapticsEnabled = true
        keepsScreenAwake = true
        recordsVideo = true
        soundCues = true
        audioCoaching = false
        speaksReps = true
        speaksHoldTime = true
        speaksFormCues = true
        speaksCountdown = true
        holdAnnounceInterval = 5
        repDepth = .standard
        overlayStyle = .outline
        reviewOverlayMode = .skeleton
        pinnedMovements = Movement.allCases.filter(\.isTrackingSupported)
    }
    #endif
}
