# Contrat de sous-traitance de données personnelles (modèle)

Modèle de travail du 25 septembre 2026, à adapter et faire valider par un juriste. Il vise la loi fédérale sur la protection des données (LPD) et, pour une école publique genevoise, la loi sur l'information du public, l'accès aux documents et la protection des données personnelles (LIPAD). Pour un établissement en France, les clauses de l'article 28 du RGPD doivent être vérifiées une à une.

## Parties

Le responsable du traitement : l'établissement scolaire À COMPLÉTER (nom, adresse, représentant), ci-après « l'Établissement ».

Le sous-traitant : Xavier Morvan, éditeur de MathClass, À COMPLÉTER (adresse), ci-après « le Prestataire ».

## Article 1. Objet

Le Prestataire met à disposition de l'Établissement l'application MathClass : exercices de mathématiques rédigés à la main sur iPad, transcription et correction automatiques, suivi par l'enseignant. Pour fournir ce service, il traite des données personnelles d'élèves et d'enseignants pour le compte de l'Établissement. Le présent contrat fixe les conditions de ce traitement.

## Article 2. Description du traitement

La nature des données, les personnes concernées, les finalités et les durées de conservation figurent à l'annexe 1.

## Article 3. Instructions

Le Prestataire ne traite les données que sur instruction documentée de l'Établissement. L'usage de MathClass conformément à sa documentation vaut instruction. Le Prestataire informe l'Établissement s'il estime qu'une instruction est contraire au droit applicable.

Le Prestataire ne se sert pas des données pour ses propres besoins, ne les vend pas et ne les utilise pas pour entraîner un modèle d'intelligence artificielle.

## Article 4. Confidentialité

Toute personne autorisée par le Prestataire à accéder aux données est tenue au secret. À la date du contrat, seul Xavier Morvan a accès à l'administration du service.

## Article 5. Sécurité

Le Prestataire applique les mesures techniques et organisationnelles décrites à l'annexe 2 et les maintient à un niveau adapté au risque, en tenant compte du fait que les personnes concernées sont en majorité mineures.

## Article 6. Sous-traitants ultérieurs

L'Établissement autorise les sous-traitants ultérieurs listés à l'annexe 3. Le Prestataire n'en ajoute ou n'en remplace aucun sans l'accord écrit préalable de l'Établissement, sollicité au moins 30 jours à l'avance. Le Prestataire impose à chaque sous-traitant ultérieur des obligations de protection au moins équivalentes à celles du présent contrat.

## Article 7. Transferts à l'étranger

Les transferts hors de Suisse sont limités à ceux décrits à l'annexe 3. Ils reposent sur une décision d'adéquation du Conseil fédéral (Union européenne ; entreprises américaines certifiées Swiss-U.S. Data Privacy Framework).

## Article 8. Droits des personnes concernées

Le Prestataire aide l'Établissement à répondre aux demandes d'accès, de rectification et de suppression. L'enseignant peut consulter, corriger et supprimer les données de sa classe directement dans l'app. Si une personne concernée s'adresse directement au Prestataire, celui-ci transmet sa demande à l'Établissement sans délai.

## Article 9. Violation de la sécurité des données

Le Prestataire informe l'Établissement dans les meilleurs délais, et au plus tard 48 heures après en avoir eu connaissance, de toute violation de la sécurité des données. Il communique la nature de la violation, les données et personnes concernées, les conséquences probables et les mesures prises ou proposées, afin que l'Établissement puisse remplir ses propres obligations d'annonce.

## Article 10. Audit

Le Prestataire met à disposition de l'Établissement les informations nécessaires pour démontrer le respect du présent contrat et accepte les vérifications menées par l'Établissement ou un auditeur mandaté par lui, moyennant un préavis raisonnable.

## Article 11. Fin du contrat

À la fin du contrat, le Prestataire supprime toutes les données de l'Établissement dans un délai de 30 jours, sauf demande écrite de restitution préalable. Les suppressions dans les sauvegardes des sous-traitants ultérieurs suivent leurs propres délais, indiqués à l'annexe 3. Le Prestataire confirme la suppression par écrit.

## Article 12. Durée, droit applicable, for

Le contrat court aussi longtemps que l'Établissement utilise MathClass. Il est soumis au droit suisse. For : À COMPLÉTER.

Lieu, date, signatures : À COMPLÉTER.

---

## Annexe 1. Description du traitement

Personnes concernées : élèves des classes de l'Établissement inscrits dans MathClass par leur enseignant ; enseignants de l'Établissement titulaires d'un compte.

Données des élèves : prénom, nom, niveau (1 à 5), groupe, copies manuscrites (images), étapes transcrites, résultats par étape, catégories d'erreurs, temps passé, progression, identifiant d'iPad aléatoire, identifiant de connexion anonyme.

Données des enseignants : nom, prénom, adresse e-mail, contenu pédagogique créé.

Données sensibles au sens de la LPD : aucune n'est demandée. L'Établissement veille à ce que les enseignants n'en saisissent pas (par exemple dans le nom d'un groupe).

Finalités : exercices en classe, transcription et correction des copies, retour à l'élève, suivi et statistiques pour l'enseignant.

Conservation : copies, transcriptions et résultats supprimés automatiquement douze mois après leur envoi ; suppression immédiate de toutes les données d'une classe quand l'enseignant la supprime ; suppression immédiate de toutes les données d'un enseignant quand il supprime son compte.

## Annexe 2. Mesures techniques et organisationnelles

Contrôle d'accès côté serveur (règles de sécurité Firestore et Cloud Storage) : un enseignant n'accède qu'aux classes qu'il a créées ; un élève n'accède qu'à sa classe et à son propre travail. Ces règles sont couvertes par des tests automatisés, que le Prestataire exécute avant chaque mise en production.

Les élèves se connectent sans adresse e-mail ni mot de passe, par un compte anonyme lié à leur fiche par le serveur après vérification du code de la classe.

Chiffrement des échanges (HTTPS). Les fonctions serveur vérifient l'identité de l'appelant avant tout traitement.

Minimisation : le modèle d'intelligence artificielle ne reçoit ni nom ni identifiant d'élève ; la liste de connexion n'affiche que le prénom et l'initiale du nom.

Clé d'accès au service d'intelligence artificielle stockée dans le gestionnaire de secrets de Google Cloud, jamais dans l'app.

Accès administrateur au projet Google Cloud limité au Prestataire, avec authentification à deux facteurs (À VÉRIFIER : l'activer sur le compte Google du Prestataire).

## Annexe 3. Sous-traitants ultérieurs

Google (services Firebase et Google Cloud ; entité contractante À VÉRIFIER, voir ci-dessous) :
Cloud Firestore et Cloud Storage, emplacement À VÉRIFIER ; Cloud Functions à Zurich (europe-west6) ; Firebase Authentication aux États-Unis (identifiants anonymes des élèves, comptes des enseignants), Google étant certifié Swiss-U.S. Data Privacy Framework ; Vertex AI (modèle Claude d'Anthropic) dans l'Union européenne (europe-west1). Délai d'effacement des données d'authentification dans les sauvegardes : 180 jours selon la documentation de Firebase.

L'entité Google contractante exacte dépend du compte Google Cloud du Prestataire. À VÉRIFIER dans la console Google Cloud.
