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
| Math & State Engine | Vector dot products for 2D joint-angle extraction, EMA keypoint smoothing, deterministic finite state machines for rep/hold detection |
| Local Persistence | SQLite (indexed timestamps, joint-angle telemetry logs, MP4 file references) |
| Monetization | StoreKit 2 / RevenueCat |
| Feedback | `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` (haptics), `AVAudioPlayer` (short cue sounds), `AVSpeechSynthesizer` (Pro real-time audio coaching) |

## Core Feature Set

### 1. Live Workout HUD & Overlay
- Full-bleed live camera preview with a custom SwiftUI `Canvas` overlay
  rendering a 2px semi-transparent skeleton: `#00FF66` for valid form,
  `#FF3366` for a form-break warning.
- High-contrast, large-format typography (80pt+) for glanceable rep counts
  and hold timers, readable from 6–10 feet away.
- Onboarding camera-angle wizard to verify optimal 45°–90° side-profile
  framing before a session starts.

### 2. Movement Algorithms
- **Push-Up Counter** — state machine: `TOP` (≥160°) → `BOTTOM` (≤90°) →
  `TOP` (lockout). Hip-sag warning if Shoulder-Hip-Ankle alignment strays
  more than 15°.
- **Handstand Timer** — inversion detection (wrists below hips/ankles in
  image space) combined with a line-alignment hold timer across
  Wrist-Shoulder-Hip-Ankle (≥165°).

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
