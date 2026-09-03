# Pose & Movement Measurement — canonical rules

How this app measures a body and decides that something happened. Every
tracker follows these rules; a new movement is written by applying them, not
by inventing its own approach.

Read this before touching anything in `Pose/` or `Movements/`. Product
context is in [SPEC.md](SPEC.md); current build state is in `CLAUDE.md`.

The rules exist because each one is a bug we already shipped. The failures
are catalogued at the bottom — if you're about to break a rule, read its
entry first.

---

## 0. The one product constraint everything derives from

**The app must work from any camera angle, with no setup step.** Prop the
phone, start training. The only requirement is that most of the body is
visible.

That single constraint is why the math looks the way it does. Almost every
rule below is a consequence of it.

---

## 1. Coordinate spaces

Three spaces exist. Using the wrong one is the single most common bug in
this codebase.

| Space | Type | Units | Origin | Use it for |
|---|---|---|---|---|
| **Image normalized** | `Pose.points: [CGPoint]` | 0…1 per axis | frame top-left | **Drawing only** |
| **Aspect-corrected 2D** | `corrected(_:)`, private | 0…1 × aspect | frame top-left | Legacy fallback when world points are missing |
| **Metric 3D world** | `Pose.worldPoints: [SIMD3<Double>]` | metres | hip midpoint | **All measurement** |

### Law 1 — Measure in 3D, draw in 2D. Never mix.

`Pose.angle(at:from:to:)` prefers world points and only falls back to 2D.
Anything that produces a number a state machine acts on must go through it
or use `worldPoint(_:)` directly.

Why: the 2D projection cannot measure a joint whose motion runs along the
camera axis. Filmed head-on, a push-up's torso collapses to a few pixels
and no amount of 2D trigonometry recovers it. World landmarks are
view-independent, which is what makes Law 0 achievable at all.

Corollary: **never feed world coordinates to a renderer.** They are metres,
not fractions of a frame. The review overlay once drew them as image
fractions and produced garbage. This is why `TelemetryStore` persists both
spaces (CVT2, 5 floats/landmark: `x, y` normalized + `wx, wy, wz` metric).

Axis conventions in world space:
- **y runs downward**, matching the image. "Above" means a *smaller* y.
- **z is depth**, and it is the weakest axis — see Law 5.

---

## 2. The primitives

Everything is built from four measurements. Add new ones here rather than
computing geometry inside a tracker.

### `angle(at:from:to:)` → degrees, 0…180
Interior angle at a vertex. The one primitive behind every movement rule.
A straight limb or body reads ~180°; deviation either way is flexion.

```
elbow = angle(at: .leftElbow, from: .leftShoulder, to: .leftWrist)
hip   = angle(at: .leftHip,   from: .leftShoulder, to: .leftAnkle)
```

Returns `nil` when a landmark is missing or the vectors are degenerate.
**`nil` means unknown, never zero** — see Law 8.

### `isTorsoHorizontal` → `Bool?`
Verticality of the shoulder→hip vector: `abs(torso.y) / length`. Upright ≈ 1,
lying flat ≈ 0. True below **0.7** (more than ~45° off vertical).

This is the orientation gate. It distinguishes a push-up from someone
standing and bending their arms, which sweeps an identical elbow range.

Note it measures *the body's* orientation, not the camera's. A torso running
straight into depth is still horizontal. Comparing image x to image y here —
the obvious implementation — silently reintroduces a required camera angle.

### `bodyLineDepthFraction` → `Double?`
How much of the shoulder→ankle line lies along the camera axis:
`abs(line.z) / length`, 0…1. Above **0.6** the body is pointed end-on and
posture is not measurable. See Law 5.

### `worldMidpoint(_:_:)`
Bilateral joints are averaged before comparing heights or directions.
Single-sided comparisons flip meaning when the body rotates.

---

## 3. Confidence

### Weakest-link rule
A joint triple is only as trustworthy as its least visible landmark:

```swift
private func confidence(_ pose: Pose, _ joints: PoseJoint...) -> Float {
    joints.reduce(Float(1)) { min($0, pose.confidence[$1.rawValue]) }
}
```

### Side selection
Measure on whichever side is more visible, then check the *better* side
against the threshold. Filmed side-on, one arm is occluded by the body
essentially always.

### Two thresholds, deliberately different

| Purpose | Constant | Value | Rationale |
|---|---|---|---|
| Counting a rep / timing a hold | `minConfidence` | **0.5** | A missed rep reads as a broken app |
| Judging form | `formConfidence` | **0.8** | A wrong warning is worse than no warning |

