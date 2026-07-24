# House Music

Multi-room audio controller for a mixed Yamaha MusicCast / AirPlay home network.
iOS + Apple Watch, SwiftUI, targeting iOS 17 / watchOS 10.

## Build

1. `xcodegen generate` to produce `HouseMusic.xcodeproj` from [project.yml](project.yml).
2. Open in Xcode and run, or `xcodebuild -scheme HouseMusic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
3. `swift test` runs the kit unit tests. `HM_LIVE=1 swift test --filter LiveIntegrationTests` exercises the real receivers on the LAN (reads plus one muted volume round-trip on the Office, restored).
4. TestFlight: fill in [deploy/.env](deploy/env.example) and run [scripts/testflight.sh](scripts/testflight.sh).

Layout: [HouseMusicKit](Sources/HouseMusicKit) is the platform-agnostic core (YXC client, discovery, preset engine, Spotify, config store); [App/](App) holds the iOS app, Watch app, and shared model.

## Spec

We have a multi-room home network with two Yamaha receivers. The DJ controller and SL1210s are plugged into the RX-V685 as "Decks".

### Rooms and devices

| Room | Devices |
|---|---|
| Living Room | Yamaha RX-V685 with an Apple TV; DJ controller and SL1210s plugged in as "Decks"; AirPort Express plugged in as "Stream here" (a permanent AirPlay 2 target) |
| Dining Room | Yamaha WXA-50 (AirPlay 1) |
| Master Bedroom | Yamaha RX-S602 with another Apple TV |
| Master Bathroom | Yamaha WXA-50 |
| Office | Yamaha WXA-50 |

The Dining Room WiiM Mini is not part of this system (it cannot join MusicCast groups).

### Play modes

Sources and room combinations are selected independently: pick a source, pick the rooms. Named room combinations cover the common cases:

- "Upstairs": Living Room and Dining Room
- "Upstairs Downstairs": whole house except Office
- "Whole House": includes the Office

Modes:

- Streaming from our iPhones or laptops (BBC Sounds, podcasts) to one or multiple rooms (multi-room via "Stream here", see Streaming routing below)
- Playing from Spotify to one or multiple rooms (Spotify Connect interacting with MusicCast, tuned for maximum ease of use)
- Playing from Decks into one or multiple rooms as selected; most often just "Upstairs", occasionally "Upstairs Downstairs" or "Whole House"
- "DJ time": playing from Decks when DJing. Living Room only, with Pure Direct set on the RX-V685
- "Telly time": Apple TV, Living Room output only
- "TV in bed": Apple TV in Master Bedroom only
- "All off": everything off

### Preset semantics

A preset is a source plus a room combination plus its volume baselines. Presets are declarative: activating one puts the whole house into that state. Rooms not in the preset turn off. Devices are assumed always available; no offline or partial-failure handling.

Pure Direct and MusicCast distribution are mutually exclusive (confirmed by experience; that is why "DJ time" is Living Room only). The app must not offer Pure Direct on multi-room presets.

### Streaming routing

Multi-room phone streaming uses the "Stream here" pattern: you always AirPlay to the AirPort Express (input `audio5` on the RX-V685), and the active preset decides which rooms hear it by distributing that input over MusicCast Link, exactly like the Decks. The phone-side target never changes; the room combination lives in the preset. This sidesteps the WXA-50s' lack of AirPlay 2 entirely for multi-room streaming. Note the Living Room amp must be on to serve distribution, even if silent there.

Single-room streaming stays direct AirPlay to that room's device, and Spotify stays on Spotify Connect as above. If the Express ever dies, the fallback is AirPlaying to the RX-V685 itself and distributing its `airplay` input the same way.

### Features

- Very simple iOS and Apple Watch app with the right combination of presets for inputs and outputs
- Generic, not hardcoded: MusicCast devices are auto-discovered (SSDP), rooms and inputs come from the devices themselves, and presets are user-defined, so the app works in any MusicCast home and can go in the App Store
- Input/output curation in Settings: each device exposes far more inputs than we use, so configuration hides everything unused; only the curated inputs and rooms appear when defining presets
- Live state: the app reflects the actual state of the devices, including changes made elsewhere (MusicCast app, remotes, front panels)
- Universal volume control across the active preset's rooms
- Per-room, per-preset volume baselines: activating a preset restores its baselines, and a "save this volume to preset" action calibrates the baseline from the current level
- Siri support for selecting presets: "Spotify in Dining Room", "TV in bed", "DJ time", "Decks upstairs", etc
- Spotify Web API integration: presets that involve Spotify transfer the active session to the right room or group themselves, so "Spotify in Dining Room" works end to end without opening the Spotify app. We have a family plan; each user logs into their own account on their own device (more users may be added later)
- Presets do not attempt to wake the Apple TVs (tested 2026-07-14: receiver power-on plus input switch does not wake an Apple TV over CEC). Picking up the Siri remote wakes the Apple TV, which cascades to the Living Room projector via CEC; the Master Bedroom projector has no CEC either way

Explicitly not wanted: native internet radio presets (the built-in radio is a pain and we never use it); streaming stays phone-originated.

That's it.

## Infrastructure notes

- The Master Bedroom RX-S602 is the only device on Wi-Fi; accepted as-is
- DHCP reservations for the Yamahas are in place
- Apple Developer account exists: team 86H54WCPYP, bundle prefix org.whitelabel, same setup as the [eightful](https://github.com/smagdali/eightful) repo (which is also the iOS + watchOS project template to crib from)
- Distribution: App Store release. This is why the app is generic with auto-discovery; our house is just one configuration

## Open questions

None. The original research questions (Yamaha APIs, AirPlay 2 vs MusicCast, WiiM per zone) are answered in [notes/research.md](notes/research.md) and [notes/network-discovery.md](notes/network-discovery.md); Pure Direct exclusivity and Apple TV wake were settled by testing.
