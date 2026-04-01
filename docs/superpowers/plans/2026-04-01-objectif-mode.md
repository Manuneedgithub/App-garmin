# Mode Objectif Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter un mode "Objectif" sur la montre Garmin où la session s'arrête automatiquement quand un nombre cible de paniers est atteint, et adapter les modèles iPhone pour stocker et afficher cet objectif.

**Architecture:** Côté Garmin, on ajoute `GoalSession.mc` (modèle), `GoalMenu.mc` (sélection objectif), `GoalView.mc` (tracking), `GoalSummaryView.mc` (résumé + envoi), et `MainMenu.mc` (menu racine à 3 modes). `BasketApp.mc` pointe vers `MainMenu`. Côté iPhone, on ajoute `targetMade: Int?` dans `TemplateSeries` et `ShotSeries`, et on l'affiche dans `SessionDetailView`.

**Tech Stack:** Monkey C (Connect IQ SDK 9.1.0), Swift 5 / SwiftUI iOS 16+

---

## Fichiers créés / modifiés

### Garmin
| Fichier | Action |
|---------|--------|
| `garmin-app/source/MainMenu.mc` | Créer — menu racine 3 entrées |
| `garmin-app/source/GoalSession.mc` | Créer — modèle données + toDictionary() |
| `garmin-app/source/GoalMenu.mc` | Créer — sélection objectif chips + boutons |
| `garmin-app/source/GoalView.mc` | Créer — tracking tir par tir avec barre objectif |
| `garmin-app/source/GoalSummaryView.mc` | Créer — résumé final + envoi iPhone |
| `garmin-app/source/BasketApp.mc` | Modifier — pointer vers MainMenu |

### iPhone
| Fichier | Action |
|---------|--------|
| `ios-app/BasketTrainer/Models/Models.swift` | Modifier — `targetMade: Int?` dans `TemplateSeries` et `ShotSeries` |
| `ios-app/BasketTrainer/Managers/GarminManager.swift` | Modifier — lire `targetMade` dans `parseAndStore()` |
| `ios-app/BasketTrainer/Views/ManualSessionView.swift` | Modifier — toggle + stepper objectif dans `SeriesEditorRow` |
| `ios-app/BasketTrainer/Views/SessionDetailView.swift` | Modifier — afficher objectif dans `seriesList` |

---

## Task 1 : MainMenu.mc — Menu racine 3 modes

**Files:**
- Create: `garmin-app/source/MainMenu.mc`

- [ ] **Step 1 : Créer `MainMenu.mc`**

```monkeyc
import Toybox.WatchUi;
import Toybox.Lang;

// Menu racine : choix du mode d'entraînement
class MainMenuView extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => "Basket Trainer"});
        addItem(new WatchUi.MenuItem("Tirs libres",       null, 0, null));
        addItem(new WatchUi.MenuItem("Objectif simple",   null, 1, null));
        addItem(new WatchUi.MenuItem("Objectif complexe", null, 2, null));
    }
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as Number;
        if (id == 0) {
            // Tirs libres : mode existant
            var menu = new ExerciseMenuView();
            var del  = new ExerciseMenuDelegate(null);
            WatchUi.pushView(menu, del, WatchUi.SLIDE_LEFT);
        } else if (id == 1) {
            // Objectif simple : choisir exercice puis objectif
            var menu = new ExerciseMenuGoalDelegate(null);
            var view = new ExerciseMenuView();
            WatchUi.pushView(view, menu, WatchUi.SLIDE_LEFT);
        } else {
            // Objectif complexe : non implémenté dans ce plan
            // (sera géré via guided session depuis iPhone)
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
```

- [ ] **Step 2 : Modifier `BasketApp.mc` pour utiliser `MainMenuView`**

Modifier `garmin-app/source/BasketApp.mc`, remplacer le contenu de `getInitialView()` :

```monkeyc
function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
    var menu     = new MainMenuView();
    var delegate = new MainMenuDelegate();
    return [menu, delegate];
}
```

- [ ] **Step 3 : Build pour vérifier la compilation**

Dans VS Code : `Cmd+Shift+P` → "Monkey C: Build for Device"

Expected : pas d'erreur de compilation (juste des warnings typecheck inoffensifs).

- [ ] **Step 4 : Commit**

