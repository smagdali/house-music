# Research: control architecture (2026-07-14)

Deep research pass over the spec's open questions. 22 sources fetched, 95 claims
extracted, top 25 adversarially verified (23 confirmed, 2 refuted on phrasing).
Combined here with the live findings in [network-discovery.md](network-discovery.md).

## Recommended architecture

Drive everything with the Yamaha Extended Control (YXC) HTTP API directly from a
small iOS + watchOS app. Use MusicCast Link (the YXC `/dist` endpoints) as the
only multi-room transport; it is the only mechanism that spans all five Yamahas
and the only one that can carry the Decks analog signal at all. AirPlay 2 stays
what it is today: the way you fling BBC Sounds or Spotify from a phone at a
single room (or at the two AVRs plus WiiM as a group). Apple Home/HomeKit adds
nothing the app cannot do better itself. No new hardware needed.

## 1. The YXC API

- Plain, unauthenticated HTTP on port 80 at `http://{ip}/YamahaExtendedControl/v1/`.
  Confirmed live on all five devices. No token, pairing, or login; anything on
  the LAN can control them. The app needs only an ATS local-networking exception
  and the iOS 14+ Local Network permission prompt.
- Everything a preset scene needs is a single zone-scoped GET:
  `setPower`, `setVolume`, `setMute`, `setInput` (with `mode=autoplay_disabled`
  to stop auto-resume), and `setPureDirect?enable=true` for DJ time. Input IDs
  `phono`, `airplay`, `mc_link`, and our `audio4` (Decks) are all selectable.
- Capabilities are discoverable at runtime: `getFeatures` per device reports the
  zone's `func_list` (the RX-V685 main zone includes `pure_direct`), input list,
  and volume range; `getLocationInfo` enumerates zones.
- Grouping is the Advanced-spec `/dist` module and uses POST with JSON bodies
  (one of the two refuted claims was "everything is GET"; grouping is not).
  Making a group: generate a random 32-hex group id, POST `setClientInfo` to
  each client, `setServerInfo` (type=add, zone, client_list) to the master,
  then `startDistribution`. Teardown is the reverse. Up to 9 clients per call;
  we need at most 4.
- Discovery: SSDP M-Search for MediaRenderer, then check the device description
  for `X_yxcControlURL`. Fine on iOS; on watchOS, shipping the five known device
  IDs with a config screen is the pragmatic fallback.
- Docs: the official spec PDFs (Basic and Advanced, Rev 2.00, 2018) are only
  mirrored on community sites these days, but they match current library
  behavior and the API has been stable since 2017.

## 2. AirPlay 2 vs MusicCast vs HomeKit for our play modes

AirPlay 2 coverage is split and cannot be fixed in software:

