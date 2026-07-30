import Toybox.Lang;
import Toybox.Time;
import Toybox.Background;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Attention;

// Alert state + matching logic. Shared with the background service, so no
// UI references in this module.
//
// Alert dict: {sid, sname, r, h, thr, until}
//   thr:   fire when a matching departure is <= thr minutes away
//   until: epoch after which the alert auto-expires (0 = never)
(:background)
module AlertKit {
    function get() {
        return Store.get("alert", null);
    }

    function armed() {
        return get() != null;
    }

    function arm(sid, sname, route, headsign, thrMin, windowMin) {
        var until = 0;
        if (windowMin > 0) {
            until = Time.now().value() + windowMin * 60;
        }
        Store.set("alert", {
            "sid" => sid,
            "sname" => sname,
            "r" => route,
            "h" => headsign,
            "thr" => thrMin,
            "until" => until
        });
        Background.registerForTemporalEvent(new Time.Duration(300));
    }

    // Foreground only (temporal events can't be deleted from the background
    // scope; the service reports expiry via Background.exit instead).
    function disarm() {
        Store.del("alert");
        try {
            Background.deleteTemporalEvent();
        } catch (e) {
        }
    }

    function expired(a) {
        var until = a["until"];
        return until != null && until > 0 && Time.now().value() > until;
    }

    // Earliest matching departure within the threshold, in minutes, or null.
    // Route must match; same-headsign departures are preferred so "18 to
    // Centraal" doesn't fire for the opposite direction when both are due.
    function check(a, deps) {
        var best = null;
        var bestExact = false;
        var now = Time.now().value();
        for (var i = 0; i < deps.size(); i++) {
            var d = deps[i];
            if (!a["r"].equals(d["r"])) {
                continue;
            }
            var diff = d["e"] - now;
            if (diff < -30) {
                continue;
            }
            var mins = (diff <= 0) ? 0 : diff / 60;
            if (mins > a["thr"]) {
                continue;
            }
            var exact = a["h"].equals(d["h"]);
            if (best == null || (exact && !bestExact)
                || (exact == bestExact && mins < best)) {
                best = mins;
                bestExact = exact;
            }
        }
        return best;
    }

    function describe(a, mins) {
        var when = (mins <= 0) ? "now" : "in " + mins + " min";
        return a["r"] + " > " + a["h"] + " " + when;
    }
}

// Foreground half: periodic polling while the app is open, vibration, and
// the full-screen alert view.
module Alerter {
    var pending = false;
    var _lastPoll = 0;
    var _poller = null;

    // Called from view timers (~every 30s). Polls the alert's stop at most
    // every 40s regardless of which screen is open.
    function pollIfDue() {
        var a = AlertKit.get();
        if (a == null) {
            return;
        }
        if (AlertKit.expired(a)) {
            AlertKit.disarm();
            Util.toast("Alert expired");
            return;
        }
        var now = Time.now().value();
        if (pending || now - _lastPoll < 40) {
            return;
        }
        _lastPoll = now;
        pending = true;
        if (_poller == null) {
            _poller = new AlertPoller();
        }
        _poller.go(a);
    }

    // Piggyback on data another view just fetched for the same stop.
    function checkDeps(stopId, deps) {
        var a = AlertKit.get();
        if (a == null || stopId == null || !stopId.equals(a["sid"])) {
            return;
        }
        if (AlertKit.expired(a)) {
            AlertKit.disarm();
            return;
        }
        var mins = AlertKit.check(a, deps);
        if (mins != null) {
            fire(a, mins);
        }
    }

    function fire(a, mins) {
        AlertKit.disarm();
        buzz();
        WatchUi.pushView(new AlertView(AlertKit.describe(a, mins)),
                         new AlertDelegate(), WatchUi.SLIDE_UP);
    }

    function buzz() {
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(100, 700),
                new Attention.VibeProfile(0, 250),
                new Attention.VibeProfile(100, 700)
            ]);
        }
        if (Attention has :playTone) {
            Attention.playTone(Attention.TONE_ALERT_HI);
        }
    }
}

class AlertPoller {
    var _alert;

    function initialize() {
    }

    function go(a) {
        _alert = a;
        new ApiClient().stopTimes(a["sid"], 15, method(:onData));
    }

    function onData(deps, err) {
        Alerter.pending = false;
        if (deps == null) {
            return;
        }
        var a = AlertKit.get();
        if (a == null) {
            return;
        }
        var mins = AlertKit.check(a, deps);
        if (mins != null) {
            Alerter.fire(a, mins);
        }
    }
}

class AlertView extends WatchUi.View {
    var _msg;

    function initialize(msg) {
        View.initialize();
        _msg = (msg == null) ? "Departure soon" : msg;
    }

    function onShow() {
        Alerter.buzz();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.2, Graphics.FONT_TINY, "ALERT",
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        // Split "18 > Centraal in 6 min" across two lines if needed.
        var line1 = _msg;
        var line2 = null;
        if (dc.getTextWidthInPixels(_msg, Graphics.FONT_SMALL) > w * 0.85) {
            var idx = _msg.find(" in ");
            if (idx == null) {
                idx = _msg.find(" now");
            }
            if (idx != null) {
                line1 = _msg.substring(0, idx);
                line2 = _msg.substring(idx + 1, _msg.length());
            }
        }
        line1 = Util.truncate(dc, line1, Graphics.FONT_SMALL, (w * 0.85).toNumber());
        if (line2 == null) {
            dc.drawText(w / 2, h * 0.45, Graphics.FONT_SMALL, line1,
                        Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(w / 2, h * 0.38, Graphics.FONT_SMALL, line1,
                        Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h * 0.52, Graphics.FONT_MEDIUM, line2,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.75, Graphics.FONT_XTINY, "BACK to dismiss",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class AlertDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onSelect() {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }
}
