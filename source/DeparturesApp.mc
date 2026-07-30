import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

(:background, :glance)
class DeparturesApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        var view = new NearbyView();
        return [view, new NearbyDelegate(view)];
    }

    (:glance)
    function getGlanceView() {
        return [new DeparturesGlanceView()];
    }

    function getServiceDelegate() {
        return [new DeparturesBgService()];
    }

    // Data handed back by the background service via Background.exit().
    function onBackgroundData(data) {
        if (data instanceof Dictionary) {
            var glance = data["glance"];
            if (glance != null) {
                Store.set("glance", glance);
            }
            if (data["expired"] == true) {
                AlertKit.disarm();
            }
            if (data["fired"] == true) {
                AlertKit.disarm();
                Store.set("pendingAlert", { "msg" => data["msg"] });
            }
        }
        WatchUi.requestUpdate();
    }
}