MediaPipe emits an extrapolated landmark for a cropped-out ankle rather than
nothing. With the phone close, legs leave frame constantly. Form judged off a
guessed ankle is the "keep your hips in line" false positive that made the
feature untrustworthy.

---

## 4. Smoothing

`PoseSmoother` applies an EMA (`factor = 0.6`) to **both** point arrays
before any tracker sees the pose. Raw landmarks jitter enough to cross a
threshold repeatedly in a few frames, which double-counts reps.

Smooth once, centrally, upstream of the state machines. Do not smooth again
inside a tracker, and do not let a tracker see raw poses.

---

## 5. What you are allowed to say

### Law 5 — Say nothing you cannot measure.

Depth is the weakest axis of a monocular estimate. Joint angles measured
across the image survive that fine — elbow flexion is measured across the
body, not along it — but **straightness measured end-on is dominated by z
error** and will read as bent no matter how straight the person is.

So the two judgements are gated differently:

| Judgement | Gate |
|---|---|
| Counting reps / timing holds | Orientation only. Runs at any camera angle. |
| Form and posture feedback | Also requires `bodyLineDepthFraction ≤ 0.6` and `formConfidence` landmarks. Goes quiet otherwise. |

Every tracker exposes `isFormMeasurable` (or equivalent in `diagnostics`) so
the HUD can explain silence rather than appearing to approve.

**An unmeasurable pose is not a failing one.** When measurement becomes
impossible, clear the failure state and emit `.formRecovered` — otherwise
the skeleton stays stuck red because the legs left the frame.

---

## 6. Thresholds

### Law 3 — Thresholds calibrate to the person. Never ship a fixed angle.

Fixed gates do not survive contact with real bodies. Arm proportions, how far
someone locks out, how deep they go, and residual landmark error all shift
the numbers. A literal 160° lockout means a person whose arms read 150° at
the top counts **zero reps forever**.

The pattern, from `PushUpTracker`:

1. Observe the driving angle's running extremes, with slow decay
   (`0.05°/frame` ≈ 1.5°/s) so one unusually deep rep doesn't set the gates
   permanently.
2. Refuse to count until total travel exceeds `minimumRange` (**45°**), so
   fidgeting in position can't calibrate its way into counting.
3. Place gates as *fractions into the observed range*, not absolute angles.

| Gate | Fraction | Why asymmetric |
|---|---|---|
| Bottom (depth) | **0.42** | Loose. Depth coaching belongs in form feedback, not in withholding the count. |
| Top (lockout) | **0.25** | Tighter. The top of a rep is unambiguous and it's what separates consecutive reps. |

Nominal angles (`lockoutAngle = 160`, `bottomAngle = 90`) survive only as
pre-calibration seeds.

---

## 7. Counting vs. scoring

### Law 4 — Never withhold the count for form.

**An uncounted rep reads as "the app is broken", not as "go deeper."** This
is the single most damaging failure mode the app has, and it has been
introduced twice — once for push-ups (fixed depth gate) and once for
handstands (165° straightness gate that timed nothing for a real hold).

The split:

- **Did it happen?** — geometry only. Count it.
- **How well?** — a continuous 0…1 score, reported alongside, never a gate.

`MovementProgress.formQuality` carries the score. Handstands compute it as:

```swift
let worstDeviation = angles.map { abs(idealAlignment - $0) }.max() ?? 0
return max(0, 1 - worstDeviation / 90)
```

### Law 7 — Score the worst joint, not the average.

Averaging a perfect shoulder with a 40° piked hip scored **78%** — a bad
handstand reading as a good one. A line is only as good as its biggest bend,
which is also how a coach reads it. This was caught by a test, not by eye.

Time-weight the running mean (`quality × seconds`), not frame-count-weight,
so a dropped frame doesn't skew the score.

---

## 8. Time

Holds accrue **frame to frame only**:

```swift
guard let previous = lastTimestampMs else { return nil }
let delta = timestampMs - previous
guard delta > 0, delta <= maxFrameGapMs else { return nil }   // 500 ms
```

Losing the pose sets `lastTimestampMs = nil`, which pauses the clock rather
than silently crediting a minute spent out of frame. Never compute a hold as
`now − startTime`.

Whole-second crossings emit `.holdTick(seconds:)` for haptics and audio.

### A hold set is many holds

A session is a *set of attempts*, not one unbroken hold — you come down,
shake out, and go again. Leaving position closes the attempt; re-entering
opens a new one, each timed and scored on its own.

