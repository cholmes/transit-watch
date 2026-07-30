import Toybox.Lang;
import Toybox.WatchUi;

// All Menu2-based flows: main menu, favorites, search, stop lists, board
// actions, and the alert arming wizard (line -> threshold -> window).
module Menus {

    function pushMainMenu(nearbyView) {
        var menu = new WatchUi.Menu2({ :title => "Departures" });
        menu.addItem(new WatchUi.MenuItem("Favorites", null, "favs", null));
        if (WatchUi has :TextPicker) {
            menu.addItem(new WatchUi.MenuItem("Search stops", null, "search", null));
        }
        menu.addItem(new WatchUi.MenuItem("Rescan location", null, "rescan", null));
        var alert = AlertKit.get();
        if (alert != null) {
            menu.addItem(new WatchUi.MenuItem("Cancel alert",
                alert["r"] + " <=" + alert["thr"] + "'", "cancel", null));
        }
        WatchUi.pushView(menu, new MainMenuDelegate(nearbyView), WatchUi.SLIDE_UP);
    }

    function pushStopList(title, stops) {
        var menu = new WatchUi.Menu2({ :title => title });
        for (var i = 0; i < stops.size(); i++) {
            var s = stops[i];
            var label = (Favorites.isFav(s["id"]) ? "* " : "") + s["n"];
            menu.addItem(new WatchUi.MenuItem(label,
                Util.formatDistance(s["dist"]), i, null));
        }
        WatchUi.pushView(menu, new StopListDelegate(stops), WatchUi.SLIDE_LEFT);
    }

    function pushBoardMenu(boardView) {
        var stop = boardView.stop();
        var menu = new WatchUi.Menu2({ :title => stop["n"] });
        menu.addItem(new WatchUi.MenuItem("Set alert", null, "alert", null));
        var alert = AlertKit.get();
        if (alert != null) {
            menu.addItem(new WatchUi.MenuItem("Cancel alert",
                alert["r"] + " <=" + alert["thr"] + "'", "cancel", null));
        }
        menu.addItem(new WatchUi.MenuItem(
            Favorites.isFav(stop["id"]) ? "Unpin stop" : "Pin stop",
            null, "pin", null));
        menu.addItem(new WatchUi.MenuItem("Pin / unpin line", null, "pinline", null));
        menu.addItem(new WatchUi.MenuItem("Refresh", null, "refresh", null));
        WatchUi.pushView(menu, new BoardMenuDelegate(boardView), WatchUi.SLIDE_UP);
    }

    // Distinct route+headsign combinations from the board's departures.
    function pushLinePicker(stop, deps, forAlert) {
        var lines = [];
        for (var i = 0; i < deps.size() && lines.size() < 10; i++) {
            var d = deps[i];
            var seen = false;
            for (var j = 0; j < lines.size(); j++) {
                if (lines[j]["r"].equals(d["r"]) && lines[j]["h"].equals(d["h"])) {
                    seen = true;
                    break;
                }
            }
            if (!seen) {
                lines.add({ "r" => d["r"], "h" => d["h"] });
            }
        }
        if (lines.size() == 0) {
            Util.toast("No departures to pick");
            return;
        }
        var menu = new WatchUi.Menu2({
            :title => forAlert ? "Alert on line" : "Pin line"
        });
        for (var i = 0; i < lines.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(lines[i]["r"], lines[i]["h"], i, null));
        }
        WatchUi.pushView(menu, new LinePickerDelegate(stop, lines, forAlert),
                         WatchUi.SLIDE_LEFT);
    }

    function pushThresholdMenu(stop, line) {
        var values = [3, 4, 5, 6, 8, 10, 12, 15];
        var def = Cfg.alertMinutes();
        var menu = new WatchUi.Menu2({ :title => "Alert when <=" });
        for (var i = 0; i < values.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(values[i] + " min",
                (values[i] == def) ? "default" : null, i, null));
        }
        WatchUi.pushView(menu, new ThresholdDelegate(stop, line, values),
                         WatchUi.SLIDE_LEFT);
    }

    function pushWindowMenu(stop, line, thr) {
        var labels = ["Next 30 min", "Next hour", "Next 2 hours", "Until it fires"];
        var values = [30, 60, 120, 0];
        var menu = new WatchUi.Menu2({ :title => "Active for" });
        for (var i = 0; i < labels.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(labels[i], null, i, null));
        }
        WatchUi.pushView(menu, new WindowDelegate(stop, line, thr, values),
                         WatchUi.SLIDE_LEFT);
    }
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    var _view;

    function initialize(view) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item) {
        var id = item.getId();
        if ("favs".equals(id)) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            var favs = Favorites.all();
            if (favs.size() == 0) {
                Util.toast("No favorites yet");
                return;
            }
            var loc = _view.loc();
            var stops = [];
            for (var i = 0; i < favs.size(); i++) {
                var f = favs[i];
                var dist = null;
                if (loc != null && f["la"] != null && f["lo"] != null) {
                    dist = Util.distanceM(loc[0], loc[1], f["la"], f["lo"]);
                }
                stops.add({
                    "id" => f["id"], "n" => f["n"],
                    "la" => f["la"], "lo" => f["lo"], "dist" => dist
                });
            }
            Util.sortByKey(stops, "dist");
            Menus.pushStopList("Favorites", stops);
        } else if ("search".equals(id)) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.pushView(new WatchUi.TextPicker(""),
                             new SearchDelegate(_view), WatchUi.SLIDE_UP);
        } else if ("rescan".equals(id)) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            _view.rescanLocation();
        } else if ("cancel".equals(id)) {
            AlertKit.disarm();
            Util.toast("Alert cancelled");
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}

