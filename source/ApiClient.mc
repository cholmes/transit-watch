import Toybox.Lang;
import Toybox.Communications;
import Toybox.Time;

// Client for the Transitous API (https://transitous.org), a community-run
// MOTIS instance aggregating open GTFS + GTFS-RT feeds worldwide. Any other
// MOTIS deployment works too via the apiBase setting.
//
// One instance per request: the instance holds the caller's callback until
// the async response arrives. Callbacks are invoked as cb.invoke(result, err)
// where exactly one of the two is null.
//
// Departure dictionaries produced by this client:
//   r   route short name        h    headsign
//   e   departure epoch (UTC)   rt   realtime flag
//   m   mode (BUS, TRAM, ...)   sid  stop id
//   sn  stop name               sla/slo  stop lat/lon
(:background)
class ApiClient {
    const USER_AGENT = "Departures-Garmin/0.1 (+https://github.com/cholmes/transit-watch)";

    // MOTIS versions endpoints independently; stoptimes is v6 in current
    // MOTIS. If the server 404s (older deployment), we retry once on v1.
    const STOPTIMES_PATH = "/api/v6/stoptimes";
    const STOPTIMES_FALLBACK_PATH = "/api/v1/stoptimes";

    var _cb;
    var _params;
    var _retried = false;

    function initialize() {
    }

    // Free-text stop search -> [{id, n, la, lo}]. loc biases results.
    function searchStops(text, loc, cb) {
        _cb = cb;
        var params = {
            "text" => text,
            "type" => "STOP"
        };
        if (loc != null) {
            params["place"] = fmtPlace(loc[0], loc[1]);
        }
        request("/api/v1/geocode", params, method(:onStopsResponse));
    }

    // All departures around a coordinate -> [departure dicts].
    function nearbyTimes(lat, lon, radiusM, n, cb) {
        _cb = cb;
        _params = {
            "center" => fmtPlace(lat, lon),
            "radius" => radiusM,
            "n" => n
        };
        request(STOPTIMES_PATH, _params, method(:onTimesResponse));
    }

    // Next departures for one stop -> [departure dicts].
    function stopTimes(stopId, n, cb) {
        _cb = cb;
        _params = {
            "stopId" => stopId,
            "n" => n
        };
        request(STOPTIMES_PATH, _params, method(:onTimesResponse));
    }

    function fmtPlace(lat, lon) {
        return lat.format("%.5f") + "," + lon.format("%.5f");
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
        if (code == 404 && !_retried) {
            _retried = true;
            request(STOPTIMES_FALLBACK_PATH, _params, method(:onTimesResponse));
            return;
        }
        if (code != 200 || data == null || !(data instanceof Dictionary)) {
            _cb.invoke(null, "Error " + code);
            return;
        }
        var stopTimes = data["stopTimes"];
        if (stopTimes == null || !(stopTimes instanceof Array)) {
            _cb.invoke(null, "Bad response");
            return;
        }
        var hideTrains = Cfg.hideTrains();
        var cutoff = Time.now().value() - 60;
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
            if (epoch == null || epoch < cutoff) {
                continue;
            }
            var mode = st["mode"];
            if (mode == null) {
                mode = "TRANSIT";
            }
            if (hideTrains && isTrain(mode)) {
                continue;
            }
            var route = st["routeShortName"];
            if (route == null) {
                route = mode;
            }
            var headsign = st["headsign"];
            if (headsign == null) {
                headsign = "";
            }
            out.add({
                "r" => route,
                "h" => headsign,
                "e" => epoch,
                "rt" => (st["realTime"] == true),
                "m" => mode,
                "sid" => place["stopId"],
                "sn" => place["name"],
                "sla" => place["lat"],
                "slo" => place["lon"]
            });
        }
        _cb.invoke(out, null);
    }

    function isTrain(mode) {
        return mode.find("RAIL") != null || mode.equals("LONG_DISTANCE")
            || mode.equals("RAIL");
    }
}
