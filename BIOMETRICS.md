# Per-movement biometrics

What each movement is *counted on*, what it's *scored on*, and what we
deliberately don't say about it.

This is the bridge between three documents that already exist:
[POSE.md](POSE.md) is normative and says how measurement works at all;
`MOVEMENTS.md` is the strategic catalogue (difficulty, build order, what's
worth supporting); this file is the engineering answer to "so what exactly do
we measure for a dip?" Nothing here overrides POSE.md.

**Keep it current.** A tracker landing without its row updated here is how the
three views of a movement drift apart.

---

## 0. How to read a row

Every movement gets the same five fields, because the same five questions
decide a tracker:

| Field | Question | Law |
|---|---|---|
| **Counted on** | The one measurement that *is* the movement | Law 9 |
| **Gate** | How we know you're in the position at all | §11 step 3 |
| **Scored** | Form, reported alongside, never withheld from the count | Law 4, Law 7 |
| **Quiet about** | What we refuse to claim | Law 5 |
| **Review** | Which overlays and charts earn their place | — |

Two rules do most of the work here:

- **Count the thing the movement is, not a proxy for it** (Law 9). A push-up
  is the chest going down. The elbow angle correlates and is easier to reach
  for, and counting on it let anyone fake reps by waving a hand.
- **Say nothing you cannot measure** (Law 5). Several biometrics a coach
  would name are simply not in a 33-point pose. They are listed as "quiet
  about" rather than quietly approximated.

---

## 1. What the camera can and can't give us

Worth stating once, because it decides half the rows below.

**Available.** Metric 3D joint centres for shoulders, elbows, wrists, hips,
knees, ankles, plus the nose. Angles between any three of them. Heights of
any of them relative to each other. The lower of a pair (which hand is
planted, which foot is down).

**Not available, and no amount of cleverness fixes it:**

| Wanted | Why not |
|---|---|
| **Scapular protraction / retraction** | One coarse point per shoulder. Protraction is 2–4 cm of scapular travel, and filmed side-on it runs along the depth axis — the weakest one. There is no honest number in it. |
| **Grip** (pronated / supinated / neutral) | Three coarse hand points, no orientation. A chin-up and a pull-up are the same pose. |
| **Hand width apart from wrist separation** | Wrist separation *is* visible, so wide-grip is separable; "hands stacked" vs "hands together" is not. |
| **Spinal segmentation** (hollow vs flat back) | No spine landmarks. Shoulder-hip-ankle is the only line we have. |
| **Muscular tension / effort** | Not visible at all. Tempo is the closest honest proxy. |
| **Ground contact** | No floor plane. The nearest honest substitute is *the part of the body known to be on the ground* — the planted hand or foot — which is how the planche and push-up measurements work. |

---

## 2. Ground references, since several rows depend on one

There is no floor in a pose. Where a measurement needs one, use the body part
that is on the floor, and pick the one that **stays** there:

| Movement family | Ground reference | Watch out for |
|---|---|---|
| Push-ups, planche, elbow lever | The **lower** of the two wrists | Their midpoint moves when a hand lifts — that was the hand-wave exploit |
| Squats, lunges, standing work | The **lower** of the two ankles | A raised heel is a real fault, not a reference |
| Dips, hanging work | The bar (= the wrists) | Both hands leave together or you fall, so the midpoint is safe here |
| Handstand | The **lower** of the two wrists | Same as push-ups |

---

## 3. Built today

Seven trackers. These rows describe what ships, not what's planned.

### Push-up — `PushUpTracker`

| | |
|---|---|
| **Counted on** | **Chest height above the planted hand**, as a fraction of that arm's length. ~0.95 at the top, ~0.39 chest-to-floor. Not the elbow. |
| **Gate** | `isTorsoHorizontal` — torso more than ~45° off vertical. Separates a push-up from standing and bending your arms, which sweeps an identical elbow range. |
| **Scored** | Hip sag: shoulder-hip-ankle more than 15° off straight, only while posture is measurable. Depth consistency and tempo, post-hoc. |
| **Quiet about** | Hand width, elbow flare direction (needs the depth axis side-on), scapular position. |
| **Review** | Angle overlay (**both elbows** — one arm giving out before the other is the thing worth seeing). No Line overlay: a push-up has a body line and sagging it is a fault, but nobody reviews a push-up to study their plank. Depth meter replays. |

The elbow angle is still measured and displayed. Nothing counts on it.

### Pull-up — `PullUpTracker`

| | |
|---|---|
| **Counted on** | Elbow angle, gated at a fraction into the person's own range. |
| **Gate** | Upright torso **and** both wrists above the shoulders by 0.15 m. |
| **Scored** | Kipping: shoulder-hip-knee more than 35° off straight (generous — a little swing is normal). |
| **Quiet about** | Grip (chin-up is indistinguishable), chin-over-bar as such — the *bar* isn't a landmark, so height is inferred from the elbow rather than seen. |
| **Review** | Angle overlay (both elbows). No Line. Depth meter replays, filling **upward**, since a pull-up's deep end is its top. |