```bash
git add garmin-app/source/MainMenu.mc garmin-app/source/BasketApp.mc
git commit -m "feat(garmin): add MainMenu with 3 modes (tirs libres, objectif simple, objectif complexe)"
```

---

## Task 2 : GoalSession.mc — Modèle de données

**Files:**
- Create: `garmin-app/source/GoalSession.mc`

- [ ] **Step 1 : Créer `GoalSession.mc`**

```monkeyc
import Toybox.Lang;
import Toybox.Time;
import Toybox.Communications;

// ─────────────────────────────────────────────────
// Modèle de données pour une session "Objectif"
// L'objectif est un nombre de paniers à rentrer.
// La session s'arrête quand madeShots == targetMade.
// ─────────────────────────────────────────────────
class GoalSession {
    var exerciseId   as Number;
    var exerciseName as String;
    var targetMade   as Number;  // objectif : nombre de paniers à rentrer
    var madeShots    as Number;  // paniers réussis jusqu'ici
    var totalShots   as Number;  // tirs au total (réussis + ratés)
    var results      as Array;   // [Boolean] — true=réussi, false=raté
    var startTime    as Number;  // timestamp Unix

    function initialize(exId as Number, target as Number) {
        exerciseId   = exId;
        exerciseName = getExerciseName(exId);
        targetMade   = target;
        madeShots    = 0;
        totalShots   = 0;
        results      = new [0];
        startTime    = Time.now().value();
    }

    // Enregistre un tir
    function recordShot(made as Boolean) as Void {
        results.add(made);
        totalShots++;
        if (made) { madeShots++; }
    }

    // Vrai quand l'objectif est atteint
    function isGoalReached() as Boolean {
        return madeShots >= targetMade;
    }

    // Pourcentage de réussite (0-100)
    function percentage() as Number {
        if (totalShots == 0) { return 0; }
        return (madeShots * 100) / totalShots;
    }

    // Sérialise pour envoi à l'iPhone
    function toDictionary() as Dictionary {
        return {
            "exerciseId"   => exerciseId,
            "exerciseName" => exerciseName,
            "totalShots"   => totalShots,
            "madeShots"    => madeShots,
            "percentage"   => percentage(),
            "startTime"    => startTime,
            "results"      => results,
            "duration"     => Time.now().value() - startTime,
            "targetMade"   => targetMade
        };
    }
}
```

- [ ] **Step 2 : Build pour vérifier**

`Cmd+Shift+P` → "Monkey C: Build for Device"

Expected : compilation OK.

- [ ] **Step 3 : Commit**

```bash
git add garmin-app/source/GoalSession.mc
git commit -m "feat(garmin): add GoalSession model with targetMade and isGoalReached()"
```

---

## Task 3 : GoalMenu.mc — Sélection de l'objectif

**Files:**
- Create: `garmin-app/source/GoalMenu.mc`

- [ ] **Step 1 : Créer `GoalMenu.mc`**

