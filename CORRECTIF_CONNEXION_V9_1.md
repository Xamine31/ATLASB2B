# Netbeds V9.1 — correctif écran de chargement

Correction : l’application ne reste plus indéfiniment sur « Ouverture de votre espace Netbeds… » lorsque la vérification de la session Supabase ne répond pas.

- Déblocage de l'écran sur l'événement Supabase `INITIAL_SESSION` ou après réponse `getUser()`.
- Délai maximal de 12 secondes pour la vérification de session.
- Affichage d'un message de diagnostic et bouton « Réessayer la connexion ».
- Aucun changement des tables ni des fonctions financières ; ne pas réexécuter les migrations.

À déployer : remplacer les fichiers du dépôt par ceux du ZIP, faire un commit, puis vérifier GitHub Actions.

Ce correctif ne résout pas à lui seul les erreurs de configuration, d'authentification ou d'accès réseau à Supabase : il les rend visibles.