Two guards keep that from turning noise into data:

| Guard | Constant | Why |
|---|---|---|
| Grace window before an attempt closes | `holdGapToleranceMs` **400 ms** | One dropped frame would otherwise chop a clean hold into fragments |
| Shortest attempt worth recording | `minimumHoldSeconds` **1.0 s** | A wobble on the way up isn't a hold, and listing it buries the real attempts |

Discarded time is never credited: `holdDuration` sums the *recorded* holds
plus the one in progress, so a rejected blip contributes nothing.

`finish()` closes whatever is still open. Without it, stopping the recording
while still inverted would silently discard the attempt in progress.

### Kick-up success

Every entry into inversion is an attempt, counted in `beginHold` whether or
not it turns into anything. The ones that never reach `minimumHoldSeconds`
are discarded as holds but still counted as attempts — which is exactly what
makes a success rate meaningful, since the failures *are* the discarded ones.
A landed kick-up is a hold of at least `HoldSegment.kickUpSuccessSeconds`
(**2 s**): getting up and holding two seconds is a landed kick-up even if it
isn't a good handstand yet.

The grace window applies first, so a dropped frame mid-hold cannot inflate
the attempt count by splitting one kick-up into two.

**The set's headline number is the best single hold, not the total.** Six
five-second handstands are not a thirty-second handstand, and any personal
record or trend line that sums them is lying about progress.

---

## 9. Hysteresis

### Law 6 — Every transition needs a dead band or a dwell count.

Landmark noise sitting exactly on a threshold will otherwise fire
continuously.

| Mechanism | Where | Value |
|---|---|---|
| Dwell margin around a rep gate | `PushUpTracker.dwellMargin` | `max(5°, range × 0.1)` — scales with the person |
| Consecutive bad frames before flagging form | push-up `framesToFlag` | 12 (~0.4 s) |
| Same, for a hold | handstand `framesToFlag` | 20 (~0.7 s) |

Form breaks fire **once per episode** (`badFormFrames == framesToFlag`, not
`>=`), then latch until recovery.

---

## 10. Law 8 — `nil` is unknown. `false` is measured-and-negative.

Optionals in this layer mean "not measurable", and callers must not coerce
them. `?? 0` on an angle silently converts "I can't see the hip" into "the
hip is folded at 0°" and produces a confident wrong warning. Diagnostics show
`—` for nil; they never show a fabricated number.

Same principle at the movement level: `Movement.makeTracker()` returns `nil`
for pull-ups, muscle-ups, L-sits and planche, and the HUD says the movement
isn't tracked yet. It does **not** substitute a push-up counter that would
appear to work while counting nothing. Keep that pattern when adding
movements.

---

## 11. Writing a new tracker

Conform to `MovementTracker`. `update(pose:timestampMs:)` runs in this order —
deviating from it is how bugs get in:

1. **Handle `nil` pose.** Clear cached angles, pause any clock, drop out of
   position. Return `nil`.
2. **Measure.** Compute the driving angles on the more-visible side and cache
   them for `diagnostics`.
3. **Orientation gate.** Is the body in a posture this movement can even
   occur in? On a transition into or out of position, reset the phase so a
   half-finished rep can't complete later, and clear form state.
4. **Calibrate.** Feed the driving angle into the observed range.
5. **Form.** Check measurability first, then the judgement. Return early on
   an emitted event.
6. **Advance the state machine.** Return at most one event per frame.

Also required:
- Populate `TrackerDiagnostics` honestly — `isReady`, both labelled angles,
  and a `note` explaining *why* nothing is counting ("calibrating…",
  "waiting for inversion", "gates 118°/152° · form off").
- `reset()` must clear calibration and clocks, not just totals.
- Trackers are `struct`s. `TrainIdleView` copies, mutates, writes back.

---

## 12. Verification

There is no XCTest target. Pure-logic files compile into a standalone
harness, which is how all of this is actually tested:

```
swiftc main.swift "<src>/Pose/PoseSkeleton.swift" "<src>/Movements/PushUpTracker.swift" ... -o test
```

Synthetic poses are built in **world space** and rotated, so a single fixture
generator produces every camera angle.

### `Movements/` stays pure

Nothing in `Movements/` may import app state — no `UserDefaults`, no
`AppSettings`, no SwiftUI. That directory compiles into the standalone
harness, and the harness is the *only* way this app's measurement is
verified; a settings dependency would break it silently.

