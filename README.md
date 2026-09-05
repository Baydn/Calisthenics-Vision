# Calisthenics Vision

**Your phone, propped up anywhere, counts your reps and times your holds —
no wearable, no manual logging, no "get in position first."**

Calisthenics Vision is an iOS app that uses on-device computer vision to
track calisthenics training in real time: rep counting, hold timing, and
form feedback, all from a single camera at whatever angle you happened to
prop it up.

> 📹 Demo GIFs are on the way — the app is running end-to-end on device
> today, screen capture is next.

## Why

Most fitness-tracking apps ask you to follow their setup: stand here, face
the camera like this, then start. Calisthenics Vision works the other way —
prop the phone up wherever it lands, side-on, head-on, or anywhere in
between, and just train. The only requirement is that most of your body is
in frame.

That constraint drives the core technical decision: joint angles are
measured from **3D world landmarks**, not the 2D image projection. Filmed
head-on, a 2D skeleton collapses the torso to almost nothing and can't
recover the geometry — 3D can.

## What it does today

- **Push-ups** — full rep state machine, hip-sag detection, thresholds that
  calibrate to *your* range of motion rather than a fixed angle
- **Handstands** — hold timing per attempt, line-quality scored continuously
  (never gated — a wobbly handstand still counts as a handstand)
- Live skeleton overlay, spoken and haptic rep/hold feedback, sound cues
- Post-workout video review with a frame-accurate skeleton and angle charts
  synced to the recording
- Session history, calendar, and per-movement progress tracking

Pull-ups, squats, and dips are tracked under the hood; muscle-ups, L-sits,
and planche are catalogued but not yet wired up to a tracker — they're
next.

## How it works

| Layer | Choice |
|---|---|
| Platform | iOS 17+, Swift, SwiftUI |
| Pose estimation | Google MediaPipe Tasks Vision, Metal GPU delegate, 33 3D keypoints |
| Capture | `AVCaptureSession`, dual-sink: 1080p recording + live frame delivery |
| Measurement | Joint angles from 3D world landmarks, EMA-smoothed, deterministic state machines per movement |
| Persistence | SwiftData (sessions), flat binary telemetry files (per-frame landmarks), filesystem (video) |

The measurement layer follows a written set of rules — coordinate spaces,
calibration, what a rep counter is and isn't allowed to gate on — in
[POSE.md](POSE.md). The full architecture and feature spec is in
[SPEC.md](SPEC.md).

Every piece of movement-detection logic (angle math, rep state machines,
hold timers) is compiled into a standalone `swiftc` test harness and
verified independently of the app, including that the same geometry
measures identically side-on, head-on, oblique, and inclined.

## Getting started

```bash
git clone https://github.com/Baydn/Calisthenics-Vision.git
cd Calisthenics-Vision
pod install
open "Calisthenics Vision.xcworkspace"
```

Open the `.xcworkspace`, not the `.xcodeproj` — the project uses CocoaPods
for MediaPipe. Requires Xcode 16+ and a physical device for camera testing
(the Simulator has no camera).

## Status

Actively in development, in daily use for real training sessions on
device. Camera → pose estimation → rep/hold tracking → history → session
review is a complete loop. Design for all core screens is finished; more
movements and the social/community layer are in progress.

---

Built solo by [Baydon](https://github.com/Baydn).
