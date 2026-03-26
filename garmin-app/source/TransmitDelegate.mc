import Toybox.Communications;
import Toybox.Lang;

// Listener partagé pour tous les appels Communications.transmit()
// Gère l'échec silencieusement (pas de téléphone connecté = normal en simulateur)
class TransmitDelegate extends Communications.ConnectionListener {
    function initialize() {
        Communications.ConnectionListener.initialize();
    }

    function onComplete() as Void {
        // Envoi réussi
    }

    function onError() as Void {
        // Échec silencieux (montre non couplée ou hors portée)
    }
}