User preferences are applied one level up, in `TrackerFactory`. A tracker's
own defaults are the ones the tests exercise.

### Mandatory matrix for any new tracker

| Case | Asserts |
|---|---|
| Side-on, head-on, oblique, inclined | Identical counts — Law 0 |
| Rolled about the camera axis (0/30/60°) | Identical counts |
| Wrong orientation (standing, lying) | Counts **zero** |
| Partial rep / abandoned mid-way | Counts zero |
| Enter mid-movement | No free rep before the first lockout |
| Poor form but real movement | **Still counted**, scored lower — Law 4 |
| Confidence below threshold | No form warning; counting unaffected |
| Frame gap mid-hold | Gap not credited |
| Reset | Clears calibration, not just totals |

For a segmented hold additionally: several attempts recorded separately, rest
between them uncounted, a brief dropout not splitting one hold, a sub-second
blip discarded along with its time, and finishing mid-hold keeping it.

Current coverage: **38 push-up checks, 46 handstand checks**, all passing.

A fixture that shares a bug with the code proves nothing — the aspect-ratio
distortion bug passed 14 tests because the fixtures were generated in the
same distorted space. Fixtures must be built from physical reasoning
(metres, real limb lengths), never from a recording of the code's own output.

`VideoFileSource` replays a real clip through the identical pipeline. A clip
of known rep count is a repeatable assertion a live camera can never provide.

---

## 13. Failure catalogue

Every rule above, and the bug that earned it.

| Symptom | Root cause | Rule |
|---|---|---|
| Reps counted while standing and waving arms | No orientation gate; elbow sweep is identical | §2 `isTorsoHorizontal` |
| Zero reps facing the camera; hip reads "—" | Angles from the 2D projection; torso collapses to nothing head-on | Law 1 |
| Angles wrong for anything not axis-aligned | x÷width vs y÷height are different real distances; fixtures shared the distortion so tests passed | Law 1, §12 |
| Zero reps for a real person | Fixed 160°/90° gates | Law 3 |
| Red "keep your hips in line" while correctly in position | Straightness measured along the depth axis | Law 5 |
| Warning stuck on after the legs left frame | Unmeasurable treated as failing | Law 5 |
| Handstand timed nothing while actually held | Straightness used as a gate on the clock | Law 4 |
| Bad handstand scored 78% | Averaging masked a 40° pike | Law 7 |
| Review skeleton drawn nowhere near the body | World metres rendered as image fractions | Law 1 |
| Replay stretched | Writer sized from the sensor's landscape format while the connection was rotated to portrait | — (`VideoRecorder` sizes from the first real frame) |
| Preview sideways in portrait, upside down in landscape | `RotationCoordinator` built with `previewLayer: nil` returns 0° forever — the native sensor orientation, which is landscape | — (rotation follows the *interface*; see `CameraController.rotationAngle(for:)`) |
| Skeleton beside the body in landscape | Overlay assumed a 9:16 source while the data output emits physically rotated 16:9 buffers | Law 1 (draw in the space the frames are actually in) |
| SIGSEGV on the first device build | Main-actor state read from the capture queue | `CLAUDE.md` concurrency invariant |
| Random crash when switching tabs | The Train screen owned the capture stack, so every tab switch tore down an `AVCaptureSession` and a MediaPipe graph; `AVCaptureVideoDataOutput` doesn't retain its delegate, so a frame landed on freed memory | — (`CaptureStack`, owned above the tab bar) |
| A set of short holds reported as one long hold | Personal records read the session total rather than the best attempt | §8 |

---

## 14. Constants, in one place

Change these deliberately; each has a reason above.

**Pose** — verticality gate `0.7` · depth-dominant `0.6` · EMA factor `0.6`

**PushUpTracker** — `lockoutAngle 160` `bottomAngle 90` (seeds only) ·
`maxHipDeviation 15` · `minimumRange 45` · `bottomGateFraction 0.42` ·
`topGateFraction 0.25` · `minConfidence 0.5` · `formConfidence 0.8` ·
`maxBodyLineDepth 0.6` · `framesToFlag 12` · range decay `0.05`/frame

**HandstandTracker** — `idealAlignment 180` · `warnDeviation 45` (warn only,
never a gate) · `minConfidence 0.5` · `framesToFlag 20` · `maxFrameGapMs 500`
· `holdGapToleranceMs 400` · `minimumHoldSeconds 1.0` ·
`HoldSegment.kickUpSuccessSeconds 2.0` · quality taper `90°` → 0
· inversion separation `0.3 m`
