import Toybox.Application;
import Toybox.Lang;

// ─────────────────────────────────────────────────
// File d'attente persistante des séances à envoyer
// Stockée dans Application.Properties sous "pendingQ"
// Survit aux redémarrages de l'app montre.
// Max 20 séances pour protéger la mémoire embarquée.
// ─────────────────────────────────────────────────
class PendingQueue {
    static const MAX_SIZE = 20;
    static const KEY      = "pendingQ";

    // Lit le tableau depuis Properties (tableau vide si absent)
    private static function load() as Array {
        var raw = Application.Properties.getValue(KEY);
        if (raw == null) { return new [0]; }
        return raw as Array;
    }

    // Sauvegarde le tableau dans Properties
    private static function save(arr as Array) as Void {
        Application.Properties.setValue(KEY, arr);
    }

    // Ajoute une séance en attente (no-op si queue pleine)
    static function enqueue(dict as Dictionary) as Void {
        var arr = load();
        if (arr.size() >= MAX_SIZE) { return; }
        arr.add(dict);
        save(arr);
    }

    // Retire et retourne le premier élément (null si vide)
    static function dequeue() as Dictionary or Null {
        var arr = load();
        if (arr.size() == 0) { return null; }
        var item = arr[0] as Dictionary;
        arr.remove(arr[0]);
        save(arr);
        return item;
    }

    // Lit sans supprimer (null si vide)
    static function peek() as Dictionary or Null {
        var arr = load();
        if (arr.size() == 0) { return null; }
        return arr[0] as Dictionary;
    }

    // Nombre de séances en attente
    static function size() as Number {
        return load().size();
    }

    // True si aucune séance en attente
    static function isEmpty() as Boolean {
        return load().size() == 0;
    }
}