| Device | AirPlay |
|---|---|
| RX-V685, RX-S602 | AirPlay 2 (added via 2019 firmware, confirmed on Yamaha's update table) |
| WXA-50 (all three) | AirPlay 1 only, permanently (single-band Wi-Fi hardware; firmware notes through v2.86 never mention AirPlay 2) |
| WiiM Mini | AirPlay 2 |

Consequences, mode by mode:

- **Decks to multiple rooms / whole house**: MusicCast Link only. Yamaha's FAQ
  explicitly supports sharing analog and phono inputs to linked rooms. AirPlay 2
  cannot do this at all (its group playback originates from an Apple device, not
  from a receiver input). Scene = RX-V685 `input=audio4` as distribution server,
  target rooms joined as clients, each room restored to its baseline volume.
- **DJ time**: no grouping at all; `setInput=audio4` + `setPureDirect=true` on
  the RX-V685. Caveat: whether Pure Direct can coexist with simultaneous
  distribution (for Decks-upstairs-while-DJing) needs a bench test on the unit.
- **Telly time / TV in bed**: single-receiver scenes, trivial.
- **Streaming/Spotify**: phone picks the AirPlay target as today. The app's job
  is just to have the room powered, on the right input, at baseline volume.
  Multi-room AirPlay 2 reaches only Living Room, Master Bedroom, and the WiiM.
- **Universal volume**: there is no group-volume endpoint. Yamaha's own spec
  tells controller apps to do it client-side: store each room's volume, scale
  all rooms by the master's change ratio. That is exactly our per-room-baseline
  model, so the "missing" feature is actually a fit.
- **Siri**: App Intents in our own app (scenes as intents, exposed to Siri,
  Shortcuts, and the Watch). HomeKit is not needed for this and the WXA-50s
  never appear in Apple Home anyway.

Group formation speed: with Link Control at "standard" or "stability" a group
can take 2 to 3 minutes to reach working state; Yamaha recommends Link Control
"speed", which assumes wired Ethernet. For snappy scene switching the Yamahas
should be on Ethernet with `setLinkControl=speed`.

## 3. Buy a WiiM per WXA-50?

No. A WiiM per zone would buy AirPlay 2 everywhere for phone-originated audio,
but does nothing for the Decks use case (the analog signal still has to travel
over MusicCast Link) and adds a second grouping and volume domain to manage.
Since MusicCast Link already spans all five Yamahas and is fully scriptable,
pure MusicCast is the simpler architecture. Revisit only if phone-originated
whole-house streaming over MusicCast (AirPlay into the RX-V685, redistributed
via mc_link) proves annoying in practice.

## 4. Building the app

Highly feasible. Every call is unauthenticated HTTP to fixed LAN IPs, so the
iOS/watchOS client is a thin URLSession layer plus App Intents. No Swift YXC
library exists; the references to study are:

- [aiomusiccast](https://github.com/vigonotion/aiomusiccast) (MIT, async Python,
  v0.15.0 Nov 2025): the backend of Home Assistant's `yamaha_musiccast`
  integration, so its device and grouping state model is production-proven.
  Best architectural reference.
- [yamaha-yxc-nodejs](https://github.com/foxthefox/yamaha-yxc-nodejs) (MIT,
  v3.2.1 Nov 2025): 1:1 method-per-endpoint wrapper including all `/dist` calls.
- [pyamaha](https://github.com/rsc-dev/pyamaha) (MIT, stale since 2017 but the
  API has not changed): complete endpoint listing, plus UDP event callbacks.

Note: remote power-on requires network standby enabled on each device (check
via the MusicCast app or `getFeatures`).

## Risks and open questions

1. Does Pure Direct on the RX-V685 block simultaneous MusicCast distribution?
   Test empirically.
2. Wired group size beyond 9 clients is hinted at for 2018+ models; irrelevant
   at our scale but worth knowing if the fleet grows.

(MusicCast Link latency was flagged by the research as unquantified, but it has
never been a problem in practice on this system, so it is not a risk here.)

## Key sources

- YXC API Specification, Basic and Advanced (Yamaha Rev 2.00 PDFs, mirrored):
  [Basic](https://community.symcon.de/uploads/short-url/7r8QTdkYFNfJVJmKbtqvdleuzKt.pdf),
  [Advanced](https://community.symcon.de/uploads/short-url/vRXaJXAn6vI2DSQYMHF0aqLbdir.pdf)
- [Yamaha MusicCast update models table](https://web.archive.org/web/20191216034011/https://usa.yamaha.com/products/contents/audio_visual/musiccast/update_models.html)
  (AirPlay 2 rollout, archived; the live page now redirects)
- [Yamaha MusicCast FAQ](https://usa.yamaha.com/products/contents/audio_visual/musiccast/musiccast-faqs.html)
  (analog/phono input sharing to linked rooms)
- [Home Assistant yamaha_musiccast integration](https://www.home-assistant.io/integrations/yamaha_musiccast/)
- [Embedded Lab Vienna security examination of MusicCast](https://wiki.elvis.science/index.php?title=Examination_of_YAMAHA_MusicCast_devices)
  (confirms no authentication)
- [Apple App Intents](https://developer.apple.com/documentation/appintents)
