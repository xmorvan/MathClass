# Banque d'exercices intégrée — cahier des charges

À lancer dans une session dédiée. Objectif : le prof trouve ses exercices tout faits, déjà étiquetés, et le diagnostic des élèves s'appuie dessus.

## Périmètre

- France : collège (6e → 3e) et lycée (seconde, première et terminale, spécialité et tronc commun).
- Suisse : Maturité gymnasiale (niveaux standard et renforcé).
- IB : Mathematics AA et AI (SL et HL).
- Couvrir **chaque savoir-faire** du référentiel (`functions/taxonomy_source.txt`, 187 aujourd'hui) à chaque niveau où il est enseigné : au moins 8 exercices par savoir-faire et par niveau, de difficulté 1 à 5, dont des énoncés à texte (problèmes).

## Contrat avec l'app

- Le référentiel est le contrat : chaque exercice porte 1 à 4 `skillIDs` existants, le plus central en premier. Si un savoir-faire manque, il est **ajouté** au référentiel (jamais renommé), puis `python3 tools/build_taxonomy.py` est relancé.
- Format d'un exercice (champs de `Core/Models/Exercise.swift`) : `title`, `statement` (LaTeX entre `$…$`), `expectedAnswer` (LaTeX, la forme demandée : factorisée, simplifiée, avec unité…), `difficultyLevel` (1–5), `skillIDs`, plus pour la banque : `levels` (ex. `["fr-4e", "fr-3e", "ch-matu-standard", "ib-aa-sl"]`), `solutionSteps` (le corrigé ligne par ligne, en LaTeX), `source: "bank"`.
- Rangement proposé : collection Firestore `bankExercises/{id}` en lecture pour tout prof ; le prof copie un exercice dans sa banque (`exercises/`, avec son `teacherID`) pour le modifier. Règles de sécurité et tests (`firestore-tests/rules.test.mjs`) à écrire.

## Qualité, vérifiée automatiquement

1. **Originalité** : aucun exercice copié d'un manuel ou d'un site ; énoncés rédigés ou générés puis relus.
2. **Justesse** : le corrigé `solutionSteps` passé dans `correct_submission` (SymPy + Claude) doit être noté 100 % juste ; une copie fausse type (erreur classique du savoir-faire) doit être notée fausse, à la bonne ligne. Réutiliser `functions/tests/grading_benchmark.py`.
3. **Étiquetage** : pour chaque exercice, `tag_exercises` doit retrouver le savoir-faire principal ; les écarts sont relus.
4. **Couverture** : un rapport par programme et par niveau (savoir-faire × niveau → nombre d'exercices) ; aucune case vide.

## Dans l'app, ensuite

- Parcours « Banque » dans l'éditeur d'exercices et dans l'assistant de devoir : filtrer par programme, niveau, domaine, compétence, savoir-faire, difficulté.
- Depuis le diagnostic d'un élève : « Proposer des exercices sur ce savoir-faire » (remédiation ciblée, envoyés en direct avec la fonction existante).
- Correspondance référentiel ↔ programmes officiels (libellés du programme affichés au prof).