class StopListDelegate extends WatchUi.Menu2InputDelegate {
    var _stops;

    function initialize(stops) {
        Menu2InputDelegate.initialize();
        _stops = stops;
    }

    function onSelect(item) {
        var idx = item.getId();
        var board = new StopBoardView(_stops[idx]);
        WatchUi.pushView(board, new StopBoardDelegate(board), WatchUi.SLIDE_LEFT);
    }
}

class SearchDelegate extends WatchUi.TextPickerDelegate {
    var _view;

    function initialize(view) {
        TextPickerDelegate.initialize();
        _view = view;
    }

    function onTextEntered(text, changed) {
        if (text != null && text.length() > 1) {
            new SearchRunner().run(text, _view.loc());
        }
        return true;
    }

    function onCancel() {
        return true;
    }
}

class SearchRunner {
    var _loc;

    function initialize() {
    }

    function run(text, loc) {
        _loc = loc;
        Util.toast("Searching...");
        new ApiClient().searchStops(text, loc, method(:onData));
    }

    function onData(stops, err) {
        if (stops == null || stops.size() == 0) {
            Util.toast("No stops found");
            return;
        }
        for (var i = 0; i < stops.size(); i++) {
            var s = stops[i];
            s["dist"] = null;
            if (_loc != null && s["la"] != null && s["lo"] != null) {
                s["dist"] = Util.distanceM(_loc[0], _loc[1], s["la"], s["lo"]);
            }
        }
        Menus.pushStopList("Results", stops);
    }
}

class BoardMenuDelegate extends WatchUi.Menu2InputDelegate {
    var _view;

    function initialize(view) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item) {
        var id = item.getId();
        var stop = _view.stop();
        if ("alert".equals(id)) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Menus.pushLinePicker(stop, _view.deps(), true);
        } else if ("cancel".equals(id)) {
            AlertKit.disarm();
            Util.toast("Alert cancelled");
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if ("pin".equals(id)) {
            var nowFav = Favorites.toggle(stop);
            Util.toast(nowFav ? "Stop pinned" : "Stop unpinned");
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if ("pinline".equals(id)) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            Menus.pushLinePicker(stop, _view.deps(), false);
        } else if ("refresh".equals(id)) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            _view.refresh();
        }
    }
}

class LinePickerDelegate extends WatchUi.Menu2InputDelegate {
    var _stop;
    var _lines;
    var _forAlert;

    function initialize(stop, lines, forAlert) {
        Menu2InputDelegate.initialize();
        _stop = stop;
        _lines = lines;
        _forAlert = forAlert;
    }

    function onSelect(item) {
        var line = _lines[item.getId()];
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (_forAlert) {
            Menus.pushThresholdMenu(_stop, line);
        } else {
            var pinned = Favorites.toggleLine(_stop["id"], line["r"]);
            Util.toast(pinned ? "Line " + line["r"] + " pinned"
                              : "Line " + line["r"] + " unpinned");
        }
    }
}

class ThresholdDelegate extends WatchUi.Menu2InputDelegate {
    var _stop;
    var _line;
    var _values;

    function initialize(stop, line, values) {
        Menu2InputDelegate.initialize();
        _stop = stop;
        _line = line;
        _values = values;
    }

    function onSelect(item) {
        var thr = _values[item.getId()];
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        Menus.pushWindowMenu(_stop, _line, thr);
    }
}

class WindowDelegate extends WatchUi.Menu2InputDelegate {
    var _stop;
    var _line;
    var _thr;
    var _values;

    function initialize(stop, line, thr, values) {
        Menu2InputDelegate.initialize();
        _stop = stop;
        _line = line;
        _thr = thr;
        _values = values;
    }

    function onSelect(item) {
        var windowMin = _values[item.getId()];
        AlertKit.arm(_stop["id"], _stop["n"], _line["r"], _line["h"],
                     _thr, windowMin);
        Util.toast("Alert: " + _line["r"] + " <=" + _thr + "'");
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
