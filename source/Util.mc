import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;

// ISO 8601 timestamp parsing ("2026-07-30T17:05:00+02:00", "...Z", optional
// fractional seconds). Monkey C has no built-in parser, so this converts to
// epoch seconds with plain integer math.
(:background)
module Iso {
    const MDAYS = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];

    function field(s, a, b) {
        var sub = s.substring(a, b);
        return (sub == null) ? null : sub.toNumber();
    }

    function isLeap(y) {
        return (y % 4 == 0) && ((y % 100 != 0) || (y % 400 == 0));
    }

    // Leap days in [1970, y] inclusive, counting each leap year once.
    function leapCount(y) {
        var f = (y / 4) - (y / 100) + (y / 400);
        return f - 477; // f(1969) = 492 - 19 + 4
    }

    // Returns epoch seconds (UTC) or null if the string is unparseable.
    function toEpoch(s) {
        if (s == null || !(s instanceof String) || s.length() < 19) {
            return null;
        }
        var y = field(s, 0, 4);
        var mo = field(s, 5, 7);
        var d = field(s, 8, 10);
        var h = field(s, 11, 13);
        var mi = field(s, 14, 16);
        var sec = field(s, 17, 19);
        if (y == null || mo == null || d == null || h == null || mi == null
            || sec == null || mo < 1 || mo > 12 || y < 1971) {
            return null;
        }

        var days = (y - 1970) * 365 + leapCount(y - 1) + MDAYS[mo - 1] + (d - 1);
        if (isLeap(y) && mo > 2) {
            days += 1;
        }

        // Timezone suffix after position 19: "Z", "+02:00", "-05:30",
        // optionally preceded by fractional seconds.
        var offSec = 0;
        var rest = s.substring(19, s.length());
        if (rest != null && rest.length() > 0) {
            var idx = rest.find("+");
            var sign = 1;
            if (idx == null) {
                idx = rest.find("-");
                sign = -1;
            }
            if (idx != null && rest.length() >= idx + 6) {
                var oh = field(rest, idx + 1, idx + 3);
                var om = field(rest, idx + 4, idx + 6);
                if (oh != null && om != null) {
                    offSec = sign * (oh * 3600 + om * 60);
                }
            }
        }

        return days * 86400 + h * 3600 + mi * 60 + sec - offSec;
    }
}

module Util {
    // Equirectangular approximation, fine at city scale.
    function distanceM(la1, lo1, la2, lo2) {
        var kx = Math.cos(Math.toRadians(la1)) * 111320.0;
        var dy = (la2 - la1) * 110540.0;
        var dx = (lo2 - lo1) * kx;
        return Math.sqrt(dx * dx + dy * dy);
    }

    function formatDistance(d) {
        if (d == null) {
            return null;
        }
        if (d < 950) {
            return d.toNumber() + " m";
        }
        return ((d / 100).toNumber() / 10.0).format("%.1f") + " km";
    }

    // In-place insertion sort of an array of dictionaries by a numeric key;
    // null sorts last. Lists here are small (<= ~25 items).
    function sortByKey(arr, key) {
        for (var i = 1; i < arr.size(); i++) {
            var item = arr[i];
            var v = item[key];
            var j = i - 1;
            while (j >= 0) {
                var w = arr[j][key];
                var after = (v != null) && (w == null || w > v);
                if (!after) {
                    break;
                }
                arr[j + 1] = arr[j];
                j -= 1;
            }
            arr[j + 1] = item;
        }
        return arr;
    }

    function minutesUntil(epoch) {
        var now = Time.now().value();
        var diff = epoch - now;
        if (diff <= 0) {
            return 0;
        }
        return (diff + 30) / 60; // round to nearest minute
    }

    function truncate(dc, text, font, maxWidth) {
        if (text == null) {
            return "";
        }
        if (dc.getTextWidthInPixels(text, font) <= maxWidth) {
            return text;
        }
        var len = text.length();
        while (len > 1) {
            len -= 1;
            var t = text.substring(0, len) + "…";
            if (dc.getTextWidthInPixels(t, font) <= maxWidth) {
                return t;
            }
        }
        return text.substring(0, 1);
    }

    function toast(msg) {
        if (Toybox.WatchUi has :showToast) {
            Toybox.WatchUi.showToast(msg, null);
        }
    }
}
