# Rapport de tests de bout en bout — 25.09.2026

Tests menés en **production** (projet `mathclass-a9328`, vrai Claude), sur le
simulateur iPad (iOS 27), l'app Mac et le compte de test
`prof.test.201032@mathclass.test`, classe « 4e B Test » (MX-XMW8).

## À faire par Xavier

1. **Déployer la fonction de correction** (le garde-fou d'autorisations a bloqué
   le déploiement automatique) :

   ```
   firebase deploy --only functions:correct_submission
   ```

   Sans ce déploiement, la production accepte encore une réponse finale fausse
   (constaté : « x = 5 » validé pour 2(x + 3) = 14) et le bouton
   « Lancer la correction » du prof échoue.
2. **iPad physique** : déverrouiller l'iPad, accepter « Faire confiance à cet
   ordinateur », puis dans Xcode choisir « Xavier's iPad » et Cmd+R. À tester
   là : Apple Pencil et scan du QR code (impossibles sur simulateur).
3. Nouveau build TestFlight (n° 2) quand tu le souhaites : tout ce qui suit
   n'est pas dans le build 1.

## Parcours validés

**Professeur (iPad et Mac)** : inscription, connexion, déconnexion, profil,
changement de langue, démo (chargement et réinitialisation), classes (collage,
CSV, manuel, ajout et suppression d'élèves, suppression de classe), groupes,
chapitres et compétences, exercices (manuel, photo + IA, modification,
suppression), devoirs (3 modes, ciblage d'élèves), boîte de soumissions et
détail, tableau de bord en direct (dont l'envoi d'un exercice à un élève),
statistiques (3 vues) et export PDF, correction manuelle d'une note.

**Élève (iPad)** : code classe, choix du nom, écriture, reconnaissance,
correction des étapes lues, soumission, 2e chance, niveaux progressifs,
évaluation (correction en arrière-plan), changement de devoir, reprise après
relance, déconnexion.

## Défauts trouvés et corrigés aujourd'hui

| Gravité | Défaut | Correction |
|---|---|---|
| Critique | Réponse finale fausse acceptée : SymPy ne savait pas comparer des équations, tout reposait sur Claude | Équations comparées par leurs solutions ; dernière étape vérifiée contre la réponse attendue (**à déployer**) |
| Critique | « Réinitialiser la démo » supprimait sans confirmation des exercices utilisés dans de vrais devoirs, et en laissait 24 sur 30 | Confirmation ; exercices utilisés conservés ; les 30 supprimés sinon |
| Majeur | PDF des statistiques Mac vide, enregistré dans un dossier caché | Rapport imprimable dédié, fenêtre « Enregistrer sous » |
| Majeur | Changer de langue coupait les mises à jour en direct (boîte de soumissions et tableau « En direct » vides) | Les écouteurs survivent au changement |
| Majeur | Élève bloqué sur « Aucun devoir actif » si le devoir le plus récent ne le concernait pas | Il arrive sur un devoir qui le concerne |
| Majeur | Copie d'évaluation jamais corrigée si l'iPad est fermé pendant la correction | Bouton prof « Lancer la correction » (**à déployer**) et note manuelle |
| Majeur | Énoncés avec fractions, puissances, etc. affichés en LaTeX brut chez l'élève | Rendu KaTeX |
| Moyen | Pas de moyen pour le prof de corriger une note de l'IA | Menu « Modifier la note » (iPad et Mac) |
| Moyen | Suppression d'un exercice utilisé dans des devoirs sans avertissement | Avertissement avec le nombre de devoirs |
| Moyen | Nouveau devoir invisible chez l'élève sans « Recharger » | Apparition automatique |
| Moyen | Compétences affichées par identifiant dans les statistiques | Noms affichés |
| Moyen | Import d'image Mac : pas de titre ni de compétences suggérés | Aligné sur l'iPad |
| Mineur | « Échoué / Revisez » affiché alors qu'une 2e chance est offerte | « Pas encore », avec un encouragement |
| Mineur | Confiance de lecture faible : aucune étape proposée | Les étapes lues sont proposées, avec un avertissement |
| Mineur | Énoncé élève dans une colonne étroite et haute | Bande pleine largeur ajustée au texte |
| Mineur | Profil refermé au changement de langue ; feuille de connexion Mac transparente ; classe non présélectionnée dans « Nouveau devoir » ; libellés non traduits | Corrigés |

## Limites connues (non corrigées)

- La correction peut encore juger « équivalent » un résultat non mis sous la
  forme demandée (ex. « factoriser » : une forme développée est égale). Le
  prof peut corriger la note à la main.
- Le modèle Période/Séance (« Nouvelle séance ») n'est pas lu par l'app élève.
- Les devoirs n'ont pas de nom (affichés par mode et date).
- Fournisseur Claude : API Anthropic temporaire. Repasser à Vertex AI Europe
  (demande de quota à refaire après le 27.09.2026) avant tout élève réel.

## Tests automatiques

- Python (`functions/`) : 102 tests, tous verts.
- Swift (`MathClassTests`) : 27 tests, tous verts.
- Émulateurs (`firestore-tests`, `npm run e2e`) : 13/13.
