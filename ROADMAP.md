# Roadmap — becoming the best calisthenics tracker

Written 2026-09-02 after surveying the market. Current state is in `CLAUDE.md`,
the product spec in [SPEC.md](SPEC.md), the measurement rules in [POSE.md](POSE.md).

This file is the *plan*: what the competition does, where we already win,
where we're behind, and the order to build in. Revise it when the market or
the priorities move — don't let it rot into a wish list.

---

## 1. What we're competing against

Two markets barely overlap, and we sit in the gap between them.

### Camera / AI form apps
**Onyx**, **Kemtai**, **iBalance**, Tempo and Mirror (hardware-backed).
They do pose estimation and form scoring. Their reviews name the same
failures over and over:

| Complaint | Source |
|---|---|
| "When instructors face profile instead of toward the camera, the app **stops counting reps** without indicating you need to re-orient" | Onyx |
| Repeatedly nagged to "move further away from the camera" | Onyx |
| On some devices half the exercises don't track **with no indication** | Onyx |
| Crashed at the end of a workout, progress lost | Onyx |
| Needs a large space, and you end up too far away to read the screen | Kemtai |

### Calisthenics training apps
**Cali Move**, **Thenx** ($19.99/mo, criticised as expensive with no
progression system), **GainStrong**, **Fitloop**, **Calitracker**,
**Calistree** (1,100+ exercises in a skill tree), **Caliathletics**,
**Hybrid Calisthenics** (beginner regressions).

These win on *programming*: skill trees, regressions, structured plans,
huge exercise libraries, community feeds. Almost none of them measure
anything with a camera — they're logbooks with content.

### The gap
Nobody does **trustworthy measurement** and **calisthenics progression**
together. The camera apps can't program; the training apps can't see.

---

## 2. Where we already win

Worth stating plainly, because these are hard-won and easy to erode.

- **Angle-agnostic measurement.** Onyx's single most-cited failure — silently
  stops counting when you turn side-on — is the exact problem our 3D
  world-landmark work solved. This is our headline claim and it's real.
- **We never withhold the count** (POSE.md Law 4). Competitors go quiet and
  leave you guessing; we count the rep and score the form separately.
- **We say when we can't measure** rather than inventing a number
  (POSE.md Law 5, Law 8). Onyx's "no indication" complaint is precisely this.
- **Video + telemetry replay** with frame-accurate joint angles and event
  markers. Most rivals give you a score, not a reviewable recording.
- **Per-person calibration** (POSE.md Law 3) — no fixed angle gates that
  count zero reps for a real body.
- **Price.** $4.99/mo against Thenx's $19.99.

---

## 3. Where we're behind

Ordered by how much it costs us.

1. **Two tracked movements.** Push-ups and handstands. Every rival ships
   dozens to hundreds. This is the biggest single gap.
2. **No audio.** SPEC §5 specifies sound cues and `AVSpeechSynthesizer`
   coaching; only haptics exist. For a camera app this is not a nicety —
   Kemtai's own reviewers say you end up too far away to read the screen,
   and you certainly can't read it upside down.
3. **No progression system.** No skill tree, no regressions, no levels.
   This is the defining feature of the calisthenics category.
4. **No programs.** No structured sessions, no rest timers (a named Thenx
   complaint), no "what should I do today".
5. **No sharing.** We generate annotated video and don't let anyone post it.
6. **No Health integration, no Watch, no widgets, no cloud sync.**
7. **Free tier may be too thin.** 7-day history against competitors whose
   core logging is permanently free.

---

## 4. The plan

### Phase 1 — Make the core undeniable

The premise is proven; these make it usable and defensible.

**1.1 Audio coaching and cues.** Rep counts, hold seconds, form callouts and
countdown spoken aloud, plus short non-speech cues. Gate speech behind the
Pro tier per SPEC §4 but keep basic cues free — a silent camera app is
broken, not upsold. *Biggest usability win available; unlocks eyes-free and
upside-down training.*

**1.2 Framing feedback that doesn't nag.** We know when landmarks leave the
frame. Show it once, quietly, and stop — Onyx's repeated "move further away"
is a top complaint, but silence when it genuinely can't see you is what our
own Law 5 forbids. One persistent, non-blocking indicator.

**1.3 More trackers, in this order:** pull-ups → dips → squats → L-sit →
muscle-up → planche. Each follows POSE.md §11 and ships with its own test
matrix. Pull-ups first: it's the movement people actually want counted, and
the elbow/shoulder geometry is close to what we've built.

**1.4 A camera-angle hint per movement.** Not forced rotation — that
contradicts the core principle — but a one-line suggestion that a planche
films better wide. Dismissible, remembered.

### Phase 2 — Make progress mean something

**2.1 Skill progression.** Per-movement levels with regressions and
concrete unlock criteria, measured rather than self-reported. This is the
one thing we can do that no rival can: *Calistree asks you to tick a box;
we can watch you hold it.* Strongest differentiator in the plan.

**2.2 Structured sessions.** Multi-movement workouts with rest timers,
tracked end to end in one recording.

**2.3 Richer analytics.** Tempo (Pro, already specced), rep consistency,
fatigue within a set, left/right asymmetry — all derivable from telemetry
we already store.

**2.4 HealthKit.** Write workouts, read body metrics. Table stakes.

### Phase 3 — Reach

**3.1 Shareable clips.** Export the recording with the skeleton, rep markers
and stats burned in. We already have the video and the telemetry; this is
mostly rendering, and it is the cheapest growth lever we have.

**3.2 Cloud sync**, then widgets and a Watch companion.

**3.3 Community.** Only if the numbers justify it — it's a large surface
and Calitracker already owns the free-feed niche.

---

## 5. Decisions needed from Baydon

These change what gets built and I shouldn't guess at them.

- **Free tier.** Is 7-day history too thin against permanently-free rivals?
  Suggested alternative: unlimited history, gate *analysis* (trends, tempo,
  coaching) instead of *records*.
- **Breadth vs depth.** Ship six shallow trackers, or two more excellent
  ones plus progression? Depth suits the differentiator; breadth suits the
  App Store listing.
- **Handstand focus.** Dedicated handstand apps (iBalance, UpsideUp) are a
  real niche and we're already strong there. Lead with it, or stay general?
- **iOS 26 floor.** Currently deployment target 17.0 with a Liquid Glass
  fallback. Raising it simplifies the UI work and drops older devices.

---

## 6. Explicitly not doing

- **Forcing landscape** for planche or push-ups. Contradicts "prop the phone
  anywhere", and would fire mid-set.
- **Reintroducing a required camera angle** in any form (POSE.md Law 0).
- **Calorie estimates.** Kemtai's are called out as inaccurate; ours would
  be worse, and inventing a number breaks Law 8.
- **Barbell / weighted tracking.** Camera pose is unreliable for it, and
  it's not the market.
