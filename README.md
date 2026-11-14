# AtlasB2B Premium — reconstruction GitHub Pages + Supabase

**Version de TEST uniquement** : aucun paiement, aucun crédit prépayé, aucune réservation réelle, aucun reversement fournisseur et aucune API hôtelière opérationnelle.

## 1. Ce qui fonctionne dans la démo (après configuration Supabase)
- Compte Supabase Auth, trois espaces : **Admin**, **DMC** et **Agence cliente**.
- Admin : valide les agences et les DMC, gère le registre des API (sans clés), publie les hôtels, règle la majoration commerciale de chaque agence, accepte/refuse les **demandes fictives**.
- DMC : crée ses hôtels en brouillon, ajoute descriptifs, photo d'hôtel, catégories de chambres et photo par type, importe les tarifs Excel de type NATBEDS.
- Agence approuvée : recherche les hôtels publiés et les tarifs de vente calculés par Supabase ; dépose des demandes manuelles, sans blocage de stock ni argent.
- Export Excel des tarifs enregistrés. Import Excel en transaction unique, pour éviter les saisons partiellement mises à jour si une erreur survient.

## 2. Installation dans GitHub Codespaces (Linux)
1. Dézipper et transférer **le contenu** du dossier à la racine du dépôt `ATLASB2B` (et non le dossier parent).
2. Vérifier que `package.json`, `index.html`, `vite.config.js`, `src/`, `supabase/`, `.github/workflows/deploy.yml` se trouvent à la racine. **Supprimer les anciens workflows de Pages (`pages.yml` ou autres fichiers de déploiement) pour ne garder QUE `.github/workflows/deploy.yml`.**
3. Exécuter `npm install` puis `npm run dev` dans Codespaces. **Ne pas utiliser `npm.cmd` dans Codespaces** : `npm.cmd` est réservé à Windows PowerShell.
4. Créer `.env.local` à partir de `.env.example` et renseigner la **Project URL** et la clé **publishable/anon** de Supabase. Ne jamais publier `.env.local`.
5. Pour compiler localement : `npm run build` puis `npm run check:dist`.

## 3. Installation Supabase
1. Créer un projet **de test** Supabase, activer le fournisseur Email dans Authentication.
2. **Nouvelle base vide :** exécuter **une seule fois** `supabase/schema.sql` depuis SQL Editor.
3. **Projet Supabase ayant déjà le schéma AtlasB2B précédent :** NE PAS réexécuter `schema.sql`. Faire une sauvegarde puis exécuter `supabase/migration_depuis_v1.sql` à la place. Ne pas supprimer tes tables existantes.
4. Dans Supabase Auth > URL Configuration, autoriser l’URL exacte de GitHub Pages : `https://TON_COMPTE.github.io/ATLASB2B/` ; ajouter la même URL aux redirections autorisées.
5. Créer ton propre utilisateur via le site ; après confirmation du courriel, promouvoir son compte dans Supabase SQL Editor avec :

```sql
update public.profiles
set role='admin', agency_id=null, dmc_id=null
where email='TON_EMAIL_ADMIN';
```

Cette manipulation est une étape d'installation réservée au propriétaire du projet. Vérifier que **exactement un utilisateur attendu** a été modifié, puis se déconnecter et reconnecter. Ne jamais exécuter sur une adresse non vérifiée.

6. Inscrire deux autres utilisateurs de test, puis utiliser l'espace Admin pour valider l'agence et convertir l'autre en DMC.

## 4. GitHub Pages : étapes exactes
1. Dans GitHub > Settings > Pages > Build and deployment, choisir **GitHub Actions** et **pas** « Deploy from a branch ».
2. Dans GitHub > Settings > Secrets and variables > Actions > **Variables**, créer :
   - `VITE_SUPABASE_URL` = `https://...supabase.co`
   - `VITE_SUPABASE_ANON_KEY` = **clé publique** Supabase (`sb_publishable_...` ou ancienne `anon`)
3. La workflow fournie vérifie que les deux variables sont définies, compile avec `GITHUB_PAGES=true`, vérifie que `dist/index.html` pointe vers les scripts `/<DEPOT>/assets/...` et publie **dist**. Si le site tente `/src/main.jsx`, c'est que GitHub Pages publie toujours la source ou l'ancien artefact.
4. Pousser sur `main` ; Actions > `Deploy AtlasB2B to GitHub Pages` : vérifier les étapes **Build**, **Validate built files and paths**, **Deploy**.
5. Ouvrir `https://TON_COMPTE.github.io/ATLASB2B/` ; en cas de page blanche, ouvrir `https://TON_COMPTE.github.io/ATLASB2B/diagnostic.html` pour détecter les fichiers 404.
6. Vider le cache du navigateur (`Ctrl + F5`) après un nouveau déploiement.

**Important :** un `.env.local` dans Codespaces n'est pas automatiquement pris en compte par GitHub Actions. Les variables GitHub sont nécessaires à la compilation en ligne.

## 5. Parcours de test
- Admin : inviter/valider la DMC et l'agence ; ouvrir le registre fournisseur API (configuration uniquement).
- DMC : créer un hôtel, ajouter types de chambres, photos, puis importer `modele_tarifs_natbeds.xlsx` en saisissant l'année de saison. Enregistrer les tarifs.
- Admin : publier l'hôtel, définir la marge commerciale de l'agence.
- Agence : rechercher les dates couvertes par la grille, vérifier le prix, créer une **demande sans paiement**.
- Admin : marquer la demande comme validée ou refusée **dans la simulation**.

## 6. Points bloquants connus / limites
- **Pas de backend bancaire ni de credentials de fournisseurs dans GitHub Pages.** Pour de vrais paiements, soldes prépayés, débit agence, confirmations API, il faudra une couche serveur sécurisée et une validation juridique du montage.
- **Pas de stock hôtelier garanti** : une grille tarifaire ne constitue pas une disponibilité réelle. Les réservations ne sont que des demandes de test.
- **Import Excel** : six périodes / cinq pensions du modèle NATBEDS. Les promotions, suppléments et réductions enfants ne sont pas encore calculés. L'import remplace atomiquement les anciens tarifs dont la période chevauche la nouvelle saison ; faire des essais sur des hôtels fictifs uniquement.
- **Photos** : stockage Supabase public, sans données confidentielles. La V1 prend une photo principale par hôtel et par type de chambre ; galerie complète à venir.
- **Rôles** : la création d'un nouvel utilisateur se fait en agence en attente ; un admin peut le transformer en DMC. Les droits sont vérifiés en PostgreSQL (RLS), pas simplement en masquant les boutons.
- **Tarifs nets** : la lecture directe de `booking_requests.net_total_eur` est interdite aux clients. Les prix agence sont calculés par fonction SQL.
- **Version commerciale** : prévoir tests automatisés d'intégration Supabase, observabilité, gestion des disponibilités, historiques de versions de tarifs, suppression RGPD, validations financières et contrôles légaux.

## 7. Vérifications possibles dans ce ZIP
- Sources JS/CSS/SQL et configuration GitHub Actions incluses.
- `scripts/check-dist.mjs` détecte automatiquement le problème « `/src/main.jsx` publié sur GitHub Pages » après compilation.
- Vérification locale complète : `npm install && npm run build && npm run check:dist` sur une machine avec accès à npm.
- Le modèle Excel NATBEDS fourni est un **exemple** et reste inchangé.