```monkeyc
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;

// ─────────────────────────────────────────────────
// Écran de sélection de l'objectif paniers
//
//   ┌──────────────────────────┐
//   │     Lancer Franc         │  titre exercice
//   │  Objectif : 10 paniers   │  valeur courante
//   │                          │
//   │  5  10  15  20  25  30   │  chips rapides
//   │                          │
//   │  ▲ +1     ▼ -1           │
//   │  SELECT pour valider     │
//   └──────────────────────────┘
// ─────────────────────────────────────────────────

class GoalMenuView extends WatchUi.View {
    private var _exerciseId as Number;
    private var _target     as Number;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GRAY   = 0x888888;

    function initialize(exerciseId as Number, initialTarget as Number) {
        View.initialize();
        _exerciseId = exerciseId;
        _target     = initialTarget;
    }

    function setTarget(t as Number) as Void {
        _target = t;
        WatchUi.requestUpdate();
    }

    function getTarget() as Number {
        return _target;
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // Nom exercice
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 30, Graphics.FONT_XTINY, getExerciseName(_exerciseId),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Objectif courant
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 90, Graphics.FONT_NUMBER_MEDIUM, _target.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 130, Graphics.FONT_TINY, "paniers",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Chips rapides
        var chips = [5, 10, 15, 20, 25, 30];
        var chipW = w / chips.size();
        for (var i = 0; i < chips.size(); i++) {
            var chip = chips[i] as Number;
            var cx2  = (i * chipW) + chipW / 2;
            var col  = (chip == _target) ? COLOR_ORANGE : COLOR_GRAY;
            dc.setColor(col, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx2, 178, Graphics.FONT_XTINY, chip.toString(),
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // Instructions
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 52, 220, Graphics.FONT_XTINY, "\u2191 +1",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + 52, 220, Graphics.FONT_XTINY, "\u2193 -1",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 240, Graphics.FONT_XTINY, "START = valider",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}

class GoalMenuDelegate extends WatchUi.BehaviorDelegate {
    private var _view       as GoalMenuView;
    private var _exerciseId as Number;

    function initialize(view as GoalMenuView, exerciseId as Number) {
        BehaviorDelegate.initialize();
        _view       = view;
        _exerciseId = exerciseId;
    }

    // Bouton HAUT → +1
    function onNextPage() as Boolean {
        var t = _view.getTarget() + 1;
        if (t > 50) { t = 50; }
        _view.setTarget(t);
        return true;
    }

    // Bouton BAS → -1
    function onPreviousPage() as Boolean {
        var t = _view.getTarget() - 1;
        if (t < 1) { t = 1; }
        _view.setTarget(t);
        return true;
    }

    // SELECT → lancer la session
    function onSelect() as Boolean {
        var session = new GoalSession(_exerciseId, _view.getTarget());
        var view    = new GoalView(session);
        var del     = new GoalDelegate(session, view);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
```

- [ ] **Step 2 : Ajouter `ExerciseMenuGoalDelegate` dans `ExerciseMenu.mc`**

Ajouter à la fin de `garmin-app/source/ExerciseMenu.mc` :

```monkeyc
// Délégué pour le mode Objectif : après avoir choisi l'exercice, 
// affiche GoalMenuView au lieu de ShotCountMenuView
class ExerciseMenuGoalDelegate extends WatchUi.Menu2InputDelegate {
    private var _accumulator as Object or Null;

    function initialize(accumulator as Object or Null) {
        Menu2InputDelegate.initialize();
        _accumulator = accumulator;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var exerciseId = item.getId() as Number;
        var view       = new GoalMenuView(exerciseId, 10);
        var del        = new GoalMenuDelegate(view, exerciseId);
        WatchUi.pushView(view, del, WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
```

- [ ] **Step 3 : Build**

`Cmd+Shift+P` → "Monkey C: Build for Device"

Expected : compilation OK.

- [ ] **Step 4 : Commit**

```bash
git add garmin-app/source/GoalMenu.mc garmin-app/source/ExerciseMenu.mc
git commit -m "feat(garmin): add GoalMenu (target selection with chips and +/-1 buttons)"
```

---

## Task 4 : GoalView.mc — Écran de tracking

**Files:**
- Create: `garmin-app/source/GoalView.mc`

- [ ] **Step 1 : Créer `GoalView.mc`**

