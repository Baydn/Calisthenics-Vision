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

    var cameraPosition: AVCaptureDevice.Position { usesFrontCamera ? .front : .back }

    private let defaults: UserDefaults

    private enum Keys {
        static let frontCamera = "settings.frontCamera"
        static let ultraWide = "settings.ultraWide"
        static let countdown = "settings.countdownSeconds"
        static let haptics = "settings.haptics"
        static let screenAwake = "settings.keepScreenAwake"
        static let recordsVideo = "settings.recordsVideo"
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
    }

    #if DEBUG
    func resetToDefaults() {
        for key in [Keys.frontCamera, Keys.ultraWide, Keys.countdown,
                    Keys.haptics, Keys.screenAwake, Keys.recordsVideo] {
            defaults.removeObject(forKey: key)
        }
        usesFrontCamera = true
        prefersUltraWide = false
        countdownSeconds = 3
        hapticsEnabled = true
        keepsScreenAwake = true
        recordsVideo = true
    }
    #endif
}
