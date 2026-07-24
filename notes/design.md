# App design decisions (2026-07-23)

Settled with Stefan, stepping through the five open design questions. Next step
is a clickable HTML mockup of these screens for review with Kay, then SwiftUI.

## 1. Main screen: preset grid

A grid of big preset buttons, a universal volume slider, and a live now-playing
strip at the top. Ad-hoc source + room combinations live behind a single
"Custom" button (Kay's two-axis model as the editor), and any custom combo can
be saved as a new preset. The daily driver is one tap.

```
+------------------------------+
| House Music              gear|
| > Decks -> Upstairs          |
+------------------------------+
| [ Decks    ]  [ Spotify  ]   |
| [ Upstairs ]  [ Dining   ]   |
| [ DJ time  ]  [ Telly    ]   |
| [ TV bed   ]  [ All off  ]   |
|                              |
| [ + Custom source & rooms ]  |
+------------------------------+
| -- volume --------o-------   |
+------------------------------+
```

## 2. Watch: presets + volume

One preset per screen page, swipe between them, tap to fire. Digital crown is
universal volume. One line of live state. No editing on the Watch. A
complication / smart-stack widget opens straight into it. Designed watch-first;
it is likely the most-used surface.

## 3. Onboarding: wizard, then Settings

First run: discover devices, confirm rooms (names come from the devices), pick
which inputs matter per device (hide the rest), then offer starter presets
built from what discovery found. Everything revisitable in Settings. Baseline
calibration is not part of setup; baselines are saved from live use via "save
this volume to preset".

## 4. Spotify preset with nothing playing: prep, transfer, open

The preset powers the rooms, forms the group, sets baselines, transfers the
Spotify session so the target is the active device, then opens the Spotify app
for the user to pick music. One extra tap, no guessing.

## Preset ordering is per-person

Stefan and Kay have different listening habits, so the grid order of presets is
personal, not shared. Preset definitions, curation, and baselines are household
data (shared via CloudKit); ordering lives with each person's account and never
syncs between them. Reordering uses the Home Screen convention: long-press a
tile to enter wiggle mode, drag to taste.

## Baselines: no wizard stage, long-press the slider to save

The wizard does not set volume baselines (they cannot be judged without real
music in real context, and it would bloat a two-minute setup). Presets are born
with a safe default (-30 dB per room). Calibration is a gesture: long-press the
volume slider to save the current level as the active preset's baseline; the
baseline tick under the slider moves to match. Firing a preset always returns
volume to its tick.

## Mute, not play/pause

The transport control in the now-playing strip and on the Watch is mute, not
play/pause. Mute (YXC setMute) works identically on every zone of every device
for every source, so the button is always present and always honest; muting a
preset mutes all its rooms. True pause remains available where the platform
already provides it (Control Center, lock screen, watch Now Playing for
Spotify/AirPlay; Siri remote for Apple TV).

Considered and rejected: contextual play/pause per source (button appears and
disappears; Decks and Apple TV can never honour it), and reverse-engineering
the Apple TV Companion protocol for pause (no public API exists; pyatv-style
pairing is disproportionate for one button).

## Deployment baseline

iOS 17 / watchOS 10. App Intents and interactive widgets are mature there, it
is the natural SwiftUI floor, and it reaches back to the iPhone XS (2018).

## Visual direction (round 2)

Big, bold, and colour-coded, with contrast beyond WCAG AAA: white text on
near-black, dark ink on bright preset tiles. Each preset has its own colour
(Decks amber, DJ time red, Spotify green, Telly time violet, TV in bed blue;
All off stays dark), carried through the now-playing indicator and the Watch.
The app is dark-first, styled after the hi-fi gear it controls.

## 5. Config sync: CloudKit family sharing from day one

Presets, curation, and baselines live in a shared CloudKit zone; being in the
same iCloud family makes the share invitation one tap. A baseline saved on one
phone appears on the other. Accepted cost: this is the largest chunk of
non-audio engineering in the app. (Family Sharing alone does not sync app data
across Apple IDs; CloudKit record sharing is the mechanism.)

## Spotify app registration (2026-07-24)

Client ID 5a444101070b4b4983069d17237b30b3, redirect URI
housemusic://spotify-callback, PKCE flow (no client secret in the app, ever).
App is in development mode; both household Spotify accounts must be added
under User Management in the dashboard.