```monkeyc
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;

// ─────────────────────────────────────────────────
// ÉCRAN TRACKING — Mode Objectif
//
//   ┌──────────────────────────┐
//   │      Lancer Franc        │  y=30  gris xtiny
//   │   Objectif : 10 🏀       │  y=55  blanc xtiny
//   │                          │
//   │       5 / 8              │  y=110 blanc grand : mis/total
//   │                          │
//   │  ████████░░░░░░░░        │  y=160 barre progression objectif
//   │                          │
//   │  ● ● ● ● ● ● ● ○ ○      │  y=190 points résultats
//   │                          │
//   │  ▲ Réussi   ▼ Raté       │  y=225 gris xtiny
//   └──────────────────────────┘
// ─────────────────────────────────────────────────

class GoalView extends WatchUi.View {
    private var _session as GoalSession;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;
    private const COLOR_RED    = 0xFF3333;
    private const DOT_RADIUS   = 6;
    private const DOT_SPACING  = 15;

    function initialize(session as GoalSession) {
        View.initialize();
        _session = session;
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w  = dc.getWidth();
        var cx = w / 2;

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // Nom exercice
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 30, Graphics.FONT_XTINY, _session.exerciseName,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Objectif
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 55, Graphics.FONT_XTINY,
                    "Objectif : " + _session.targetMade.toString(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Compteur principal : mis / total tirs
        var shotText = _session.madeShots.toString() + " / " + _session.totalShots.toString();
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 110, Graphics.FONT_NUMBER_MEDIUM, shotText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Barre de progression vers l'objectif
        drawProgressBar(dc, cx, 155);

        // Points résultats (12 derniers)
        drawResultDots(dc, cx, 190);

        // Instructions
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 48, 225, Graphics.FONT_XTINY, "\u2191 R\u00e9ussi",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + 48, 225, Graphics.FONT_XTINY, "\u2193 R\u00e9t\u00e9",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawProgressBar(dc as Graphics.Dc, cx as Number, cy as Number) as Void {
        var barW   = 160;
        var barH   = 10;
        var x      = cx - barW / 2;
        var pct    = (_session.madeShots * 100) / _session.targetMade;
        if (pct > 100) { pct = 100; }
        var filled = (barW * pct) / 100;

        // Fond gris
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, cy, barW, barH, 5);

        // Remplissage : orange → vert quand objectif atteint
        if (filled > 0) {
            var barColor = (_session.madeShots >= _session.targetMade) ? COLOR_GREEN : COLOR_ORANGE;
            dc.setColor(barColor, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, cy, filled, barH, 5);
        }
    }

    private function drawResultDots(dc as Graphics.Dc, cx as Number, cy as Number) as Void {
        var count = _session.results.size();
        if (count == 0) { return; }
        var displayCount = count > 12 ? 12 : count;
        var startIdx     = count - displayCount;
        var totalWidth   = displayCount * DOT_SPACING;
        var startX       = cx - (totalWidth / 2) + (DOT_SPACING / 2);

        for (var i = 0; i < displayCount; i++) {
            var made  = _session.results[startIdx + i] as Boolean;
            var color = made ? COLOR_GREEN : COLOR_RED;
            var x     = startX + (i * DOT_SPACING);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, cy, DOT_RADIUS);
            dc.setColor(COLOR_BG, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(x, cy, DOT_RADIUS);
        }
    }
}

// ─────────────────────────────────────────────────
// DELEGATE — Boutons pendant la session objectif
// ─────────────────────────────────────────────────
class GoalDelegate extends WatchUi.BehaviorDelegate {
    private var _session as GoalSession;
    private var _view    as GoalView;

    function initialize(session as GoalSession, view as GoalView) {
        BehaviorDelegate.initialize();
        _session = session;
        _view    = view;
    }

    // Bouton HAUT → Tir réussi
    function onNextPage() as Boolean {
        _session.recordShot(true);
        if (_session.isGoalReached()) {
            showSummary();
        } else {
            WatchUi.requestUpdate();
        }
        return true;
    }

    // Bouton BAS → Tir raté
    function onPreviousPage() as Boolean {
        _session.recordShot(false);
        // Pas d'auto-stop sur un raté
        WatchUi.requestUpdate();
        return true;
    }

    // Bouton BACK → annuler
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    private function showSummary() as Void {
        var summaryView = new GoalSummaryView(_session);
        var summaryDel  = new GoalSummaryDelegate(_session);
        WatchUi.pushView(summaryView, summaryDel, WatchUi.SLIDE_LEFT);
    }
}
```

- [ ] **Step 2 : Build**

`Cmd+Shift+P` → "Monkey C: Build for Device"

Expected : compilation OK.

- [ ] **Step 3 : Commit**

```bash
git add garmin-app/source/GoalView.mc
git commit -m "feat(garmin): add GoalView tracking screen with progress bar toward target"
```

---

## Task 5 : GoalSummaryView.mc — Résumé final + envoi

**Files:**
- Create: `garmin-app/source/GoalSummaryView.mc`

- [ ] **Step 1 : Créer `GoalSummaryView.mc`**

