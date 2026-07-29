# sfizz integration seam

## Spike result (recorded)

The plan called for vendoring [sfizz](https://github.com/sfztools/sfizz) as the SFZ
playback engine. The spike found this is not currently buildable here:

| Requirement | Status |
| --- | --- |
| `cmake` | not installed |
| `ninja` | not installed |
| Homebrew | not installed |
| `ios-cmake` toolchain | not present |
| sfizz transitive C++ deps (abseil, libsndfile, simde) | not vendored |
| Device to validate the `.a` against | not available |

AudioKit's half of the spike **did** pass, and is what the architecture actually
depends on:

```
PASS  AudioKit DynamicOscillator vends AVAudioNode (AVAudioUnitMIDIInstrument)
PASS  Owned AVAudioEngine starts with AudioKit node attached
PASS  AudioKit DSP renders non-silent audio through owned engine (peak=1.0)
PASS  System DLS soundbank exists
PASS  AVAudioUnitSampler loads system DLS
PASS  AVAudioUnitSampler renders note (peak=0.12)
```

## Decision

`MXAudioDSP` ships a **native Swift SFZ engine** (`MXSFZSampler`) behind the
`MXSFZEngine` protocol. It implements the behaviour the test scenarios actually
pin down — region matching, velocity layers, round-robins, loop points, choke
groups, and disk streaming with a preload window.

sfizz remains swappable: it only has to conform to `MXSFZEngine`. No call site
outside this seam knows which implementation is live.

## Swapping sfizz in later

1. `git submodule add https://github.com/sfztools/sfizz Vendor/sfizz/upstream`
2. Build static libs for `arm64` device + `arm64/x86_64` simulator with
   [ios-cmake](https://github.com/leetal/ios-cmake), then combine into an
   `.xcframework`.
3. Add a `.binaryTarget` for that xcframework and a `.target` holding the
   ObjC++ bridge (`MXSfizzBridge.mm`). Swift must not be called from the render
   thread, so the bridge owns the `sfizz::Sfizz` instance and exposes only
   POD-in/POD-out entry points.
4. Conform the bridge to `MXSFZEngine`.
5. Flip `MXSFZEngineFactory.preferred` to `.sfizz`.
6. Re-run the `SFZ-*` suite. Those tests are engine-agnostic by construction, so
   they are the acceptance gate for the swap.

## Bridge contract

`MXSFZEngine` (see
`Packages/MXAudioDSP/Sources/SFZ/MXSFZEngine.swift`) is deliberately
POD-only so it can be satisfied by a C or C++ implementation without bridging
Swift objects across the render boundary.
