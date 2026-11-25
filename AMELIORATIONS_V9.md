# Netbeds V9 — Liste des modifications

| Domaine | Avant V8 | Après V9 | Vérification |
|---|---|---|---|
| Navigation | Barre latérale et pages internes parfois imbriquées | Nouvelle coque fixe, barre supérieure sticky, responsive, routes hash | Contrôle syntaxique et structurel |
| Typographie et palette | Styles CSS accumulés | Système graphique V9 avec DM Sans + Outfit et palette Excel bleu marine/or | CSS analysé par PostCSS |
| Hôtels | Liste et édition dans le même composant, URL peu précise | Liste, création, fiche / chambres / tarifs / promotions / suppression sur routes distinctes | Contrôle structurel |
| Suppression hôtel | Pas de parcours dédié | Confirmation sur page propre, RPC limitant la suppression aux brouillons sans réservations | SQL à tester sur Supabase |
| Contrats | Formulaire et liste en parallèle | Pages liste, nouveau, édition, suppression brouillon admin | Parsing et contrôle structurel |
| Agences | Gestion générale dense | Liste partenaires, fiche de compte, activation/suspension et conditions commerciales par agence | Contrôle structurel |
| Marges hôtel | Formulaires inline | Pages de création/édition/suppression d'exception de marge | Contrôle structurel |
| Fournisseurs API | Création inline | Pages liste, ajout, édition, suppression avec confirmation | Contrôle structurel |
| Réservations | Tableau et boutons de validation inline | Liste de dossiers et fiche détaillée pour confirmer/refuser | Contrôle structurel |
| Opérations financières | Plusieurs formulaires inline | Pages séparées : rechargement, écriture, règlement, validation rechargement et règlement | Contrôle structurel |
| Profil | Email et nom minimal | Photo, présentation, société, téléphone, mot de passe, rôle en lecture seule | Migration SQL à exécuter |
| Recherche agence | Fiche d'hôtel en état local | URL fiche avec paramètres de recherche ; récupération des offres en cas de rechargement | Analyse JSX |
| Excel | Import/export modèle NATBEDS | Même logique et classeurs inchangés, ainsi que les 10 chambres / 7 règles | SHA256 classeurs identiques |
| RateHawk | Fournisseur fictif | Conservé sans connexion réelle | Vérification structurelle V8 |
| GitHub Pages | Publication depuis `dist` | Workflow conservé, ajout `check:v9` | Contrôle structurel, build npm non vérifié |

## Contrôles réalisés

- Parsing des fichiers JavaScript et JSX avec TypeScript (syntaxe seulement).
- Parsing des CSS avec PostCSS.
- `npm run check:v7`, `npm run check:v8`, `npm run check:v9` réussis.
- Présence des fichiers Excel `.xlsx` et identité SHA256 avec ceux de la V8.
- Vérification du workflow de déploiement GitHub Pages (contenu et chemins).
- **Non réalisés :** build Vite complet avec dépendances npm, tests end-to-end dans navigateur, exécution SQL réelle, audits RLS sur instance Supabase.

## Recommandations pour la suite

1. Ajouter des tests de bout en bout Playwright et des tests SQL PostgreSQL sur base de staging.
2. Construire un calendrier de disponibilité/allotements avant d'autoriser des confirmations automatiques.
3. Ajouter un système de notifications, un historique détaillé des éditions et une recherche globale.
4. Créer un registre d'incidents fournisseur (statut incertain, prix modifié, annulation), sans double réservation.
5. Ajouter les vraies conditions commerciales des contrats et les promotions au moteur de cotation.
6. Mettre en place une sauvegarde/recette des migrations Supabase et des politiques RLS avant toute exploitation.
7. Étudier les obligations juridiques pour les fonds prépayés et la revente de prestations touristiques.