```monkeyc
import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Communications;

// ─────────────────────────────────────────────────
// RÉSUMÉ FINAL — Mode Objectif
//
//   ┌──────────────────────────┐
//   │      Résultat            │  gris xtiny
//   │    Lancer Franc          │  blanc tiny
//   │                          │
//   │       10 / 23            │  blanc grand : mis/total
//   │        43%               │  coloré selon perf
//   │                          │
//   │  Objectif : 10 ✓         │  vert tiny
//   │                          │
//   │  ▶ Sauvegarder           │  gris xtiny
//   │  ↩ Quitter               │  gris xtiny
//   └──────────────────────────┘
// ─────────────────────────────────────────────────

class GoalSummaryView extends WatchUi.View {
    private var _session as GoalSession;

    private const COLOR_BG     = Graphics.COLOR_BLACK;
    private const COLOR_WHITE  = Graphics.COLOR_WHITE;
    private const COLOR_ORANGE = 0xFF6600;
    private const COLOR_GREEN  = 0x33CC66;
    private const COLOR_GRAY   = 0x888888;
    private const COLOR_RED    = 0xFF3333;

    function initialize(session as GoalSession) {
        View.initialize();
        _session = session;
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w   = dc.getWidth();
        var cx  = w / 2;
        var pct = _session.percentage();

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        // Titre
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 28, Graphics.FONT_XTINY, "R\u00e9sultat",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Nom exercice
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 50, Graphics.FONT_TINY, _session.exerciseName,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Score mis / total
        var scoreText = _session.madeShots.toString() + " / " + _session.totalShots.toString();
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 98, Graphics.FONT_NUMBER_MEDIUM, scoreText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Pourcentage
        var pctColor = scoreColor(pct);
        dc.setColor(pctColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 140, Graphics.FONT_MEDIUM, pct.toString() + "%",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Objectif atteint
        dc.setColor(COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 168, Graphics.FONT_XTINY,
                    "Objectif : " + _session.targetMade.toString() + " \u2713",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Instructions
        dc.setColor(COLOR_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 200, Graphics.FONT_XTINY, "\u25b6 Sauvegarder",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, 220, Graphics.FONT_XTINY, "\u21a9 Quitter",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function scoreColor(pct as Number) as Number {
        if (pct >= 70) { return COLOR_GREEN; }
        if (pct >= 50) { return COLOR_ORANGE; }
        return COLOR_RED;
    }
}

class GoalSummaryDelegate extends WatchUi.BehaviorDelegate {
    private var _session as GoalSession;

    function initialize(session as GoalSession) {
        BehaviorDelegate.initialize();
        _session = session;
    }

    // SELECT → envoyer à l'iPhone + retour menu
    function onSelect() as Boolean {
        Communications.transmit(_session.toDictionary(), null, new GoalTransmitListener());
        // Retour au menu principal (3 pops : GoalSummary, GoalView, GoalMenu)
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    // BACK → quitter sans envoyer
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

class GoalTransmitListener extends Communications.ConnectionListener {
    function initialize() {
        Communications.ConnectionListener.initialize();
    }
    function onComplete() as Void {
    }
    function onError() as Void {
    }
}
```

- [ ] **Step 2 : Build**

`Cmd+Shift+P` → "Monkey C: Build for Device"

Expected : compilation OK.

- [ ] **Step 3 : Test sur simulateur**

Lancer le simulateur FR255, naviguer : Objectif simple → Lancer Franc → objectif 5 → tirer 5 réussis → vérifier que le résumé apparaît automatiquement avec "Objectif : 5 ✓".

- [ ] **Step 4 : Commit**

```bash
git add garmin-app/source/GoalSummaryView.mc
git commit -m "feat(garmin): add GoalSummaryView with auto-stop and transmit to iPhone"
```

---

## Task 6 : iPhone — Modèles `targetMade`

**Files:**
- Modify: `ios-app/BasketTrainer/Models/Models.swift`

- [ ] **Step 1 : Ajouter `targetMade` dans `TemplateSeries`**

Dans `Models.swift`, remplacer :

```swift
struct TemplateSeries: Codable {
    var exerciseType: ExerciseType
    var totalShots: Int
}
```

par :

```swift
struct TemplateSeries: Codable {
    var exerciseType: ExerciseType
    var totalShots: Int
    var targetMade: Int?   // nil = mode tirs libres, non-nil = mode objectif
}
```

- [ ] **Step 2 : Ajouter `targetMade` dans `ShotSeries`**

Dans `Models.swift`, remplacer :

```swift
struct ShotSeries: Codable, Identifiable {
    var id: UUID = UUID()
    var exerciseType: ExerciseType
    var totalShots: Int
    var madeShots: Int
    var results: [Bool]
```

par :

