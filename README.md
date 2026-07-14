# House Music

Multi-room audio controller for a mixed Yamaha MusicCast / AirPlay home network.

## Spec

We have a multi-room home network with two Yamaha receivers. The DJ controller and SL1210s are plugged into the RX-V685 as "Decks".

### Rooms and devices

| Room | Devices |
|---|---|
| Living Room | Yamaha RX-V685 with an Apple TV; DJ controller and SL1210s plugged in as "Decks" |
| Dining Room | Yamaha WXA-50 (AirPlay 1) and WiiM Mini (AirPlay 2) |
| Master Bedroom | Yamaha RX-S602 with another Apple TV |
| Master Bathroom | Yamaha WXA-50 |
| Office | Yamaha WXA-50 |

### Play modes

- Streaming from our iPhones or laptops (BBC Sounds, podcasts, etc)
- Spotify from our iPhones or laptops
- Playing from Decks into multiple rooms; most often just Living Room and Dining Room (upstairs) but occasionally whole house
- "DJ time": playing from Decks when DJing. Living Room only, with Pure Direct set on the RX-V685
- "Telly time": Apple TV, Living Room output only
- "TV in bed": Apple TV in Master Bedroom only
- "Upstairs Downstairs": whole house except Office
- "Whole House": includes the Office

### Features

- Very simple iOS and Apple Watch app with the right combination of presets for inputs and outputs
- Universal volume control, but with the ability to calibrate the per-room baseline in Settings
- When a preset is activated after a break, volume is returned to that baseline
- Siri support for selecting presets: "Spotify in Dining Room", "TV in bed", "DJ time", "Decks upstairs", etc

That's it.

## Open questions

- Can we query the network to identify the servers?
- Research Yamaha's APIs for controlling their receivers. They all have web interfaces too.
- Which combination of AirPlay 2, MusicCast, Apple Home, and Yamaha API control best supports these features?
- Should we buy a WiiM for each WXA-50 for simplicity/effectiveness? The mixed multi-room support we have now, because of the lack of AirPlay 2 everywhere, is a pain.
