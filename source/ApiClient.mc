import Toybox.Lang;
import Toybox.Communications;

// Client for the Transitous API (https://transitous.org), a community-run
// MOTIS instance aggregating open GTFS + GTFS-RT feeds worldwide. Any other
// MOTIS deployment works too via the apiBase setting.
//
// One instance per request: the instance holds the caller's callback until
// the async response arrives. Callbacks are invoked as cb.invoke(result, err)
// where exactly one of the two is null.
(:background)
class ApiClient {
    const USER_AGENT = "TransitWatch-Garmin/0.1 (+https://github.com/cholmes/transit-watch)";

    var _cb;

    function initialize() {
    }

    // Nearby stops for a lat/lon -> [{id, n, la, lo}]
    function nearbyStops(lat, lon, cb) {
        _cb = cb;
        request("/api/v1/reverse-geocode", {
            "place" => lat.format("%.5f") + "," + lon.format("%.5f"),
            "type" => "STOP"
        }, method(:onStopsResponse));
    }

    // Free-text stop search -> [{id, n, la, lo}]
    function searchStops(text, cb) {
        _cb = cb;
        request("/api/v1/geocode", {
            "text" => text,
            "type" => "STOP"
        }, method(:onStopsResponse));
    }

    // Next departures for a stop -> [{r, h, e, rt}] sorted by time.
    //   r: route short name, h: headsign, e: epoch seconds, rt: realtime flag
    function stopTimes(stopId, n, cb) {
        _cb = cb;
        request("/api/v1/stoptimes", {
            "stopId" => stopId,
            "n" => n
        }, method(:onTimesResponse));
    }

    function request(path, params, handler) {
        Communications.makeWebRequest(
            Cfg.apiBase() + path,
            params,
            {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => { "User-Agent" => USER_AGENT },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            handler
        );
    }

    function onStopsResponse(code, data) {
        if (code != 200 || data == null || !(data instanceof Array)) {
            _cb.invoke(null, "Error " + code);
            return;
        }
        var out = [];
        for (var i = 0; i < data.size(); i++) {
            var m = data[i];
            if (m instanceof Dictionary && m["id"] != null && m["name"] != null) {
                out.add({
                    "id" => m["id"],
                    "n" => m["name"],
                    "la" => m["lat"],
                    "lo" => m["lon"]
                });
            }
        }
        _cb.invoke(out, null);
    }

    function onTimesResponse(code, data) {
        if (code != 200 || data == null || !(data instanceof Dictionary)) {
            _cb.invoke(null, "Error " + code);
            return;
        }
        var stopTimes = data["stopTimes"];
        if (stopTimes == null || !(stopTimes instanceof Array)) {
            _cb.invoke(null, "Bad response");
            return;
        }
        var out = [];
        for (var i = 0; i < stopTimes.size(); i++) {
            var st = stopTimes[i];
            if (!(st instanceof Dictionary)) {
                continue;
            }
            var place = st["place"];
            if (!(place instanceof Dictionary)) {
                continue;
            }
            var when = place["departure"];
            if (when == null) {
                when = place["scheduledDeparture"];
            }
            var epoch = Iso.toEpoch(when);
            if (epoch == null) {
                continue;
            }
            var route = st["routeShortName"];
            if (route == null) {
                route = st["mode"];
            }
            if (route == null) {
                route = "?";
            }
            var headsign = st["headsign"];
            if (headsign == null) {
                headsign = "";
            }
            out.add({
                "r" => route,
                "h" => headsign,
                "e" => epoch,
                "rt" => (st["realTime"] == true)
            });
        }
        _cb.invoke(out, null);
    }
}
