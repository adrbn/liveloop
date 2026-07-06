# LiveLoop — Design

A native macOS clone of [CamLoop](https://camloop.app), with every paid feature
free and open source. This document captures the architecture and the reasoning
behind the non-obvious choices.

## Goal

Let a user record a short clip of themselves and broadcast a **seamless loop** of
it through a **virtual camera** on any video call, switching between their live
webcam and the loop with a global shortcut, while their audio is never touched.

## Two processes

macOS exposes software cameras through **Core Media I/O (CMIO) camera system
extensions** — the only mechanism modern conferencing apps (which use library
validation) will load. The legacy DAL plug-in path is blocked. So LiveLoop is:

1. **`LiveLoop.app`** — a menu-bar app (`LSUIElement`) that owns all the logic:
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

## Signing reality

A CMIO camera extension carries the **restricted** entitlement
`com.apple.developer.system-extension.install`. With System Integrity Protection
enabled (the default), macOS will only:

- **launch** an app carrying that entitlement if a provisioning profile
  authorizes it (a paid-account / Developer ID concern), and
- **activate** the extension if it is Developer ID-signed **and** notarized, *or*
  if system-extension developer mode is on (which itself requires SIP off).

Consequently:

- **Distribution / other Macs:** Developer ID + notarization. No system changes
  for the end user.
- **Self-signed personal use:** disable SIP once and enable
  `systemextensionsctl developer on`.

The code is identical either way; only the certificate differs.

## Testing

Pure logic is isolated so it can be tested headlessly (no app host):
`PingPongSequencer`, `LagScheduler`, `SplitMix64`, and `ClipLibrary` CRUD are
covered by `Tests/LiveLoopTests`. The CMIO pieces are validated manually with
Photo Booth / QuickTime as the client.

## Deliberately out of scope (v1)

**AI frame morphing** — learned frame interpolation for a perfect single-direction
loop. Ping-pong + crossfade already reads as seamless for the low-motion clips
this tool targets, so the Core ML model is a documented stretch goal rather than
v1 weight.
