import Toybox.Lang;
import Toybox.Application;

// Thin wrapper around persistent storage, usable from the app, glance and
// background scopes.
(:glance, :background)
module Store {
    // Keys:
    //   "favs"         Array of stop dicts {id, n, la, lo}
    //   "pinlines"     Dictionary stopId -> Array of route short names
    //   "alert"        Armed alert dict {sid, sname, r, h, thr}
    //   "pendingAlert" Alert that fired from the background {msg}
    //   "glance"       {stop, deps: [{r, h, e}]} for the glance view
    //   "lastLoc"      [lat, lon] of the last GPS fix

    function get(key, def) {
        var v = Application.Storage.getValue(key);
        return (v == null) ? def : v;
    }

    function set(key, value) {
        Application.Storage.setValue(key, value);
    }

    function del(key) {
        Application.Storage.deleteValue(key);
    }
}

// User settings, with safe defaults if a property is missing.
(:background)
module Cfg {
    function num(key, def) {
        try {
            var v = Application.Properties.getValue(key);
            if (v != null && v instanceof Number) {
                return v;
            }
        } catch (e) {
        }
        return def;
    }

    function apiBase() {
        try {
            var v = Application.Properties.getValue("apiBase");
            if (v != null && v instanceof String && v.length() > 8) {
                return v;
            }
        } catch (e) {
        }
        return "https://api.transitous.org";
    }

    function alertMinutes() {
        return num("alertMinutes", 6);
    }

    function refreshMs() {
        var s = num("refreshSeconds", 30);
        if (s < 15) {
            s = 15;
        }
        return s * 1000;
    }

    function maxDepartures() {
        return num("maxDepartures", 10);
    }

    function radiusM() {
        var v = num("radiusM", 500);
        if (v < 100) {
            v = 100;
        }
        if (v > 3000) {
            v = 3000;
        }
        return v;
    }

    function hideTrains() {
        try {
            return Application.Properties.getValue("hideTrains") == true;
        } catch (e) {
            return false;
        }
    }
}

// Favorite ("pinned") stops and pinned lines per stop.
module Favorites {
    function all() {
        return Store.get("favs", []);
    }

    function isFav(stopId) {
        var favs = all();
        for (var i = 0; i < favs.size(); i++) {
            if (stopId.equals(favs[i]["id"])) {
                return true;
            }
        }
        return false;
    }

    // Adds the stop if absent, removes it if present. Returns true if it is
    // now a favorite.
    function toggle(stop) {
        var favs = all();
        var out = [];
        var removed = false;
        for (var i = 0; i < favs.size(); i++) {
            if (stop["id"].equals(favs[i]["id"])) {
                removed = true;
            } else {
                out.add(favs[i]);
            }
        }
        if (!removed) {
            out.add({
                "id" => stop["id"],
                "n" => stop["n"],
                "la" => stop["la"],
                "lo" => stop["lo"]
            });
        }
        Store.set("favs", out);
        return !removed;
    }

    function pinnedLines(stopId) {
        var map = Store.get("pinlines", {});
        var lines = map[stopId];
        return (lines == null) ? [] : lines;
    }

    function isPinnedLine(stopId, route) {
        var lines = pinnedLines(stopId);
        for (var i = 0; i < lines.size(); i++) {
            if (route.equals(lines[i])) {
                return true;
            }
        }
        return false;
    }

    // Reorders departures so pinned lines come first (keeping time order
    // within each partition), capped at maxOut entries.
    function orderDeps(stopId, deps, maxOut) {
        var pinned = pinnedLines(stopId);
        var out = [];
        if (pinned.size() > 0) {
            for (var i = 0; i < deps.size(); i++) {
                if (isPinnedLine(stopId, deps[i]["r"])) {
                    out.add(deps[i]);
                }
            }
        }
        for (var i = 0; i < deps.size(); i++) {
            if (pinned.size() == 0 || !isPinnedLine(stopId, deps[i]["r"])) {
                out.add(deps[i]);
            }
        }
        if (out.size() > maxOut) {
            var trimmed = [];
            for (var i = 0; i < maxOut; i++) {
                trimmed.add(out[i]);
            }
            out = trimmed;
        }
        return out;
    }

    // Returns true if the line is now pinned.
    function toggleLine(stopId, route) {
        var map = Store.get("pinlines", {});
        var lines = map[stopId];
        if (lines == null) {
            lines = [];
        }
        var out = [];
        var removed = false;
        for (var i = 0; i < lines.size(); i++) {
            if (route.equals(lines[i])) {
                removed = true;
            } else {
                out.add(lines[i]);
            }
        }
        if (!removed) {
            out.add(route);
        }
        map[stopId] = out;
        Store.set("pinlines", map);
        return !removed;
    }
}
