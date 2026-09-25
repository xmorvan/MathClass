# Mise en ligne pour des prospects

Objectif : envoyer à un enseignant un lien qui lui permet d'installer MathClass sur son iPad (ou son Mac), de créer son compte, de charger la classe de démo et d'essayer le parcours élève. Le canal retenu est TestFlight avec un lien public : pas de publication sur l'App Store, jusqu'à 10 000 testeurs, et chaque build reste installable 90 jours après son envoi (sources : developer.apple.com/testflight et l'aide App Store Connect, consultées le 25.09.2026).

Les étapes sont dans l'ordre où elles se font. Compter une demi-journée sur le Mac si la compilation ne révèle pas de grosse surprise, puis un à deux jours d'attente pour la validation d'Apple.

## 1. Console Firebase et Google Cloud

1. Firebase, Authentication, Sign-in method : activer « Anonyme » (connexion des élèves). Laisser « E-mail/Mot de passe » actif.
2. Firebase, Paramètres du projet, Général : relever l'emplacement de Cloud Firestore et du bucket Cloud Storage. Le reporter dans docs/legal (politique de confidentialité, fiche écoles, annexe 3 du contrat). Si l'emplacement n'est ni en Suisse ni dans l'UE, en parler au juriste avant d'inviter des prospects.
3. Google Cloud console, même projet : activer l'API « Vertex AI ».
4. Google Cloud, Vertex AI, Model Garden : ouvrir Claude Haiku 4.5 et l'activer (accepter les conditions d'Anthropic). Vérifier que la région europe-west1 est proposée.
5. Google Cloud, IAM : vérifier que le compte de service des Cloud Functions a le rôle « Vertex AI User » (par défaut, le compte de service Compute Engine a souvent le rôle Éditeur, qui suffit).
6. Google Cloud, Facturation : définir une alerte de budget (par exemple 50 CHF par mois) pour être prévenu si un usage anormal fait grimper la facture de Vertex AI.
7. Compte Google administrateur : activer l'authentification à deux facteurs.

## 2. Déploiement du serveur

Depuis le dossier du projet, sur le Mac :

```
cd functions && python3.12 -m venv venv && venv/bin/pip install -r requirements.txt -r requirements-dev.txt
venv/bin/python -m pytest tests
cd ../firestore-tests && npm install && npm test
cd .. && firebase deploy --only functions,firestore:rules,firestore:indexes,storage
```

Les deux séries de tests doivent passer avant le déploiement. Au premier déploiement, accepter la question sur l'accès des règles Storage à Firestore et la création de la tâche planifiée (Cloud Scheduler).

Contrôle après déploiement : dans la console Firebase, Functions, on doit voir neuf fonctions, dont purge_old_submissions.

## 3. Compilation dans Xcode

1. Ouvrir MathClass.xcodeproj, laisser Xcode résoudre les paquets Swift.
2. Compiler la cible iPad (MathClass) puis la cible Mac (MathClass-macOS). Le code modifié n'a pas pu être compilé dans l'environnement où il a été écrit ; s'il y a des erreurs, les copier et les faire corriger.
3. Lancer sur le simulateur iPad et dérouler le scénario du paragraphe 5 une fois, de bout en bout.

## 4. TestFlight

1. App Store Connect, Apps : créer l'app si elle n'existe pas (identifiant de bundle xavier-morvan.MathClass, plateformes iPadOS et macOS). Les textes et réponses sur la confidentialité sont dans fiche-app-store.md.
2. Xcode : Product, Archive (cible iPad), puis Distribute App, App Store Connect, Upload. Même chose pour la cible Mac.
3. App Store Connect, TestFlight : remplir « Informations de test » (texte « À tester » et adresse de contact), puis les informations pour la revue : un compte enseignant de test avec la démo chargée (voir fiche-app-store.md).
4. Créer un groupe de testeurs externes, par exemple « Prospects », y ajouter le build et l'envoyer en revue. Le premier build doit être validé par Apple avant que des testeurs externes puissent l'installer.
5. Une fois validé : activer le lien public du groupe. C'est ce lien qui va dans les e-mails aux prospects et sur la landing page.
6. Tous les deux mois environ, envoyer un nouveau build pour que le lien reste utilisable (limite de 90 jours par build).

## 5. Scénario d'essai pour un prospect

Avec un seul iPad :

1. Installer TestFlight, ouvrir le lien public, installer MathClass.
2. Choisir « Enseignant », créer un compte.
3. Profil, « Charger les données de démo ». Une classe « Démo, 3e A » apparaît avec dix élèves, six exercices et un devoir actif. Relever son code (MX-XXXX).
4. Se déconnecter, choisir « Élève », saisir le code, choisir un nom.
5. Résoudre un exercice au stylet, vérifier la transcription, lire la correction.
6. Se déconnecter de la session élève, revenir en enseignant : la copie apparaît dans la boîte de réception et dans les statistiques.

Avec un iPad et un Mac, l'enseignant reste connecté sur le Mac pendant que l'élève travaille sur l'iPad ; le tableau de bord en direct se met à jour pendant la séance.

## 6. Avant de passer à l'App Store public

Relecture juridique terminée et documents publiés ; emplacement des données confirmé ; Firebase App Check activé (empêche d'autres programmes que l'app d'appeler le serveur) ; remplacement de l'icône provisoire ; captures d'écran iPad et Mac ; prix et modèle commercial décidés.
