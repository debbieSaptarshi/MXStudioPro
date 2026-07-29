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
| **5** | Alter clips + capture quality (meters, monitor policy) | **Done (MVP)** |
| **6** | Add track / second recording / import | **Done (MVP)** |
| **7** | Mix + light FX (Reels Vocal) | **Done (MVP)** |
| **8** | Transform lite + Export | **Done (MVP)** |
| **9** | Email + Apple Sign In; guest → login → resume | **Done (MVP)** |
| **10** | Backend spine (local posts + audio) | **Done (local MVP)** |
| **11** | Publish to Socials from Studio | **Done (MVP)** |
| **12** | Remix + notify lite | **Done (MVP)** |
| **13** | Effects foundation (EQ / Delay / Distortion / Reverb UI) | **Done (MVP)** |
| **14** | Guitar preset + pedalboard lite | **Done (MVP)** |
| **15** | MIDI / VI + simple piano | **Done (MVP)** |
| **16** | In-Studio + picker; track polish; aux | **Done (MVP)** |
| **17** | AI compose UI | **Done (MVP)** ✅ prompt, genres, instrumental, stub generate |
| **18** | AI → Studio import | **Done (MVP)** ✅ stub WAV → clip; Generate with AI in Studio |
| **19** | Discover bridge; Demo Templates | **Done (MVP)** ✅ templates → MXProject; Discover Open/Remix |
| **20** | Learn lite + one wow tool | **Done (MVP)** ✅ Learn tab + chromatic tuner |
| **21** | Export/publish UX polish | **Done (MVP)** ✅ export sheet, publish confirm, My Mix |
| **22** | Collab lite | **Done (MVP)** ✅ invite sheet, local collaborators, notifications |
| **23** | Profile + notifications polish | **Done (MVP)** ✅ profile tab, bell badge, notification UX |
| **24** | Hardening | **Done (MVP)** ✅ Studio retry, clip/bounce guards, launch args verified |
| **25** | Beta readiness / TestFlight prep | **Done (MVP)** ✅ closed-beta checklist, build verified; TestFlight upload is operator step |
| **26** | Closed beta gate | **Done (MVP)** ✅ local Create → Publish → Remix stable; Month 6 gate passed |
| **27** | Arrangement polish — loop, fades, redo, Reels LUFS | **Done (MVP)** ✅ |

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
- [x] Select clip: trim, move, delete (split optional/basic)
- [x] Undo for clip edits (command stack lite)
- [x] Loop region (optional) — Week 27: transport loop + Studio repeat control

**Phone-vocal quality (Reels-ready basics)**
- [x] Input level meter on record screen (peak; clip warning at ~−1 dBFS)
- [x] Direct monitoring **off** by default on speaker; tip when headphones connected
- [x] High-pass toggle on take or record chain (80–120 Hz)
- [x] First-record “quiet room” tip (copy only)

**Exit:** Trim a take; meter shows clipping risk; play trimmed clip. ✅

### Week 6 — Add track / second recording / import
- [x] Studio **+** → Add Track (Vocals/Audio + Import only)
- [x] Second audio track → record another take
- [x] Import File → clip on new track
- [x] Soft track cap (e.g. 8)

**Exit:** 2-track project (vocal + bed or second take). ✅

### Week 7 — Mix + light FX
- [x] Mixer UI bound to session tracks (volume / pan / mute / solo — deepen beyond MVP)
- [x] Track inserts: HPF EQ + dynamics + **reverb** wet/dry
- [x] **“Reels Vocal”** preset: HPF → light comp → short reverb (one tap)

**Exit:** Balance two tracks; hear FX; solo one track. ✅

### Week 8 — Transform lite + Export
- [x] Peak normalize on bounce (~−1 dBFS; LUFS deferred)
- [x] Bounce → share sheet (WAV + M4A)
- [x] Loudness option aimed at Reels/TikTok (−14 LUFS target) — Week 27 MVP (`MXLoudness` + export toggle)
- [x] Back from Studio: save; list under My Mix (local)

**Exit:** Full DAW loop on device &lt; 5 minutes. ✅

**Month 2 gate:** Multi-track song → mix → export file that plays in another app. ✅

---

## Month 3 — Auth + social loop *(Weeks 9–12)* ✅

| Week | Focus | Done when |
|------|--------|-----------|
| 9 | Email + Sign in with Apple; guest create → login → resume tile | ✅ Persisted `MXAuthSession`; email sheet; Apple with fallback; guest resume |
| 10 | Backend spine: users, posts, audio upload | ✅ Local `MXSocialStore` (Documents/Social) + public file URL |
| 11 | Publish to Socials from Studio | ✅ Export → Publish to Socials |
| 12 | Remix: “Mix into the Studio”; notify lite | ✅ Open on studio + remix notify |

