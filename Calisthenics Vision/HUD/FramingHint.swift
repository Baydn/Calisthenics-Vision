//
//  FramingHint.swift
//  Calisthenics Vision
//
//  In-set framing feedback (BACKLOG.md F2). The idle-state version of this —
//  "step into frame" before a set even starts — was cut deliberately: you
//  prop the phone, tap record, and *then* walk into shot, so being out of
//  frame before a set begins is normal, not a problem. Once recording is
//  under way it's different: staying silent while several seconds go
//  uncounted wastes the set.
//
//  Says which part is missing, or says nothing (POSE.md Law 5) — never a
//  vague "get in position". A limb passing behind the body for a moment is
//  normal and shouldn't flicker a hint on and off, so a region only counts
//  as missing once its confidence has stayed below `minConfidence` — the
//  same bar counting itself uses — for several *seconds*, not frames.
//

import Foundation

struct FramingHint: Equatable {

    /// Coarse enough to say something useful without pretending the
    /// confidence array can localize more precisely than this.
    enum Region: String, CaseIterable {
        case head = "Head"
        case arms = "Arms"
        case legs = "Legs"

        var joints: [PoseJoint] {
            switch self {
            case .head: [.nose]
            case .arms: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist]
            case .legs: [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
            }
        }
    }

    private static let minConfidence: Float = 0.5
    private static let flagAfter: TimeInterval = 3

    private var missingSinceMs: [Region: Int] = [:]
    private var noPoseSinceMs: Int?

    /// Text for the HUD pill, or nil when nothing has been missing long
    /// enough to be worth interrupting the set over.
    private(set) var message: String?

    mutating func update(pose: Pose?, timestampMs: Int) {
        guard let pose else {
            missingSinceMs.removeAll()
            if noPoseSinceMs == nil { noPoseSinceMs = timestampMs }
            message = elapsed(since: noPoseSinceMs, at: timestampMs) >= Self.flagAfter
                ? "Out of frame" : nil
            return
        }
        noPoseSinceMs = nil

        // Whichever region has been missing longest wins, so the hint
        // doesn't flicker between two at once going quiet and reappearing.
        var longestMissing: (region: Region, sinceMs: Int)?
        for region in Region.allCases {
            let confidence = region.joints.reduce(Float(1)) { min($0, pose.confidence[$1.rawValue]) }
            if confidence < Self.minConfidence {
                if missingSinceMs[region] == nil { missingSinceMs[region] = timestampMs }
            } else {
                missingSinceMs[region] = nil
            }
            guard let sinceMs = missingSinceMs[region],
                  elapsed(since: sinceMs, at: timestampMs) >= Self.flagAfter
            else { continue }
            if sinceMs < (longestMissing?.sinceMs ?? .max) {
                longestMissing = (region, sinceMs)
            }
        }
        message = longestMissing.map { "\($0.region.rawValue) out of frame" }
    }

    mutating func reset() {
        missingSinceMs.removeAll()
        noPoseSinceMs = nil
        message = nil
    }

    private func elapsed(since startMs: Int?, at nowMs: Int) -> TimeInterval {
        guard let startMs else { return 0 }
        return Double(nowMs - startMs) / 1000
    }
}
