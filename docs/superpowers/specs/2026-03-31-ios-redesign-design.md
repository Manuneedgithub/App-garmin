# Design Spec — Redesign iOS Basket Trainer

**Date :** 2026-03-31
**Scope :** Toutes les vues SwiftUI de l'app iPhone
**Objectif :** Moderniser l'interface vers un style iOS natif clean avec support light/dark mode

---

## 1. Système de design

### Couleurs
- **Accent :** `#FF6600` (orange fixe — identité de l'app)
- **Succès :** `Color(.systemGreen)` — `#34C759` en light, adaptatif
- **Erreur :** `Color(.systemRed)` — `#FF3B30` en light, adaptatif
- **Fond principal :** `Color(.systemGroupedBackground)` — `#f2f2f7` / `#000000`
- **Fond carte :** `Color(.systemBackground)` — `#ffffff` / `#1c1c1e`
- **Fond carte secondaire :** `Color(.secondarySystemBackground)` — `#f2f2f7` / `#2c2c2e`
- **Séparateurs :** `Color(.separator)` — adaptatif

Toutes les couleurs de fond utilisent les **couleurs sémantiques iOS** pour s'adapter automatiquement au mode clair/sombre. Seul l'orange `#FF6600` est codé en dur.

### Dark mode
Automatique — suit le réglage système iOS (`Paramètres → Affichage`). Pas de toggle manuel dans l'app. Le modificateur `.preferredColorScheme` n'est **pas** appliqué globalement (suppression du `preferredColorScheme(.dark)` actuel dans `BasketTrainerApp.swift`).

### Typographie
SF Pro système (`.font(.largeTitle)`, etc.) — pas d'import de police externe.

| Rôle | Style SwiftUI | Usage |
|---|---|---|
| Titre navigation | `.largeTitle.bold()` | Titres d'onglet |
| Titre section | `.title2.bold()` | En-têtes de section |
| Label carte | `.headline` (semibold) | Noms d'exercice |
| Corps | `.body` | Contenu général |
| Métadonnée | `.caption` | Dates, durées |
| Chiffres clés | `.largeTitle.bold()` + `.monospacedDigit()` | Scores, pourcentages |

### Composants réutilisables
- **`StatCard`** — icône + chiffre + label, fond `systemBackground`, coins 14pt
- **`SessionRow`** — emoji + nom + date/durée + score/%, coins 14pt
- **`ExerciseProgressRow`** — emoji + nom + barre de progression colorée + sous-stats
- **Bouton CTA principal** — fond `#FF6600`, coins 14pt, padding vertical 16pt, icône circulaire à gauche

### Règle de couleur pour les pourcentages
| Seuil | Couleur |
|---|---|
| ≥ 70% | `systemGreen` |
| ≥ 50% | `#FF6600` (accent) |
| < 50% | `systemRed` |

---

## 2. HomeView

**Suppression :** `preferredColorScheme(.dark)` dans `BasketTrainerApp.swift`.

**Structure :**
1. Grand titre navigation "Basket Trainer" + sous-titre date du jour
2. Rangée de 3 `StatCard` horizontaux (Séances / Tirs / Réussite%)
3. Bouton CTA "Nouvel entraînement" (fond orange, pleine largeur)
4. Section "Templates" — scroll horizontal de chips si `store.templates` non vide
5. Section "Récentes" — liste des 5 dernières `SessionRow` avec lien "Tout voir" → onglet Historique
6. Badge connexion montre supprimé de la toolbar

**Changements notables :**
- Templates en `ScrollView(.horizontal)` au lieu de liste verticale
- `SessionRow` affiche désormais la durée (si disponible) à côté de la date
- Suppression du `GuidedSessionBanner` (conservé fonctionnellement, redesigné avec même style de card)

---

## 3. HistoryView

**Structure :**
1. Grand titre "Historique"
2. Barre de recherche (`searchable` modifier iOS natif)
3. Filtres en chips horizontaux : Tous / Lancer Franc / 3 Points / Mi-distance
4. Liste groupée par date en style `List` avec `Section` iOS (remplace le `ForEach` + headers actuels)

**Chips de filtre :**
- Actif : fond `#FF6600`, texte blanc
- Inactif : fond `systemBackground`, texte `secondary`, bordure `separator`
- Scroll horizontal dans un `ScrollView(.horizontal, showsIndicators: false)`

**SessionRow étendu :**
- Badge "⌚ Montre" sur les séances `sentFromWatch == true`
- Badge orange "N séries" sur les séances `isComplex == true`

---

## 4. StatsView

**Structure :**
1. Grand titre "Statistiques"
2. Sélecteur de période : segmented control 7j / 30j / 3m / Tout
3. Card graphique (Swift Charts — `BarChart`) :
   - Axe Y : pourcentage de réussite
   - Axe X : jours/semaines selon la période
   - Couleur des barres : `#FF6600`
   - Header : réussite moyenne + delta vs période précédente (↑/↓ + X%)
4. Section "Par exercice" — liste de `ExerciseProgressRow` groupés par catégorie (Lancer Franc / 3 Points / Mi-distance)

**`ExerciseProgressRow` :**
- Emoji + nom de catégorie + pourcentage (coloré selon règle)
- Barre de progression fine (hauteur 5pt)
- Sous-label : N séances · N tirs

---

## 5. SessionDetailView

**Structure :**
1. Bouton retour "‹ Historique"
2. Card header unifié :
   - Emoji + nom exercice + date/heure/durée
   - Score "X/Y" + pourcentage (côte à côte, séparateur vertical)
   - Barre de progression colorée
3. Card "Tir par tir" : points numérotés (1–N) en cercles verts/rouges

**Séances complexes :** une card par série, chacune avec son propre score et barre de progression, puis card récapitulatif global.

---

## 6. ManualSessionView / EditSessionView

**Structure :**
1. Sheet modale — nav bar "Annuler" / titre / "Ajouter" (ou "Enregistrer" pour édition)
2. Section exercice : liste sélectionnable (emoji + nom, coche orange sur sélection)
3. Section résultat : stepper +/− pour "Tirs réussis" et "Total tirs"
   - Pourcentage calculé en temps réel affiché en grand au centre de la card
4. (Si template préfillé) Séries pré-configurées affichées en lecture seule au-dessus

---

## 7. WorkoutConfigView

**Structure :**
1. Titre "Envoyer à la montre"
2. Card exercice sélectionné (tap → sheet de sélection)
3. Card statut connexion montre (point vert/orange + "Forerunner 255 · Synchro il y a Xmin")
4. Bouton CTA orange "Envoyer à la montre"
5. Texte hint en bas : "Ou lancez directement depuis la montre — les données seront synchronisées automatiquement."

---

## 8. TemplatesView

Conserve sa logique actuelle (liste de templates, tap → préfill ManualSession). Redesigné avec :
- Cards `systemBackground` coins 14pt
- Bordure gauche orange 3pt sur chaque card (accent visuel)
- Nom du template + résumé "N séries · N tirs"

---

## Fichiers impactés

| Fichier | Nature du changement |
|---|---|
| `BasketTrainerApp.swift` | Supprimer `.preferredColorScheme(.dark)` |
| `Views/HomeView.swift` | Redesign complet + templates horizontal |
| `Views/HistoryView.swift` | Chips filtres + searchable + groupes iOS |
| `Views/StatsView.swift` | Sélecteur période + delta + ExerciseProgressRow |
| `Views/SessionDetailView.swift` | Header card unifié + numérotation dots |
| `Views/ManualSessionView.swift` | Stepper +/− + % live |
| `Views/EditSessionView.swift` | Même style que ManualSessionView |
| `Views/WorkoutConfigView.swift` | Statut connexion + hint |
| `Views/TemplatesView.swift` | Cards avec bordure gauche orange |

Aucun changement aux modèles de données, à `SessionStore`, ni à `GarminManager`.