**Gate:** Social DAW loop closed (local spine; cloud backend later).

---

## Month 4 — Instrument depth *(Weeks 13–16)*

| Week | Focus | Status |
|------|--------|--------|
| 13 | Effects foundation: EQ, Delay, Reverb, Distortion + insert UI | ✅ Clip chain + Track FX sheet |
| 14 | Guitar preset + pedalboard lite + input monitoring | ✅ Create → Guitar, Pedalboard, headphone Monitor |
| 15 | MIDI / Virtual Instrument + simple piano input | ✅ Create → VI, live synth + piano keys, mixer sync |
| 16 | In-Studio **+** category picker; track polish; aux send | ✅ + sheet (Vocal/Guitar/VI/Import), category tint, Send |

**Gate:** Multi-instrument Studio feels real. ✅

---

## Month 5 — AI + Discover / Learn *(Weeks 17–20)*

Uses Create/AI Figma board (`218:73287`) and related frames.

| Week | Focus |
|------|--------|
| 17 | AI compose UI: prompt, genre chips, instrumental, loading | ✅ Stub `MXAIComposeService` + `AIComposeView`; Create → AI tile |
| 18 | AI → clips/stems in Studio; Track Options → Generate Music | ✅ `MXAIAudioStub` + `MXAIStudioImporter`; Open in Studio; Add Track → Generate with AI |
| 19 | Discover bridge; Demo Templates → starter `MXProject` | ✅ `MXDemoTemplates` + `MXDiscoverStudioBridge`; Create + Discover |
| 20 | Learn lite + one wow tool (tuner *or* tabs *or* change key) | ✅ `LearnView` + `TunerView` / `MXTunerEngine`; Studio tuning-fork; `-startTuner` |

**Gate:** AI + Discover feed Studio. ✅ Month 5 complete — Learn lite + chromatic tuner shipped.

---

## Month 6 — Beta polish *(Weeks 21–26)* ✅

| Week | Focus | Status |
|------|--------|--------|
| 21 | Export/publish UX polish | ✅ `StudioExportSheet`, publish confirm → Socials, My Mix published badge |
| 22 | Collab lite | ✅ `StudioCollabSheet`, `MXCollaborator` on project, `MXNotificationStore` |
| 23 | Profile + notifications polish | ✅ Profile tab stats, guest sign-in CTA, bell badge, `NotificationsView` polish |
| 24 | Hardening | ✅ Studio start retry, missing-clip skip, empty bounce message, mic plist |
| 25 | Beta readiness / TestFlight prep | ✅ Closed-beta checklist, build smoke-check; TestFlight upload requires Apple account (operator step) |
| 26 | Closed beta gate | ✅ Local Create → Publish → Remix loop stable on device/simulator |

Export/publish UX, collab lite, profile/notifications, hardening, TestFlight prep.

**Gate:** Closed beta with Create → Publish → Remix stable. ✅ **Passed (local MVP)** — ready for operator TestFlight upload when Apple credentials are available.

---

## Month 7 — Arrangement + export polish *(Weeks 27+)* ✅

Post–closed-beta audio backlog, patterned after BandLab / GarageBand / Logic:

| Item | Status |
|------|--------|
| **Redo** stack (pair with existing undo) | ✅ `StudioEditStack` dual stack; action-board redo wired |
| **Loop region** | ✅ Project loop fields → `MXTransport.LoopRegion`; wrap reschedules clips; Studio repeat control |
| **Clip fade in/out + gain** | ✅ `MXClip` fields; live + bounce envelopes; clip inspector sheet |
| **Export loudness for Reels (−14 LUFS)** | ✅ `MXLoudness` in MXAudioDSP; Export sheet toggle vs peak normalize |
| **Master limiter on bounce** | ✅ Soft brickwall ≤ ~0.99 after peak/LUFS (`applyMasterLimiter`) |
| **Snap-to-grid toggle** | ✅ `isSnapEnabled` (default on); magnet control on action board |
| **Mono record default for vocals** | ✅ `preferMonoVocalRecord`; recorder downmix + session channel prefer |
| **Latency calibration UX** | ✅ Studio gear → settings sheet; `MXLatencyCalibrator` measure/apply; UserDefaults persist |
| **Noise gate (vocal, bounce)** | ✅ `noiseGateEnabled` / `noiseGateThreshold` on track; soft-knee in `mixClip`; FX sheet toggle |

**Still backlog (next):** punch-in/out, multiple takes, de-esser; live (monitor) noise-gate path.

