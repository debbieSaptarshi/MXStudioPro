# MXStudio Pro — Product Roadmap

**Last updated:** 30 Jul 2026  
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
| **28** | Vocal capture polish — de-esser, live gate, pre-roll | **Done (MVP)** ✅ |
| **29** | Quiet-room checklist; loop schedule clamp; punch comps lite | **Done (MVP)** ✅ |
| **30** | Mixer channel strips; insert chain UI; bounce FX parity | **Done (MVP)** ✅ |
| **31** | Studio shell ↔ Figma layout parity | **Done (MVP)** ✅ Guitar Studio proportions |
| **32** | Guitar Studio Section (Figma) | **Done (MVP)** ✅ Pedalboard presets + Dist→Delay→Rev |
| **33** | Piano Studio Section (Figma) | **Done (MVP)** ✅ Virtual Piano + bank + MIDI capture |
| **34** | Drum & Others Studio Section (Figma) | **Next** |
| **35** | Quick Landscape Studio Section (Figma) | Planned |

### Figma anchors (shipped / in use)

| Screen | Node | Role in product |
|--------|------|-----------------|
| Create Mix hub | `96:72447` / guest hub | Entry; Vocals / Guitar / VI / AI live |
| Record Vocal or Audio with Mic | [`95:83675`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-83675) | Record mode |
| Studio – After Record (Vocal) | [`95:85026`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-85026) | Arrangement after take |
| Studio – Guitar | [`95:85203`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-85203) | Guitar Studio shell |
| Studio – MIDI / VI | [`95:85253`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-85253) | Piano Studio shell |
| Drum Midi | [`95:88141`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-88141) | Drum pad / parts studio |
| Recording landscape | [`95:81418`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-81418) | Quick Landscape record |
| Studio landscape | [`97:113250`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=97-113250) | Quick Landscape arrange |
| Create / AI board | [`218:73287`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=218-73287) | AI compose |

Exact pixel parity is **not** required; working audio + clear navigation is. Use the section frames below as the north-star layout for each Studio mode.

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
- [x] Loop region (optional) — Week 27: transport loop + Studio repeat control; Week 29: schedule clamp to loop end

**Phone-vocal quality (Reels-ready basics)**
- [x] Input level meter on record screen (peak; clip warning at ~−1 dBFS)
- [x] Direct monitoring **off** by default on speaker; tip when headphones connected
- [x] High-pass toggle on take or record chain (80–120 Hz)
- [x] First-record “quiet room” tip → Week 29 interactive checklist

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

## Month 7 — Arrangement + export polish *(Weeks 27–28)* ✅

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
| **Noise gate (vocal, bounce + live)** | ✅ Bounce soft-knee; Week 28 live playback expander + monitor gate |
| **Punch-in / punch-out (MVP)** | ✅ Record while playing keeps playhead; clip placed at punch-in beat; loop wrap punches out |
| **Multiple takes lite (MVP)** | ✅ `MXClip.takeIndex` + `isActive`; overlapping takes deactivate; Takes (N) picker; playback/bounce skip inactive |
| **De-esser (vocal)** | ✅ Week 28 live EQ peaking ~6.5 kHz + bounce `MXBiquad`; Reels Vocal enables light amount |
| **Pre-roll buffer** | ✅ Week 28 ring while record-armed; Settings 0–500 ms; clip start shifts / trims at 0 |

---

## Month 8 — Capture onboarding + comps *(Week 29)* ✅

Patterned after GarageBand first-record tips, Logic punch comps, BandLab take lanes:

| Item | Status |
|------|--------|
| **Quiet-room checklist (onboarding)** | ✅ Interactive checklist on first Record; auto-check headphones + mic level; holds auto-Rec until dismissed |
| **Clamp clip schedules to loop end** | ✅ `MXLoopScheduleClamp` caps `AVAudioPlayerNode` frames so audio doesn’t bleed past loop on hostTime |
| **Playlist lanes / crossfade comps lite** | ✅ Punch splits active takes into before/after; ~12 ms abut fades; ghost inactive takes; take-lane activation |

**Takes / punch Week 29 limits:** abut fade dips (not overlapping X-fades); ghosts only when inactive takes exist; no always-on multi-row playlist folder.

---

## Month 8 continued — Mixer + export parity *(Week 30)* ✅

Patterned after BandLab channel strips and GarageBand insert order:

