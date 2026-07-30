#!/usr/bin/env bash
# Sanity-check that Transitous serves nearby stops + realtime departures for
# the app's initial test cities, using the same endpoints the watch calls.
# Usage: ./tools/verify_coverage.sh [api-base]
set -euo pipefail

BASE="${1:-https://api.transitous.org}"
UA="Departures-Garmin/0.1 (+https://github.com/cholmes/transit-watch; coverage-check)"

check_city() {
    local name="$1" lat="$2" lon="$3"
    echo "== ${name} =="

    # Nearby departures (the app's home screen): stoptimes around a point.
    # Falls back from v6 to v1 exactly like the app does.
    local url="${BASE}/api/v6/stoptimes?center=${lat}%2C${lon}&radius=500&n=10"
    local out
    out=$(curl -fsS -H "User-Agent: ${UA}" "$url" 2>/dev/null) \
        || out=$(curl -fsS -H "User-Agent: ${UA}" \
            "${BASE}/api/v1/stoptimes?center=${lat}%2C${lon}&radius=500&n=10")

    echo "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
sts = d.get("stopTimes", [])
rt = sum(1 for s in sts if s.get("realTime"))
print(f"  {len(sts)} departures returned, {rt} with realtime data")
for s in sts[:5]:
    p = s.get("place", {})
    when = p.get("departure") or p.get("scheduledDeparture")
    live = "RT" if s.get("realTime") else "sched"
    print(f"    {s.get(\"routeShortName\",\"?\"):>5} -> {s.get(\"headsign\",\"\")[:30]:<30} {when} [{live}]")
'
    echo
}

check_city "Amsterdam (Dam Square)"      52.3731 4.8932
check_city "Minneapolis (Nicollet Mall)" 44.9778 -93.2708
check_city "Portland (Pioneer Square)"   45.5190 -122.6793

echo "If each city lists departures (ideally with [RT]), the watch app will work there."
