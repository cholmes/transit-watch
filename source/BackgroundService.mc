import Toybox.Lang;
import Toybox.System;
import Toybox.Background;

// Runs at most every 5 minutes (Garmin OS limit) while an alert is armed.
// Checks the alerted stop and wakes the user if the line is within the
// threshold; also refreshes the glance data as a side effect.
(:background)
class DeparturesBgService extends System.ServiceDelegate {
    var _alert;

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() {
        _alert = AlertKit.get();
        if (_alert == null) {
            Background.exit(null);
            return;
        }
        if (AlertKit.expired(_alert)) {
            Background.exit({ "expired" => true });
            return;
        }
        new ApiClient().stopTimes(_alert["sid"], 15, method(:onData));
    }

    function onData(deps, err) {
        if (deps == null) {
            Background.exit(null);
            return;
        }

        var trimmed = [];
        for (var i = 0; i < deps.size() && i < 4; i++) {
            trimmed.add({
                "r" => deps[i]["r"],
                "h" => deps[i]["h"],
                "e" => deps[i]["e"],
                "rt" => deps[i]["rt"]
            });
        }
        var glance = { "stop" => _alert["sname"], "deps" => trimmed };

        var mins = AlertKit.check(_alert, deps);
        if (mins != null) {
            var msg = AlertKit.describe(_alert, mins);
            if (Background has :requestApplicationWake) {
                try {
                    Background.requestApplicationWake(msg);
                } catch (e) {
                }
            }
            Background.exit({ "fired" => true, "msg" => msg, "glance" => glance });
        } else {
            Background.exit({ "fired" => false, "glance" => glance });
        }
    }
}
