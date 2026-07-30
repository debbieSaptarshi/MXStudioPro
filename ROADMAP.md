# MXStudio Pro — Product Roadmap

**Last updated:** 30 Jul 2026  
**North star (first 8 weeks):**  
Add track → Record audio → Clip on timeline → Alter → Add another track → Mix → Export  

Social / AI / Learn stay out of the critical path until the DAW loop is demoable on a real phone.

**Current focus:** Month 19 (W73–76) **in progress** — next: beat browser, real sidechain, K-weighted LUFS.

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
| **34** | Drum & Others Studio Section (Figma) | **Done (MVP)** ✅ Pads + Hide Tracks + Others labels |
| **35** | Quick Landscape Studio Section (Figma) | **Done (MVP)** ✅ landscape compact + Quick Recording |
| **36** | Equal-power crossfades (arrangement) | **Done (MVP)** ✅ overlapping punch X-fades |
| **37** | Multi-row playlist folder (take lanes) | **Done (MVP)** ✅ one row per takeIndex; collapse chevron |
| **38** | Playback strip meters (mixer) | **Done (MVP)** ✅ live peak + peak-hold beside faders |
| **39** | Wet input monitoring for guitar pedalboard | **Done (MVP)** ✅ Dist→Delay→Rev on armed guitar monitor |
| **40** | Per-part drum lanes (Kick/Snare/Hats…) | **Done (MVP)** ✅ BandLab-style part columns |
| **41** | Record orientation lock + landscape chrome | **Done (MVP)** ✅ opt-in portrait lock; densified Rec |
| **42** | Per-part drum mute (Kick/Snare/Hats… M) | **Done (MVP)** ✅ mute re-renders WAV beds |
| **43** | Arrange timeline strip meters | **Done (MVP)** ✅ header meters reuse W38 peaks |
| **44** | Per-part drum solo (Kick/Snare/Hats… S) | **Done (MVP)** ✅ solo + mute → audible bed |
| **45** | MIDI quantize lite (16th note starts) | **Done (MVP)** ✅ |
| **46** | Clip fade wedges on arrange timeline | **Done (MVP)** ✅ |
| **47** | Stem export (per-track bounce) | **Done (MVP)** ✅ |
| **48** | Import tempo detect lite | **Done (MVP)** ✅ |
| **49** | Drum step sequencer lite (16-step × kit) | **Done (MVP)** ✅ |
| **50** | Drag fade wedges to edit clip fades | **Done (MVP)** ✅ |
| **51** | Quantize strength / swing + re-quantize | **Done (MVP)** ✅ |
| **52** | Track volume automation lane lite | **Done (MVP)** ✅ |
| **53** | Step seq velocity + multi-bar + load from clip | **Done (MVP)** ✅ |
| **54** | Clip-relative vol/pan automation + meet-in-middle fades | **Done (MVP)** ✅ |
| **55** | Piano-roll lite (edit note start/pitch on selected MIDI clip) | **Done (MVP)** ✅ |
| **56** | Latency calibration UX + input monitoring polish | **Done (MVP)** ✅ |
| **57** | Step pattern library + copy/paste bars + live step cursor | **Done (MVP)** ✅ |
| **58** | Piano-roll note length drag + velocity lane | **Done (MVP)** ✅ |
| **59** | Master bus limiter + live LUFS meter | **Done (MVP)** ✅ |
| **60** | Figma pixel-pass After Record + Drum Midi shells | **Done (MVP)** ✅ |
| **61** | Step-seq swing independent of MIDI swing + pattern slots | **Done (MVP)** ✅ |
| **62** | Piano-roll multi-select transpose + scale lock lite | **Done (MVP)** ✅ |
| **63** | Sidechain lite (kick → bass) + shared reverb send visual | **Done (MVP)** ✅ |
| **64** | Snap resolution picker (1/8, 1/16, 1/32) + beat grid density | **Done (MVP)** ✅ |
| **65** | Triplet + dotted snap grids (1/8T, 1/16T, 1/8., 1/16.) | **Done (MVP)** ✅ |
| **66** | Snap readout on arrange ruler + magnet chrome | **Done (MVP)** ✅ |
| **67** | Zoom-adaptive arrange grid + pinch/± zoom | **Done (MVP)** ✅ |
| **68** | Piano-roll draw mode lite | **Done (MVP)** ✅ |
| **69** | Pitch correction lite (vocal clip) | **Done (MVP)** ✅ |
| **70** | Time-stretch clip lite | **Done (MVP)** ✅ |
| **71** | LUFS report sheet after bounce | **Done (MVP)** ✅ |
| **72** | Cloud auth sync spine (stub) | **Done (MVP)** ✅ |

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
| **Snap-to-grid toggle** | ✅ `isSnapEnabled` (default on); magnet control on action board; W64 resolution picker 1/8·1/16·1/32 + beat grid density |
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

**Takes / punch Week 29 limits (superseded where noted):** abut fade dips → Week 36 equal-power X-fades; Week 37 always-on multi-row playlist folder (session-local collapse).

---

## Month 8 continued — Mixer + export parity *(Week 30)* ✅

Patterned after BandLab channel strips and GarageBand insert order:

| Item | Status |
|------|--------|
| **Full mixer view (channel strips)** | ✅ Horizontal scroll of per-track strips: vertical fader, pan, M/S, Rev; Send for MIDI; Reels for vocals |
| **Insert chain UI** | ✅ FX sheet chips HPF → EQ → Dly → Dist → Dyn → Rev; Record Vocal EQ opens FX sheet |
| **Bounce live-insert parity** | ✅ Offline HPF, EQ mid, de-ess, gate, delay, Reels soft-comp, `MXSimpleReverb`; FX tail flush; skip Distortion AU |

**Month 10 backlog:** Week 36 equal-power crossfades ✅ → playlist folder ✅ → strip meters ✅ → wet guitar monitor ✅. *(Bounce Dist soft-clip shipped in Week 32.)*

---

## Month 9 — Instrument Studio sections *(Weeks 31–35)* ✅

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

**Week 32 notes:** Pedalboard gated on `track.category == .guitar` so vocal lanes in a Guitar project keep Dyn chain. Wet input monitoring shipped in Week 39 (`MXMonitorGuitarFX`).

### Week 33 — Piano Studio Section ✅

**Figma cluster (≈ y=9854)**
| Frame | Node | Intent |
|-------|------|--------|
| Studio – MIDI / VI | [`95:85253`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-85253) | Arrange + VI track |
| Piano Midi | [`95:86149`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-86149) | Piano FX / MIDI edit surface |
| Virtual Piano | [`95:87783`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-87783) | Full keyboard play surface |
| Virtual Piano v2 | [`95:88011`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-88011) | Alternate keyboard / octave UI |

