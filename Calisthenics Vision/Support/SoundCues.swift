//
//  SoundCues.swift
//  Calisthenics Vision
//
//  Short non-speech tones for rep, hold-second, form-break and countdown
//  events (BACKLOG.md F1). A tone confirms faster than a spoken number and
//  still works with speech off — unlike `AudioCoach` this is on by default,
//  since a beep isn't the social nuisance a voice is.
//
//  Synthesised rather than shipped as audio assets: four short sine tones,
//  each with its own pitch so the events stay distinguishable by ear.
//
//  Uses the same AVAudioSession category and options as `AudioCoach` so the
//  two never disagree about ducking, but owns its activation independently —
//  each is toggled separately and either has to work with the other off.
//

import AVFoundation

@MainActor
final class SoundCues {

    static let shared = SoundCues()

    private enum Event: CaseIterable {
        case countdown, rep, holdTick, formBreak

        /// Distinct pitches so the four stay tellable apart by ear alone.
        var frequency: Double {
            switch self {
            case .countdown: 880.00    // A5
            case .rep:       1_046.50  // C6 — the brightest, since it's the one you wait for
            case .holdTick:  659.25    // E5 — softer, it repeats every second of a hold
            case .formBreak: 293.66    // D4 — low, a caution rather than a confirmation
            }
        }
        var duration: TimeInterval {
            self == .formBreak ? 0.12 : 0.07
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var isSessionActive = false

    private lazy var tones: [Event: AVAudioPCMBuffer] = Dictionary(
        uniqueKeysWithValues: Event.allCases.map { ($0, makeBuffer(for: $0)) }
    )

    private var isEnabled: Bool { AppSettings.shared.soundCues }

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    // MARK: - Session

    func begin() {
        guard isEnabled, !isSessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            isSessionActive = true
        } catch {
            isSessionActive = false
        }
    }

    func end() {
        guard isSessionActive else { return }
        player.stop()
        engine.stop()
        isSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - Events

    func countdown() { play(.countdown) }
    func repCounted() { play(.rep) }
    func holdTick() { play(.holdTick) }
    func formBreak() { play(.formBreak) }

    private func play(_ event: Event) {
        guard isEnabled else { return }
        if !isSessionActive { begin() }
        guard isSessionActive, let buffer = tones[event] else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    // MARK: - Tone synthesis

    private func makeBuffer(for event: Event) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(event.duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]

        // A short fade in/out so the tone doesn't click at its edges.
        let fadeSamples = min(Int(frameCount) / 4, 200)
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let envelope: Double
            if frame < fadeSamples {
                envelope = Double(frame) / Double(fadeSamples)
            } else if frame > Int(frameCount) - fadeSamples {
                envelope = Double(Int(frameCount) - frame) / Double(fadeSamples)
            } else {
                envelope = 1
            }
            channel[frame] = Float(sin(2 * .pi * event.frequency * t) * envelope * 0.35)
        }
        return buffer
    }
}
