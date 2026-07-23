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
syncs between them.

## 5. Config sync: CloudKit family sharing from day one

Presets, curation, and baselines live in a shared CloudKit zone; being in the
same iCloud family makes the share invitation one tap. A baseline saved on one
phone appears on the other. Accepted cost: this is the largest chunk of
non-audio engineering in the app. (Family Sharing alone does not sync app data
across Apple IDs; CloudKit record sharing is the mechanism.)