**Done when (GarageBand Keyboard / BandLab Keys)**
- [x] On-screen keyboard matches Virtual Piano layout (octaves, hold, velocity lite)
- [x] Optional MIDI note clips / piano-roll lite (even single-lane draw is enough for MVP)
- [x] Piano FX sheet from Piano Midi frame; instrument preset switch (synth bank)
- [x] Record button disabled for MIDI-armed track; play keys → audible; export includes rendered audio or stub capture
- [x] Demo: Create → VI → play progression → Open FX → bounce with keys bed

**Week 33 notes:** Performance capture — play keys while transport runs, Stop/pause drops a rendered WAV + piano-roll lite clip. Soft Keys / Warm Pad / Pulse Bass / Pluck / Synthwave bank. Rec stays disabled for MIDI-armed tracks.

### Week 34 — Drum & Others Studio Section ✅

**Figma cluster (≈ y=11232)**
| Frame | Node | Intent |
|-------|------|--------|
| Drum Midi | [`95:88141`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-88141) | Drum pads + part lanes |
| Studio – Hide Tracks | [`95:85310`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-85310) | Collapsed track headers for more net |
| (Create hub) Drum / Bass / Sampler tiles | Create Mix | Entry points for “Others” |

**Done when (BandLab Drum Machine / GarageBand Drums)**
- [x] Create → Drum (enable tile) opens drum pad surface + timeline
- [x] Pad hits trigger drum kit / synth percussion; pattern or one-shot clips on timeline
- [x] Drum parts column (kick/snare/hat lanes) or simplified pad → clip workflow *(pad → performance capture clip)*
- [x] Hide Tracks mode collapses headers to icon rail (Figma `95:85310`) for denser arrange
- [x] Bass / Sampler remain “Others”: either lite presets or keep disabled with clear labels
- [x] Demo: lay 4-bar beat → layer vocal/guitar → bounce

**Week 34 notes:** 8 GM-ish pads (Kick/Snare/Clap/HH/Tom/Perc/Ride), Drum Kit short one-shot synth, capture on Stop like Piano. Hide Tracks sidebar toggle. Bass/Looper/Sampler labeled “Others — coming soon”.

### Week 35 — Quick Landscape Studio Section ✅

