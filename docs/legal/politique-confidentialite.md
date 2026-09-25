# Politique de confidentialité de MathClass

Version de travail du 25 septembre 2026. À faire relire par un juriste avant publication. Les passages marqués À COMPLÉTER ou À VÉRIFIER doivent être réglés avant la mise en ligne.

## 1. Qui est responsable

MathClass est édité par Xavier Morvan, Genève, Suisse (adresse postale : À COMPLÉTER). Contact pour toute question sur vos données : À COMPLÉTER (adresse e-mail dédiée).

MathClass est un outil pour la classe. Deux situations se présentent.

Pour les comptes des enseignants, MathClass décide de l'usage des données et en est responsable.

Pour les données des élèves, c'est l'établissement scolaire (ou l'enseignant qui utilise MathClass de sa propre initiative) qui décide de l'usage de l'outil avec sa classe. MathClass traite ces données pour son compte, selon ses instructions, en qualité de sous-traitant. Un contrat de sous-traitance est proposé aux établissements.

## 2. Données traitées

### Enseignants

Nom, prénom et adresse e-mail, fournis à l'inscription. Le mot de passe est géré par le service d'authentification de Google (Firebase Authentication) ; MathClass n'y a jamais accès en clair.

Le contenu créé par l'enseignant : classes, listes d'élèves, groupes, chapitres, compétences, exercices et photos d'exercices, séances.

### Élèves

Les élèves n'ont ni adresse e-mail ni mot de passe. Ils rejoignent leur classe avec un code fourni par l'enseignant, puis choisissent leur nom dans une liste.

MathClass traite les données suivantes :

| Donnée | Origine | Usage |
|---|---|---|
| Prénom et nom | saisis par l'enseignant | identifier l'élève dans la classe |
| Niveau (1 à 5) et groupe | saisis par l'enseignant | proposer des exercices adaptés |
| Copie manuscrite (image du tracé sur l'iPad) | produite par l'élève | transcrire le raisonnement |
| Étapes transcrites en notation mathématique | vérifiées par l'élève | corriger le raisonnement |
| Résultat par étape, catégorie d'erreur, temps passé, progression | calculés par MathClass | retour à l'élève, suivi par l'enseignant |
| Identifiant d'iPad | nombre aléatoire créé par l'app | savoir quel iPad est lié à quel élève |
| Identifiant de connexion anonyme | créé par Firebase Authentication | réserver à l'élève l'accès à son propre travail |

La liste des noms proposée lors de la connexion n'affiche que le prénom et l'initiale du nom.

### Données techniques

Firebase Authentication conserve les adresses IP de connexion pendant quelques semaines. MathClass n'intègre aucun outil de mesure d'audience, aucun traceur publicitaire et aucun service d'analyse de comportement.

## 3. Pourquoi ces données sont traitées

Les données servent uniquement à faire fonctionner MathClass en classe : proposer les exercices, transcrire et corriger le travail des élèves, donner un retour immédiat, et permettre à l'enseignant de suivre sa classe (statistiques, rapports PDF).

MathClass ne vend aucune donnée, n'affiche aucune publicité et ne se sert pas des données des élèves à d'autres fins.

## 4. Correction automatique

La transcription des copies et la correction étape par étape sont réalisées par un modèle d'intelligence artificielle (Claude, développé par Anthropic), complété par un calcul symbolique (SymPy) qui vérifie l'équivalence des expressions. Le résultat est une aide pédagogique. L'élève vérifie la transcription avant correction, et l'enseignant voit chaque copie et chaque résultat. Aucune décision ayant des effets juridiques pour l'élève n'est prise automatiquement.

Ce qui est envoyé au modèle : l'image du tracé, les étapes transcrites, l'énoncé de l'exercice et la réponse attendue. Le nom de l'élève, son niveau, sa classe et ses identifiants ne sont pas envoyés.

## 5. Prestataires et lieux de traitement

| Prestataire | Service | Lieu |
|---|---|---|
| Google (Firebase) | base de données Cloud Firestore et stockage des images Cloud Storage | À VÉRIFIER dans la console Firebase (emplacement de la base et du bucket) |
| Google (Firebase) | fonctions serveur (Cloud Functions) | Zurich, Suisse (europe-west6) |
| Google (Firebase Authentication) | comptes enseignants, comptes anonymes des élèves | États-Unis |
| Google Cloud (Vertex AI) | exécution du modèle Claude | Union européenne (région europe-west1, Belgique) |

Selon la documentation de Firebase, le service Firebase Authentication fonctionne uniquement depuis des centres de données situés aux États-Unis. Google déclare respecter le Swiss-U.S. Data Privacy Framework et l'EU-U.S. Data Privacy Framework. Depuis le 15 septembre 2024, la Suisse reconnaît un niveau de protection adéquat aux entreprises américaines certifiées dans ce cadre. Pour un élève, Firebase Authentication ne contient qu'un identifiant anonyme, sans nom ni adresse e-mail.

Google agit comme sous-traitant de MathClass selon ses conditions de traitement des données (Data Processing and Security Terms).

## 6. Durée de conservation

Les copies manuscrites, les transcriptions et les résultats sont supprimés automatiquement douze mois après leur envoi.

Quand un enseignant supprime une classe, MathClass supprime immédiatement la classe, ses élèves, leurs copies, leurs images et leur progression.

Quand un enseignant supprime son compte depuis l'app, MathClass supprime immédiatement ses classes (avec tout ce qu'elles contiennent), ses exercices et son profil. Selon la documentation de Firebase, les données d'authentification disparaissent ensuite des systèmes actifs et des sauvegardes de Google dans un délai de 180 jours.

Selon Google, les requêtes envoyées au modèle Claude via Vertex AI ne sont pas conservées. À VÉRIFIER dans les conditions de Google Cloud applicables au compte.

## 7. Sécurité

Les échanges entre l'app et les serveurs sont chiffrés (HTTPS). L'accès aux données est contrôlé côté serveur : un enseignant n'accède qu'aux classes qu'il a créées ; un élève n'accède qu'à sa propre classe et à son propre travail, jamais aux fiches de ses camarades. Ces règles font l'objet de tests automatisés.

## 8. Vos droits

Toute personne concernée peut demander l'accès à ses données, leur rectification ou leur suppression. Pour un élève, la demande passe normalement par l'enseignant ou l'établissement, qui peut corriger ou supprimer les données directement dans l'app. Vous pouvez aussi écrire à l'adresse de contact indiquée au point 1.

En Suisse, l'autorité de surveillance est le Préposé fédéral à la protection des données et à la transparence (PFPDT). Pour une école publique, l'autorité cantonale de protection des données est compétente (à Genève, le Préposé cantonal à la protection des données et à la transparence). En France, il s'agit de la CNIL.

## 9. Modifications

Toute modification de cette politique est publiée sur cette page avec sa date. Les établissements sous contrat sont informés à l'avance de tout changement de prestataire.
