# Network discovery findings (2026-07-14)

Answer to the spec question "can we query the network to identify the servers": yes.
All five Yamaha devices answer the Yamaha Extended Control (YXC) HTTP API on port 80
with no authentication, and the WiiM Mini answers the Linkplay HTTP API. A subnet
sweep of `GET /YamahaExtendedControl/v1/system/getDeviceInfo` found everything;
in the app proper, SSDP (UPnP MediaRenderer + `X_yxcControlURL`) or mDNS is the
polite way to discover them.

## Device map

| Room | Model | IP | Device ID | Firmware | YXC API |
|---|---|---|---|---|---|
| Living Room | RX-V685 | 192.168.6.21 | BC30D93644DA | 2.17 | 2.17 |
| Master Bedroom | RX-S602 | 192.168.6.34 | 4C1B86A6835D | 1.52 | 2.17 |
| Dining Room | WXA-50 | 192.168.6.56 | AC44F24F7404 | 2.86 | 2.08 |
| Bathroom | WXA-50 | 192.168.6.74 | 00A0DE9868A8 | 2.86 | 2.08 |
| Office | WXA-50 | 192.168.6.43 | AC44F24FC12F | 2.86 | 2.08 |
| Dining Room | WiiM Mini | 192.168.6.85 | (Linkplay API, not YXC) | Linkplay 4.6.819436 | n/a |

IPs are DHCP-assigned; the app should discover by device ID, not hardcode IPs.

## RX-V685 (Living Room) capabilities confirmed via API

- Inputs (renamed ones): `phono` PHONO, `hdmi1` Apple TV, `hdmi2` PlayStation 5,
  `hdmi4` Sony 4K Bluray, `audio3` Cassette, `audio4` **Decks**, `audio5` Stream here.
- Main zone `func_list` includes `pure_direct`, so "DJ time" can toggle Pure Direct
  programmatically (`setPureDirect`).
- Volume range 0 to 161, step 1; `actual_volume` (dB) also exposed, useful for
  per-room baseline calibration.
- MusicCast distribution: the receiver can act as link server from `main` or `zone2`
  to up to 19 clients, which covers "Decks to whole house".

## Zone names as configured on the devices

- RX-V685: main = "Living Room" (zone2 = "Room", apparently unused)
- RX-S602: main = "Master Bedroom"
- WXA-50s: "Dining Room", "Bathroom", "Office"

## Notes

- Both receivers report YXC API 2.17; the WXA-50s report API 2.08 on their older
  netmodule generation. Feature availability per zone should be read from
  `getFeatures` at runtime rather than assumed.
- No auth on any YXC endpoint; the app just needs to be on the LAN.
- The WiiM Mini speaks the Linkplay API (`https://<ip>/httpapi.asp?command=...`),
  entirely separate from MusicCast.
