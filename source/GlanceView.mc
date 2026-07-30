import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Time;
import Toybox.Application;

// Widget-loop glance: next departures for the alerted / last viewed stop,
// from cached data (refreshed by the app and the background service).
(:glance)
class DeparturesGlanceView extends WatchUi.GlanceView {

    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var fTitle = (Graphics has :FONT_GLANCE) ? Graphics.FONT_GLANCE : Graphics.FONT_TINY;
        var fBig = (Graphics has :FONT_GLANCE_NUMBER) ? Graphics.FONT_GLANCE_NUMBER : Graphics.FONT_SMALL;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.clear();

        var g = Application.Storage.getValue("glance");
        var alert = Application.Storage.getValue("alert");

        var title = "DEPARTURES";
        if (g != null && g["stop"] != null) {
            title = g["stop"].toUpper();
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, h * 0.08, fTitle, title, Graphics.TEXT_JUSTIFY_LEFT);

        var line = "Open for nearby";
        var mins = null;
        if (g != null && g["deps"] != null) {
            var now = Time.now().value();
            var deps = g["deps"];
            for (var i = 0; i < deps.size(); i++) {
                var diff = deps[i]["e"] - now;
                if (diff > -30) {
                    mins = (diff <= 0) ? 0 : diff / 60;
                    line = deps[i]["r"] + " > " + deps[i]["h"];
                    break;
                }
            }
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (mins == null) {
            dc.drawText(0, h * 0.45, fTitle, line, Graphics.TEXT_JUSTIFY_LEFT);
        } else {
            var minsTxt = (mins <= 0) ? "now" : mins + "'";
            if (alert != null) {
                minsTxt = "! " + minsTxt;
            }
            var minsW = dc.getTextWidthInPixels(minsTxt, fBig);
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w, h * 0.42, fBig, minsTxt, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var maxW = w - minsW - 8;
            var t = line;
            while (t.length() > 2
                   && dc.getTextWidthInPixels(t, fTitle) > maxW) {
                t = t.substring(0, t.length() - 1);
            }
            dc.drawText(0, h * 0.45, fTitle, t, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }
}
