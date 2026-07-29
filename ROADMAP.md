# MXStudio Pro — Product Roadmap

**Last updated:** 29 Jul 2026  
**North star (first 8 weeks):**  
Add track → Record audio → Clip on timeline → Alter → Add another track → Mix → Export  

Social / AI / Learn stay out of the critical path until the DAW loop is demoable on a real phone.

---

## Current status

| Week | Focus | Status |
|------|--------|--------|
| **1** | App ↔ engine (`MXStudioEngine` / `MXAudioCore`), Studio shell, Create → Vocals | **Done** |
| **2** | Transport, metronome, BPM, seek, count-in, interruptions | **Done** |
| **3** | `MXProject` / tracks / clips model, save/load, reopen | **Done** |
| **4** | Record vocal UI → WAV → clip on beat net → play back | **Done (MVP)** |
| **5** | Alter clips + capture quality (meters, monitor policy) | **Next** |

### Figma anchors (shipped / in use)

| Screen | Node | Role in product |
|--------|------|-----------------|
| Create Mix hub | `96:72447` / guest hub | Entry; only **Vocals/Audio** live |
| Record Vocal or Audio with Mic | [`95:83675`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-83675) | Record mode |
| Studio – After Record | [`95:85026`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-85026) | Arrangement after take |
| Create / AI board | [`218:73287`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=218-73287) | Deferred to Months 5+ |

Exact pixel parity is **not** required; working audio + clear navigation is.

---

## Month 1 — Engine + one recording path *(complete)*

*“Sound goes in, clip exists, project saves.”*

- [x] Link engine into `MXStudioPro`
- [x] `StudioSessionController` owns graph + transport + project
- [x] Play / stop / metronome / BPM / seek / count-in
- [x] Project JSON + `Audio/` folder; kill → reopen
- [x] Record → WAV → `MXClip` → timeline block → playback

**Exit demo:** Create → Vocals → Record → hear take → reopen project.

---

## Month 2 — Alter, multi-track, mix, export *(Weeks 5–8)*

*“Make a small multi-track song and bounce it.”*

### Week 5 — Alter clips + capture quality
**Goal:** Fix a bad start/end without re-recording; stop silent/clipped takes.

**Arrangement**
- [ ] Select clip: trim, move, delete (split optional/basic)
- [ ] Undo for clip edits (command stack lite)
- [ ] Loop region (optional)

**Phone-vocal quality (Reels-ready basics)**
- [ ] Input level meter on record screen (peak; clip warning at ~−1 dBFS)
- [ ] Direct monitoring **off** by default on speaker; tip when headphones connected
- [ ] High-pass toggle on take or record chain (80–120 Hz)
- [ ] First-record “quiet room” tip (copy only)

**Exit:** Trim a take; meter shows clipping risk; play trimmed clip.

### Week 6 — Add track / second recording / import
- [ ] Studio **+** → Add Track (Vocals/Audio + Import only)
- [ ] Second audio track → record another take
- [ ] Import File → clip on new track
- [ ] Soft track cap (e.g. 8)

**Exit:** 2-track project (vocal + bed or second take).

### Week 7 — Mix + light FX
- [ ] Mixer UI bound to `MXTrackChain` (volume / pan / mute / solo — deepen beyond MVP)
- [ ] Track inserts: EQ (expose) + **1** FX (reverb *or* delay)
- [ ] **“Reels Vocal”** preset: HPF → light comp → short reverb (one tap)

**Exit:** Balance two tracks; hear FX; solo one track.

### Week 8 — Transform lite + Export
- [ ] Clip gain / fade *or* simple normalize
- [ ] Bounce via `MXOfflineRenderer` → share sheet (WAV + M4A)
- [ ] Loudness option aimed at Reels/TikTok (−14 / −16 LUFS target)
- [ ] Back from Studio: save; list under My Mix (local)

**Exit:** Full DAW loop on device &lt; 5 minutes.

**Month 2 gate:** Multi-track song → mix → export file that plays in another app.

---

## Month 3 — Auth + social loop *(Weeks 9–12)*

| Week | Focus | Done when |
|------|--------|-----------|
| 9 | Email + Sign in with Apple; guest create → login → resume tile | Skip vs Continue match product rules |
| 10 | Backend spine: users, posts, audio upload | Public URL for exported mix |
| 11 | Publish to Socials from Studio | Post on Home with real audio |
| 12 | Remix: “Mix into the Studio”; notify lite | A publishes → B remixes → A notified |

**Gate:** Social DAW loop closed. Do **not** start this month until Month 2 Friday demos are green.

---

## Month 4 — Instrument depth *(Weeks 13–16)*

