# Politique de confidentialité de MathClass

Version de travail du 25 septembre 2026, mise à jour le 27 septembre 2026 (diagnostic des erreurs, emplacements vérifiés). À faire relire par un juriste avant publication. Les passages marqués À COMPLÉTER ou À VÉRIFIER doivent être réglés avant la mise en ligne.

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
| Copie manuscrite (image du tracé sur l'iPad) | produite par l'élève | montrer la copie à l'enseignant ; la transcrire si la lecture sur l'iPad n'est pas disponible |
| Étapes transcrites en notation mathématique, phrase-réponse saisie au clavier | vérifiées par l'élève | corriger le raisonnement |
| Résultat par étape, temps passé, progression | calculés par MathClass | retour à l'élève, suivi par l'enseignant |
| Diagnostic des étapes fausses : savoir-faire en cause, type d'erreur, courte note | proposé par le modèle d'IA, que l'enseignant peut confirmer, corriger ou retirer | aider l'enseignant à repérer ce que l'élève doit retravailler |
| Bilan par savoir-faire (maîtrisé, fragile, non maîtrisé, à confirmer) | calculé par l'app à partir des copies | statistiques de l'enseignant |
| Identifiant d'iPad | nombre aléatoire créé par l'app | savoir quel iPad est lié à quel élève |
| Identifiant de connexion anonyme | créé par Firebase Authentication | réserver à l'élève l'accès à son propre travail |

La liste des noms proposée lors de la connexion n'affiche que le prénom et l'initiale du nom.

### Données techniques

Firebase Authentication conserve les adresses IP de connexion pendant quelques semaines. MathClass n'intègre aucun outil de mesure d'audience, aucun traceur publicitaire et aucun service d'analyse de comportement.

## 3. Pourquoi ces données sont traitées

Les données servent uniquement à faire fonctionner MathClass en classe : proposer les exercices, transcrire et corriger le travail des élèves, donner un retour immédiat, et permettre à l'enseignant de suivre sa classe (statistiques, rapports PDF).

MathClass ne vend aucune donnée, n'affiche aucune publicité et ne se sert pas des données des élèves à d'autres fins.

## 4. Correction et diagnostic automatiques

Le processus, dans l'ordre :

1. L'écriture de l'élève est lue sur l'iPad lui-même (moteur MyScript intégré à l'app) : rien ne sort de l'appareil pour cette étape. L'élève voit ce qui est lu et le corrige si besoin.
2. L'image du tracé est enregistrée pour que l'enseignant puisse voir la copie.
3. La correction est faite d'abord par un calcul symbolique (SymPy) sur les serveurs de MathClass ; le modèle d'intelligence artificielle (Claude, développé par Anthropic) n'est consulté que pour les étapes que ce calcul ne peut pas trancher.
4. Quand une copie est fausse, le modèle propose un diagnostic de chaque étape fausse : le savoir-faire en cause (par exemple « Développer › produit de trois facteurs »), le type d'erreur et une courte note qui cite ce que l'élève a écrit. Ce diagnostic est visible par l'enseignant seul ; il est marqué « Proposé par l'IA » et l'enseignant peut le confirmer, le corriger ou le retirer.
5. Les statistiques de l'enseignant regroupent ces diagnostics par savoir-faire et par élève. Les phrases de synthèse (« En Développer, Zoé ne maîtrise pas … ») sont assemblées par l'app à partir d'un modèle fixe ; le prénom y est ajouté sur l'appareil de l'enseignant.

Le résultat est une aide pédagogique : aucune note scolaire, aucune décision ayant des effets juridiques ou significatifs pour l'élève n'est prise automatiquement ; l'enseignant reste seul juge de l'évaluation.

Ce qui est envoyé au modèle : l'énoncé de l'exercice, la réponse attendue, les étapes transcrites de l'élève et les savoir-faire de l'exercice ; l'image du tracé seulement si la lecture sur l'iPad n'est pas disponible. Le nom de l'élève, son niveau, sa classe et ses identifiants ne sont jamais envoyés. Le modèle sert aussi à classer les exercices de l'enseignant par savoir-faire (sans aucune donnée d'élève).

