//
//  Movement.swift
//  Calisthenics Vision
//
//  The movement catalogue and how a session's result is presented.
//
//  Only a handful of these have trackers. The rest are listed anyway, with an
//  honest "not tracked yet" state, because a library that hides everything
//  unbuilt can't show you where the app is going — and because picking one
//  still lets you record the set.
//
//  Nothing whose only distinguishing feature is hand placement is here.
//  MediaPipe gives three coarse points per hand and no grip, so a diamond
//  push-up and a standard push-up are the same pose to it, and a chin-up is
//  identical to a pull-up. Offering them would mean labelling one as the
//  other. Wide-grip pull-ups *are* here: wrist separation is visible even
//  though grip isn't.
//
//  Raw values are persisted in SwiftData — never rename an existing one.
//

import Foundation

enum MovementCategory: String, CaseIterable, Identifiable, Hashable {
    case push, pull, legs, core, skill

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .push:  "Push"
        case .pull:  "Pull"
        case .legs:  "Legs"
        case .core:  "Core & Static"
        case .skill: "Skill"
        }
    }
}

/// What you need to attempt a movement, so the library can be filtered by
/// what's actually in the room — a real barrier for someone starting out.
enum Equipment: String, CaseIterable, Identifiable, Hashable {
    case floor, bar, dipBars, wall

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .floor:   "Floor"
        case .bar:     "Bar"
        case .dipBars: "Dip bars"
        case .wall:    "Wall"
        }
    }
}

enum Movement: String, CaseIterable, Identifiable, Hashable, Codable {

    // Push
    case pushUps
    case dip
    case pikePushUp
    case pseudoPlanchePushUp
    case handstandPushUp
    case oneArmPushUp
    case planchePushUp

    // Pull
    case deadHang
    case australianRow
    case negativePullUp
    case pullUps
    case wideGripPullUp
    case lSitPullUp
    case muscleUps
    case oneArmPullUp

    // Legs
    case wallSit
    case squat
    case jumpSquat
    case lunge
    case cossackSquat
    case bulgarianSplitSquat
    case shrimpSquat
    case pistolSquat
    case nordicCurl

    // Core & static
    case plank
    case sitUp
    case sidePlank
    case hollowBody
    case hangingKneeRaise
    case lSit
    case hangingLegRaise
    case toesToBar
    case vSit
    case dragonFlag
    case backLever
    case frontLever
    case humanFlag
    case planche

