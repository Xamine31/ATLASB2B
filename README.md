# AtlasB2B Premium — V6 catalogue et recherche

**Prototype de test uniquement.** GitHub Pages + Supabase. Aucune connexion effective aux fournisseurs hôteliers, aucun paiement réel, aucun debit automatique. La V5 finances (validation manuelle par admin) reste incluse.

## Changements V6

- Interface modernisée : **Manrope**, vert forêt, sauge, champagne, terracotta et ivoire.
- **Hôtels** : liste → clic sur un hôtel → 4 onglets (établissement, chambres, tarifs, promotions). La création ouvre une fiche complète.
- **10 catégories NATBEDS**, initialisées à la création de chaque hôtel : SGL, DBL, TRIPL, QDL, SUITE, JUNIOR SUITE, SGL SV, DBL SV, TRPL SV, QDL SV. Libellé, capacité, description, photo et visibilité éditables. Nouvelles chambres possibles.
- **7 réductions du modèle NATBEDS** : 0–2 ans, 2–6 ans, 6–11 ans, 3e adulte, réservation anticipée, voyage de noces, senior. Elles sont configurables et **non publiques par défaut**. Leur activation ne modifie pas automatiquement le prix des réservations : affichage informatif seulement.
- **Import Excel persistant** : bouton « Enregistrer dans Supabase » → RPC `import_hotel_excel_v6` → transaction SQL → relecture depuis Postgres. Les réductions par saison sont enregistrées dans `hotel_promotion_periods` ; les tarifs nets dans `rates`.
- **Recherche** : les offres nécessitent compte agence approuvé + hôtel publié + chambre rendue publique + tarif couvrant chaque nuit. Filtrage par nom d'hôtel / ville / pays. Prix majorés de l'agence, sans exposer les prix nets.

## Installer sur ton projet existant (V5)

**ÉTAPE 1 : SAUVEGARDE** du dépôt et de la base Supabase de test (ne pas tester sur une base de production).

**ÉTAPE 2 : SUPABASE (OBLIGATOIRE AVANT DE METTRE EN LIGNE LA V6)**

Dans Supabase → SQL Editor, exécuter **une fois** `supabase/migration_v6_catalogue.sql`. Cette migration conserve les réservations et tables financières de V5. Vérifier la présence des colonnes `room_types.is_public`, `room_types.display_name` et des tables `hotel_promotions`, `hotel_promotion_periods`.

- Si tu utilises une base **vierge**, exécuter dans l'ordre : `supabase/schema.sql`, `supabase/migration_v5_finances.sql`, puis `supabase/migration_v6_catalogue.sql`.
- Si tu es déjà sur V5, exécuter **uniquement** la migration V6.
- Ne jamais rejouer `schema.sql` sur une base contenant déjà les tables.
- La migration ajoute un filtre aux politiques RLS des chambres. Les chambres préexistantes sont publiques par défaut ; les chambres initialisées sur une nouvelle fiche sont masquées par défaut jusqu'à validation manuelle.

**ÉTAPE 3 : GITHUB**

Décompresser le ZIP **directement à la racine** du dépôt `ATLASB2B` et remplacer les fichiers existants. Dans Settings → Pages, choisir `GitHub Actions` et conserver les variables de dépôt `VITE_SUPABASE_URL` et `VITE_SUPABASE_ANON_KEY` (clé publique seulement). Le workflow construit `dist` et le publie, jamais `src` directement.

**ÉTAPE 4 : TEST PARCOURS**

1. Connecté comme Admin ou DMC, ouvrir **Hôtels** → **Nouvel hôtel**. Compléter identité, photo, description.
2. **Chambres** : vérifier les 10 catégories ; pour les chambres proposées à la vente, cocher **Publique** ; ajouter description et photo.
3. **Tarifs** : importer `exemple_tarifs_fictifs.xlsx`, choisir l'année de départ (novembre) correspondant au séjour ; vérifier l'aperçu, puis **Enregistrer dans Supabase**. Attendre la relecture et vérifier que le nombre de lignes enregistrées est supérieur à zéro.
4. **Promotions** : vérifier 7 règles, pourcentages et périodes ; modifier descriptions et activer **Publique** uniquement pour les règles à communiquer. Les remises ne sont pas déduites des prix automatiquement.
5. Admin : publier l'hôtel et approuver un compte agence dans **Agences & DMC**.
6. Agence : **Rechercher un hôtel**, ville ou nom, dates comprises dans la grille. Les offres doivent apparaître, ainsi que les descriptions et promotions publiques. Prix = somme des prix nets/nuit × (1+majoration agence). Toute réservation est une simple demande.
7. Si résultats vides, contrôler dans cet ordre : (1) agence validée ; (2) hôtel publié ; (3) chambre publique ; (4) tarifs réels dans table `rates` ; (5) période du séjour couverte ; (6) migration V6 exécutée ; (7) F12 → Console et Réseau.
8. Finances : les validations manuelles et le fonctionnement test de V5 demeurent inchangés.

## Limites à connaître

- **Marge fixe par agence**, prix nets non montrés aux agences. Pas encore de disponibilité par chambre / stop sales / allotements : le moteur correspond à une **recherche tarifaire**, pas à une confirmation de disponibilité réelle.
- Promos importées et visibles si publiées, mais **jamais appliquées automatiquement** au prix. Pourcentage de réduction théorique, règles d'éligibilité et cumul non finalisés.
- Import remplace les tarifs de l'hôtel qui se chevauchent sur **l'ensemble de la saison importée**. Une erreur SQL annule toute la transaction ; néanmoins sauvegarder les données avant import.
- Photos stockées dans le bucket public `hotel-photos`, visibles à toute personne connaissant leur URL. Ne pas y placer des documents confidentiels.
- Deux versions des tables financière/hôtel peuvent demander une adaptation si tu as personnalisé ton schéma Supabase. La migration n'a pas été exécutée contre ton vrai projet Supabase.
- L'archive contient le code source. **La compilation complète et le test de connexion réelle Supabase ne sont pas vérifiés ici**, faute d'accès npm/Supabase.

## Développement local

```bash
npm install
cp .env.example .env.local
# compléter VITE_SUPABASE_URL et VITE_SUPABASE_ANON_KEY dans .env.local
npm run dev
```

Test du déploiement :

```bash
GITHUB_PAGES=true GITHUB_REPOSITORY=Xamine31/ATLASB2B npm run build
GITHUB_PAGES=true GITHUB_REPOSITORY=Xamine31/ATLASB2B npm run check:dist
```

## Sécurité

Jamais de clé `service_role`, de jetons fournisseurs, de secrets bancaires ou d'ordres SEPA dans le code front-end public. Les validations financières restent des écritures simulées, initiées et contrôlées par l'administrateur. Une revue juridique et un audit technique sont indispensables avant usage commercial.
