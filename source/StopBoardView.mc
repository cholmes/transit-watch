import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Timer;

// Full departure board for one stop. Auto-refreshes; MENU/SELECT opens
// actions (pin stop, pin line, set alert, refresh).
class StopBoardView extends WatchUi.View {
    var _stop;               // {id, n, la, lo}
    var _deps = null;
    var _status = "Loading...";
    var _top = 0;
    var _timer = null;
    var _fetching = false;

    function initialize(stop) {
        View.initialize();
        _stop = stop;
    }

    function stop() {
        return _stop;
    }

    function deps() {
        return (_deps == null) ? [] : _deps;
    }

    function onShow() {
        if (_timer == null) {
            _timer = new Timer.Timer();
        }
        _timer.start(method(:onTick), Cfg.refreshMs(), true);
        refresh();
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

    function refresh() {
        if (_fetching) {
            return;
        }
        _fetching = true;
        new ApiClient().stopTimes(_stop["id"], Cfg.maxDepartures(),
                                  method(:onData));
    }

    function onData(deps, err) {
        _fetching = false;
        if (deps == null) {
            if (_deps == null) {
                _status = err;
            }
            WatchUi.requestUpdate();
            return;
        }
        _deps = Favorites.orderDeps(_stop["id"], deps, Cfg.maxDepartures());
        _status = (_deps.size() == 0) ? "No upcoming departures" : null;
        if (_top >= _deps.size()) {
            _top = 0;
        }

        // This stop becomes the glance stop (last viewed wins; the
        // background service overrides it with the alerted stop).
        var trimmed = [];
        for (var i = 0; i < _deps.size() && i < 4; i++) {
            trimmed.add({
                "r" => _deps[i]["r"],
                "h" => _deps[i]["h"],
                "e" => _deps[i]["e"],
                "rt" => _deps[i]["rt"]
            });
        }
        Store.set("glance", { "stop" => _stop["n"], "deps" => trimmed });

        Alerter.checkDeps(_stop["id"], _deps);
        WatchUi.requestUpdate();
    }

    function scroll(delta) {
        if (_deps == null || _deps.size() == 0) {
            return;
        }
        _top += delta;
        if (_top < 0) {
            _top = 0;
        }
        if (_top >= _deps.size()) {
            _top = _deps.size() - 1;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var fName = Graphics.FONT_XTINY;
        var fRoute = Graphics.FONT_SMALL;
        var fSub = Graphics.FONT_XTINY;
        var xPad = (w * 0.10).toNumber();
        var xR = w - xPad;

        var y = (h * 0.05).toNumber();
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        var name = (Favorites.isFav(_stop["id"]) ? "* " : "") + _stop["n"];
        name = Util.truncate(dc, name, fName, (w * 0.76).toNumber());
        dc.drawText(w / 2, y, fName, name, Graphics.TEXT_JUSTIFY_CENTER);
        y += dc.getFontHeight(fName) + 3;

        if (_deps == null || _deps.size() == 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_TINY,
                        (_status == null) ? "..." : _status,
                        Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var rowH = dc.getFontHeight(fRoute) + dc.getFontHeight(fSub) + 5;
        for (var i = _top; i < _deps.size(); i++) {
            if (y + rowH > h * 0.96) {
                break;
            }
            var d = _deps[i];
            var mins = Util.minutesUntil(d["e"]);
            var minsTxt = (mins <= 0) ? "now" : mins + " min";
            dc.setColor(d["rt"] ? Graphics.COLOR_GREEN : Graphics.COLOR_LT_GRAY,
                        Graphics.COLOR_TRANSPARENT);
            dc.drawText(xR, y, fRoute, minsTxt, Graphics.TEXT_JUSTIFY_RIGHT);

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var route = d["r"];
            if (Favorites.isPinnedLine(_stop["id"], route)) {
                route = "* " + route;
            }
            var minsW = dc.getTextWidthInPixels(minsTxt, fRoute);
            route = Util.truncate(dc, route, fRoute, xR - xPad - minsW - 10);
            dc.drawText(xPad, y, fRoute, route, Graphics.TEXT_JUSTIFY_LEFT);
            y += dc.getFontHeight(fRoute);

            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            var hs = Util.truncate(dc, d["h"], fSub, xR - xPad);
            dc.drawText(xPad, y, fSub, hs, Graphics.TEXT_JUSTIFY_LEFT);
            y += dc.getFontHeight(fSub) + 5;
        }
    }
}

class StopBoardDelegate extends WatchUi.BehaviorDelegate {
    var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() {
        Menus.pushBoardMenu(_view);
        return true;
    }

    function onMenu() {
        Menus.pushBoardMenu(_view);
        return true;
    }

    function onNextPage() {
        _view.scroll(1);
        return true;
    }

    function onPreviousPage() {
        _view.scroll(-1);
        return true;
    }
}