    // Skill
    case crowStand
    case elbowLever
    case handstand
    case pressToHandstand
    case handstandWalk

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pushUps:              "Push-Up"
        case .dip:                  "Dip"
        case .pikePushUp:           "Pike Push-Up"
        case .pseudoPlanchePushUp:  "Pseudo Planche Push-Up"
        case .handstandPushUp:      "Handstand Push-Up"
        case .oneArmPushUp:         "One-Arm Push-Up"
        case .planchePushUp:        "Planche Push-Up"
        case .deadHang:             "Dead Hang"
        case .australianRow:        "Australian Row"
        case .negativePullUp:       "Negative Pull-Up"
        case .pullUps:              "Pull-Up"
        case .wideGripPullUp:       "Wide-Grip Pull-Up"
        case .lSitPullUp:           "L-Sit Pull-Up"
        case .muscleUps:            "Muscle-Up"
        case .oneArmPullUp:         "One-Arm Pull-Up"
        case .wallSit:              "Wall Sit"
        case .squat:                "Squat"
        case .jumpSquat:            "Jump Squat"
        case .lunge:                "Lunge"
        case .cossackSquat:         "Cossack Squat"
        case .bulgarianSplitSquat:  "Bulgarian Split Squat"
        case .shrimpSquat:          "Shrimp Squat"
        case .pistolSquat:          "Pistol Squat"
        case .nordicCurl:           "Nordic Curl"
        case .plank:                "Plank"
        case .sitUp:                "Sit-Up"
        case .sidePlank:            "Side Plank"
        case .hollowBody:           "Hollow Body"
        case .hangingKneeRaise:     "Hanging Knee Raise"
        case .lSit:                 "L-Sit"
        case .hangingLegRaise:      "Hanging Leg Raise"
        case .toesToBar:            "Toes-to-Bar"
        case .vSit:                 "V-Sit"
        case .dragonFlag:           "Dragon Flag"
        case .backLever:            "Back Lever"
        case .frontLever:           "Front Lever"
        case .humanFlag:            "Human Flag"
        case .planche:              "Planche"
        case .crowStand:            "Crow Stand"
        case .elbowLever:           "Elbow Lever"
        case .handstand:            "Handstand"
        case .pressToHandstand:     "Press to Handstand"
        case .handstandWalk:        "Handstand Walk"
        }
    }

    var category: MovementCategory {
        switch self {
        case .pushUps, .dip, .pikePushUp, .pseudoPlanchePushUp,
             .handstandPushUp, .oneArmPushUp, .planchePushUp:
            .push
        case .deadHang, .australianRow, .negativePullUp, .pullUps,
             .wideGripPullUp, .lSitPullUp, .muscleUps, .oneArmPullUp:
            .pull
        case .wallSit, .squat, .jumpSquat, .lunge, .cossackSquat,
             .bulgarianSplitSquat, .shrimpSquat, .pistolSquat, .nordicCurl:
            .legs
        case .plank, .sitUp, .sidePlank, .hollowBody, .hangingKneeRaise, .lSit,
             .hangingLegRaise, .toesToBar, .vSit, .dragonFlag, .backLever,
             .frontLever, .humanFlag, .planche:
            .core
        case .crowStand, .elbowLever, .handstand, .pressToHandstand, .handstandWalk:
            .skill
        }
    }

    /// 1–10, for the standard version of the movement. Progressions inside a
    /// skill get their own numbers once levels exist — a tuck front lever is
    /// not a 9.
    var difficulty: Int {
        switch self {
        case .plank, .deadHang:                             1
        case .wallSit, .sitUp, .squat, .australianRow:      2
        case .pushUps, .jumpSquat, .lunge, .sidePlank,
             .hollowBody, .negativePullUp:                  3
        case .dip, .pullUps, .hangingKneeRaise, .crowStand: 4
        case .pikePushUp, .wideGripPullUp, .cossackSquat,
             .bulgarianSplitSquat, .lSit, .hangingLegRaise: 5
        case .handstand, .toesToBar, .elbowLever:           6
        case .pseudoPlanchePushUp, .handstandPushUp, .muscleUps,
             .lSitPullUp, .shrimpSquat, .pistolSquat,
             .nordicCurl, .vSit:                            7
        case .oneArmPushUp, .dragonFlag, .backLever,
             .handstandWalk:                                8
        case .frontLever, .humanFlag, .pressToHandstand:    9
        case .planchePushUp, .oneArmPullUp, .planche:       10
        }
    }

    var tier: String {
        switch difficulty {
        case ...2:  "Foundation"
        case 3...4: "Beginner"
        case 5...6: "Intermediate"
        case 7...8: "Advanced"
        default:    "Elite"
        }
    }

    var equipment: Equipment {
        switch self {
        case .pullUps, .wideGripPullUp, .lSitPullUp, .muscleUps, .oneArmPullUp,
             .deadHang, .negativePullUp, .australianRow, .hangingKneeRaise,
             .hangingLegRaise, .toesToBar, .frontLever, .backLever, .humanFlag:
            .bar
        case .dip, .lSit:
            .dipBars
        case .wallSit, .handstandPushUp:
            .wall
        default:
            .floor
        }
    }

    /// SF Symbol standing in for the custom glyphs in the Figma frames.
    var symbolName: String {
        switch category {
        case .push:  "arrow.up.to.line"
        case .pull:  "figure.strengthtraining.functional"
        case .legs:  "figure.step.training"
        case .core:  "figure.core.training"
        case .skill: "figure.gymnastics"
        }
    }

    /// Free tier ships push-ups and handstands; everything else is Pro
    /// (SPEC.md §4).
    var isPro: Bool {
        switch self {
        case .pushUps, .handstand: false
        default: true
        }
    }

    /// Reps are counted; holds are timed.
    var isTimedHold: Bool {
        switch self {
        case .handstand, .lSit, .planche, .plank, .sidePlank, .hollowBody,
             .vSit, .backLever, .frontLever, .humanFlag, .deadHang, .wallSit,
             .crowStand, .elbowLever, .handstandWalk:
            true
        default:
            false
        }
    }

    /// What usually comes before this, as a graph rather than a ladder.
    ///
    /// Nothing here gates anything — you can attempt any movement at any
    /// time, and the tree draws these as suggestions of where a movement
    /// leads. A skill tree that locks you out is a game mechanic; this is a
    /// map, and people arrive at calisthenics from wrestling, gymnastics and
    /// climbing with wildly different starting points.
    ///
    /// Several movements have more than one parent, which is the whole reason
    /// this isn't a list: an L-sit pull-up needs both a pull-up and an L-sit.
    var prerequisites: [Movement] {
        switch self {
        // Push
        case .dip, .pikePushUp, .pseudoPlanchePushUp, .oneArmPushUp: [.pushUps]
        case .handstandPushUp:      [.pikePushUp, .handstand]
        case .planchePushUp:        [.pseudoPlanchePushUp, .planche]

        // Pull
        case .australianRow, .negativePullUp, .hangingKneeRaise: [.deadHang]
        case .pullUps:              [.negativePullUp, .australianRow]
        case .wideGripPullUp, .muscleUps, .oneArmPullUp: [.pullUps]
        case .lSitPullUp:           [.pullUps, .lSit]

        // Legs
        case .squat:                [.wallSit]
        case .jumpSquat, .lunge, .cossackSquat, .nordicCurl: [.squat]
        case .bulgarianSplitSquat:  [.lunge]
        case .shrimpSquat, .pistolSquat: [.bulgarianSplitSquat]

        // Core & static
        case .sidePlank, .hollowBody: [.plank]
        case .lSit, .dragonFlag:    [.hollowBody]
        case .vSit:                 [.lSit]
        case .hangingLegRaise:      [.hangingKneeRaise]
        case .toesToBar:            [.hangingLegRaise]
        case .backLever:            [.hollowBody, .deadHang]
        case .frontLever:           [.backLever]
        case .humanFlag:            [.sidePlank, .backLever]
        case .planche:              [.pseudoPlanchePushUp, .elbowLever]

        // Skill
        case .elbowLever:           [.crowStand]
        case .handstand:            [.crowStand]
        case .pressToHandstand, .handstandWalk: [.handstand]

        // Roots — nothing comes before these.
        case .pushUps, .deadHang, .wallSit, .plank, .sitUp, .crowStand: []
        }
    }

    /// Whether rep depth is a meaningful setting for this movement — true
    /// wherever the tracker gates on a fraction of the person's own range.
    var tunesRepDepth: Bool {
        switch self {
        case .pushUps, .pullUps, .squat, .dip: true
        default: false
        }
    }

    /// One line on what this movement is, shown in the library.
    var summary: String {
        isTimedHold
            ? "Timed hold · \(tier.lowercased()) · \(equipment.displayName.lowercased())"
            : "Counted reps · \(tier.lowercased()) · \(equipment.displayName.lowercased())"
    }
}

