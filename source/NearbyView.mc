import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Position;
import Toybox.Timer;
import Toybox.Time;

// Home screen: all upcoming departures around the user, grouped by stop.
// Favorite stops float to the top; pinned lines float within their stop.
// UP/DOWN selects a stop group, SELECT opens its full board, MENU opens
// favorites / search / rescan.
class NearbyView extends WatchUi.View {
    var _groups = null;      // [{id, n, la, lo, fav, dist, deps, k}]
    var _status = "Locating...";
    var _sel = 0;
    var _timer = null;
    var _loc = null;         // [lat, lon]
    var _fetching = false;
    var _gpsRequested = false;

    function initialize() {
        View.initialize();
    }

    function onShow() {
        var pending = Store.get("pendingAlert", null);
        if (pending != null) {
            Store.del("pendingAlert");
            WatchUi.pushView(new AlertView(pending["msg"]), new AlertDelegate(),
                             WatchUi.SLIDE_UP);
            return;
        }
        if (_timer == null) {
            _timer = new Timer.Timer();
        }
        _timer.start(method(:onTick), Cfg.refreshMs(), true);
        if (_groups == null && !_fetching) {
            locate();
        } else {
            refresh();
        }
    }

    function onHide() {
        if (_timer != null) {
            _timer.stop();
        }
    }

    function onTick() {
        refresh();
        Alerter.pollIfDue();
    }

    function loc() {
        return _loc;
    }

    function locate() {
        var got = false;
        var info = Position.getInfo();
        if (info != null && info.position != null) {
            var deg = info.position.toDegrees();
            if (deg[0] != 0.0 || deg[1] != 0.0) {
                setLoc(deg[0], deg[1]);
                got = true;
            }
        }
        if (!got) {
            var last = Store.get("lastLoc", null);
            if (last != null) {
                setLoc(last[0], last[1]);
                got = true;
            }
        }
        if (!_gpsRequested) {
            _gpsRequested = true;
            Position.enableLocationEvents(Position.LOCATION_ONE_SHOT,
                                          method(:onPosition));
        }
        if (!got) {
            _status = "Locating...";
            WatchUi.requestUpdate();
        }
    }

    function rescanLocation() {
        _gpsRequested = false;
        locate();
    }

    function onPosition(info) {
        if (info != null && info.position != null) {
            var deg = info.position.toDegrees();
            if (deg[0] != 0.0 || deg[1] != 0.0) {
                Store.set("lastLoc", [deg[0].toFloat(), deg[1].toFloat()]);
                if (_loc == null) {
                    setLoc(deg[0], deg[1]);
                } else {
                    _loc = [deg[0], deg[1]]; // picked up on next refresh
                }
            }
        }
    }

    function setLoc(lat, lon) {
        _loc = [lat, lon];
        refresh();
    }

    function refresh() {
        if (_loc == null || _fetching) {
            return;
        }
        _fetching = true;
        new ApiClient().nearbyTimes(_loc[0], _loc[1], Cfg.radiusM(), 30,
                                    method(:onData));
    }

    function onData(deps, err) {
        _fetching = false;
        if (deps == null) {
            if (_groups == null) {
                _status = err + "\nCheck phone connection";
            }
            WatchUi.requestUpdate();
            return;
        }
        _groups = buildGroups(deps);
        _status = null;
        if (_groups.size() == 0) {
            _status = "No departures within " + Cfg.radiusM() + " m";
        }
        if (_sel >= _groups.size()) {
            _sel = 0;
        }
        WatchUi.requestUpdate();
    }

    function buildGroups(deps) {
        var groups = [];
        var bySid = {};
        for (var i = 0; i < deps.size(); i++) {
            var d = deps[i];
            var sid = d["sid"];
            if (sid == null) {
                continue;
            }
            var g = bySid[sid];
            if (g == null) {
                var dist = null;
                if (_loc != null && d["sla"] != null && d["slo"] != null) {
                    dist = Util.distanceM(_loc[0], _loc[1], d["sla"], d["slo"]);
                }
                g = {
                    "id" => sid,
                    "n" => (d["sn"] == null) ? "Stop" : d["sn"],
                    "la" => d["sla"],
                    "lo" => d["slo"],
                    "fav" => Favorites.isFav(sid),
                    "dist" => dist,
                    "deps" => []
                };
                bySid[sid] = g;
                groups.add(g);
            }
            if (g["deps"].size() < 6) {
                g["deps"].add(d);
            }
        }
        for (var i = 0; i < groups.size(); i++) {
            var g = groups[i];
            var k = (g["dist"] == null) ? 99999.0 : g["dist"];
            if (g["fav"]) {
                k -= 1000000;
            }
            g["k"] = k;
            g["deps"] = Favorites.orderDeps(g["id"], g["deps"], 3);
        }
        Util.sortByKey(groups, "k");
        if (groups.size() > 8) {
            var trimmed = [];
            for (var i = 0; i < 8; i++) {
                trimmed.add(groups[i]);
            }
            groups = trimmed;
        }
        return groups;
    }