| Item | Status |
|------|--------|
| **Full mixer view (channel strips)** | ✅ Horizontal scroll of per-track strips: vertical fader, pan, M/S, Rev; Send for MIDI; Reels for vocals |
| **Insert chain UI** | ✅ FX sheet chips HPF → EQ → Dly → Dist → Dyn → Rev; Record Vocal EQ opens FX sheet |
| **Bounce live-insert parity** | ✅ Offline HPF, EQ mid, de-ess, gate, delay, Reels soft-comp, `MXSimpleReverb`; FX tail flush; skip Distortion AU |

**Still backlog (next):** true overlapping equal-power crossfades; expanded multi-row playlist folder; playback strip meters. *(Bounce Dist soft-clip shipped in Week 32.)*

---

## Month 9 — Instrument Studio sections *(Weeks 31–35)* **Next**

Figma page **⭐ Complete Design** groups dedicated Studio experiences. Shared chrome (header, 60pt lanes, 70pt details, action board) stays one `StudioView`; each section adds mode-specific UI + audio behavior.

**Week 31 (done):** Shell layout parity — timeline fills, details/action board pinned, track headers 60pt, `+ ADD TRACK`, Figma transport cluster. Reference: [`Studio - Guitar`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-85203).

### Week 32 — Guitar Studio Section ✅

**Figma cluster (≈ y=8476)**
| Frame | Node | Intent |
|-------|------|--------|
| Studio – Guitar | [`95:85203`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-85203) | Multi-track arrange with guitar + vocal lanes |
| Click on Guitar | [`95:88337`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-88337) | Track focus / options |
| Select Guitar Effect | [`95:89964`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-89964) | Pedalboard / FX pick |

**Done when (BandLab / GarageBand guitar path)**
- [x] Create → Guitar opens shell matching Figma proportions (already close after W31)
- [x] Pedalboard sheet matches Select Guitar Effect flow (Dist / Delay / Rev order + Clean/Crunch/Lead/Ambient presets)
- [x] Input monitor defaults on with headphones tip; DI / mic policy clear
- [x] Armed guitar track shows guitar category chrome (tint, icon, Pedalboard title)
- [x] Demo: record guitar take over a second track → hear FX → bounce *(cold Rec schedules beds; bounce soft-clip Dist)*

**Week 32 notes:** Pedalboard gated on `track.category == .guitar` so vocal lanes in a Guitar project keep Dyn chain. Live monitor remains dry (hear pedals on playback/bounce). Wet input monitoring deferred.

### Week 33 — Piano Studio Section **Next**

**Figma cluster (≈ y=9854)**
| Frame | Node | Intent |
|-------|------|--------|
| Studio – MIDI / VI | [`95:85253`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-85253) | Arrange + VI track |
| Piano Midi | [`95:86149`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-86149) | Piano FX / MIDI edit surface |
| Virtual Piano | [`95:87783`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-87783) | Full keyboard play surface |
| Virtual Piano v2 | [`95:88011`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-88011) | Alternate keyboard / octave UI |

**Done when (GarageBand Keyboard / BandLab Keys)**
- [ ] On-screen keyboard matches Virtual Piano layout (octaves, hold, velocity lite)
- [ ] Optional MIDI note clips / piano-roll lite (even single-lane draw is enough for MVP)
- [ ] Piano FX sheet from Piano Midi frame; instrument preset switch (synth bank)
- [ ] Record button disabled for MIDI-armed track; play keys → audible; export includes rendered audio or stub capture
- [ ] Demo: Create → VI → play progression → Open FX → bounce with keys bed

### Week 34 — Drum & Others Studio Section

**Figma cluster (≈ y=11232)**
| Frame | Node | Intent |
|-------|------|--------|
| Drum Midi | [`95:88141`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-88141) | Drum pads + part lanes |
| Studio – Hide Tracks | [`95:85310`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-85310) | Collapsed track headers for more net |
| (Create hub) Drum / Bass / Sampler tiles | Create Mix | Entry points for “Others” |

**Done when (BandLab Drum Machine / GarageBand Drums)**
- [ ] Create → Drum (enable tile) opens drum pad surface + timeline
- [ ] Pad hits trigger drum kit / synth percussion; pattern or one-shot clips on timeline
- [ ] Drum parts column (kick/snare/hat lanes) or simplified pad → clip workflow
- [ ] Hide Tracks mode collapses headers to icon rail (Figma `95:85310`) for denser arrange
- [ ] Bass / Sampler remain “Others”: either lite presets or keep disabled with clear labels
- [ ] Demo: lay 4-bar beat → layer vocal/guitar → bounce