/// How a session's result reads — a rep count, a single hold, or a set of
/// them.
enum SessionResult: Hashable {
    case reps(Int)
    case hold(TimeInterval)
    /// Several holds in one set. `best` is what a hold session is judged on;
    /// the total is the sum of every counted hold.
    case holdSet(count: Int, best: TimeInterval, total: TimeInterval)

    var displayValue: String {
        switch self {
        case .reps(let count):
            "\(count) reps"
        case .hold(let duration):
            "\(Self.durationLabel(duration)) hold"
        case .holdSet(let count, let best, _):
            "\(count) holds · \(Self.durationLabel(best)) best"
        }
    }

    /// `m:ss` — minutes unpadded, seconds zero-padded (e.g. "0:38", "1:02").
    static func durationLabel(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// `m:ss.hh` — the same clock with hundredths, for a timer that's actually
    /// running. Whole seconds alone make a live hold look frozen between
    /// ticks, which reads as the app having stopped counting.
    ///
    /// Truncates rather than rounds: rounding would show "0:01.00" at 0.995 s,
    /// so the clock would briefly claim time that hasn't elapsed.
    static func preciseDurationLabel(_ duration: TimeInterval) -> String {
        let clamped = max(0, duration)
        let whole = Int(clamped)
        let hundredths = Int((clamped - Double(whole)) * 100)
        return "\(whole / 60):"
            + String(format: "%02d", whole % 60)
            + String(format: ".%02d", min(99, hundredths))
    }
}