**Figma cluster (≈ y=12610)**
| Frame | Node | Intent |
|-------|------|--------|
| Recording landscape | [`95:81418`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=95-81418) | Landscape record / capture |
| Studio landscape | [`97:113250`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=97-113250) | Landscape arrange (812×375) |
| Virtual Piano (landscape) | [`97:137230`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=97-137230) | Landscape keys |
| Quick Recording (portrait) | [`96:58733`](https://www.figma.com/design/dw9rjcvqf3IadTXi0o33BD/MXStudioProV1?node-id=96-58733) | Minimal capture entry |

**Done when (GarageBand Quick / BandLab quick capture)**
- [x] Support landscape orientation for Studio (+ optional lock for record) — orientations enabled; record lock shipped in Week 41
- [x] Landscape layout: track column + wide net + compact bottom transport (Figma 812×375)
- [x] Quick Recording entry from Create: minimal chrome → one-take record → drop into Studio
- [x] Landscape Virtual Piano usable for VI projects — compact keys (~72pt) + hide details strip
- [x] Demo: rotate phone → arrange 4+ tracks comfortably → rotate back → export

**Week 35 notes:** Auto-collapse track headers in landscape; compact action board / header Collab icon; piano + drum pads shrink for 812×375; Quick Recording skips quiet-room tip.

**Month 9 gate:** Guitar / Piano / Drum / Landscape each have a Figma-faithful entry path and a 60-second demo that produces audible audio in Studio. ✅

---

## Month 10 — Arrangement depth *(Weeks 36–39)* ✅ ✅

Reference: Logic Pro / Pro Tools equal-power crossfades; GarageBand / BandLab playlist comps; Studio One strip meters.

| Week | Focus | Status |
|------|--------|--------|
| **36** | True overlapping equal-power crossfades (punch seams + clip fades) | **Done (MVP)** ✅ |
| **37** | Expanded multi-row playlist folder (always-on take lanes) | **Done (MVP)** ✅ |
| **38** | Playback strip meters (mixer + optional timeline) | **Done (MVP)** ✅ |
| **39** | Wet input monitoring for guitar pedalboard | **Done (MVP)** ✅ |

### Week 36 — Equal-power crossfades ✅

**Done when (Logic / Pro Tools X-fade)**
- [x] Punch comps create real timeline overlap (~12 ms+) instead of abut dips
- [x] Equal-power in/out curves (`cos`/`sin`) so `gOut² + gIn² ≈ 1` (`MXCrossfade`)
- [x] Live schedule + bounce both sum overlapping faded clips without level dip (`fadeEnvelope`)
- [x] Take-lane activation treats short X-fade overlaps as soft abut (co-active)
- [x] Unit tests for envelope power + split overlap geometry
- [x] Demo: punch over a take → seamless splice on play + bounce

**Week 36 notes:** `MXCompRegionSplit` extends before/after into the punch; both seams share `min(xf, punch/2)`. Soft-overlap default 0.08 beats. Manual clip fades also use equal-power.

### Week 37 — Expanded multi-row playlist folder ✅

**Done when (GarageBand / Logic playlist lite)**
- [x] Multi-take track (≥2 distinct `takeIndex`) expands to one timeline row per take lane
- [x] Active take editable (`InteractiveStudioClip`); inactive takes on own dimmed rows; tap activates via `setActiveTake`
- [x] Track header height matches expanded folder height
- [x] Folder defaults open; chevron collapses to single summary lane (session-local `@State`, not persisted)
- [x] Takes menu lists one representative clip per `takeIndex`
- [x] Single-take tracks unchanged (one lane)

**Week 37 notes:** `StudioSessionController.takes(onTrackID:)` returns one rep per takeIndex (prefer active). Ghosts only in expanded playlist rows; collapsed summary shows actives only. No empty lanes, no drag between lanes, no punch/activation math changes.

### Week 38 — Playback strip meters ✅

**Done when (Studio One / Logic / GarageBand mixer meters)**
- [x] Mixer strips show vertical peak meters beside each fader (`PlaybackStripMeter`)
- [x] Meters move during playback of audio clips (post-FX reverb-node taps → `trackPlaybackLevels`)
- [x] Peak hold marker visible (`trackPlaybackPeakHolds`, ~0.995 decay)
- [x] Mute/solo → meter goes quiet (player / chain volume already zeroed into tap path)
- [x] Stop → meters decay / zero (`stopPlaybackMeterPolling` + `zeroPlaybackMeters`)
- [x] Demo: play multi-track mix with mixer open → see per-track activity (`ensurePlaybackMetersRunning` on mixer appear)

**Week 38 notes:** Tap on clip insert reverb (bus 0, 1024). MIDI live: tap `MXTrackChain.trackMixer`. Poll ~33 ms. No timeline lane meters, no LUFS/RMS. Input record meters unchanged.

### Week 39 — Wet guitar input monitoring ✅

**Done when (BandLab / GarageBand guitar monitor)**
- [x] Armed guitar + Monitor on → hear Dist→Delay→Rev (light EQ mid) while input armed / recording
- [x] Changing pedalboard preset / Dist·Delay·Rev·EQ updates live monitor without restarting Rec
- [x] Vocal armed → dry monitor + optional noise gate (no guitar inserts)
- [x] Monitor off → silence (detach all monitor nodes)
- [x] Speaker path still prefers Monitor off (existing feedback policy)
- [x] Recorded WAV remains dry DI (write tap on `inputNode`; FX only on parallel monitor + playback/bounce)

**Week 39 notes:** `MXMonitorGuitarFX` on `MXRecorder`; wet path `input → EQ → Dist → Delay → Rev → monitorMixer → master`. `syncMonitorChain()` pushes armed-track pedal params. Headphones tip mentions pedalboard. AU chain adds some monitor latency vs dry DI.

### Month 10 gate ✅

Equal-power X-fades → playlist folder → strip meters → wet guitar monitor. Arrangement depth MVP complete.

---

## Month 11 — Drum depth + capture chrome *(Weeks 40+)*

Reference: BandLab kit part columns; GarageBand Drummer lanes; Logic Drum Kit Designer.

| Week | Focus | Status |
|------|--------|--------|
| **40** | Per-part drum lanes (kick / snare / hat columns beyond pad→clip) | **Done (MVP)** ✅ |
| **41** | Optional record orientation lock; Record landscape chrome | **Done (MVP)** ✅ |
| **42** | Per-part drum mute (Kick/Snare/Hats… M) | **Done (MVP)** ✅ |
| **43** | Arrange timeline strip meters | **Done (MVP)** ✅ |
| **44** | Per-part drum solo (Kick/Snare/Hats… S) | **Done (MVP)** ✅ |
| — | Cloud / backend beyond local MVP (auth, social, AI) | **Planned** (parallel / later) |

### Week 40 — Per-part drum lanes ✅

**Done when (BandLab / GarageBand kit columns)**
- [x] Drum tracks expand into fixed Kick / Snare / Hats / Toms / Perc / Ride rows
- [x] Pad hits map to parts via shared `MXDrumPart` (same map as `DrumPadView`)
- [x] One performance clip still owns the WAV bed; each row filters `midiNotes` for that part
- [x] Empty part columns show faint clip shell (aligned); header lists part labels
- [x] Chevron collapses part folder to summary lane (session-local `@State`)
- [x] Multi-take playlist folder (≥2 takes) still wins over part columns
- [x] Capture names clips `Drums N` / `drums_*.wav`
- [x] Unit tests for pad→part mapping + note filter

**Week 40 notes:** Parts are arrange UI only — not separate WAVs. Per-part mute shipped in Week 42. Playlist takes remain orthogonal (`takeIndex`). Deferred: step sequencer, SFZ kit choke, nested takes×parts.

### Week 41 — Record orientation lock + landscape chrome ✅

**Done when (GarageBand densify + opt-in lock)**
- [x] Settings: “Lock portrait while recording” (UserDefaults, default **off**)
- [x] Lock on → record stays portrait via `MXOrientationLock` + `MXAppDelegate` mask; exit unlocks Studio rotate
- [x] Lock off → landscape record densifies chrome (Figma `95:81418`): waveform dominant, mixer/tips hidden, compact header/details/Rec
- [x] Quick Recording uses same chrome/lock path (`RecordVocalView`)
- [x] Studio arrange landscape + piano/pads unchanged when not in record

**Week 41 notes:** Unlock on `StudioView.onDisappear` to avoid mask leaks. Preference change while recording re-applies immediately. Cloud/backend remains Month 11+ parallel work.

### Week 42 — Per-part drum mute ✅

**Done when (BandLab / GarageBand kit-piece mute)**
- [x] Each Kick / Snare / Hats / Toms / Perc / Ride row has an **M** toggle in the expanded part folder
- [x] Mute silences that part in playback + bounce without deleting `midiNotes`
- [x] Persisted on `MXSessionTrack.mutedDrumParts` (Codable; older projects decode empty)
- [x] WAV bed re-renders from `excludingMuted` notes on toggle; empty audible → silence WAV
- [x] New MIDI drum captures store full notes but render bed with current mutes
- [x] Muted lanes dim in arrange; track-level M still mutes the whole track
- [x] Live pads stay audible while composing (mute is playback/mix state)
- [x] Unit tests for mute filter + silence WAV

**Week 42 notes:** Parts remain one shared performance clip (no per-part WAVs). Playlist takes still win over part columns when ≥2 takes. Deferred: nested takes×parts, step sequencer, SFZ choke.

### Week 43 — Arrange timeline strip meters ✅

**Done when (Logic / Pro Tools / BandLab arrange meters)**
- [x] Each expanded arrange track header shows a live vertical peak meter during playback
- [x] Same levels as mixer (`trackPlaybackLevels` / peak-hold) — no new AVAudio taps
- [x] Mute/solo quiet the meter; stop/pause decay/zero via existing poll
- [x] Playlist / drum-part folders: one meter per parent track (not per sub-row)
- [x] Collapsed Hide Tracks rail: no meter (layout unchanged)
- [x] Input record meters unchanged

**Week 43 notes:** Slim 5 pt meter beside M/S in `StudioTrackHeader`. Reuses Week 38 post-FX / trackMixer taps.

### Week 44 — Per-part drum solo ✅

**Done when (BandLab / GarageBand kit-piece solo)**
- [x] Each Kick / Snare / Hats / Toms / Perc / Ride row has an **S** toggle in the expanded part folder
- [x] Solo isolates audible parts (mute wins over solo for the same part)
- [x] Multi-part solo is additive; empty solo set = all unmuted parts audible
- [x] Persisted on `MXSessionTrack.soloedDrumParts` (Codable; older projects decode empty)
- [x] WAV bed re-renders via `MXDrumPart.audibleNotes(muted:soloed:)`
- [x] Live pads stay audible while composing
- [x] Unit tests for solo + mute interaction

**Week 44 notes:** Same shared performance clip as mute. Nested takes×parts still deferred.

### Month 11 remaining

| Focus | Status |
|-------|--------|
| Cloud / backend beyond local MVP (auth, social, AI) | **Planned** |
| Optional: nested takes×drum parts; step sequencer; SFZ choke | Backlog |

---

## Month 12 — SOTA DAW polish *(Weeks 45–48)*

Reference: GarageBand / BandLab MIDI quantize; Logic / Pro Tools fade wedges; Ableton / BandLab stem export; Mixed In Key / GarageBand tempo detect.

| Week | Focus | Status |
|------|--------|--------|
| **45** | MIDI quantize lite — snap captured note starts to 16ths | **Done (MVP)** ✅ |
| **46** | Clip fade wedges on arrange timeline (visual equal-power fades) | **Done (MVP)** ✅ |
| **47** | Stem export — one WAV(+M4A) per track from Export sheet | **Done (MVP)** ✅ |
| **48** | Import tempo detect lite (estimate BPM from imported audio) | **Done (MVP)** ✅ |

### Week 45 — MIDI quantize lite ✅

**Done when (GarageBand / BandLab Quantize)**
- [x] Pure `MXMIDIQuantize` snaps note `startBeat` to 16th grid; length preserved
- [x] Studio Settings toggle “Quantize MIDI capture” (default **on**), separate from arrange snap
- [x] Drum + piano Pause/Stop commit applies quantize to absolute starts before localizing / rendering bed
- [x] Live pads/keys stay unquantized while playing
- [x] Unit tests for snap edges, length preserve, empty / bad resolution

**Week 45 notes:** Arrange `snapBeat` shares `MXMIDIQuantize.snapBeat`. Strength / swing deferred.

### Week 46 — Clip fade wedges ✅

**Done when (Logic / Pro Tools fade visualization)**
- [x] Active arrange clips show equal-power fade-in / fade-out wedges matching `fadeInSeconds` / `fadeOutSeconds`
- [x] Wedge width converts seconds → beats via project BPM (`MXClipFadeGeometry`)
- [x] Drawn on `InteractiveStudioClip` (summary, playlist, drum-part lanes); not on ghosts / empty shells
- [x] Edit remains clip inspector sliders (drag-to-edit deferred)
- [x] Unit tests for beat width + equal-power gain helpers

### Week 47 — Stem export ✅

**Done when (Ableton / BandLab stem bounce)**
- [x] Export sheet → “Export stems” bounces each track with audio to its own WAV + M4A
- [x] Ignores mute/solo (true stems); skips tracks with no active audio files
- [x] Same loudness toggle as mix bounce (Reels −14 LUFS or peak)
- [x] Share sheet presents all stem files
- [x] Per-stem FX / fades via existing `mixClip` path

### Week 48 — Import tempo detect lite ✅

**Done when (Mixed In Key / GarageBand / BandLab tempo detect lite)**
- [x] Pure `MXTempoDetect` estimates BPM from mono PCM + sampleRate via energy-onset autocorrelation (60–200)
- [x] Studio `importAudioFile` auto-applies confident estimate via `setBPM` (clamped 40–240); stores `lastDetectedBPM`
- [x] Detect failure is non-fatal — import still places the clip at the current project BPM
- [x] Clip `lengthBeats` computed after any tempo update
- [x] Unit tests: synthetic click trains (90/120/140), silence, short/empty input

**Week 48 notes:** Auto-apply + banner (“Tempo set to N BPM from import”) + transport BPM. Full beat grid / Mixed In Key key+BPM deferred.

---

## Month 13 — Performance + wow polish *(Weeks 49–52)* ✅

Reference: BandLab step sequencer; GarageBand Smart Drums; Logic automation; Cubasis / FL Mobile piano roll depth.

| Week | Focus | Status |
|------|--------|--------|
| **49** | Drum step sequencer lite (16-step × kit parts → MIDI clip) | **Done (MVP)** ✅ |
| **50** | Drag fade wedges to edit clip fades | **Done (MVP)** ✅ |
| **51** | Quantize strength / swing + re-quantize selected clip | **Done (MVP)** ✅ |
| **52** | Volume automation lane lite (track) | **Done (MVP)** ✅ |

### Week 49 — Drum step sequencer lite ✅

**Done when (BandLab / GarageBand Smart Drums lite)**
- [x] Pure `MXDrumStepSequencer` maps 6 kit rows × 16 steps ↔ MIDI notes
- [x] Studio Pads / Steps toggle on drums surface; cell tap previews kit hit
- [x] **Add to timeline** places one-bar MIDI clip + WAV bed at playhead
- [x] Unit tests: empty, four-on-the-floor, round-trip, toggle bounds

**Week 49 notes:** Fixed velocity / 1 bar only. Pattern library, step cursor, load-from-clip deferred.

### Week 50 — Drag fade wedges ✅

**Done when (Logic / Pro Tools fade drag)**
- [x] Selected clips show fade-in / fade-out knobs on wedge edges
- [x] Drag converts Δx → seconds via `MXClipFadeGeometry.seconds`; live wedge preview
- [x] Commits through `setClipFades` with undo snapshot; inspector sliders still work
- [x] Inverse geometry unit tests

### Week 51 — Quantize strength / swing ✅

**Done when (GarageBand Strength + Logic Swing)**
- [x] `MXMIDIQuantize.quantizeStarts` accepts strength 0…1 + swing 0…1 (odd 16ths)
- [x] Capture commit uses session Strength / Swing; Settings sliders when Quantize on
- [x] Clip inspector **Re-quantize MIDI** rewrites notes + audible bed
- [x] Unit tests for strength 0/0.5, swing delay, empty

### Week 52 — Volume automation lane lite ✅

**Done when (Logic / Ableton volume automation lite)**
- [x] `MXAutomationPoint` + `MXVolumeAutomation` linear interp; persisted on track
- [x] Track header **A** toggles automation lane; tap add / drag move / tap-again delete
- [x] Live playhead follows automation; bounce samples per-frame gain
- [x] Unit tests for interp, upsert, move/remove

**Week 52 notes:** Track-level only (not clip-relative). No pencil draw / pan automation yet.

---

## Month 14 — Award-app DAW depth *(Weeks 53–56)* ✅

Raise existing features to SOTA bars from BandLab, GarageBand, Logic, Cubasis, FL Mobile, CapCut/Reels.

| Week | Focus | Status | Reference |
|------|--------|--------|-----------|
| **53** | Step seq velocity + multi-bar patterns + load grid from selected clip | **Done (MVP)** ✅ | BandLab / FL Mobile |
| **54** | Clip-relative volume + pan automation; meet-in-middle fade clamp | **Done (MVP)** ✅ | Logic / Ableton |
| **55** | Piano-roll lite (edit note start/pitch on selected MIDI clip) | **Done (MVP)** ✅ | Cubasis / GarageBand |
| **56** | Latency calibration UX + input monitoring polish | **Done (MVP)** ✅ | GarageBand / BandLab |

### Week 53 — Step seq velocity + multi-bar + load from clip ✅

**Done when (BandLab / FL Mobile)**
- [x] Velocity grid `[[UInt8]]` (0=off, 1–127=on); cell opacity + vertical drag
- [x] Pattern length 1 / 2 / 4 bars; `patternLengthBeats(bars:)` + resize
- [x] **Load** from selected drums MIDI clip; **Add** advances playhead by pattern length
- [x] Unit tests: multi-bar round-trip, velocity preserve, inferred bars, louder-wins

**Week 53 notes:** 3-bar patterns via inferred load only (picker is 1/2/4). Step playback cursor deferred.

### Week 54 — Clip-relative vol/pan automation + meet-in-middle fades ✅

**Done when (Logic / Ableton)**
- [x] `MXClipFadeGeometry.meetInMiddle` — prefer edited edge or proportional shrink
- [x] `setClipFades` / trim / envelope use meet-in-middle clamp
- [x] Clip-local `volumeAutomation` + `panAutomation` on `MXClip`; live + bounce follow
- [x] Automation lane modes: Track / Clip Vol / Clip Pan (selected clip)
- [x] Unit tests: meet-in-middle, pan interp/combine, beat clamp

**Week 54 notes:** Clip pan is offset added to track pan (clamped −1…1). Bezier / pencil draw deferred.

### Week 55 — Piano-roll lite ✅

**Done when (Cubasis / GarageBand)**
- [x] `MXMIDINoteEdit` clamp / move / add / remove helpers + unit tests
- [x] Session `updateMIDINote` / `addMIDINote` / `deleteMIDINote` re-render audible bed
- [x] `MIDIPianoRollEditorView` — drag pitch/start, tap add, tap-again delete
- [x] Clip inspector **Edit Piano Roll** opens the editor for MIDI clips

**Week 55 notes:** Note length resize and multi-select deferred. Drum clips share the same editor.

### Week 56 — Latency calibration UX + monitor polish ✅

**Done when (GarageBand / BandLab)**
- [x] Studio Settings: auto-calibrate gated on headphones; applied ms readout
- [x] Manual 0–80 ms offset slider + Reset; persist via `MXLatencyCalibrator`
- [x] Monitor tip tied to calibration; clear error / unstable σ warning retained
- [x] Engine chirp loopback path already trims takes via compensation frames

**Week 56 notes:** Hardware loopback still needs real headphones. Simulated measure remains for CI. Month 14 gate passed (local MVP).

## Month 15 — SOTA polish epic *(Weeks 57–60)* ✅

Raise shipped features to award-app bar without blocking cloud work.

| Week | Focus | Status | Reference |
|------|--------|--------|-----------|
| **57** | Step pattern library + copy/paste bars + live step cursor | **Done (MVP)** ✅ | BandLab / FL Mobile |
| **58** | Piano-roll note length drag + velocity lane | **Done (MVP)** ✅ | Cubasis / Logic |
| **59** | Master bus limiter + live LUFS meter | **Done (MVP)** ✅ | GarageBand / Reels |
| **60** | Figma pixel-pass After Record + Drum Midi shells | **Done (MVP)** ✅ | Figma `95:85026` / `95:88141` |

### Week 57 — Step pattern library + copy/paste + live cursor ✅

**Done when (BandLab / FL Mobile / Ableton Push)**
- [x] Pattern **Library** menu: Four-on-floor, Boom-bap, Half-time, Disco hats → fill grid (tile across bars)
- [x] **Copy** / **Paste** one bar into selected bar index (`extractBar` / `replacingBar`)
- [x] Live step **cursor** highlights current 16th while transport plays (`stepIndex(atBeat:bars:)`)
- [x] Unit tests: step wrap, extract/replace/copy bar, preset motifs + multi-bar tile

**Week 57 notes:** Clipboard is session-local (`@State`). Cursor wraps over pattern length independent of arrange loop. Swing-on-steps still deferred.

### Week 58 — Piano-roll note length + velocity lane ✅

**Done when (Cubasis / Logic / FL Mobile)**
- [x] Trailing-edge drag resizes note `lengthBeats` (`MXMIDINoteEdit.resizing`)
- [x] Velocity lane under roll: vertical drag sets 1…127; bar height + note opacity reflect velocity
- [x] Session `updateMIDINote` accepts optional length + velocity; bed re-renders on gesture end
- [x] Unit tests for resize clamp + velocity clamp

**Week 58 notes:** Multi-select / transpose deferred. Length handle is the right ~25% of each note block.

### Week 59 — Master bus limiter + live LUFS ✅

**Done when (GarageBand / Reels)**
- [x] Settings **Master limiter** toggle (UserDefaults, default on) → live Dynamics brickwall on `masterBus` + bounce `masterLimiterEnabled`
- [x] Live momentary LUFS readout on Mixer header (`masterBus` tap → mean-square → LUFS)
- [x] `MXLoudness.momentaryLUFS` / public `loudnessFromMeanSquare` + unit tests
- [x] Bounce / stems respect limiter off (still allow peak/LUFS normalize without brickwall)

**Week 59 notes:** Not K-weighted / not broadcast-legal. Live LUFS is momentary (poll window), not integrated program loudness. Loudness report sheet deferred.

### Week 60 — Figma pixel-pass After Record + Drum Midi ✅

**Done when (Figma `95:85026` / `95:88141`)**
- [x] Pin Studio header **64** / landscape **56**; action board **76** / **64** (parity with Record transport)
- [x] Drum pad surface **148** portrait; step seq **200** / **140** so arrange keeps room
- [x] Drum part rows **36** / **32**; ADD TRACK **40**; track list spacing **2**; banners align to header
- [x] Action-board **snap magnet** toggle; expanded-part meter uses arrangement height

**Week 60 notes:** No Figma MCP in cloud — parity from ROADMAP W31 tokens + Record chrome. Create hub + landscape re-audit remain optional polish.

## Month 16 — Award-app depth *(Weeks 61–64)* ✅

Improve what already ships to SOTA bars from BandLab, GarageBand, Logic, Cubasis, FL Mobile.

| Week | Focus | Status | Reference |
|------|--------|--------|-----------|
| **61** | Step-seq swing independent of MIDI swing + pattern slots save/recall | **Done (MVP)** ✅ | BandLab / FL Mobile |
| **62** | Piano-roll multi-select transpose + scale lock lite | **Done (MVP)** ✅ | Cubasis / Logic |
| **63** | Sidechain lite (kick → bass) + shared reverb send visual | **Done (MVP)** ✅ | Ableton / GarageBand |
| **64** | Snap resolution picker (1/8, 1/16, 1/32) + beat grid density | **Done (MVP)** ✅ | Logic / Pro Tools |

### Week 61 — Step swing + pattern slots ✅

**Done when (BandLab swing + FL Mobile slots)**
- [x] `MXDrumStepSequencer.notes(..., swing:)` delays odd 16ths via `MXMIDIQuantize.swungGridBeat`
- [x] Session `drumStepSwing` persisted; independent of `midiQuantizeSwing`
- [x] User pattern slots A–D save/recall/clear (`PatternSlotBank` + UserDefaults)
- [x] Step seq UI: Swing slider + Slots menu; surface height 224/158
- [x] Unit tests for swing delay + slot bank Codable

**Week 61 notes:** Live cursor stays on the straight 16th grid (FL Mobile). Swing applies at **Add to timeline** only.

### Week 62 — Piano-roll multi-select + scale lock ✅

**Done when (Cubasis multi-select + Logic transpose / scale)**
- [x] Multi-select `Set<UUID>`; tap = sole select / delete; long-press toggles membership
- [x] Batch Δ-drag move via `movingMany` / `moveMIDINotes`
- [x] Transpose chrome ±1 / ±12
- [x] `MXMIDIScale` Major / Natural Minor + scale lock snap on add/drag (hidden for drums)
- [x] Unit tests for transpose, movingMany, scale snap

**Week 62 notes:** Draw mode / marquee deferred. Scale lock is session-local UI state.

### Week 63 — Sidechain lite + shared reverb send visual ✅

**Done when (Ableton / GarageBand sidechain + shared send)**
- [x] Pure `MXSidechainDuck` (Effects): `gain(timeSinceTrigger:amount:attack:release:)` instant-duck → hold → linear release; `secondsSinceKick(playheadBeat:notes:bpm:)` finds the nearest past kick (note 36 / `MXDrumPart.kick`, raw-36 fallback via `isKick`)
- [x] `MXSessionTrack.sidechainEnabled` (default false) + `sidechainAmount` 0…100 (default 50); Codable decode-with-defaults for back-compat
- [x] `StudioSessionController.setSidechainEnabled(_:trackID:)` / `setSidechainAmount(_:trackID:)`
- [x] Duck folded into `applyVolumeAutomationAtPlayhead` + `syncLiveInstrumentMix`: source = drums-category MIDI clip kicks; multiplied into destination clip/live-instrument volume at the playhead; `applyPlayhead` now ticks the mix when any track has sidechain on
- [x] Mixer UI: compact **SC** toggle + amount on channel strips; **Sidechain** toggle + SC Amt in the FX sheet (hidden on the drum source track); `insertChainBar` shows **SC** chip when armed
- [x] Shared reverb send visual: **Send** control now on audio strips too (aliases into insert Rev via `setTrackReverbSend`); `insertChainBar` shows **Send** chip when `reverbSend > 0.5` for audio + MIDI
- [x] Unit tests: `MXSidechainDuck` gain curve (ducked at trigger, ~1 after release, amount 0 → always 1) + `secondsSinceKick` nearest-past-kick / tempo scaling / nil cases

**Week 63 notes:** Apple's `DynamicsProcessor` is self-keyed only, so this is an **envelope duck** (playback mix), not a real key-input sidechain — bounce path unchanged this week. Audio tracks are not rewired into a real aux bus; Send stays aliased to the insert Rev mix (shared visual only).

### Week 64 — Snap resolution + beat grid density ✅

**Done when (Logic / Pro Tools snap resolution)**
- [x] `StudioSessionController.SnapResolution` enum (1/8 = 0.5, 1/16 = 0.25, 1/32 = 0.125), `Codable` / `CaseIterable`
- [x] Session `snapResolution` (default 1/16); `snapBeat(_:)` passes `snapResolution.beats` into `MXMIDIQuantize.snapBeat(_:resolution:)`
- [x] Arrange min-length floors scale to the grid cell (`max(0.125, snapResolution)`) so 1/32 trims tighter
- [x] `MXMIDIQuantize.eighth` / `.thirtySecond` named constants (sixteenth already existed)
- [x] Settings segmented picker under Snap toggle (visible when snap on); subtitle reflects current resolution
- [x] `StudioView.beatNet` draws subdivision lines at snap resolution (bar strong / beat medium / subdiv lighter), capped at 128 lines; `beatsVisible = 8`
- [x] `MXMIDIQuantizeTests` extended for snapBeat at 0.5 and 0.125 resolutions

**Week 64 notes:** `snapResolution` is a session preference (not persisted), matching `isSnapEnabled`. MIDI/step-seq quantize keeps its own 16th grid — only arrange edits and the beat overlay follow the picker.

## Month 17 — Arrange snap SOTA *(Weeks 65–68)* ✅

Raise arrange snap + grid chrome to Logic / Pro Tools award-app bar.

| Week | Focus | Status | Reference |
|------|--------|--------|-----------|
| **65** | Triplet + dotted snap grids (1/8T, 1/16T, 1/8., 1/16.) | **Done (MVP)** ✅ | Logic / Pro Tools |
| **66** | Snap readout on arrange ruler + magnet chrome | **Done (MVP)** ✅ | Logic / Pro Tools |
| **67** | Zoom-adaptive grid density (auto-thin subdivs) | **Done (MVP)** ✅ | Logic / Ableton |
| **68** | Piano-roll draw mode lite | **Done (MVP)** ✅ | Cubasis / FL Mobile |

### Week 65 — Triplet + dotted snap grids ✅

**Done when (Logic / Pro Tools snap menu)**
- [x] `SnapResolution` String-backed enum adds `eighthTriplet` (1/3), `sixteenthTriplet` (1/6), `dottedEighth` (0.75), `dottedSixteenth` (0.375)
- [x] `MXMIDIQuantize` constants for triplet + dotted resolutions; `snapBeat` works unchanged
- [x] Settings Grid control is a Menu (7 options) instead of a 3-way segmented picker
- [x] `beatNet` subdiv overlay follows any resolution including irrational triplets
- [x] Unit tests for 1/8T, 1/16T, dotted 1/8, dotted 1/16 snap edges

**Week 65 notes:** MIDI capture quantize stays on its own 16th grid. Snap preference still session-local.

### Week 66 — Snap readout on ruler + magnet ✅

**Done when (Logic / Pro Tools ruler chrome)**
- [x] Action-board magnet shows active `displayName` (`1/16`, `1/8T`, …) when snap is on
- [x] Long-press magnet cycles `SnapResolution.next` (enables snap if off)
- [x] Arrange ruler trailing badge shows the same resolution label
- [x] Accessibility labels include the active grid name

**Week 66 notes:** Tap still toggles snap on/off; long-press cycles resolution (GarageBand/Logic muscle memory).

### Week 67 — Zoom-adaptive grid density ✅

**Done when (Logic / Ableton)**
- [x] Pure `MXBeatGridDensity` — `visibleSubdivBeats` coarsens/hides subdivs when pixels-per-line &lt; 6; zoom clamp helpers
- [x] `beatNet` draws coarsened subdivs (or none) based on current `pixelsPerBeat` while snap edits keep full resolution
- [x] Arrange `beatsVisible` is session-local `@State` (4 / 8 / 16 / 32); ruler **− / +** buttons + pinch-on-ruler
- [x] Unit tests for draw threshold, coarsen/nil, zoom clamp/steps

**Week 67 notes:** Pinch lives on the ruler only so clip drag/trim stays free. Pinch settles to the nearest stop on end.

### Week 68 — Piano-roll draw mode lite ✅

**Done when (Cubasis / FL Mobile)**
- [x] Pure `MXMIDINoteEdit.applyingPaintCell` / `cellStart` / `cellOccupied` — paint inserts snap-length note; erase removes overlapping pitch+cell
- [x] Session `paintMIDINoteCell` + `addMIDINote(..., lengthBeats:)`
- [x] Piano-roll **pencil** toggle; drag stroke paints or erases (first cell sets polarity); notes ignore hits while drawing
- [x] Snap cell follows arrange `snapResolution` when magnet on (else 16th); scale lock respected
- [x] One undo per stroke; bed re-render on stroke end
- [x] Unit tests for floor cell, paint-once, erase, scale snap

**Week 68 notes:** Tap-add (non-draw) still uses free start + default 16th length. Velocity-while-drawing and chord paint deferred.

## Month 18 — Wow + cloud spine *(Weeks 69–72)*

| Week | Focus | Status | Reference |
|------|--------|--------|-----------|
| **69** | Pitch correction lite (vocal clip) | **Done (MVP)** ✅ | GarageBand / CapCut |
| **70** | Time-stretch clip lite | **Done (MVP)** ✅ | Ableton / BandLab |
| **71** | LUFS report sheet after bounce | **Done (MVP)** ✅ | Reels / YouTube Loudness |
| **72** | Cloud auth sync spine (beyond local MVP) | **Done (MVP)** ✅ | BandLab |

### Week 69 — Pitch correction lite ✅

**Done when (GarageBand Pitch Correction / CapCut AutoTune lite)**
- [x] Pure `MXPitchCorrect` — ACF F0, snap chromatic or Limit-to-Key pitch classes, amount 0…1, windowed OLA resample
- [x] Session `applyPitchCorrection` bakes trimmed region → new WAV (undo; keeps fades/gain/timeline)
- [x] Clip inspector: Amount slider + Limit to key (project `musicalKey`) + Apply (audio clips only)
- [x] Unit tests: midi math, detect A4, amount 0 identity, flat tone pulls toward chromatic, silence safe

**Week 69 notes:** Not Flex Pitch note blobs / formant preserve / live AUTimePitch. Bounce inherits baked file automatically.

### Week 70 — Time-stretch clip lite ✅

**Done when (Ableton warp / BandLab stretch lite)**
- [x] Pure `MXTimeStretch` WSOLA-lite — factor 0.5…2.0 pitch-preserving OLA; identity near 1.0
- [x] Session `applyTimeStretch(toLengthBeats:)` bakes new WAV; updates lengthBeats, fades, clip automation
- [x] Clip inspector: stretch length slider (0.5×…2×) + Apply Time Stretch
- [x] Unit tests: identity, 1.5× longer, 0.75× shorter, empty safe

**Week 70 notes:** No warp markers / transient mode / live AUTimePitch. MIDI clips excluded (stretch notes separately later).

### Week 71 — LUFS report sheet after bounce ✅

**Done when (Reels / YouTube loudness report lite)**
- [x] `MXLoudness.Report` — integrated LUFS + sample-peak dBFS + optional target headroom
- [x] Bounce `Result` carries measured LUFS / peak / target after normalize
- [x] Export success UI shows Loudness report card (Integrated, Target, Headroom, True peak)
- [x] Unit tests for report tone / headroom / silence

**Week 71 notes:** Labeled “Approx LUFS · not broadcast-certified” — still mean-square gated MVP, not K-weighted ITU meter. Stems bounce does not yet attach per-stem reports.

### Week 72 — Cloud auth sync spine ✅

**Done when (BandLab account sync lite)**
- [x] `MXAuthSession.cloudLinked` — signed-in true; guest/sign-out false; persisted
- [x] `MXCloudSyncSpine` — status idle/syncing/offline/error + `lastSyncedAt`; stub `syncNow` (no network/secrets)
- [x] Profile (`MyMixView`) shows sync row + Sync now; guest shows Local only
- [x] `finishSignIn` kicks stub sync for linked accounts

**Week 72 notes:** Stub only — no remote API. Real backend / Keychain tokens remain operator work.

## Month 19 — Award-app SOTA *(Weeks 73–76)*

Raise shipped DAW features toward award-winning mobile music apps (BandLab, GarageBand, Cubasis, Logic Remote bars).

| Week | Focus | Status | Reference |
|------|--------|--------|-----------|
| **73** | Vocal harmonies lite (1–2 voice stack bake) | **Done (MVP)** ✅ | CapCut / BandLab |
| **74** | Beat browser + one-shot pack import | **Done (MVP)** ✅ | BandLab / Loopcloud |
| **75** | Real key-input sidechain + bounce duck parity | **Planned** | Ableton / Logic |
| **76** | K-weighted LUFS upgrade + inter-sample true peak | **Planned** | ITU BS.1770 / YouTube |

### Week 73 — Vocal harmonies lite ✅

**Done when (CapCut auto-harmony / BandLab vocal stack)**
- [x] Pure `MXHarmony` — fixed-interval duration-preserving OLA pitch shift + `stack` (dry + voices, soft peak normalize)
- [x] Preset intervals: Major 3rd (+4), Perfect 5th (+7), Low 4th (−5)
- [x] Session `applyHarmonies` bakes trimmed region → new WAV (undo; keeps fades/gain/timeline)
- [x] Clip inspector: Third / Fifth / Low 4th toggles + Mix slider + Apply Harmonies (audio clips only)
- [x] Unit tests: ratio math, identity, length preserve, pitch raise, mix energy, silence safe

**Week 73 notes:** Not live formant-preserving harmony / separate track-per-voice / MIDI harmony. Bounce inherits the baked stack automatically.

### Week 74 — Beat browser + one-shot pack import ✅

**Done when (BandLab / Loopcloud lite)**
- [x] `MXBeatCatalog` — 4 procedural loops + 4 one-shots (no binary assets); PCM → WAV writer
- [x] `BeatBrowserView` — Loops / One-shots list; tap imports
- [x] Session `importBeatItem` — new imported track + clip at beat 0 (no tempo-detect on one-shots)
- [x] Studio **+** → **Beats** entry (alongside Import / AI)

**Week 74 notes:** Procedural first-party stubs only — not licensed Loopcloud packs / MXPacks download. Create hub Sampler tile still disabled.

**SOTA backlog (enter when spare capacity — improve what already ships)**
- **Capture:** Punch UI chrome parity with Figma landscape Rec; take comp crossfade dial; pre-roll ms in Settings already — surface better
- **Drums:** SFZ kit choke groups; nested takes × part columns
- **Step seq:** Swing per step grid ✅ W61; pattern slots save/recall ✅ W61; SFZ kit choke later
- **Piano roll:** Multi-select transpose ✅ W62; scale lock ✅ W62; draw mode ✅ W68
- **Automation:** Bezier / curved automation; relative vs absolute clip gain modes
- **Mix:** Sidechain lite from kick to bass ✅ W63 (envelope duck); shared reverb send visual ✅ W63; certified LUFS / loudness report sheet ← W71; real key-input sidechain + audio aux bus later
- **Arrange:** Snap resolution picker ✅ W64; beat grid density ✅ W64; triplet/dotted ✅ W65; ruler/magnet readout ✅ W66; zoom-adaptive densify ✅ W67; clip gain automation later
- **Export:** Video + audio Reels export; loudness report sheet after bounce ✅ W71
- **Wow:** Pitch correction lite ✅ W69; time-stretch clip ✅ W70; harmonies ✅ W73; beat browser ✅ W74
- **Social/AI:** Cloud auth sync stub ✅ W72; real model API for AI compose; live Discover catalog; real cloud backend
- **Figma parity:** Create hub + landscape 812×375 second pass; After Record chrome re-audit vs `95:85026`
- **SOTA polish candidates:** Clip gain automation; take-lane crossfade dial; inter-sample true-peak ← W76; sidechain on bounce path ← W75; audio→aux reverb bus; K-weighted LUFS ← W76; SFZ kit choke; nested takes×parts; Bezier automation; video+audio Reels export; real MXPacks / Loopcloud catalog

**SOTA next (Month 19 remainder / beyond)**
- Nested takes × drum parts; SFZ kit choke
- Video+audio Reels export; real MXPacks download
- Cloud auth / social / AI beyond local MVP
- Real key-input sidechain + audio→aux reverb bus ← W75
- Bezier automation; K-weighted LUFS ← W76

## Month 18 implementation notes

*(Weeks 69–72 continue below Month 17.)*

### Implementation notes (shared — Month 9)

1. Prefer **one Studio shell** with `StudioPreset` / track `category` driving overlays (pedalboard, keyboard, drum pads, landscape `ViewThatFits` / size-class layouts).
2. Ship **vertical slice per week** — UI + audio path — not all Figma variants in one PR.
3. Reference apps: BandLab (pads + multi-track), GarageBand (keyboard, guitar amps, Quick), Logic (hide tracks density).
4. Defer: full amp sims, pro piano roll depth, AUv3 hosting depth.

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
- Snap to grid, loop region ✅ Week 27+ (loop + `isSnapEnabled`; W64 resolution picker 1/8·1/16·1/32 + beat grid density)
- Undo/redo ✅ Week 27

### Mix / FX
- Full mixer view ✅ Week 30 channel strips
- Insert chain UI ✅ Week 30 FX chips + Record EQ entry
- Shared reverb send ✅ MIDI aux; audio Rev on strip; W63 Send control + chip on audio strips too
- Sidechain lite (kick → bass) ✅ W63 envelope duck (`MXSidechainDuck`); real key-input sidechain later
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
- Noise gate / light denoise ✅ Week 27 bounce + Week 28 live/monitor expander (`syncMonitorChain` / vocal gate)
- Wet guitar monitor ✅ Week 39 `MXMonitorGuitarFX` parallel pedalboard (dry DI write)
- De-esser ✅ Week 28 (live EQ peaking ~6.5 kHz + bounce `MXBiquad`; Reels Vocal enables light amount)
- Mono record default for vocals ✅ Week 27+ (`preferMonoVocalRecord` + `MXRecorder.preferMono`)
- **Export loudness for Reels** ✅ Week 27 (−14 LUFS MVP)
- Quiet-room checklist (onboarding) ✅ Week 29

### Later “wow”
- Pitch correction, time stretch, harmonies
- Stem export ✅ Week 47; video+audio Reels export
- Beat browser; import tempo detect ✅ Week 48 lite (`MXTempoDetect`)

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
                  → W31–35 Instrument Studio sections ← done
                    → W36–39 Arrangement depth ← done
                      → W40–44 Drum depth + capture chrome ← done
                        → W45–48 Quantize + fades + stems + tempo detect ← done
                          → W49–52 Step seq + drag fades + swing + automation ← done
                            → W53–56 Month 14 award-app depth ✅
                              → W57–W60 Month 15 SOTA polish ✅
                                → W61–W64 Month 16 award-app depth ✅
                                  → W65–W68 Month 17 snap SOTA + piano draw ✅
                                    → W73 Month 19 harmonies ✅ ← next W74–76
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
| 31–35 | Guitar / Piano / Drum / Landscape Studio |
| 36–39 | Arrangement depth (X-fades → playlist → meters → wet monitor) |
| 40–44 | Drum part lanes + mute/solo + record chrome + timeline meters |
| 45–48 | MIDI quantize + fade wedges + stem export + import tempo |
| 49–52 | Step sequencer + drag fades + swing quantize + automation *(done)* |
| 53–56 | Step velocity / clip automation / piano-roll lite / latency UX *(done)* |
| 57–60 | Step library + piano-roll depth + master LUFS + Figma pixel-pass *(done)* |
| 61–64 | Step swing / multi-select / sidechain / snap resolution *(done)* |
| 65–68 | Triplet/dotted snap + ruler readout + zoom grid + piano draw *(done)* |
| 69–72 | Pitch correction / time-stretch / LUFS report / cloud auth spine *(done)* |
| 73–76 | Harmonies ✅ / beat browser / real sidechain / K-weighted LUFS |

---

*Reframe in one line:* Months 1–2 are not “BandLab the social app” — they are a **working mobile DAW for audio tracks**, with Flow B (Create hub) as the doorway into Studio, and Reels-grade vocal capture as the quality bar for the first recording path.
