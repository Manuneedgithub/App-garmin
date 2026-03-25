import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Point d'entrée principal de l'application
class BasketApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    // Premier écran affiché : le menu de sélection d'exercice
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var menu = new ExerciseMenuView();
        var delegate = new ExerciseMenuDelegate();
        return [menu, delegate];
    }
}

// Raccourci global pour accéder à l'app
function getApp() as BasketApp {
    return Application.getApp() as BasketApp;
}