| Week | Focus |
|------|--------|
| 13 | Effects foundation: EQ, Delay, Reverb, Distortion + insert UI |
| 14 | Guitar preset + pedalboard lite + input monitoring |
| 15 | MIDI / Virtual Instrument + simple piano input |
| 16 | In-Studio **+** category picker; track polish; aux send |

**Gate:** Multi-instrument Studio feels real.

---

## Month 5 — AI + Discover / Learn *(Weeks 17–20)*

Uses Create/AI Figma board (`218:73287`) and related frames.

| Week | Focus |
|------|--------|
| 17 | AI compose UI: prompt, genre chips, instrumental, loading |
| 18 | AI → clips/stems in Studio; Track Options → Generate Music |
| 19 | Discover bridge; Demo Templates → starter `MXProject` |
| 20 | Learn lite + one wow tool (tuner *or* tabs *or* change key) |

**Gate:** AI + Discover feed Studio.

---

## Month 6 — Beta polish *(Weeks 21–26)*

Export/publish UX, collab lite, profile/notifications, hardening, TestFlight.

**Gate:** Closed beta with Create → Publish → Remix stable.

---

## Audio feature backlog (prioritized)

Use this as the menu when a week has spare capacity. **Bold** items are near-term.

### Capture
- **Input meter + clip warning**
- **Monitor policy (speaker vs headphones)**
- Punch-in / punch-out
- Multiple takes + take picker
- Pre-roll buffer
- Latency calibration UX (engine already has `MXLatencyCalibrator`)

### Phone-vocal / Reels quality
- **HPF on take**
- **Reels Vocal preset chain**
- Noise gate / light denoise
- De-esser
- Mono record default for vocals
- **Export loudness for Reels**
- Quiet-room checklist (onboarding)

### Arrangement
- **Trim / move / delete**
- Fade in/out, clip gain
- Snap to grid, loop region
- Undo/redo

### Mix / FX
- Full mixer view
- Insert chain UI
- Shared reverb send
- Master limiter on bounce

### Later “wow”
- Pitch correction, time stretch, harmonies
- Stem export, video+audio Reels export
- Beat browser / tempo detect from import

---

## Explicitly deferred (do not pull into Weeks 5–8)

| Item | Why |
|------|-----|
| Social publish / remix | Needs Month 2 gate |
| AI generate | Month 5 |
| Guitar amp / MIDI piano roll | Month 4 |
| Flex Pitch / Change Key | After export works |
| Looper / Sampler / Live tiles | Later presets; keep Create tiles visible but disabled |
| Pixel-perfect every Studio frame | Shell must serve the loop first |
| Cloud sync / collab depth | Month 6+ |

Create hub: only **Vocals/Audio** + (Week 6) **Import** need to be real.

---

## Weekly rhythm

| Day | Focus |
|-----|--------|
| Mon | Plan week against gate; pick 1 demo scene |
| Tue–Thu | Build |
| Fri | Device demo + Figma parity note + risk log |

### Friday demo scripts

| Week | Script |
|------|--------|
| **4 (done)** | “I recorded my voice and played it back.” |
| **5** | “I trimmed the take and didn’t clip the mic.” |
| **6** | “I added a second track / import.” |
| **7** | “I mixed levels and added a vocal preset.” |
| **8** | “I exported the song to Files / share sheet.” |

If a Friday demo fails, that week isn’t done — don’t start social work.

---

## Success criteria (end of Week 8)

- [ ] Cold launch → Create → Vocals → Record → Alter → + Track → Mix → Export &lt; 5 minutes  
- [ ] Project reopens with clips intact  
- [ ] No audio glitches on a 2-track, ~1 minute song  
- [ ] Export file plays in another app  
- [ ] Record UI shows level / clip warning  

---

## Dependency chain

```text
W1–4 Engine + project + record → clip     ← you are here (MVP done)
  → W5–8 Alter + multi-track + mix + export
    → W9–12 Auth + publish + remix
      → W13–16 FX + guitar/MIDI
        → W17–20 AI + Discover
          → W21–26 TestFlight beta
```

If slipped: **never cut W5–8 or W11–12** — cut Live/Looper, full Learn, collab depth, pixel polish instead.

---

## One-line per month

| Weeks | Line |
|-------|------|
| 1–4 | Engine boots; record → clip → play *(done)* |
| 5–8 | Alter → multi-track → mix → export |
| 9–12 | Publish & remix |
| 13–16 | Guitar/MIDI DAW |
| 17–20 | AI + Discover |
| 21–26 | TestFlight beta |

---

*Reframe in one line:* Months 1–2 are not “BandLab the social app” — they are a **working mobile DAW for audio tracks**, with Flow B (Create hub) as the doorway into Studio, and Reels-grade vocal capture as the quality bar for the first recording path.
