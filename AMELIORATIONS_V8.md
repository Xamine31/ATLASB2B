# Netbeds — évolutions intégrées à la V8

## Identité et ergonomie

- Nouvelle marque **Netbeds**, titres et identité du portail modifiés.
- Thème issu des couleurs réellement présentes dans le fichier Excel tarifaire d'origine : marine `#082B55`, or `#E6AD32`, blanc `#FFFFFF`, bleu pâle `#EAF0F6`, gris bleuté `#F5F8FB`.
- Typographie **Plus Jakarta Sans**, cartes, boutons, barres de navigation et espaces harmonisés.
- Navigation propre aux profils Admin / DMC / Agence.

## Catalogue et contrats

- Gestion des hôtels en liste puis fiche avec onglets Établissement, Chambres, Tarifs et Promotions.
- Descriptions et photos de l'hôtel et des chambres, visibilité par catégorie.
- Dix catégories de chambres et sept règles de promotions initialisables.
- Nouvelle page **Contrats hôteliers** : référence, fournisseur, type de source, devise, validité, modalités de paiement, annulation, versions, statuts.
- Propositions de contrats en brouillon par DMC, validation et publication des contrats par Admin.
- Les contrats sont un registre commercial dans cette V8 : leur validité n'est **pas encore appliquée comme filtre automatique** au moteur de recherche.

## Excel

- Import du modèle initial **NATBEDS** avec les six périodes, dix chambres, cinq pensions, réductions et promotions, selon le format existant de V6.
- Enregistrement atomique SQL des tarifs et promotions et relecture des données depuis Supabase après import.
- **Export au format visuel du modèle Excel original**, complété par une feuille « Historique des tarifs » pour préserver les lignes qui ne correspondent pas exactement aux périodes du modèle.
- Liens pour télécharger le modèle et l'exemple prérempli depuis le portail.
- Promotions paramétrables : visibilité, description, pourcentage et périodes. Les promotions ne sont **pas** automatiquement appliquées au prix des réservations.

## Agences et commercialisation

- Recherche regroupée par hôtel, prix **« À partir de »** correspondant au tarif de base sans promotions, selon les dates et la marge applicable.
- Fiche détaillée avec choix du type de chambre, pension, nombre de chambres, adultes/enfants et récapitulatif tarifaire.
- Nouvelle page Admin **Conditions agences** : marge générale, seuil d'alerte de crédit, exceptions de marge par hôtel et remise à zéro de l'exception.
- Calcul du tarif d'agence et de son blocage côté Supabase, en incluant l'exception de marge par hôtel.
- Fiche voyageur : nom principal, email, téléphone, résidence/nationalité, demandes spéciales, acceptation explicite avant soumission. Coordonnées et blocage de crédit sont enregistrés dans une **seule transaction SQL**, empêchant un blocage orphelin si la validation des voyageurs échoue.
- La capacité chambre est contrôlée, mais **un moteur complet d'allotements/stock réel par nuit manque encore**.

## Finance

- Conservation du portefeuille prépayé fictif V7, demandes de rechargement contrôlées par Admin, blocage à la réservation, libération sur refus, débit sur confirmation, fournisseur à régler, marge brute, écritures d'audit.
- Prévention d'un double débit par statut et verrouillage transactionnel de la réservation.
- Règlements fournisseurs en brouillon et validation manuelle, export CSV de contrôle, sans virement bancaire réel.
- Le seuil d'alerte de crédit est configurable ; **la notification automatique de seuil n'est pas encore implémentée**.
- Devise comptable unique EUR à ce stade ; la devise des contrats est informative et n'entraîne pas de conversion automatique.

## RateHawk simulé

- Nouvelle page Admin **RateHawk simulé** : activer/désactiver le simulateur, initialiser trois hôtels fictifs.
- Ces hôtels fictifs apparaissent dans la recherche agence avec une étiquette explicite.
- Trois réponses fournisseurs simulées : confirmé, rejeté, en attente.
- Confirmé : capture du crédit bloqué, écriture de débit, création d'une dette fournisseur API.
- Rejeté : libération du blocage. En attente : blocage conservé jusqu'à intervention Admin.
- Requêtes idempotentes : un même résultat simulé ne peut pas être rejoué une deuxième fois.
- **Aucun appel API RateHawk**, aucun accès à leur véritable catalogue, aucune confirmation réelle, aucun voucher fournisseur.

## Sécurité et publication

- Utilisation conservée de Supabase Auth, PostgreSQL RLS et RPC sécurisées ; aucune clé de service dans le client.
- GitHub Actions publie `dist` compilé et vérifie les variables Vite ainsi que les chemins GitHub Pages.
- Migration V8 **additive** après les migrations précédentes, à exécuter sur copie de test après sauvegarde.
- Analyse syntaxique de tous les fichiers JS/JSX et contrôles structurels automatisés.

## Restant à développer et à valider avant une utilisation commerciale

API RateHawk réelle et certification, intégration d'autres fournisseurs, contrôle d'allotement par nuit, annulations et pénalités complètes, recalcul des promotions et âges exacts des enfants, paiements réels, remboursements bancaires, gestion comptable et TVA, multi-devises, e-mails/notifications, conformité RGPD, rapprochement bancaire réel, audits de sécurité, tests end-to-end avec Supabase et tests de concurrence au-delà des garde-fous actuels.