**Known gap.** Counting on the elbow has the same shape of weakness the
push-up had — but letting go of a bar drops you off it, so there's no free
version of the exploit. Revisit if bar-height inference ever lands.

### Dip — `DipTracker`

| | |
|---|---|
| **Counted on** | Elbow angle. |
| **Gate** | Upright torso with the hands *beside* the hips — not overhead, which is what separates it from a pull-up. Deliberately doesn't require the wrist to stay below the shoulder, or it would drop out at the bottom of every good rep. |
| **Scored** | **Shoulder below elbow** at the bottom — the standard for a full dip. Scored and called out, never gated. |
| **Quiet about** | Torso lean (forward lean is a legitimate chest-dip variation, not a fault), ring turnout. |
| **Review** | Angle overlay (both elbows). No Line. Depth meter replays. |

### Squat — `SquatTracker`

| | |
|---|---|
| **Counted on** | Knee angle. |
| **Gate** | Upright torso with the ankles below the hips. |
| **Scored** | **Knee valgus** as knee separation ÷ ankle separation, judged only past 40% depth, and silent when the stance runs along the camera axis. A ratio, so it survives any camera distance. |
| **Quiet about** | Hip crease below knee (the crease isn't a landmark — knee angle is the honest stand-in), heel lift, foot rotation, spinal flexion. |
| **Review** | Angle overlay (both knees). No Line. Depth meter replays. |

### Handstand — `HandstandTracker`

| | |
|---|---|
| **Counted on** | Nothing — it's a hold. Time accrues frame to frame while inverted, as a **set of attempts**. |
| **Gate** | Ankles and hips above the shoulders, with a real vertical separation so lying flat doesn't qualify. |
| **Scored** | Line quality: worst of the shoulder (wrist-shoulder-hip) and hip (shoulder-hip-ankle) angles against 180°, time-weighted. **Worst joint, never the average** — averaging a good shoulder with a 40° pike scored a bad handstand at 78%. Kick-up success rate is derived from the attempts that never reached `minimumHoldSeconds`. |
| **Quiet about** | Wrist stacking, finger pressure, hollow vs arch (no spine). |
| **Review** | **Line overlay against a plumb line** — straight but leaning is still a fault and only a vertical reference shows it. Shoulder and hip angle charts. No depth meter. |

### Planche — `PlancheTracker`

| | |
|---|---|
| **Counted on** | Nothing — a hold, segmented like the handstand. |
| **Gate** | `PlancheGeometry`: locked elbows, **the lean** (shoulders out past the hands — if they stay over the wrists it isn't a planche), body roughly level, and the **feet above the hands**, which is what separates it from a pseudo planche push-up. |
| **Scored** | **Level first** (hips riding high is the universal cheat; the gymnastics standard treats 45° off level as failed), **straight second**, and straightness only where the legs are extended — a tuck is folded on purpose. Worst of the two. |
| **Quiet about** | **Scapular protraction** — a real judging criterion, genuinely not measurable (see §1). Posterior pelvic tilt, for the same reason. |
| **Review** | **Line overlay against a level reference**, not end-to-end: straight-but-tilted is precisely the fault an end-to-end line can't show. Angle overlay at the shoulder, drawn white — see §6 for why it has no bands. Charts: **OFF LEVEL** then **OFF STRAIGHT**, the same two the tracker scores. |

**A planche's shoulder wants to be closed at ~60°, not open at 180°.** That
angle *is* the lean. Scoring it against straight — copied from the handstand —
gave a textbook planche zero.

### Planche push-up — `PlanchePushUpTracker`

| | |
|---|---|
| **Counted on** | Elbow angle, on the planche gate. |
| **Gate** | The planche's, with the arm left out of it, because the arm is the thing being counted. Hip and hand drops widened to survive the bottom of a rep. |
| **Scored** | Level and straight, as the planche. |
| **Quiet about** | As the planche. |
| **Review** | Angle overlay (both elbows). Depth meter replays. |

---

## 4. Not built — what each would need

Ordered by how ready the measurement is, not by difficulty.

### Ready: the measurement already exists

| Movement | Counted on | Gate | Scored | Quiet about |
|---|---|---|---|---|
| **Plank** | Hold time | Torso horizontal, forearms or hands down, hips not folded | Hip line vs 180°; **level** (hips sagging or piking) | Bracing, breathing |
| **Dead hang** | Hold time | Upright, wrists overhead, ankles below hips | Active vs passive: shoulder-to-ear distance changes with elevation — the one shoulder measure we *can* see | Grip fatigue |
| **Wall sit** | Hold time | Knees ~90°, torso upright, ankles below knees | Knee angle held near 90°; thigh level | Wall contact (not visible) |
| **Sit-up** | Hip angle (shoulder-hip-knee) | Lying, knees bent | ROM; tempo | Neck strain, foot anchoring |
| **Australian row** | Elbow angle | Torso horizontal-ish, wrists overhead of chest, feet down | Body line; ROM | Bar height |
| **Negative pull-up** | **Descent duration** — the point of the exercise, so time is the count, not reps | Pull-up's gate | Descent evenness (tempo variance) | — |
| **Pike push-up** | Elbow angle | Torso folded (hip angle < ~120°), hands and feet down | Pike depth (hip angle held); head travel | Head contact with floor |
| **Lunge / split squat** | Front-knee angle | Upright, **ankles split** in depth or width | Per-side; front-knee valgus; torso upright | Which leg is "front" without tracking identity across reps |

### Needs one new capability

| Movement | Missing piece |
|---|---|
| **Muscle-up** | A **transition** state machine — pull / transition / dip are three phases with durations, not one rep gate. `MovementProgress` has no phase concept. |
| **L-sit** | A hold whose ideal hip angle is **90°, not 180°**. Every scoring function currently assumes straight is good. Needs an ideal-angle parameter, then it's easy. |
| **Front lever / back lever** | Same as the planche (level + straight against gravity) with a hanging gate. Mostly a gate change; the scoring is `PlancheTracker`'s. |
| **Hollow body / V-sit / dragon flag** | Ideal-angle scoring like the L-sit, plus the fact that the *hip angle changes on purpose* through some of them. |
| **Handstand push-up** | Rep counting *while inverted* — the handstand gate plus the push-up's elbow machinery. Two existing halves; nobody has bolted them together. |
| **One-arm push-up / one-arm pull-up / pistol / archer** | **Asymmetry support.** Every tracker picks the more visible side, which on these silently measures the easy limb. Needs per-side reps and per-side records — a `MovementProgress` change, flagged in `MOVEMENTS.md` §1.1. |

### Honestly out of reach

| Movement | Why |
|---|---|
| **Human flag** | Gate is fine (body horizontal, hands on a vertical pole) but the pole isn't a landmark, so "am I on a pole or doing a side plank in the air" isn't answerable. |
| **Crow stand** | Distinguishable from a tuck planche only by knees-on-elbows contact, which we can't see. |
| **Press to handstand** | A *path* through positions, not a position. Needs trajectory scoring, which nothing here does. |
| Anything separated only by grip | Chin-up vs pull-up, diamond vs standard push-up. Three coarse hand points, no orientation. Deliberately excluded from the catalogue rather than mislabelled. |

---

## 5. What review shows, per movement shape

The rule the code follows (`ReviewOverlayMode.available`, `judgesItsLine`):

| Shape | Skeleton | Line | Angle | Depth meter | Charts |
|---|---|---|---|---|---|
| **Depth-gated rep** (push-up, dip, pull-up, squat, planche push-up) | ✓ | ✗ — the line is a form note here, not the point | ✓ both sides | ✓ | Driving angle, banded against the range that set showed |
| **Line hold** (handstand, planche, levers, plank) | ✓ | ✓ against gravity — plumb or level | ✓ where one joint decides it | ✗ | The two line angles, banded against absolute geometry |
| **Shaped hold** (L-sit, V-sit) | ✓ | ✗ — no straight line to hold | ✓ hip | ✗ | Hip *deviation* from a 90° ideal — the band machinery exists, the tracker doesn't |
| **Transition** (muscle-up) | ✓ | ✗ | ✓ | ✗ | Phase durations *(not yet built)* |

**Line is offered where holding a line is the point**, not merely where one
can be drawn. That distinction is why a push-up no longer offers it.

---

## 6. Open questions

- **Per-side everything.** Asymmetric movements — one-arm push-up, one-arm
  pull-up, pistol, archer — need per-side reps and per-side records, and the
  depth meter would want two bars. Deliberately **not built yet**: there is
  no asymmetric tracker to design it against, and an API with no caller gets
  the shape wrong. The trigger is the first such tracker; do it as the first
  commit of that work, not speculatively before it.
- **Lever charts.** Front and back levers can reuse `plancheTimelines`
  wholesale — same level-first-straight-second judging, different gate. They
  arrive with the trackers.
- **Planche shoulder bands.** `focusZones` is still nil for the planche, so
  its shoulder arc draws white. That's deliberate: the "correct" shoulder
  angle depends on how far you have to lean, which depends on whether you're
  tucked, straddled or full. There is no one band that's right across the
  variations, and inventing one would be Law 3 in a new costume.

### Settled since

- ~~Planche charts~~ — built. `plancheTimelines`, level first, straight
  second, matching what the tracker scores live.
- ~~Ideal angles that aren't 180°~~ — solved by plotting the **deviation**
  rather than the raw angle (`deviationZones`), which moves the ideal to zero
  wherever it sits. L-sit and V-sit inherit it for free.