### Week 35 — Quick Landscape Studio Section

**Figma cluster (≈ y=12610)**
| Frame | Node | Intent |
|-------|------|--------|
| Recording landscape | [`95:81418`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-81418) | Landscape record / capture |
| Studio landscape | [`97:113250`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=97-113250) | Landscape arrange (812×375) |
| Virtual Piano (landscape) | [`97:137230`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=97-137230) | Landscape keys |
| Quick Recording (portrait) | [`96:58733`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=96-58733) | Minimal capture entry |

**Done when (GarageBand Quick / BandLab quick capture)**
- [ ] Support landscape orientation for Studio (+ optional lock for record)
- [ ] Landscape layout: track column + wide net + compact bottom transport (Figma 812×375)
- [ ] Quick Recording entry from Create: minimal chrome → one-take record → drop into Studio
- [ ] Landscape Virtual Piano usable for VI projects
- [ ] Demo: rotate phone → arrange 4+ tracks comfortably → rotate back → export

**Month 9 gate:** Guitar / Piano / Drum / Landscape each have a Figma-faithful entry path and a 60-second demo that produces audible audio in Studio.

### Implementation notes (shared)

1. Prefer **one Studio shell** with `StudioPreset` / track `category` driving overlays (pedalboard, keyboard, drum pads, landscape `ViewThatFits` / size-class layouts).
2. Ship **vertical slice per week** — UI + audio path — not all Figma variants in one PR.
3. Reference apps: BandLab (pads + multi-track), GarageBand (keyboard, guitar amps, Quick), Logic (hide tracks density).
4. Defer: full amp sims, pro piano roll, step sequencer, AUv3 hosting depth.

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
- Full mixer view ✅ Week 30 channel strips
- Insert chain UI ✅ Week 30 FX chips + Record EQ entry
- Shared reverb send ✅ MIDI aux; audio Rev on strip
- Master limiter on bounce ✅ Week 27+ (`StudioBounceExporter.applyMasterLimiter`)
- Bounce FX parity ✅ Week 30 (HPF/EQ/delay/reverb/comp; Dist deferred)

### Capture
- **Input meter + clip warning**
- **Monitor policy (speaker vs headphones)**
- Punch-in / punch-out ✅ Week 27+ MVP (playhead punch-in; loop-end punch-out)
- Multiple takes + take picker ✅ Week 27+ MVP; Week 29 punch comps + ghost lanes + take-lane activation
- Pre-roll buffer ✅ Week 28 (`MXRecorder` ring while armed; Studio Settings 0–500 ms)
- Latency calibration UX ✅ Week 27+ (Studio settings sheet → `MXLatencyCalibrator`; UserDefaults)
- Quiet-room checklist ✅ Week 29 (`QuietRoomChecklist` + Record overlay)
- Loop schedule clamp ✅ Week 29 (`MXLoopScheduleClamp`)

### Phone-vocal / Reels quality
- **HPF on take**
- **Reels Vocal preset chain**
- Noise gate / light denoise ✅ Week 27 bounce + Week 28 live/monitor expander (`syncMonitorNoiseGate`)
- De-esser ✅ Week 28 (live EQ peaking ~6.5 kHz + bounce `MXBiquad`; Reels Vocal enables light amount)
- Mono record default for vocals ✅ Week 27+ (`preferMonoVocalRecord` + `MXRecorder.preferMono`)
- **Export loudness for Reels** ✅ Week 27 (−14 LUFS MVP)
- Quiet-room checklist (onboarding) ✅ Week 29

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
            → W27–28 Arrangement + vocal polish ← done
              → W29 Checklist + loop clamp + comps ← done
                → W30 Mixer strips + bounce FX parity ← done
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
| 27–28 | Arrangement + vocal capture polish |
| 29 | Quiet-room checklist + loop clamp + punch comps |
| 30 | Mixer channel strips + bounce FX parity |

---

*Reframe in one line:* Months 1–2 are not “BandLab the social app” — they are a **working mobile DAW for audio tracks**, with Flow B (Create hub) as the doorway into Studio, and Reels-grade vocal capture as the quality bar for the first recording path.
