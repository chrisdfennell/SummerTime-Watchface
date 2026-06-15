import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Application entry point for the Summertime watch face.
class SummertimeApp extends Application.AppBase {

    private var mView as SummertimeView or Null = null;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Re-read settings and repaint when the user changes app settings
    // (Connect IQ app store / Garmin Connect mobile).
    function onSettingsChanged() as Void {
        if (mView != null) {
            mView.loadSettings();
        }
        WatchUi.requestUpdate();
    }

    // Return the initial view of the watch face.
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        mView = new SummertimeView();
        return [ mView ];
    }
}

function getApp() as SummertimeApp {
    return Application.getApp() as SummertimeApp;
}
