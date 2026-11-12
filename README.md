# AtlasB2B Premium — version test GitHub Pages + Supabase

**Statut : prototype fonctionnel pour tests, PAS prêt pour une exploitation commerciale.** Aucun paiement réel, aucune réservation confirmée chez un hôtel, aucune API externe branchée.

## Fonctions testables
- Connexion et inscription par Supabase Auth.
- 3 espaces séparés par rôles et sécurisés en base (RLS) : **admin**, **DMC**, **agence**.
- Validation agence / conversion d’un compte en DMC par l'administrateur.
- Admin : catalogue fournisseurs API (registre seulement, sans clés), publication des hôtels, marge agence.
- DMC : création d'hôtels en brouillon, description, photo d'établissement, chambres et photos par type, import Excel modèle NATBEDS.
- Agence validée : recherche d'offres sur les hôtels publiés, calcul serveur des prix selon les marges, demandes de réservation.
- Admin : validation/refus des demandes **en mode démonstration**.
- Export Excel des tarifs enregistrés (format tabulaire standard). Import Excel : modèle NATBEDS joint.

## Démarrage local dans VS Code / Windows PowerShell
1. Installer Node.js LTS.
2. Dans VS Code, ouvrir ce dossier.
3. Créer `.env.local` en copiant `.env.example` et remplacer les deux valeurs par **Project URL** et **publishable key** (ou ancienne clé `anon`) depuis Supabase > Project Settings > API. **Ne jamais utiliser `service_role`/secret key !**
4. Dans Supabase (projet de test neuf) : `SQL Editor` > exécuter `supabase/schema.sql`.
5. Dans Auth > Providers, activer Email. Pour les essais, confirmer les emails reçus, ou désactiver la confirmation des emails uniquement dans le projet de test.
6. Terminal :
   ```powershell
   npm.cmd install
   npm.cmd run dev
   ```
7. Ouvrir l'adresse affichée (souvent http://localhost:5173).
8. Créer ton premier compte via l'interface. Dans Supabase SQL Editor, **une seule fois** :
   ```sql
   update public.profiles
   set role='admin', agency_id=null, dmc_id=null
   where email='TON_EMAIL_ADMIN';
   ```
   Puis **se déconnecter / reconnecter**. Ne jamais publier cette instruction avec un email réel.
9. Créer un deuxième compte pour une DMC et un troisième pour une agence. Dans l'espace admin, convertir le deuxième en DMC et valider le troisième.
10. La DMC crée un hôtel et charge le fichier Excel ; admin publie ; agence cherche et envoie une demande ; admin la traite.

## Hébergement GitHub Pages, sans Vercel
1. Créer un dépôt GitHub (public pour GitHub Pages gratuit ; vérifier les conditions de votre offre GitHub si dépôt privé) et y envoyer **le contenu du dossier à la racine**, pas le dossier englobant.
2. Renommer la branche principale en `main` si nécessaire.
3. Dépôt > **Settings > Secrets and variables > Actions > Variables** :
   - `VITE_SUPABASE_URL` = URL du projet Supabase
   - `VITE_SUPABASE_ANON_KEY` = clé publique Supabase
4. Dépôt > **Settings > Pages > Build and deployment > Source** : sélectionner **GitHub Actions**.
5. La workflow `.github/workflows/pages.yml` construit et publie automatiquement le site après un push sur `main`.
6. URL typique : `https://TON_COMPTE.github.io/NOM_DU_DEPOT/`.
7. Dans Supabase > **Authentication > URL Configuration** : ajouter l'URL GitHub Pages dans **Redirect URLs**, et configurer la Site URL si nécessaire pour la confirmation email.

`VITE_` signifie que les deux variables sont **publiques** dans le navigateur. C'est normal pour la clé *publishable/anon* : la sécurité repose sur RLS et sur les fonctions SQL. Ne jamais ajouter de secrets de fournisseurs, de clés bancaires ou de `service_role` au projet GitHub Pages.

## Limites importantes
- Uniquement demandes manuelles de réservation : **pas de stock garanti, de voucher réel, de paiement, de crédit agence, de SEPA, ni de reversement fournisseur**. Le bouton « Valider » simule une décision administrative.
- Registre de partenaires API sans appels API : les clés API exigent une composante serveur sécurisée, qu'on ajoutera ultérieurement (Supabase Edge Functions convient).
- Grille NATBEDS : uniquement les lignes de tarifs de chambres 5 à 14, les 6 périodes et 5 pensions. Les réductions enfants/promotions ne sont pas calculées. L'année de saison doit être renseignée. L'export est un Excel tabulaire, pas une reconstruction exacte du modèle NATBEDS.
- L'interface de recherche gère un séjour d'au maximum 30 nuits, un type de chambre, et n'intègre pas encore de disponibilité réelle. Attention aux éventuels **chevauchements de périodes** : ne pas en créer pour une même chambre/pension.
- Comptes utilisateur : ne pas utiliser de données réelles ou sensibles pour tester. Pas encore de réinitialisation par interface, traitement RGPD complet, journaux financiers immuables ou protections renforcées de production.
- GitHub Pages peut publier un site statique React, tandis que Supabase héberge la base et l'auth. Cela évite un serveur web supplémentaire pour les **fonctionnalités testables**. L'exploitation commerciale avec réservations API, paiement et wallets nécessitera du backend sécurisé et une validation juridique.

## Vérifications de sécurité
- RLS activée sur toutes les tables applicatives.
- Les requêtes de prix agence sont exécutées dans une fonction Supabase et ne divulguent pas les tarifs nets.
- L'administrateur est le seul à gérer les API fournisseurs et à publier les hôtels.
- Une DMC peut seulement modifier ses hôtels non publiés.
- Les demandes de réservation sont créées via une fonction SQL qui recalcule les prix.
- Aucun secret API ou bancaire dans les variables publiques.
