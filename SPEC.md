# Vision Calisthenics Tracker (iOS)

## Project Overview

An iOS-native, computer-vision fitness application that uses real-time pose
estimation to automatically count reps, time static holds, detect form
breaks, and log synchronized video telemetry for calisthenics training.

## Technical Stack & Architecture

| Layer | Choice |
|---|---|
| Target Platform | iOS 17.0+ (Swift, SwiftUI) |
| ML Engine | Google MediaPipe Tasks Vision (`pose_landmarker_full.task` — 33 3D keypoints, Metal GPU delegate) |
| Camera & Video | `AVCaptureSession` dual-sink pipeline: 1080p MP4 local recording + real-time YUV frame delivery to MediaPipe at 30–60 FPS |
| Math & State Engine | Joint angles from **metric 3D world landmarks** (view-independent — the 2D projection can't measure a joint moving along the camera axis), EMA smoothing, deterministic finite state machines for rep/hold detection |
| Local Persistence | **SwiftData** for session records; flat binary files for per-frame telemetry; MP4s on the filesystem (see "Storage layout" below) |
| Monetization | StoreKit 2 / RevenueCat |
| Feedback | `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` (haptics), `AVAudioPlayer` (short cue sounds), `AVSpeechSynthesizer` (Pro real-time audio coaching) |

## Core Feature Set

### 1. Live Workout HUD & Overlay
- Full-bleed live camera preview with a custom SwiftUI `Canvas` overlay
  rendering a 2px semi-transparent skeleton: `#00FF66` for valid form,
  `#FF3366` for a form-break warning.
- High-contrast, large-format typography (80pt+) for glanceable rep counts
  and hold timers, readable from 6–10 feet away.
- **Angle-agnostic by design.** Prop the phone anywhere and start training —
  side-on, head-on, or any angle between. There is no "correct" position to
  get right first. The only requirement is that most of the body is visible.
  Onboarding therefore checks *framing* (is your whole body in shot?), never
  a prescribed angle.

### 2. Movement Algorithms

**How measurement works is specified in [POSE.md](POSE.md)** — coordinate
spaces, the angle primitive, confidence tiers, calibration, and the rules a
new tracker must follow. That document is normative; this section only says
what each movement does.

- **Push-Up Counter** — `TOP → BOTTOM → TOP` state machine on the elbow
  angle, where the gates are placed as fractions into *that person's own*
  observed range rather than at fixed angles (POSE.md Law 3). Gated on the
  torso reading more than ~45° off vertical, so standing and moving your arms
  — which sweeps the identical elbow range — never counts. A lockout must be
  observed before the counter arms, so settling into position isn't a free
  rep. Hip-sag warning if Shoulder-Hip-Ankle strays more than 15°, and only
  when the body isn't end-on to the camera and the ankles are genuinely
  visible (POSE.md Law 5).
- **Handstand Timer** — the clock runs whenever the body is inverted, judged
  from world-space joint heights, with tucked and piked handstands counting.
  Straightness is **scored, never required** (POSE.md Law 4): line quality is
  a continuous 0…1 statistic surfaced live and in review, taken from the
  worst joint rather than the average. Only a sustained, severe deviation is
  called out, and even then the clock keeps running.

### 3. Post-Workout Telemetry & Video Review
- Split-view screen: local MP4 player with a toggleable MediaPipe skeleton
  overlay.
- Timeline scrubber with color-coded event markers (green = completed rep,
  red = form break).
- Frame-accurate scrubbing queries the SQLite telemetry log at timestamp
  `T` to render the exact joint angles at that instant.

### 4. Tiered Business Model
| Tier | Price | Includes |
|---|---|---|
| Free | $0 | Unlimited push-up and handstand tracking, basic rep/hold counters, 7-day local history |
| Pro | $4.99/mo | Expanded movements (planche, pull-ups, muscle-ups, L-sits), tempo analytics, real-time audio coaching, long-term progression graphs, cloud sync |

### 5. Multisensory Feedback
Since the HUD is designed to be glanceable from 6–10 feet, feedback shouldn't
depend on the user looking directly at the screen — haptic, sound, and
animation should fire together as one bundle per event, not in isolation.

- **Haptics** — `UIImpactFeedbackGenerator` for a light tap on each completed
  rep; `UINotificationFeedbackGenerator` (success/warning) for a completed
  hold or a form-break warning.
- **Sound** — short pre-recorded cues (rep ding, PR chime) via
  `AVAudioPlayer`/`AudioServicesPlaySystemSound`. Distinct from the Pro
  **real-time audio coaching** feature, which uses `AVSpeechSynthesizer` to
  generate spoken cues (rep counts, form corrections) on the fly rather than
  playing fixed clips.
- **Animation** — since the HUD overlay is already a SwiftUI `Canvas`, most
  of this is native: `withAnimation`/spring animation for a scale-bounce on
  the rep counter, and color transitions between the `#00FF66` valid-form
  and `#FF3366` warning-form skeleton strokes.

## Storage layout

Originally specced as "SQLite for everything". Split into three stores
instead, because the three kinds of data have very different shapes:

| Data | Volume | Where |
|---|---|---|
| Session records (date, movement, reps, form breaks) | Tiny, queried constantly | SwiftData |
| Per-frame landmarks (33 × x/y/z at 30–60 FPS) | ~24 KB/s | Flat binary file per session |
| Video recordings | ~100–150 MB per 10 min | Filesystem; the record stores the filename |

A row per frame would mean thousands of inserts per second while the CPU is
already saturated with pose inference. Fixed-size records in a flat file make
writes a plain append and let the review scrubber seek to a timestamp instead
of running a query — the same property that makes frame-accurate scrubbing
(§3) cheap.

- **Telemetry format** — 8-byte header (`CVT1`, landmark count), then 400-byte
  frames: `Int32` timestamp + 33 × (x, y, z) `Float32`. Read back memory-mapped
  so a long session doesn't have to sit in RAM to be scrubbed.
- **Retention** — recordings are excluded from iCloud backup and pruned to the
  tier's history window (Free: 7 days), which keeps the library from filling
  the device. Cloud sync is a separate Pro feature.

## Future Roadmap & Backend Integrations
- **Database & Auth** — Supabase / PostgreSQL (Apple/Google Sign-In, profile
  management).
- **Global Leaderboards** — verified rankings via serverless validation of
  uploaded landmark coordinate logs.
- **Video Uploads** — Cloudflare Stream or Mux for adaptive HLS video feeds
  and community social sharing.

## Repository Target Architecture

```
Calisthenics Vision/
├── Calisthenics Vision.xcodeproj/
└── Calisthenics Vision/
    ├── App/                     # App entry point, root scene
    ├── Camera/                  # AVCaptureSession pipeline, dual-sink (record + frame delivery)
    ├── Pose/                    # MediaPipe wrapper, landmark → joint-angle math, EMA smoothing
    ├── Movements/               # Per-movement finite state machines (push-up, handstand, ...)
    ├── HUD/                     # Live overlay Canvas, rep/timer UI
    ├── Review/                  # Post-workout video player, timeline scrubber, telemetry query
    ├── Persistence/             # SQLite schema, DAOs, MP4 file references
    ├── Monetization/            # StoreKit 2 / RevenueCat, tier gating
    ├── Onboarding/              # Camera-angle wizard
    └── Assets.xcassets/
```

*(Directory names are a proposed convention — adjust to match Xcode groups
as the project is scaffolded.)*
