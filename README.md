# House Music

Multi-room audio controller for a mixed Yamaha MusicCast / AirPlay home network.

## Spec

We have a multi-room home network with two Yamaha receivers. The DJ controller and SL1210s are plugged into the RX-V685 as "Decks".

### Rooms and devices

| Room | Devices |
|---|---|
| Living Room | Yamaha RX-V685 with an Apple TV; DJ controller and SL1210s plugged in as "Decks" |
| Dining Room | Yamaha WXA-50 (AirPlay 1) |
| Master Bedroom | Yamaha RX-S602 with another Apple TV |
| Master Bathroom | Yamaha WXA-50 |
| Office | Yamaha WXA-50 |

The Dining Room WiiM Mini is not part of this system (it cannot join MusicCast groups).

### Play modes

- Streaming from our iPhones or laptops (BBC Sounds, podcasts, etc)
- Spotify from our iPhones or laptops
- Playing from Decks into multiple rooms; most often just Living Room and Dining Room (upstairs) but occasionally whole house
- "DJ time": playing from Decks when DJing. Living Room only, with Pure Direct set on the RX-V685
- "Telly time": Apple TV, Living Room output only
- "TV in bed": Apple TV in Master Bedroom only
- "Upstairs Downstairs": whole house except Office
- "Whole House": includes the Office
- "All off": everything off

### Preset semantics

Presets are declarative: activating one puts the whole house into that state. Rooms not in the preset turn off. Devices are assumed always available; no offline or partial-failure handling.

### Features

- Very simple iOS and Apple Watch app with the right combination of presets for inputs and outputs
- Live state: the app reflects the actual state of the devices, including changes made elsewhere (MusicCast app, remotes, front panels)
- Universal volume control across the active preset's rooms
- Per-room, per-preset volume baselines: activating a preset restores its baselines, and a "save this volume to preset" action calibrates the baseline from the current level
- Siri support for selecting presets: "Spotify in Dining Room", "TV in bed", "DJ time", "Decks upstairs", etc
- Spotify Web API integration: presets that involve Spotify transfer the active session to the right room or group themselves, so "Spotify in Dining Room" works end to end without opening the Spotify app. We have a family plan; each user logs into their own account on their own device (more users may be added later)
- Presets that use an Apple TV wake it where the HDMI chain supports it: the Living Room projector does CEC, the Master Bedroom one does not (acceptable; use the remote there)

Explicitly not wanted: native internet radio presets (the built-in radio is a pain and we never use it); streaming stays phone-originated.

That's it.

## Infrastructure notes

- The Master Bedroom RX-S602 is the only device on Wi-Fi; accepted as-is
- DHCP reservations for the Yamahas are in place
- Apple Developer account exists: team 86H54WCPYP, bundle prefix org.whitelabel, same setup as the [eightful](https://github.com/smagdali/eightful) repo (which is also the iOS + watchOS project template to crib from)
- Distribution: App Store release preferred, TestFlight if we have to

## Open questions

The original research questions (Yamaha APIs, AirPlay 2 vs MusicCast, WiiM per zone) are answered in [notes/research.md](notes/research.md) and [notes/network-discovery.md](notes/network-discovery.md). Still open:

- Test whether Pure Direct on the RX-V685 coexists with simultaneous MusicCast distribution
- Apple TV wake mechanism: receiver power-on plus input switch may cascade over CEC downstairs; if not, wake over the network (Companion protocol) needs investigating