```swift
struct ShotSeries: Codable, Identifiable {
    var id: UUID = UUID()
    var exerciseType: ExerciseType
    var totalShots: Int
    var madeShots: Int
    var results: [Bool]
    var targetMade: Int?   // objectif paniers (nil si mode tirs libres)
```

- [ ] **Step 3 : Mettre à jour `init(fromGarmin:)` de `ShotSeries`**

Dans `ShotSeries.init(fromGarmin:)`, ajouter la lecture de `targetMade` :

```swift
init(fromGarmin data: [String: Any]) {
    let exId = data["exerciseId"] as? Int ?? 0
    self.exerciseType = ExerciseType(rawValue: exId) ?? .freethrow
    self.totalShots   = data["totalShots"] as? Int ?? 0
    self.madeShots    = data["madeShots"]  as? Int ?? 0
    self.results      = (data["results"] as? [Bool]) ?? []
    self.targetMade   = data["targetMade"] as? Int
}
```

- [ ] **Step 4 : Build Xcode**

`Cmd+B` dans Xcode.

Expected : 0 erreur (le champ optionnel `targetMade` est rétrocompatible avec les données existantes dans UserDefaults — JSONDecoder utilise `nil` si absent).

- [ ] **Step 5 : Commit**

```bash
git add ios-app/BasketTrainer/Models/Models.swift
git commit -m "feat(ios): add targetMade optional field to TemplateSeries and ShotSeries"
```

---

## Task 7 : iPhone — GarminManager lit `targetMade`

**Files:**
- Modify: `ios-app/BasketTrainer/Managers/GarminManager.swift`

- [ ] **Step 1 : Lire `targetMade` dans `parseAndStore()`**

Dans `GarminManager.swift`, dans la méthode `parseAndStore(_:)`, après la ligne `let rawResults = dict["results"] as? [Bool] ?? []`, ajouter :

```swift
let targetMade = dict["targetMade"] as? Int
```

Puis modifier la création de `WorkoutSession` pour passer `targetMade` à la série si présent. Remplacer le bloc complet `parseAndStore` :

```swift
private func parseAndStore(_ dict: [String: Any]) {
    let exId       = dict["exerciseId"] as? Int ?? 0
    let total      = dict["totalShots"] as? Int ?? 0
    let made       = dict["madeShots"]  as? Int ?? 0
    let startTime  = dict["startTime"]  as? Int ?? 0
    let duration   = dict["duration"]   as? Int ?? 0
    let rawResults = dict["results"] as? [Bool] ?? []
    let targetMade = dict["targetMade"] as? Int

    var session = WorkoutSession(
        exerciseType: ExerciseType(rawValue: exId) ?? .freethrow,
        totalShots: total,
        madeShots: made,
        results: rawResults,
        date: Date(timeIntervalSince1970: TimeInterval(startTime))
    )
    session.duration = TimeInterval(duration)
    session.sentFromWatch = true

    // Si targetMade présent, créer une série simple avec l'objectif
    if let target = targetMade {
        var series = ShotSeries(exerciseType: ExerciseType(rawValue: exId) ?? .freethrow,
                                totalShots: total, madeShots: made, results: rawResults)
        series.targetMade = target
        session.series = [series]
    }

    DispatchQueue.main.async {
        self.lastSyncDate = Date()
        self.handleSessionOrGuided(session, results: rawResults, total: total, made: made)
    }
}
```

- [ ] **Step 2 : Build Xcode**

`Cmd+B` dans Xcode.

Expected : 0 erreur.

- [ ] **Step 3 : Commit**

```bash
git add ios-app/BasketTrainer/Managers/GarminManager.swift
git commit -m "feat(ios): parse targetMade from watch message and attach to session series"
```

---

## Task 8 : iPhone — Afficher objectif dans `SessionDetailView`

**Files:**
- Modify: `ios-app/BasketTrainer/Views/SessionDetailView.swift`

- [ ] **Step 1 : Afficher `targetMade` dans `seriesList`**

Dans `SessionDetailView.swift`, dans la fonction `seriesList(_ series:)`, après la ligne :

```swift
Text("\(ser.exerciseType.emoji) Série \(idx + 1) — \(ser.exerciseType.name)")
```

ajouter dans le même `HStack` (juste avant `Spacer()`) :