## 5. Prestataires et lieux de traitement

| Prestataire | Service | Lieu |
|---|---|---|
| Google (Firebase) | base de données Cloud Firestore (fiches, copies transcrites, diagnostics) | Zurich, Suisse (europe-west6), vérifié le 27 septembre 2026 |
| Google (Firebase) | stockage des images Cloud Storage | aujourd'hui États-Unis (us-west1) ; transfert vers Zurich prévu avant toute utilisation avec des élèves (voir notes pour le juriste) |
| Google (Firebase) | fonctions serveur (Cloud Functions) | Zurich, Suisse (europe-west6) |
| Google (Firebase Authentication) | comptes enseignants, comptes anonymes des élèves | États-Unis |
| Google Cloud (Vertex AI) | exécution du modèle Claude | Union européenne (région europe-west1, Belgique) ; en attente de l'ouverture du quota par Google. Pendant les tests internes, sans données d'élèves réels, l'API d'Anthropic aux États-Unis est utilisée. |
| MyScript (logiciel intégré à l'app) | lecture de l'écriture | sur l'iPad ; aucune donnée transmise |

Selon la documentation de Firebase, le service Firebase Authentication fonctionne uniquement depuis des centres de données situés aux États-Unis. Google déclare respecter le Swiss-U.S. Data Privacy Framework et l'EU-U.S. Data Privacy Framework. Depuis le 15 septembre 2024, la Suisse reconnaît un niveau de protection adéquat aux entreprises américaines certifiées dans ce cadre. Pour un élève, Firebase Authentication ne contient qu'un identifiant anonyme, sans nom ni adresse e-mail.

Google agit comme sous-traitant de MathClass selon ses conditions de traitement des données (Data Processing and Security Terms).

## 6. Durée de conservation

Les copies manuscrites, les transcriptions, les résultats et les diagnostics (qui sont enregistrés avec la copie) sont supprimés automatiquement douze mois après leur envoi.

Quand un enseignant supprime une classe, MathClass supprime immédiatement la classe, ses élèves, leurs copies, leurs images et leur progression.

Quand un enseignant supprime son compte depuis l'app, MathClass supprime immédiatement ses classes (avec tout ce qu'elles contiennent), ses exercices et son profil. Selon la documentation de Firebase, les données d'authentification disparaissent ensuite des systèmes actifs et des sauvegardes de Google dans un délai de 180 jours.

Selon Google, les requêtes envoyées au modèle Claude via Vertex AI ne sont pas conservées. À VÉRIFIER dans les conditions de Google Cloud applicables au compte.

## 7. Sécurité

Les échanges entre l'app et les serveurs sont chiffrés (HTTPS). L'accès aux données est contrôlé côté serveur : un enseignant n'accède qu'aux classes qu'il a créées ; un élève n'accède qu'à sa propre classe et à son propre travail, jamais aux fiches de ses camarades. Ces règles font l'objet de tests automatisés.

## 8. Vos droits

Toute personne concernée peut demander l'accès à ses données, leur rectification ou leur suppression. Pour un élève, la demande passe normalement par l'enseignant ou l'établissement, qui peut corriger ou supprimer les données directement dans l'app : modifier une note, corriger ou retirer un diagnostic, supprimer toutes les données d'un élève. Vous pouvez aussi écrire à l'adresse de contact indiquée au point 1.

En Suisse, l'autorité de surveillance est le Préposé fédéral à la protection des données et à la transparence (PFPDT). Pour une école publique, l'autorité cantonale de protection des données est compétente (à Genève, le Préposé cantonal à la protection des données et à la transparence). En France, il s'agit de la CNIL.

## 9. Modifications

Toute modification de cette politique est publiée sur cette page avec sa date. Les établissements sous contrat sont informés à l'avance de tout changement de prestataire.
