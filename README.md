# NETBEDS · Plateforme hôtelière B2B — V8

Application React/Vite publiée par GitHub Pages et adossée à Supabase Auth, PostgreSQL, RLS, Storage et fonctions RPC. **Environnement de démonstration : réservations, fonds et connecteur RateHawk fictifs.**

## 1. Installer ou mettre à jour

**Sauvegarder le dépôt GitHub et exporter une copie de la base Supabase de test avant toute migration.**

### Base existante V7

Dans Supabase > SQL Editor, exécuter **uniquement** `supabase/migration_v8_netbeds.sql` **après** l'application réussie des migrations précédentes V5, V6, V7. Ne pas relancer `schema.sql` ni V5–V7 si déjà exécutés. La migration V8 n'efface pas les agences, les hôtels ou les réservations existants. Elle crée des tables et des fonctions additionnelles, remplace `hotel_options_v7`, `submit_booking_v7` et `admin_booking_status` pour intégrer les exceptions de marge et les réservations simulées. Faire l'opération d'abord sur une base de test copiée.

### Base vierge

Exécuter dans l'ordre : `supabase/schema.sql`, `supabase/migration_depuis_v1.sql` uniquement si requis par les instructions de cette migration, `supabase/migration_v5_finances.sql`, `supabase/migration_v6_catalogue.sql`, `supabase/migration_v7_reservation_finance.sql`, puis `supabase/migration_v8_netbeds.sql`. **Lire le préambule de chaque fichier SQL** avant de l'exécuter ; les bases préexistantes peuvent nécessiter un chemin de migration différent. Une installation sur base neuve n'a pas été testée dans cet environnement.

### GitHub Pages

Décompresser les fichiers **directement à la racine du dépôt `ATLASB2B`**, si vous conservez ce dépôt : ne pas créer de sous-dossier Netbeds. Dans Settings > Pages, choisir **GitHub Actions** comme source.

Dans Settings > Secrets and variables > Actions > **Variables**, garder :

- `VITE_SUPABASE_URL` = URL publique du projet Supabase.
- `VITE_SUPABASE_ANON_KEY` = clé publique anon/publishable Supabase, **jamais une clé `service_role`**.

Le workflow `.github/workflows/deploy.yml` fait `npm install`, `npm run check:v7 && npm run check:v8`, `npm run build` puis `npm run check:dist` avant publication. **Le `base` Vite s'ajuste au nom réel du dépôt** avec `GITHUB_REPOSITORY`, donc GitHub Pages continuera de fonctionner à `https://xamine31.github.io/ATLASB2B/` tant que le dépôt reste `ATLASB2B`.

En local : copier `.env.example` vers `.env.local`, remplir les deux variables publiques puis `npm install && npm run dev`.

### Auth Supabase

Dans Supabase > Authentication > URL Configuration, conserver l'URL du site réellement publié. Avec le dépôt existant : `https://xamine31.github.io/ATLASB2B/`. Régler les redirections de connexion selon votre configuration Supabase Auth.

## 2. Tester les fonctions

1. **Admin :** se connecter et vérifier les comptes approuvés ; renseigner **Conditions agences** (marge, exceptions par hôtel, seuil d'alerte).
2. **DMC :** créer un hôtel dans **Mes hôtels**, compléter photos, description, chambres et publicité de la chambre.
3. **DMC :** ouvrir **Tarifs**, télécharger le modèle de grille, sélectionner l'année de départ de saison, importer `exemple_tarifs_fictifs.xlsx` puis cliquer sur **Enregistrer dans Supabase**. Vérifier les lignes relues. Tester **Exporter la grille Excel** : première feuille dans le format du modèle, deuxième feuille détaillée.
4. **Admin :** publier l'hôtel puis créer un **Contrat hôtelier** en brouillon, l'approuver et le publier.
5. **Agence :** disposer d'un crédit fictif validé, puis rechercher un séjour couvert par les saisons importées. Les résultats présentent une carte par hôtel et le prix « À partir de » hors promotions. Ouvrir la fiche, configurer le séjour, renseigner coordonnées et accepter les conditions. Envoyer la demande.
6. **Admin :** vérifier la réservation en attente, puis la confirmer ou la refuser. Contrôler crédit bloqué, débit et dette partenaire. Une demande de rechargement ne crédite le portefeuille qu'après validation Admin.
7. **Admin :** aller dans **RateHawk simulé**, initialiser les trois établissements fictifs et vérifier leur visibilité dans les résultats agence. Se connecter comme agence et choisir les scénarios **confirmé / refusé / en attente** sur des réservations distinctes.

## 3. Limites de fonctionnement

**Ne pas traiter de vraie réservation ni de vrai virement avec cette V8.** Les hôtels de démonstration sont fictifs. Les promotions visibles ne sont pas déduites des prix. Les contrats enregistrés ne filtrent pas encore automatiquement la commercialisation, les allotements et arrêts de vente ne sont pas encore gérés, la TVA et la multi-devise ne sont pas finalisées. L'activation réelle de RateHawk nécessitera contrat, identifiants Sandbox, Edge Functions sécurisées, certification et tests de tarification/reconfirmation. En cas de réponse incertaine, ne jamais renouveler automatiquement une réservation fournisseur.

L'application conserve l'historique financier V5–V7. Un remboursement bancaire, une dette réelle ou la détention de fonds prépayés sont **hors périmètre** et nécessiteront une validation métier, juridique et technique.

## 4. Fichiers essentiels

- `src/HotelWorkspace.jsx` : fiche hôtel/chambres/photos/promotions/tarifs et import/export Excel.
- `src/excel.js` : lecture du modèle NATBEDS, saison, chambres/pensions, export dans le même modèle.
- `src/SearchJourney.jsx` : recherche une carte par hôtel, options, voyageurs, réservation.
- `src/FinancePanel.jsx` : portefeuille, rechargements, dettes et audit.
- `src/ContractsPanel.jsx` : fiches contrat, approbation et versionnement simple.
- `src/AgencyConditions.jsx` : marges et exceptions par établissement.
- `src/RatehawkDemo.jsx` : fournisseur fictif configurable.
- `supabase/migration_v8_netbeds.sql` : tables RLS et fonctions SQL V8.
- `AMELIORATIONS_V8.md` : modifications et limitations détaillées.

## 5. Contrôles effectués à la génération

Les sources JSX/JS passent un contrôle de parsing syntaxique ; `npm run check:v6`, `npm run check:v7`, `npm run check:v8` contrôlent la structure. Le build npm et l'exécution réelle sur Supabase **ne sont pas validés ici** si l'installation des dépendances réseau n'est pas disponible. GitHub Actions jouera le rôle de premier build de référence. La migration doit être exécutée sur une **base de test**.
