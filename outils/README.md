# Dashboard privé BYM Classic

Statistiques **privées** pour le site de présentation : visiteurs, clics sur
« Télécharger », et téléchargements réels de l'APK. Rien n'est publié — ce
dossier est hors de `docs/`, donc GitHub Pages ne l'affiche jamais.

## Deux endroits pour voir les chiffres

| Où | Ce que ça montre | Confidentialité |
| --- | --- | --- |
| **Compte GoatCounter** (en ligne) | Visites, pages, referrers, navigateurs | Privé derrière ton login |
| **Ce dashboard local** (ci-dessous) | Idem + téléchargements APK, tout au même endroit | Privé : ne tourne que sur ta machine |

## Prérequis (une seule fois)

1. Crée un compte gratuit sur [goatcounter.com](https://www.goatcounter.com)
   — connexion par **email** uniquement (pas de mot de passe, pas de réseau social).
2. Ajoute ton site : **« Add new site »** →
   `https://victordiaz1000.github.io/bym-classic/`.
   Note le **code** donné (le sous-domaine, ex. `bymclassic`).
3. Génère un jeton : menu du haut → **API** → **« New API token »**.
   Colle-le quelque part sûr (gestionnaire de mots de passe).

## Activer le comptage sur le site

Le comptage est **actif** : la balise officielle GoatCounter est déjà posée
dans le `<head>` de `docs/index.html` :

```html
<script data-goatcounter="https://victordiaz1000.goatcounter.com/count"
        async src="//gc.zgo.at/count.js"></script>
```

Pour le retirer (besoin de vie privée), il suffit de supprimer cette balise.
Les clics sur « Télécharger » sont comptés en plus via `docs/script.js`
(module `initAnalytics`) — supprime aussi ce module pour tout couper.

Pour changer de site, remplace `victordiaz1000` par ton nouveau code dans la
balise ci-dessus. Puis republie (pousse sur `main` : GitHub Pages se met à jour seul).

## Lancer le dashboard local

```bash
cd outils
python dashboard-prive.py
```

Puis ouvre **<http://127.0.0.1:8787>** dans ton navigateur.

- Colle ton **code** et ton **jeton**, choisis la période, clique sur **Afficher**.
- Le code et le jeton sont enregistrés dans le **localStorage de ton
  navigateur** uniquement. Jamais dans un fichier, jamais poussés sur GitHub.
- Clique sur **« Oublier le jeton »** pour les effacer.
- **Ctrl+C** dans le terminal pour arrêter le serveur.

### Pourquoi un serveur local ?

Le dashboard appelle l'API GoatCounter et l'API GitHub. Ouvert directement
(« double-clic » sur le HTML), le navigateur **bloquerait** ces requêtes
(protection CORS). Ce petit serveur tourne **uniquement** sur `127.0.0.1`
(jamais exposé sur Internet) et relaie les appels. Ton jeton ne quitte pas
ta machine.

> Alternative sans serveur : tu peux aussi consulter directement le dashboard
> en ligne sur goatcounter.com — seul les téléchargements APK ne s'y trouvent pas.

## D'où viennent les chiffres

- **Visiteurs / clics** : compteurs **GoatCounter** (sans cookie, sans IP, sans
  donnée personnelle — conforme RGPD, hébergé en UE).
- **Téléchargements APK** : compteur **officiel de GitHub Releases**, fourni par
  l'API GitHub. C'est le nombre de téléchargements **effectifs**, pas une
  estimation, et ça ne nécessite aucun service supplémentaire.

## Confidentialité

Ce dashboard affiche des données que **toi seul** consulte. Il n'est pas
destiné à être poussé sur le dépôt public avec un jeton dedans : le jeton vit
dans ton navigateur, pas dans le code. En cas de doute, vérifie que `git status`
ne montre aucun fichier sensible avant de commiter.
