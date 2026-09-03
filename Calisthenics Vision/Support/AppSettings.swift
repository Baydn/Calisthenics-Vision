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

    /// Which camera a session starts on.
    var usesFrontCamera: Bool {
        didSet { defaults.set(usesFrontCamera, forKey: Keys.frontCamera) }
    }

    /// Start on the ultra-wide lens where the hardware has one — useful in a
    /// small room where you can't get the phone far enough back.
    var prefersUltraWide: Bool {
        didSet { defaults.set(prefersUltraWide, forKey: Keys.ultraWide) }
    }

    /// Seconds of countdown before a set begins. 0 starts immediately.
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

    var cameraPosition: AVCaptureDevice.Position { usesFrontCamera ? .front : .back }

    private let defaults: UserDefaults

    private enum Keys {
        static let frontCamera = "settings.frontCamera"
        static let ultraWide = "settings.ultraWide"
        static let countdown = "settings.countdownSeconds"
        static let haptics = "settings.haptics"
        static let screenAwake = "settings.keepScreenAwake"
        static let recordsVideo = "settings.recordsVideo"
        static let audioCoaching = "settings.audioCoaching"
        static let speaksReps = "settings.speaksReps"
        static let speaksHoldTime = "settings.speaksHoldTime"
        static let speaksFormCues = "settings.speaksFormCues"
        static let speaksCountdown = "settings.speaksCountdown"
        static let holdInterval = "settings.holdAnnounceInterval"
        static let repDepth = "settings.repDepth"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` distinguishes "never set" from "set to false", so
        // defaults land on sensible values rather than everything off.
        usesFrontCamera = defaults.object(forKey: Keys.frontCamera) as? Bool ?? true
        prefersUltraWide = defaults.object(forKey: Keys.ultraWide) as? Bool ?? false
        countdownSeconds = defaults.object(forKey: Keys.countdown) as? Int ?? 3
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        keepsScreenAwake = defaults.object(forKey: Keys.screenAwake) as? Bool ?? true
        recordsVideo = defaults.object(forKey: Keys.recordsVideo) as? Bool ?? true
        audioCoaching = defaults.object(forKey: Keys.audioCoaching) as? Bool ?? false
        speaksReps = defaults.object(forKey: Keys.speaksReps) as? Bool ?? true
        speaksHoldTime = defaults.object(forKey: Keys.speaksHoldTime) as? Bool ?? true
        speaksFormCues = defaults.object(forKey: Keys.speaksFormCues) as? Bool ?? true
        speaksCountdown = defaults.object(forKey: Keys.speaksCountdown) as? Bool ?? true
        holdAnnounceInterval = defaults.object(forKey: Keys.holdInterval) as? Int ?? 5
        repDepth = (defaults.string(forKey: Keys.repDepth))
            .flatMap(RepDepth.init(rawValue:)) ?? .standard
    }

    #if DEBUG
    func resetToDefaults() {
        for key in [Keys.frontCamera, Keys.ultraWide, Keys.countdown,
                    Keys.haptics, Keys.screenAwake, Keys.recordsVideo,
                    Keys.audioCoaching, Keys.speaksReps, Keys.speaksHoldTime,
                    Keys.speaksFormCues, Keys.speaksCountdown,
                    Keys.holdInterval, Keys.repDepth] {
            defaults.removeObject(forKey: key)
        }
        usesFrontCamera = true
        prefersUltraWide = false
        countdownSeconds = 3
        hapticsEnabled = true
        keepsScreenAwake = true
        recordsVideo = true
        audioCoaching = false
        speaksReps = true
        speaksHoldTime = true
        speaksFormCues = true
        speaksCountdown = true
        holdAnnounceInterval = 5
        repDepth = .standard
    }
    #endif
}
