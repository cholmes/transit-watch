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
