# AtlasB2B Premium V5 — GitHub Pages + Supabase

**Projet de démonstration. Aucune API hôtelière active, aucun paiement réel, aucun droit d'émettre de vouchers de voyage réel.**

Thème : forêt / champagne / terracotta / ivoire / vert sauge. Interface React + Vite et Supabase. Trois espaces : **Admin**, **DMC**, **Agence**.

## Fonctionnalités

- **Admin** : tableau de bord, validation des comptes, catalogue, page **Créer un hôtel**, publication, grilles Excel, page dédiée **Fournisseurs API** (registre sans credentials), demandes de réservation, et **Centre financier**.
- **DMC** : ses hôtels et leur création dans une page distincte, fiches/photos, types de chambres/photos, import/export Excel, demandes visibles. La publication appartient à l'admin.
- **Agence** : recherche d'offres publiées avec tarifs personnalisés, demandes de réservation manuelles, consultation du crédit fictif, demandes de rechargement par virement à contrôler par l'admin.
- **Finances** : demandes de rechargement avec référence bancaire, approbation ou refus **manuels**, mouvements de crédit validés et tracés, débits de réservations confirmées **uniquement sur demande explicite de l'admin**, remboursements/ajustements manuels, brouillons de règlements DMC/hôtels/API, validation admin, référence bancaire de règlement, export CSV de contrôle et journal d'audit. **Aucun transfert réel, aucun SEPA pain.001, aucun rapprochement automatisé.**

## Déploiement sur Supabase EXISTANT (Rebuild déjà installé)

1. Faites une **sauvegarde** et utilisez un **projet Supabase de test**.
2. Si le projet contient déjà la V2 Rebuild, **NE REJOUEZ PAS** `supabase/schema.sql` ni `supabase/migration_depuis_v1.sql` : ces fichiers créent des objets déjà existants.
3. Dans **SQL Editor**, exécutez **une seule fois** `supabase/migration_v5_finances.sql` ; assurez-vous que l'éditeur affiche `Success`.
4. Vérifiez dans Table Editor que les tables `wallet_topup_requests`, `wallet_entries`, `supplier_payables`, `finance_audit` existent.
5. Si vous démarrez d'un Supabase **totalement vierge**, exécutez d'abord `supabase/schema.sql`, puis `supabase/migration_v5_finances.sql`. **Ne lancez pas de scripts d'une autre version au hasard.**
6. Les opérations financières requièrent un utilisateur au rôle `admin`. Le code ne fournit **aucun mot de passe ni compte admin prédéfini**. Consultez le guide d'initialisation du schéma existant pour promouvoir votre propre compte administrateur depuis SQL Editor après inscription.

## GitHub Pages

1. Décompressez le ZIP et envoyez les **fichiers à la racine** de votre dépôt `ATLASB2B`. Ne mettez pas un sous-dossier contenant le projet.
2. Dans le dépôt GitHub : **Settings → Secrets and variables → Actions → Variables** :
   - `VITE_SUPABASE_URL` = URL de votre projet, ex. `https://xxx.supabase.co`
   - `VITE_SUPABASE_ANON_KEY` = clé publique `anon`/publishable **jamais** `service_role` / secret.
3. **Settings → Pages → Source → GitHub Actions**.
4. Le workflow `.github/workflows/deploy.yml` installe, compile, vérifie `dist/`, et publie ce dossier. Il ajoute automatiquement `/ATLASB2B/` à la base des ressources.
5. Dans Supabase **Authentication → URL Configuration**, configurez `https://xamine31.github.io/ATLASB2B/` comme Site URL et autorisez la redirection `https://xamine31.github.io/ATLASB2B/**` (adapter si autre dépôt).
6. Ouvrez le workflow **Actions** et vérifiez les étapes Build et Deploy. Diagnostic : `/ATLASB2B/diagnostic.html`.

Pour un test Codespaces :

```bash
npm install
cp .env.example .env.local
# Renseigner les variables VITE_* uniquement dans .env.local
npm run dev
```

Pour tester le build :

```bash
GITHUB_PAGES=true GITHUB_REPOSITORY=Xamine31/ATLASB2B npm run build
GITHUB_PAGES=true GITHUB_REPOSITORY=Xamine31/ATLASB2B npm run check:dist
```

## Tests de bout en bout

1. Avec **Admin** : approuver une agence et convertir un compte en DMC. Créer un hôtel sur **Créer un hôtel** ou laisser la DMC le créer, puis sélectionner l'hôtel dans le **Catalogue**.
2. Avec **DMC** : importer `exemple_tarifs_fictifs.xlsx`, ajouter photos et chambres, vérifier la période tarifaire. Le modèle NATBEDS se trouve dans `modele_tarifs_natbeds.xlsx`.
3. Avec **Admin** : publier l'hôtel, configurer la majoration de l'agence.
4. Avec **Agence** : rechercher un hôtel pour des dates couvertes par l'Excel, puis envoyer une **demande non engageante**.
5. Avec **Admin** : valider/refuser cette demande dans **Demandes**. Validation = **simulation administrative**, pas confirmation fournisseur.
6. Avec **Agence** : dans **Mon crédit**, indiquer une référence de virement fictive et soumettre une demande de 1 000 €.
7. Avec **Admin** : dans **Centre financier**, approuver la demande **après vérification fictive**. Vérifier le journal de crédit. Puis sélectionner une agence et saisir un débit lié à une réservation simulée confirmée. Le système doit refuser le découvert et les débits dupliqués.
8. Avec **Admin** : préparer un règlement DMC, l'approuver, exporter la **liste CSV** puis le marquer payé avec une référence bancaire fictive. Le statut est purement déclaratif.
9. Tester qu'une agence ne peut ni créer d'API ni voir des écritures d'une autre agence. Vérifier les règles RLS en base et non uniquement les menus.

## Limites empêchant un usage commercial réel

- Aucun paiement bancaire/SEPA, aucune preuve automatique de réception de fonds. La validation admin est uniquement déclarative.
- Aucun contrôle de disponibilité contractuelle, pas d'inventaire garanti, aucun vrai fournisseur/API connecté.
- Une réservation marquée « confirmée » par l'admin **ne représente pas une confirmation d'hôtel** ; pas de débit automatique : séparation délibérée pour les tests.
- Pas de workflow anti-fraude/justificatifs bancaires, de double approbation par personnes distinctes, ni de véritable rapprochement bancaire.
- Pas de devises, TVA, clôture comptable, facturation légale, fonds protégés, garantie financière ni vérification juridique.
- Le modèle Excel importe certaines grilles chambres/pensions/périodes, **pas** toutes les règles commerciales (enfants, stop sales, disponibilité, allotement).
- Les fichiers/photos d'hôtels sont publics via le bucket `hotel-photos` ; ne téléversez pas de données confidentielles dans ce bucket.
- Le registre API permet de noter des partenaires **sans appeler leurs APIs ni stocker leurs secrets**.

**Avant toute exploitation réelle avec de l'argent :** vérification juridique française (voyages / encaissement pour compte de tiers), analyse de sécurité de Supabase/RLS, paiement via prestataire adapté, audit financier, contrôles anti-double réservation, sauvegardes et tests d'intégration.
