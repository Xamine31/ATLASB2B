# Netbeds Premium V9 — Refonte du portail B2B

Netbeds Premium est une application React/Vite pour agences, partenaires DMC et administrateurs, publiée avec GitHub Pages et utilisant Supabase (Auth, PostgreSQL, Storage, RPC/RLS). Cette version conserve le moteur de réservation, les écritures financières fictives, les contrats hôteliers et le simulateur RateHawk de la V8.

> **Démonstration seulement.** Aucune réservation réelle RateHawk, aucune vérification bancaire réelle, aucun virement et aucun encaissement de fonds. L'interface a l'apparence d'un portail professionnel, mais le fonctionnement n'est pas certifié pour la production.

## Ce qui change dans la V9

- **Nouvelle structure d'interface** : barre latérale sombre fixe à gauche, barre supérieure fixe, contenu fluide et responsive, palette bleu marine/or issue du modèle Excel, typographie Outfit / DM Sans.
- **Navigation par pages** : utilisation d'adresses `#/...` compatibles GitHub Pages. Les listes et les fiches ne sont plus mélangées. Boutons Retour et navigation conservée au rechargement pour les fiches ayant les données nécessaires.
- **Hôtels** : `#/hotels` liste, `#/hotels/new` création, `#/hotels/<id>/general` modification, `/rooms`, `/rates`, `/promos` et `/delete` pour supprimer uniquement un brouillon autorisé sans réservation.
- **Contrats** : liste, création `#/contracts/new`, fiche `#/contracts/<id>` et suppression d'un contrat brouillon par un admin sur écran distinct.
- **Agences** : liste de partenaires, fiche individuelle, validation/suspension, écran de conditions commerciales agence, création/modification/suppression d'exceptions tarifaires dans des pages distinctes.
- **Fournisseurs API** : liste, création, édition et page de confirmation avant suppression. Le registre API n'établit aucune connexion réelle par lui-même.
- **Réservations** : liste de dossiers et fiche distincte avec consultation, confirmation/refus par administrateur, rappel de l'effet sur le crédit.
- **Finances** : pages distinctes pour demander un rechargement, créer un ajustement, créer un règlement, contrôler les demandes de rechargement, approuver et marquer les règlements après vérification externe.
- **Mon compte pour tous les rôles** : nom affiché, entreprise, téléphone, présentation, photo (Supabase Storage), mot de passe (Supabase Auth) et informations de rôle en lecture seule.
- **Recherche agence** : le moteur V8 est conservé, chaque hôtel reste regroupé avec son prix « À partir de » hors promotions ; fiche détaillée et configurateur ; URL partageable de la fiche avec les paramètres de recherche.
- **Tarifs Excel** : `parseNatbeds` et `exportRates` conservés ; les fichiers `modele_tarifs_natbeds.xlsx` et `exemple_tarifs_fictifs.xlsx` sont identiques à la V8. Les 10 types de chambres et les 7 règles commerciales restent configurables.

Voir `AMELIORATIONS_V9.md` pour les détails et les limites fonctionnelles.

## Mise à jour depuis V8 (recommandée)

1. **Faire une sauvegarde du dépôt GitHub et de Supabase**. Tester la migration sur une copie de la base ; ne pas appliquer sur une base commerciale.
2. Dans Supabase → SQL Editor, exécuter **seulement** `supabase/migration_v9_compte_navigation.sql`, après avoir confirmé la présence des migrations V5, V6, V7, V8. Elle ajoute des champs au profil, un bucket `account-avatars`, des politiques et `delete_draft_hotel_v9`. **Ne pas relancer** `schema.sql` ni les anciennes migrations sur une base existante.
3. Décompresser le ZIP et mettre tous les fichiers **à la racine** du dépôt GitHub actuel `ATLASB2B`, pas dans un sous-dossier.
4. Dans GitHub → Settings → Pages, sélectionner **GitHub Actions** comme source. Variables du dépôt GitHub → Settings → Secrets and variables → Actions → Variables :
   - `VITE_SUPABASE_URL` : URL publique Supabase, commençant par `https://`.
   - `VITE_SUPABASE_ANON_KEY` : clé **publique** anon/publishable. Ne jamais envoyer une clé `service_role` / `sb_secret_...` dans le frontend.
