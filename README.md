# AtlasB2B Premium V7 — parcours hôtelier et portefeuille réservé

Application React/Vite sur **GitHub Pages** et données dans **Supabase** (Auth, PostgreSQL, Storage). Trois espaces : **agence, DMC, administration**. Environnement de **démonstration** : les opérations financières sont fictives. Aucune réservation fournisseur n'est effectuée et aucun virement bancaire n'est lancé.

## Installation depuis la V6 (IMPORTANT)

1. Sauvegarder le dépôt GitHub **et** la base Supabase (schéma, données, politiques). Tester de préférence sur un projet Supabase de préproduction.
2. Les migrations V5 et V6 doivent **déjà** être appliquées. Dans Supabase → **SQL Editor**, exécuter **une seule fois** le fichier `supabase/migration_v7_reservation_finance.sql`. Ne pas réexécuter `schema.sql`, V5 ou V6 sur une base existante. La migration V7 ne supprime pas les réservations ou prix antérieurs.
3. Mettre tous les fichiers du ZIP à la racine du dépôt `ATLASB2B`, y compris `.github/workflows/deploy.yml`, et pousser sur `main`.
4. GitHub → Settings → Pages → Source **GitHub Actions**. Les variables du dépôt `VITE_SUPABASE_URL` et `VITE_SUPABASE_ANON_KEY` doivent contenir l'URL du projet et sa clé **publique**. Ne jamais utiliser une clé `service_role` côté navigateur.
5. GitHub → **Actions** → **Deploy AtlasB2B to GitHub Pages**. Ouvrir `https://xamine31.github.io/ATLASB2B/` (adapter le compte GitHub au besoin).
6. Configurer dans Supabase Auth les URL de redirection du site si nécessaire.

**Ordre de déploiement recommandé : migration SQL d'abord, GitHub ensuite.** Une nouvelle interface V7 déployée sans migration affichera notamment « Could not find the function public.hotel_search_v7 ».

## Fonctionnalités V7

### Recherche et fiche hôtel
- Une carte **par hôtel**, avec prix **« À partir de »** : meilleur prix de base pour les dates, le nombre de chambres et la composition renseignés, sans promotion.
- Détail par établissement : images, description, options chambre/pension, capacités, prix recalculés, quantité de chambres et récapitulatif.
- Le tarif de base s'appuie exclusivement sur les périodes de l'Excel, le tarif net et la majoration de l'agence. Les promotions visibles sont **indicatives et non déduites** : les règles d'application/cumul n'ont pas encore été développées.
- Aucune disponibilité d'inventaire temps réel : les résultats dépendent des tarifs publiés mais **ne garantissent pas de chambre libre**. Toute réservation reste une **demande**.

### Réservations et finances
- Une agence approuvée avec crédit suffisant soumet une demande → le prix est **recalculé par SQL** → un **blocage** est créé immédiatement dans la même transaction.
- Crédit disponible = somme des écritures de portefeuille − somme des blocages actifs.
- Une validation administrateur crée **une fois** le débit `booking_debit` et **un** règlement fournisseur en brouillon, enregistre l'audit et consomme le blocage dans la même transaction PostgreSQL.
- Un refus administrateur libère le blocage sans débit.
- L'agence peut demander un rechargement ; l'administrateur doit vérifier et approuver le crédit. Les règlements fournisseurs suivent la validation puis le rapprochement **manuels**. Aucune connexion SEPA/banque.
- Les anciens dossiers V6 sans blocage V7 sont conservés mais **ne peuvent pas être validés** avec la nouvelle fonction. Ils doivent être examinés séparément et ne sont pas migrés rétroactivement.
- L'écriture manuelle `booking_debit` est interdite en V7 : le débit est réalisé uniquement à la confirmation. Les ajustements et remboursements restent limités à l'admin.
- Les fonctions de blocage verrouillent la ligne agence pour éviter des demandes concurrentes débouchant sur un crédit négatif. L'index unique sur les débits et les contrôles de statut empêchent une double confirmation.
- La dette fournisseur est basée sur le **net fournisseur** enregistré dans la réservation. Il s'agit d'une écriture de test ; les taxes, commissions réglementaires et les annulations financières complexes ne sont pas implémentées.

## Scénario de test intégral

1. Se connecter en **admin**, vérifier qu'une agence et un DMC sont approuvés et qu'un hôtel est **publié**.
2. Pour l'hôtel : au moins une chambre **publique** et des tarifs couvrant toutes les nuits. Importer `exemple_tarifs_fictifs.xlsx` si nécessaire via la fiche hôtel.
3. En admin → **Centre financier** → une demande de rechargement fictif de l'agence (ou une écriture d'ajustement documentée), puis valider. **Ne pas prétendre qu'un virement réel est arrivé**.
4. En agence → **Mon crédit**, vérifier par exemple crédit comptabilisé 5 000 €, bloqué 0 €, disponible 5 000 €.
5. En agence → **Rechercher un hôtel**, entrer destination/dates/chambres/voyageurs, vérifier **une seule carte par hôtel** et le montant « À partir de ».
6. Ouvrir l'hôtel : changer la chambre, la pension et le nombre de chambres. Vérifier le prix. Renseigner le voyageur et soumettre.
7. Retourner dans **Mon crédit** : crédit comptabilisé inchangé, **montant bloqué** égal à la demande, disponible diminué.
8. En admin → **Demandes** → **Valider**. En centre financier : blocage 0, débit du montant de l'agence, nouveau règlement fournisseur **brouillon** du montant net, audit. Marquer ensuite le règlement **approuvé**, puis **payé** avec référence fictive ; aucun virement n'est réellement transmis.
9. Refaire avec une deuxième réservation, puis choisir **Refuser**. Le crédit bloqué doit être libéré sans débit.
10. Essayer une réservation dont le prix dépasse le disponible : refus SQL « Crédit insuffisant ». Tester deux clics / soumissions simultanées ; aucune agence ne doit pouvoir dépenser deux fois le même crédit.

## Limites avant toute production commerciale

- Aucun inventaire/allotement garanti ni confirmation auprès d'un hôtel ou d'une API.
- Tarifs enfants, suppléments, conditions d'annulation et promotions non calculés automatiquement.
- Pas de véritable encaissement, virement, rapprochement bancaire automatique, SEPA ni comptabilité légale.
- L'application ne doit **pas** être utilisée pour encaisser des fonds ou confirmer de vraies réservations. Avant toute exploitation avec argent réel : audit sécurité, tests transactionnels sur Supabase, politiques RLS, revue juridique et réglementaire (agence de voyages, fonds prépayés et réglementation des services de paiement).
- V7 exige une migration PostgreSQL testée sur **ta** base : la compilation JavaScript ne valide pas les procédures SQL en contexte réel.

## Développement

```bash
npm install
npm run check:v7
npm run build
npm run check:dist
npm run dev
```

Dans Codespaces, utiliser `npm`, pas `npm.cmd`. En local, copier `.env.example` vers `.env.local` et compléter les **clés publiques** Supabase. Le workflow GitHub Pages compile `dist` et vérifie les chemins `/ATLASB2B/assets/`. Les commentaires de code sont destinés aux mainteneurs ; l'interface utilisateur n'affiche pas de consignes techniques internes.