```swift
if let target = ser.targetMade {
    Text("🎯 \(target)")
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.green.opacity(0.8))
        .clipShape(Capsule())
}
```

Le `HStack` complet devient :

```swift
HStack {
    Text("\(ser.exerciseType.emoji) Série \(idx + 1) — \(ser.exerciseType.name)")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
    if let target = ser.targetMade {
        Text("🎯 \(target)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.8))
            .clipShape(Capsule())
    }
    Spacer()
    Text("\(ser.madeShots)/\(ser.totalShots)")
        .font(.subheadline.bold())
        .foregroundStyle(.primary)
    Text(String(format: "%.0f%%", ser.percentage))
        .font(.caption.bold())
        .foregroundStyle(percentageColor(ser.percentage))
}
```

- [ ] **Step 2 : Build Xcode**

`Cmd+B` dans Xcode.

Expected : 0 erreur.

- [ ] **Step 3 : Commit**

```bash
git add ios-app/BasketTrainer/Views/SessionDetailView.swift
git commit -m "feat(ios): show targetMade badge in session detail series list"
```

---

## Task 9 : iPhone — Ajouter toggle objectif dans `ManualSessionView`

**Files:**
- Modify: `ios-app/BasketTrainer/Views/ManualSessionView.swift`

- [ ] **Step 1 : Ajouter `targetMade` UI dans `SeriesEditorRow`**

Dans `ManualSessionView.swift`, la struct `SeriesEditorRow` commence à :

```swift
struct SeriesEditorRow: View {
    @Binding var series: ShotSeries
    let index:    Int
    let onDelete: (() -> Void)?

    private let shotOptions = [5, 10, 15, 20, 25, 30]
```

Ajouter une `@State` locale pour le toggle :

```swift
struct SeriesEditorRow: View {
    @Binding var series: ShotSeries
    let index:    Int
    let onDelete: (() -> Void)?

    private let shotOptions = [5, 10, 15, 20, 25, 30]
    @State private var hasTarget: Bool = false
```

Puis dans le `body` de `SeriesEditorRow`, après le bloc qui affiche le stepper des tirs réussis et avant le bouton supprimer, ajouter :

```swift
// Toggle objectif
Toggle("Mode objectif", isOn: $hasTarget)
    .font(.subheadline)
    .onChange(of: hasTarget) { enabled in
        series.targetMade = enabled ? series.madeShots : nil
    }

if hasTarget {
    HStack {
        Text("Objectif paniers")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Spacer()
        Stepper("\(series.targetMade ?? 1)",
                value: Binding(
                    get: { series.targetMade ?? 1 },
                    set: { series.targetMade = $0 }
                ),
                in: 1...100)
        .labelsHidden()
    }
}
```

- [ ] **Step 2 : Mettre à jour la sauvegarde template dans `ManualSessionView`**

Dans le corps de `saveSession()`, la ligne qui crée le template :

```swift
series: series.map { TemplateSeries(exerciseType: $0.exerciseType, totalShots: $0.totalShots) }
```

devient :

```swift
series: series.map { TemplateSeries(exerciseType: $0.exerciseType, totalShots: $0.totalShots, targetMade: $0.targetMade) }
```

- [ ] **Step 3 : Build Xcode**

`Cmd+B` dans Xcode.

Expected : 0 erreur.

- [ ] **Step 4 : Commit**

```bash
git add ios-app/BasketTrainer/Views/ManualSessionView.swift
git commit -m "feat(ios): add optional targetMade toggle and stepper in SeriesEditorRow"
```

---

## Vérification finale

- [ ] **Test Garmin end-to-end :**
  1. Simulateur FR255 : Menu → Objectif simple → Lancer Franc → objectif 5
  2. Tirer 5 réussis → résumé apparaît automatiquement avec "Objectif : 5 ✓"
  3. SELECT → données transmises (popup ADB normale en simulateur)

- [ ] **Test iPhone :**
  1. Sur montre réelle : compléter un entraînement objectif
  2. Vérifier dans l'historique iPhone que la session apparaît avec le badge "🎯 5"
  3. Ouvrir le détail → badge vert "🎯 5" visible dans la série

- [ ] **Rétrocompatibilité :**
  1. Les séances existantes dans UserDefaults s'affichent toujours correctement (pas de badge objectif pour elles)
  2. Le mode "Tirs libres" fonctionne identiquement
