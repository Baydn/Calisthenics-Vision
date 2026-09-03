//
//  AudioCoach.swift
//  Calisthenics Vision
//
//  Spoken coaching and cue tones (SPEC.md §5).
//
//  The HUD is designed to be readable from 6–10 feet, but that's exactly the
//  problem: to fit your whole body in frame the phone ends up far enough away
//  that reading it mid-set is a nuisance, and in a handstand you're upside
//  down and can't read it at all. Haptics carry confirmation; only audio can
//  carry a *number*.
//
//  Off by default and turned on from the Train screen. An app that starts
//  talking unprompted in a gym is worse than a silent one.
//

import AVFoundation
import Foundation

@MainActor
final class AudioCoach {

    static let shared = AudioCoach()

    private let synthesizer = AVSpeechSynthesizer()
    /// Last hold second announced, so a resumed clock doesn't repeat itself.
    private var lastSpokenHoldSecond = 0
    private var isSessionActive = false

    private var settings: AppSettings { AppSettings.shared }
    private var isEnabled: Bool { settings.audioCoaching }

    private init() {}

    // MARK: - Session

    /// Claims the audio session for the duration of a set.
    ///
    /// Ducks rather than interrupts: people train to their own music, and an
    /// app that stops it to say "three" would be uninstalled by lunchtime.
    func begin() {
        lastSpokenHoldSecond = 0
        guard isEnabled, !isSessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            isSessionActive = true
        } catch {
            // Audio is an enhancement; failing to get the session is not a
            // reason to interfere with the set.
            isSessionActive = false
        }
    }

    func end() {
        synthesizer.stopSpeaking(at: .immediate)
        lastSpokenHoldSecond = 0
        guard isSessionActive else { return }
        isSessionActive = false
        // Deactivating hands music back at full volume.
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - Events

    func countdown(_ value: Int) {
        guard settings.speaksCountdown else { return }
        say("\(value)", interrupting: true)
    }

    func setStarted() {
        guard settings.speaksCountdown else { return }
        say("Go", interrupting: true)
    }

    /// Announces the running count. Interrupts the previous number, because a
    /// queue of stale counts is worse than silence — by the time it said
    /// "four" you'd be on eight.
    func repCounted(_ total: Int) {
        guard settings.speaksReps else { return }
        say("\(total)", interrupting: true)
    }

    /// Hold time, spoken at intervals rather than every second — a voice
    /// counting every second is exhausting, and you mostly want landmarks.
    func holdTick(seconds: Int) {
        guard settings.speaksHoldTime, seconds > 0 else { return }
        guard seconds % settings.holdAnnounceInterval == 0 else { return }
        guard seconds != lastSpokenHoldSecond else { return }
        lastSpokenHoldSecond = seconds
        say("\(seconds)", interrupting: true)
    }

    func holdCompleted(index: Int, duration: TimeInterval) {
        guard settings.speaksHoldTime else { return }
        lastSpokenHoldSecond = 0
        say("Hold \(index), \(Int(duration.rounded())) seconds", interrupting: true)
    }

    /// Form callouts never interrupt a count — the count is the thing the
    /// user is waiting on, and coaching can wait a beat.
    func formIssue(_ issue: FormIssue) {
        guard settings.speaksFormCues else { return }
        say(issue.rawValue, interrupting: false)
    }

    func recordBeaten() {
        guard isEnabled else { return }
        say("New best", interrupting: true)
    }

    func setFinished(summary: String) {
        guard isEnabled else { return }
        say(summary, interrupting: true)
    }

    // MARK: - Speech

    private func say(_ text: String, interrupting: Bool) {
        guard isEnabled else { return }
        if !isSessionActive { begin() }

        if interrupting, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        } else if synthesizer.isSpeaking {
            // Don't stack non-urgent lines on top of speech already running.
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        // Slightly quick: a set doesn't wait for the sentence to finish.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.08
        utterance.postUtteranceDelay = 0
        utterance.volume = 1
        synthesizer.speak(utterance)
    }
}
