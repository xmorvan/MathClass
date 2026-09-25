# Notes pour le juriste

Dossier préparé le 25 septembre 2026 pour la relecture de la politique de confidentialité, du modèle de contrat de sous-traitance et de la fiche destinée aux écoles (même dossier). Ces notes distinguent ce qui a été vérifié sur une source officielle, ce qui reste à vérifier et les questions de fond.

## Contexte

MathClass est une app iPad et Mac pour des classes de mathématiques (collège, lycée). Éditeur : Xavier Morvan, personne physique à Genève (forme juridique à décider). Cible commerciale : établissements en Suisse romande, éventuellement en France. Les utilisateurs finaux sont en majorité mineurs.

Architecture : Google Firebase (base Cloud Firestore, stockage Cloud Storage, fonctions Cloud Functions à Zurich, authentification Firebase Authentication) et modèle d'IA Claude d'Anthropic pour la transcription et la correction.

## Faits vérifiés

Firebase Authentication fonctionne uniquement depuis des centres de données aux États-Unis ; les adresses IP sont conservées quelques semaines ; les données d'un utilisateur supprimé disparaissent des systèmes actifs et des sauvegardes en 180 jours ; Google est généralement sous-traitant au sens du RGPD et déclare respecter le Swiss-U.S. et l'EU-U.S. Data Privacy Framework. Source : https://firebase.google.com/support/privacy (consultée le 25.09.2026).

Le Conseil fédéral reconnaît un niveau de protection adéquat aux entreprises américaines certifiées Swiss-U.S. DPF depuis le 15 septembre 2024 (annexe 1 de l'ordonnance sur la protection des données). Sources : https://www.admin.ch/en/nsb?id=102054 et https://www.edoeb.admin.ch/en/15082024-new-swiss-us-data-privacy-framework.

API Anthropic en direct : entrées et sorties supprimées sous 30 jours, sauf violation de la politique d'usage (conservation jusqu'à 2 ans, scores de classification jusqu'à 7 ans). Source : https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data (mise à jour du 1er juillet 2026). Les données conservées ne servent pas à l'entraînement sans permission expresse. Source : https://platform.claude.com/docs/en/manage-claude/api-and-data-retention.

API Anthropic en direct : stockage au repos uniquement aux États-Unis, calcul aux États-Unis ou « global » ; aucune option européenne. Source : https://platform.claude.com/docs/en/manage-claude/data-residency.

Claude Haiku 4.5 (le modèle utilisé) est proposé par Google Cloud Vertex AI dans la région europe-west1, avec un traitement « Europe multi-région ». La même page indique une date de retrait « pas avant le 15 octobre 2026 ». Source : https://docs.cloud.google.com/vertex-ai/generative-ai/docs/partner-models/claude/haiku-4-5.

À Genève, la LIPAD encadre la sous-traitance par les institutions publiques : contrat exigé, contrôles possibles chez le sous-traitant, sous-traitance en cascade soumise à accord écrit préalable. Sources : https://silgeneve.ch/legis/program/books/rsg/htm/rsg_a2_08.htm et le résumé https://www.sidd.swiss/fr/perspectives/protection-des-donnees-a-geneve-lipad-et-nlpd-combinees/ (à confirmer sur le texte de la loi).

## Choix techniques faits pour réduire le risque

Le fournisseur d'IA passe de l'API Anthropic en direct (États-Unis) à Vertex AI de Google en Europe. Google devient le seul sous-traitant ultérieur, déjà présent pour Firebase, et les copies des élèves ne quittent plus l'Europe pour la correction.

Le modèle ne reçoit ni nom ni identifiant d'élève.

Les élèves n'ont ni e-mail ni mot de passe ; leur compte Firebase Authentication est anonyme.

Les règles d'accès côté serveur limitent chaque enseignant à ses classes et chaque élève à son travail ; elles sont testées automatiquement.

Suppression automatique des copies à douze mois, suppression immédiate d'une classe ou d'un compte à la demande.

## Points à vérifier avant publication

1. Emplacement de la base Cloud Firestore et du bucket Cloud Storage (console Firebase, paramètres du projet). S'ils ne sont pas en Suisse ou dans l'UE, il faut soit créer un nouveau projet au bon endroit, soit l'indiquer.
2. Conditions de Google Cloud pour les modèles partenaires sur Vertex AI : absence de conservation des requêtes, absence d'entraînement, rôle d'Anthropic (accède-t-il aux requêtes ?). Une source secondaire affirme « zero data retention » ; aucune source Google primaire relue à ce jour.
3. Entité Google contractante et acceptation des Data Processing and Security Terms (console Google Cloud).
4. Retrait du modèle Claude Haiku 4.5 possible dès le 15 octobre 2026 : prévoir le modèle de remplacement disponible en Europe sur Vertex AI et mettre à jour les documents si le modèle change.
5. Authentification à deux facteurs sur le compte Google administrateur du projet.

## Questions de fond pour le juriste

Rôles : l'établissement est-il bien responsable du traitement et l'éditeur sous-traitant pour les données des élèves ? Qu'en est-il quand un enseignant utilise l'app de sa propre initiative, sans accord de son établissement ?

Écoles publiques genevoises : faut-il une validation préalable du département (DIP) ou du préposé cantonal avant tout usage en classe ? Le contrat modèle suffit-il au regard de la LIPAD et de son règlement (RIPAD) ?

Firebase Authentication aux États-Unis : l'identifiant anonyme d'un élève, rattaché par le serveur à sa fiche, est une donnée personnelle. Le transfert repose sur la certification DPF de Google : est-ce suffisant pour une école publique, et faut-il une analyse d'impact (LPD art. 22) ?

France : la position de la CNIL et du ministère de l'Éducation nationale sur les services hébergés par des sociétés américaines en milieu scolaire rend-elle l'offre inutilisable en France tant que l'authentification reste chez Google ?

Consentement : faut-il informer les parents, ou recueillir un accord, avant qu'une copie d'élève soit traitée par une IA ? Qui s'en charge, l'école ou l'éditeur ?

Correction automatique : la mention « aide pédagogique, pas de décision automatisée » suffit-elle au regard de l'art. 21 LPD ?

Forme juridique et responsabilité : exercer en raison individuelle ou créer une Sàrl avant de signer avec des écoles ; assurance responsabilité civile professionnelle (cyber).

Mentions légales du site et conditions d'utilisation de l'app : à rédiger.