    function moveSel(delta) {
        if (_groups == null || _groups.size() == 0) {
            return;
        }
        _sel += delta;
        if (_sel < 0) {
            _sel = 0;
        }
        if (_sel >= _groups.size()) {
            _sel = _groups.size() - 1;
        }
        WatchUi.requestUpdate();
    }

    function openSelected() {
        if (_groups == null || _groups.size() == 0) {
            refresh();
            return;
        }
        var g = _groups[_sel];
        var stop = { "id" => g["id"], "n" => g["n"], "la" => g["la"], "lo" => g["lo"] };
        var board = new StopBoardView(stop);
        WatchUi.pushView(board, new StopBoardDelegate(board), WatchUi.SLIDE_LEFT);
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var fHead = Graphics.FONT_XTINY;
        var fRow = Graphics.FONT_TINY;
        var hHead = dc.getFontHeight(fHead) + 2;
        var hRow = dc.getFontHeight(fRow) + 2;
        var xPad = (w * 0.10).toNumber();
        var xR = w - xPad;

        var y = (h * 0.05).toNumber();
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, y, fHead, "NEARBY", Graphics.TEXT_JUSTIFY_CENTER);
        y += hHead;

        var alert = AlertKit.get();
        if (alert != null) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, fHead,
                        "! " + alert["r"] + " <=" + alert["thr"] + "'",
                        Graphics.TEXT_JUSTIFY_CENTER);
            y += hHead;
        }

        if (_groups == null || _groups.size() == 0) {
            drawStatus(dc, w, h);
            return;
        }

        y += 2;
        for (var gi = _sel; gi < _groups.size(); gi++) {
            var g = _groups[gi];
            if (y + hHead > h * 0.95) {
                break;
            }
            // Stop header: name left, distance right, selected = inverted.
            var distTxt = Util.formatDistance(g["dist"]);
            var distW = (distTxt == null) ? 0
                : dc.getTextWidthInPixels(distTxt, fHead) + 6;
            var name = (g["fav"] ? "* " : "") + g["n"];
            name = Util.truncate(dc, name, fHead, xR - xPad - distW);
            if (gi == _sel) {
                dc.setColor(Graphics.COLOR_DK_BLUE, Graphics.COLOR_DK_BLUE);
                dc.fillRectangle(0, y - 1, w, hHead + 2);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(xPad, y, fHead, name, Graphics.TEXT_JUSTIFY_LEFT);
            if (distTxt != null) {
                dc.setColor(gi == _sel ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY,
                            Graphics.COLOR_TRANSPARENT);
                dc.drawText(xR, y, fHead, distTxt, Graphics.TEXT_JUSTIFY_RIGHT);
            }
            y += hHead + 1;

            var deps = g["deps"];
            for (var di = 0; di < deps.size(); di++) {
                if (y + hRow > h * 0.95) {
                    break;
                }
                drawDepRow(dc, deps[di], xPad, xR, y, fRow, fHead);
                y += hRow;
            }
            y += 3;
        }
    }

    function drawDepRow(dc, d, xPad, xR, y, fRow, fSmall) {
        var mins = Util.minutesUntil(d["e"]);
        var minsTxt = (mins <= 0) ? "now" : mins + "'";
        var minsW = dc.getTextWidthInPixels(minsTxt, fRow);
        dc.setColor(d["rt"] ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY,
                    Graphics.COLOR_TRANSPARENT);
        dc.drawText(xR, y, fRow, minsTxt, Graphics.TEXT_JUSTIFY_RIGHT);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var route = d["r"];
        var routeW = dc.getTextWidthInPixels(route, fRow);
        dc.drawText(xPad, y, fRow, route, Graphics.TEXT_JUSTIFY_LEFT);

        var maxW = xR - xPad - routeW - minsW - 14;
        if (maxW > 20) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            var hs = Util.truncate(dc, d["h"], fSmall, maxW);
            dc.drawText(xPad + routeW + 7, y + 2, fSmall, hs,
                        Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    function drawStatus(dc, w, h) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var msg = (_status == null) ? "..." : _status;
        var lines = [];
        var idx = msg.find("\n");
        while (idx != null) {
            lines.add(msg.substring(0, idx));
            msg = msg.substring(idx + 1, msg.length());
            idx = msg.find("\n");
        }
        lines.add(msg);
        var fh = dc.getFontHeight(Graphics.FONT_TINY) + 2;
        var y = h / 2 - (lines.size() * fh) / 2;
        for (var i = 0; i < lines.size(); i++) {
            dc.drawText(w / 2, y, Graphics.FONT_TINY, lines[i],
                        Graphics.TEXT_JUSTIFY_CENTER);
            y += fh;
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.78, Graphics.FONT_XTINY, "MENU: search + favorites",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class NearbyDelegate extends WatchUi.BehaviorDelegate {
    var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() {
        _view.openSelected();
        return true;
    }

    function onNextPage() {
        _view.moveSel(1);
        return true;
    }

    function onPreviousPage() {
        _view.moveSel(-1);
        return true;
    }

    function onMenu() {
        Menus.pushMainMenu(_view);
        return true;
    }
}
