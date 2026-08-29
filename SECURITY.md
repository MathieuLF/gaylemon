# Sécurité

Merci de signaler les vulnérabilités par le mécanisme privé de GitHub, sans ouvrir d’issue publique contenant une donnée sensible.

## Frontières essentielles

- Les requêtes de l’agent sont signées Ed25519, bornées dans le temps et protégées contre le rejeu.
- Les documents activés sont des projections publiques filtrées; une sauvegarde brute n’est jamais servie.
- Les routes d’exploitation exigent une session autorisée et ne sont pas mises en cache.
- Le service worker exclut les routes d’agent, d’ingestion et d’exploitation.
- Les actifs immuables portent une empreinte de contenu; les autres surfaces sont revalidées.
- Les secrets, domaines, chemins, runbooks et configurations d’instance restent hors du dépôt public.

## Signalement

Inclure la révision, le composant, une reproduction minimale et l’impact. Ne joindre ni clé, ni sauvegarde, ni export réel. Révoquer immédiatement tout secret exposé; supprimer seulement sa dernière occurrence ne nettoie pas l’historique Git.