5. GitHub Actions exécute `npm install`, les vérifications V7/V8/V9, `npm run build`, `npm run check:dist` puis publie `dist`. Le code Vite calcule automatiquement le préfixe `/ATLASB2B/` à partir du nom du dépôt GitHub.
6. Ouvrir `https://xamine31.github.io/ATLASB2B/` si le dépôt est resté `ATLASB2B`. La route `#/settings` ouvre les paramètres de compte.

**Important** : la modification du nom visible du site en Netbeds ne renomme pas le dépôt GitHub. Si le dépôt change de nom, adapter les URL de redirection dans Supabase Authentication.

## Test local

```
cp .env.example .env.local
# Renseigner les deux variables publiques dans .env.local
npm install
npm run dev
```

Pour vérifier la structure et le déploiement :

```
npm run check:v7
npm run check:v8
npm run check:v9
npm run build
npm run check:dist
```

`npm run check:dist` en mode GitHub Pages nécessite les mêmes variables `GITHUB_PAGES=true` et `GITHUB_REPOSITORY=utilisateur/ATLASB2B` que le workflow de déploiement.

## Scénarios de test conseillés

1. Admin/DMC : créer un hôtel, naviguer vers `#/hotels/<id>/general`, puis ouvrir chambres, promotions et tarifs ; utiliser le modèle Excel, importer, **enregistrer dans Supabase**, vérifier les tarifs relus, exporter.
2. Admin : approuver et publier un hôtel, gérer un contrat et configurer une marge agence (standard + exception hôtel).
3. Agence approuvée : rechercher un hôtel avec des dates présentes dans la grille, ouvrir une fiche, configurer le séjour et envoyer une demande avec crédit fictif disponible.
4. Admin : ouvrir une fiche de réservation, confirmer ou refuser, vérifier le montant bloqué puis débité ou libéré dans Centre financier.
5. Agence : ouvrir `#/finance/topup` et déclarer un virement fictif. Admin : ouvrir la fiche de rechargement et approuver **après vérification dans ce scénario de test**.
6. Admin : préparer un règlement puis ouvrir la fiche fournisseur pour l'approuver et le marquer payé après vérification de la référence bancaire fictive.
7. Chaque rôle : ouvrir `#/settings`, modifier nom, présentation, téléphone, société, photo et mot de passe.
8. Vérifier un écran étroit, la barre latérale mobile, puis le retour au catalogue après avoir consulté une fiche.

## Confidentialité et sécurité

- L'administration des rôles reste protégée côté serveur par `admin_set_user`; les utilisateurs ne peuvent modifier que les colonnes de présentation de `profiles`.
- L'upload de photo s'effectue dans un dossier Supabase Storage au nom de l'UUID de l'utilisateur. Les avatars sont dans un bucket public : **ne pas y déposer de documents confidentiels**.
- Les suppressions d'hôtels sont limitées aux brouillons sans réservation, via une fonction RPC sous contrôle d'accès.
- Les débits et blocages existants restent calculés côté Supabase (V7/V8). Les écrans V9 ne prennent aucune décision financière seulement dans le navigateur.
- Aucune connexion RateHawk réelle : les trois hôtels d'essai et les scénarios fournisseur restent fictifs.

## Limites à respecter

La **compilation npm complète n'a pas été exécutée lors de la préparation de l'archive**, car le registre npm n'était pas accessible dans l'environnement de génération. Les fichiers JavaScript/JSX ont été analysés par le parseur TypeScript, les CSS par PostCSS et les vérifications structurelles V7/V8/V9 passent. La migration SQL n'a pas été exécutée sur votre instance Supabase : sauvegarder, tester, puis vérifier GitHub Actions et les opérations métier avant toute utilisation.

L'historique métier V8 est conservé mais des domaines restent partiels : disponibilité réelle/allotements, calcul automatique des promotions, conditions d'annulation réelles, TVA/multi-devises, contrat filtrant strictement les ventes, connecteur RateHawk authentifié, paiement bancaire, conformité réglementaire et journaux d'audit financiers exhaustifs.