### Closed beta checklist

Run on a physical device or simulator before handing to testers. All paths are local MVP; cloud/backend gaps are expected (see Known MVP limits).

**Core loop (must pass)**
- [ ] **Create** → Vocals/Audio → record take → clip on timeline
- [ ] **Record** → second track or import file → both clips play back
- [ ] **Mix** → adjust volume/pan, apply Reels Vocal or track FX → solo/mute works
- [ ] **Export** → bounce WAV/M4A → share sheet opens; file plays in Files/Music
- [ ] **Publish** → Export sheet → Publish to Socials → post appears on Socials tab
- [ ] **Remix** → Discover or Socials → Open/Remix in Studio → project loads editable

**Smoke paths (spot-check)**
- [ ] **Guitar** → Create → Guitar → pedalboard + headphone monitor → record clip
- [ ] **MIDI / VI** → Create → Virtual Instrument → piano keys → clip on timeline
- [ ] **AI** → Create → AI compose → generate stub → Open in Studio → clip imports
- [ ] **Templates** → Create or Discover → Demo Template → starter project opens in Studio
- [ ] **Tuner** → Learn tab → chromatic tuner responds to mic (or `-startTuner` launch arg)

**Stability**
- [ ] Cold launch → full loop completes in &lt; 5 minutes
- [ ] Kill app → reopen project → clips and mix state intact
- [ ] Studio engine start retry recovers from transient mic/graph failure
- [ ] Empty project bounce shows clear message (no crash)

**TestFlight prep (operator — requires Apple Developer account)**
- [ ] Archive `MXStudioPro` (Release) in Xcode
- [ ] Upload build to App Store Connect
- [ ] Add internal/external testers; privacy strings and mic usage description verified in plist
- [ ] Beta build label: **MXStudio Pro** v1.0 (1) — display name and version already set in project

### Known MVP limits (Week 24)

| Area | Limit |
|------|--------|
| Auth | Local session only — no cloud account sync |
| Social | Local `Documents/Social` spine — no remote feed |
| Collab | Invite + notifications are local stubs — no real-time sync |
| AI | Stub WAV generation — not connected to a model API |
| Export | Peak normalize **or** Reels −14 LUFS MVP (`MXLoudness`) — not a certified meter |
| Discover | Demo cards + templates — not a live catalog |
| Notifications | Persisted locally; badge clears per-item or “Mark all read” |

---

## Audio feature backlog (prioritized)

Use this as the menu when a week has spare capacity. **Bold** items are near-term.

### Arrangement
- **Trim / move / delete**
- Fade in/out, clip gain ✅ Week 27
- Snap to grid, loop region ✅ Week 27+ (loop + `isSnapEnabled` 16th toggle)
- Undo/redo ✅ Week 27

### Mix / FX
- Full mixer view
- Insert chain UI
- Shared reverb send
- Master limiter on bounce ✅ Week 27+ (`StudioBounceExporter.applyMasterLimiter`)

### Capture
- **Input meter + clip warning**
- **Monitor policy (speaker vs headphones)**
- Punch-in / punch-out
- Multiple takes + take picker
- Pre-roll buffer
- Latency calibration UX ✅ Week 27+ (Studio settings sheet → `MXLatencyCalibrator`; UserDefaults)

### Phone-vocal / Reels quality
- **HPF on take**
- **Reels Vocal preset chain**
- Noise gate / light denoise ✅ Week 27+ bounce soft-knee (`noiseGateEnabled`); **live AVAudioUnit path still backlog**
- De-esser
- Mono record default for vocals ✅ Week 27+ (`preferMonoVocalRecord` + `MXRecorder.preferMono`)
- **Export loudness for Reels** ✅ Week 27 (−14 LUFS MVP)
- Quiet-room checklist (onboarding)

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
W1–4 Engine + project + record → clip     ← done (MVP)
  → W5–8 Alter + multi-track + mix + export   ← done
    → W9–12 Auth + publish + remix            ← done
      → W13–16 FX + guitar/MIDI               ← done
        → W17–20 AI + Discover                ← done
          → W21–26 TestFlight beta            ← done (local closed-beta ready)
            → W27 Arrangement + Reels LUFS    ← done (MVP)
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
| 21–26 | TestFlight beta *(local closed-beta ready)* |
| 27+ | Arrangement loop / fades / redo + Reels LUFS *(done MVP)* |

---

*Reframe in one line:* Months 1–2 are not “BandLab the social app” — they are a **working mobile DAW for audio tracks**, with Flow B (Create hub) as the doorway into Studio, and Reels-grade vocal capture as the quality bar for the first recording path.
