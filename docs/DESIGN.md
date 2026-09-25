# LiveLoop — Design

A free and open-source native macOS virtual camera that loops a few seconds of
you. This document captures the architecture and the reasoning behind the
non-obvious choices.

## Goal

Let a user record a short clip of themselves and broadcast a **seamless loop** of
it through a **virtual camera** on any video call, switching between their live
webcam and the loop with a global shortcut, while their audio is never touched.

## Two processes

macOS exposes software cameras through **Core Media I/O (CMIO) camera system
extensions** — the only mechanism modern conferencing apps (which use library
validation) will load. The legacy DAL plug-in path is blocked. So LiveLoop is:

1. **`LiveLoop.app`** — a menu-bar app that owns all the logic:
   webcam capture, recording, the clip library, the loop engine, and the UI.
2. **`LiveLoopExtension`** — a CMIO camera system extension: a thin, always-on
   relay that publishes the virtual-camera device.

They share nothing but a handful of identifiers (`SharedConstants.swift`) and a
frame stream over CMIO.

### Why a thin extension + a smart app

The extension exposes a **source stream** (what meeting apps read) and a **sink
stream** (what the app writes). It relays sink → source and nothing else. All the
interesting, changeable behaviour lives in the normal app, where it is easy to
develop, debug, and unit-test. The always-running system-extension process stays
minimal, so there is very little in it that can crash. This also makes “switch
back to live” trivial: the app simply starts forwarding real webcam frames.

The cost — the app must be running for the camera to output — is exactly the
intended menu-bar model, and mirrors how OBS’s virtual camera works.

## Frame pipeline

```
Webcam ─▶ AVCaptureSession ─▶ FrameRouter ─┐
                                           ├─▶ CMIO sink ─▶ Extension ─▶ source ─▶ meeting app
Clip ─▶ LoopEngine (ping-pong + lag) ──────┘
Hotkey / menu ─▶ FrameRouter mode (live ⇄ loop, with crossfade)
```

Everything is normalised to **1920×1080 BGRA** by a single Metal-backed
`ImagePipeline`, so every buffer the extension receives is uniform.

### Seamless loop

- **Ping-pong** (`PingPongSequencer`) plays the clip forward then backward. The
  turning-point frames are shared, so the loop never cuts.
- A short **crossfade** (`ImagePipeline.blend`) smooths the live ⇄ loop switch.
- **Simulated lag** (`LagScheduler`) is a seeded PRNG (`SplitMix64`) that decides,
  per tick, whether to hold the current frame. It is deterministic given a seed
  (so it’s unit-testable) but reseeded every run (so it never visibly repeats).

### Memory

A clip is decoded once into an in-memory array of **JPEG frames**
(`ClipFrameStore`) — a few MB instead of the gigabytes raw 1080p frames would
take — and decoded on demand. Ping-pong needs random access both directions,
which this gives cheaply.

## Signing reality (a paid account is required)

A CMIO camera extension carries the **restricted** entitlement
`com.apple.developer.system-extension.install`. Authorizing it needs a
provisioning profile with the **System Extension** capability, and that
capability is **not available to free / personal Apple teams**:

```
error: Cannot create a Mac App Development provisioning profile … Personal
development teams … do not support the System Extension capability.
```

Without that profile, `sysextensiond` refuses to activate the extension and
reports the misleading *“Extension not found in App bundle”* — and this holds
**even with SIP disabled and `systemextensionsctl developer on`.** Developer mode
only relaxes the *notarization* requirement, not the requirement that the
entitlement be authorized by a profile. Verified empirically on macOS 27 / Apple
Silicon.

So there are exactly two viable paths, both needing a **paid** Apple Developer
Program membership:

- **Distribution / other Macs:** Developer ID Application signature + notarization.
  Activates with SIP on; nothing for the end user to disable.
- **Local development:** a development provisioning profile (with the System
  Extension capability) + `systemextensionsctl developer on` (which needs SIP
  off). Lets you iterate on a non-notarized build.

The code is identical either way; only the certificate/profile differs.
`scripts/release.sh` takes the first path. Automatic signing refreshes the
profiles through the Apple ID signed in to Xcode ▸ Settings ▸ Accounts, so the
script checks for one before it starts.

## Source layout

```
LiveLoop/                 Menu-bar app
  App/                    Entry point + AppState coordinator
  Camera/                 AVCaptureSession + live/loop frame router
  Loop/                   Ping-pong, lag scheduler, clip frame store, loop engine
  Recording/              AVAssetWriter clip recorder
  Library/                Clip model + library (CRUD, import/export, pin)
  VirtualCamera/          System-extension lifecycle + CMIO sink publisher
  Hotkeys/                Global hotkey (Carbon)
  Settings/ UI/ Shared/   Preferences, SwiftUI views, image pipeline
  Beta/                   Opt-in beta features (Settings ▸ Beta), all off by default
    Core/                 Their pure, unit-tested logic
LiveLoopExtension/        CMIO camera system extension (source + sink relay)
Tests/LiveLoopTests/      Loop-engine, library and beta-logic unit tests
scripts/                  release.sh · make_dmg.sh · lib.sh · make_icon.py
```

The app icon is generated from code, on Apple's macOS icon grid (an 824 px tile
on a 1024 px canvas). Regenerate the asset catalog and the README icons with:

```bash
python3 scripts/make_icon.py LiveLoop/Resources/Assets.xcassets/AppIcon.appiconset --docs docs/assets \
  --tile LiveLoopExtension/PlaceholderIcon.png --tile-size 368
```

The tile (no margin, no shadow) is what the camera extension draws on its
"Open the app to go live" card.

## Beta features

Everything under `LiveLoop/Beta/` is opt-in and must leave the default path
untouched: with every toggle off, no camera frame is sampled, no audio is
opened and no timer runs. Each feature drives the app only through the
`BetaHost` protocol (the same actions as the hotkey).

| Feature | Pure logic (`Beta/Core`) | Hooks into |
| --- | --- | --- |
| Smart switch | `PoseMatcher` (32×18 luma signatures, mean-subtracted distance) | `ClipFrameLoader` signatures, `LoopEngine.start(atFrame:)`, `FrameRouter` pending return |
| Auto away | `PresenceDetector` (hysteresis) | `LiveFrameTap` → `FaceSampler` (Vision, ~2.5 fps) |
| Connection styles | `ConnectionSimulator` (seeded, like `LagScheduler`); `LagEffects` runs it *instead of* the stutter, never both | `LoopEngine.start`/`tick`, `ImagePipeline.degraded` |
| Loop timer | `LoopSessionClock` | Menu-bar label, local notifications |
| Name alert | `NameMatcher`, `AlertCooldown` | `SFSpeechRecognizer` (on-device required), Core Audio process tap or mic |
| Automations | `AutomationCommand` (`liveloop://` parser) | Apple Event URL handler, App Intents |

## Testing

Pure logic is isolated so it can be tested headlessly (no app host):
`PingPongSequencer`, `LagScheduler`, `SplitMix64`, `ClipLibrary` CRUD and the
beta logic in `LiveLoop/Beta/Core` are covered by `Tests/LiveLoopTests`. The
CMIO pieces are validated manually with Photo Booth / QuickTime as the client.

## Deliberately out of scope (v1)

**AI frame morphing** — learned frame interpolation for a perfect single-direction
loop. Ping-pong + crossfade already reads as seamless for the low-motion clips
this tool targets, so the Core ML model is a documented stretch goal rather than
v1 weight.
