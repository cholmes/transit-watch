# Departures — realtime transit on your Garmin watch

A Garmin Connect IQ watch app that shows when the next buses, trams, metros,
trains and ferries leave from the stops around you — powered entirely by
**open realtime transit data**. Works in any city with an open GTFS / GTFS-RT
feed (1800+ feeds, 55 countries), including Amsterdam, Minneapolis and
Portland.

Built for the Forerunner 970, runs on most modern Garmin watches
(Forerunner 165/265/955/965, fēnix 7, epix 2, Venu 2/3, Vivoactive 5 — see
`manifest.xml`).

## Features

- **Nearby departures, zero taps** — open the app and see live departures
  grouped by stop within ~500 m (configurable), sorted by distance.
- **Favorites first** — pin stops; they float to the top when you're near
  them. Pin lines within a stop to float those departures to the top.
- **Departure alerts** — "buzz me when the 18 to Centraal is ≤ 6 minutes
  away, for the next hour." Precise 30-second polling while the app is open;
  best-effort background checks every 5 minutes when it's closed (a Garmin
  OS limit — see *Alert caveats*).
- **Glance** — the widget-loop glance shows a live countdown for your
  alerted / last-viewed stop without opening the app.
- **Stop search** — on-watch keyboard search for any stop by name.
- **Realtime vs schedule** — green times are live GTFS-RT predictions, gray
  times are static schedule.

## Data source

All data comes from [Transitous](https://transitous.org), a community-run,
non-commercial routing service built on the open-source
[MOTIS](https://github.com/motis-project/motis) engine, aggregating openly
licensed GTFS + GTFS-RT feeds and polling realtime updates every minute.
No API key required. The app identifies itself via `User-Agent`.

The API base URL is a user setting, so you can point the app at any MOTIS
instance (e.g. self-hosted) without code changes.

Coverage for the initial test cities (feed registry references):

| City | Feed | Realtime |
|---|---|---|
| Amsterdam (all NL) | OpenOV / OVapi national feed (`feeds/nl.json`) — GVB, NS, regional | ✓ trip + train updates, positions, alerts |
| Minneapolis–St. Paul | Metro Transit (`feeds/us-mn.json`) | ✓ |
| Portland, OR | TriMet (`feeds/us-or.json`) | ✓ |

Run `tools/verify_coverage.sh` to sanity-check all three cities against the
live API (requires plain internet access; see the script for the exact
endpoints the watch uses).

## Building

1. Install the [Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)
   via the SDK Manager, and the **Monkey C** VS Code extension (or use the
   CLI below).
2. In the SDK Manager, download the devices you want (at least
   *Forerunner 970*).
3. Generate a developer key once:
   `openssl genrsa -out developer_key.pem 4096 && openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt`
4. Build:
   ```sh
   monkeyc -f monkey.jungle -d fr970 -o bin/Departures.prg -y developer_key.der
   ```
   Or in VS Code: **Monkey C: Build Current Project** → pick `fr970`.

### Run in the simulator

```sh
connectiq &                                  # starts the simulator
monkeydo bin/Departures.prg fr970
```

The simulator proxies HTTP through your computer, so you'll see live
Transitous data. Set a GPS position via *Simulation → Location* (e.g.
Amsterdam: 52.3676, 4.9041) before testing the nearby screen.

### Sideload to the watch

Connect the watch over USB and copy `bin/Departures.prg` into the
`GARMIN/Apps` folder. It appears in the activity/app list. (HTTP requests on
a real watch go through the Garmin Connect Mobile app on your phone, so the
phone must be paired and connected.)

## Using the app

| Input | Nearby screen | Stop board |
|---|---|---|
| UP / DOWN | select stop group | scroll departures |
| SELECT | open stop board | actions menu |
| MENU | favorites / search / rescan / cancel alert | actions menu |
| BACK | exit | back to nearby |

**Setting the "leave the office" alert** (the 17:00–17:30 use case): open
your stop's board → MENU → *Set alert* → pick the line + direction → pick
threshold (e.g. 6 min) → pick *Next hour*. Keep the watch on the glance or
in the app for exact timing; if the app is closed, the check runs every
5 minutes and wakes you with a vibration + prompt.

Settings (threshold default, refresh rate, radius, hide trains, API base
URL) are edited from the Garmin Connect phone app → your device → Connect IQ
apps → Departures.

## Alert caveats (Garmin platform limits)

- A closed app can only run a background check **every 5 minutes** (max 30 s
  runtime), so a background alert can fire up to ~5 minutes late. If you arm
  a 6-minute threshold and close the app, treat it as "somewhere between 1
  and 6 minutes away" — or use a 10–12 minute threshold instead.
- Background alerts use the system "open app?" wake prompt with vibration;
  while the app is in the foreground you get the full-screen alert instantly.

## Architecture

```
source/
  DeparturesApp.mc      app entry; glance + background service wiring
  ApiClient.mc          Transitous/MOTIS REST client (geocode, stoptimes)
  Model.mc              storage, settings, favorites + pinned lines
  Util.mc               ISO-8601 parsing, distance, sorting, drawing helpers
  NearbyView.mc         home screen: departures around you, grouped by stop
  StopBoardView.mc      per-stop departure board
  Menus.mc              Menu2 flows: favorites, search, alert wizard
  Alerts.mc             alert state/matching (shared w/ background) + UI
  BackgroundService.mc  5-minute temporal event checks while alert armed
  GlanceView.mc         widget-loop glance
```

Departure timestamps arrive as ISO-8601 with offsets; the app converts to
epoch and renders relative minutes, so timezones are a non-issue. Responses
are kept small (`n` caps) to stay under Garmin's ~16 KB HTTP response limit
on older devices.

## Store release checklist

- [ ] Say hello in the Transitous Matrix room (they ask apps using the
      public instance to identify themselves) and confirm fair-use terms.
- [ ] Screenshots per device family; store icon (larger than launcher icon).
- [ ] Privacy note: location is used only to query nearby stops; nothing is
      stored server-side.
- [ ] Test on low-memory devices (Venu 2, FR 165) — trim `maxDepartures`
      defaults if needed.
- [ ] Consider adding more devices to `manifest.xml` (any CIQ ≥ 4.0 device
      with glance support should work).

## License

MIT — see `LICENSE`.
