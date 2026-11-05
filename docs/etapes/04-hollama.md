# Étape 4 — Installer / lancer Hollama (client IA distant)

Hollama est un client graphique (Electron) pour Ollama : conversation, sélection
du modèle, historique local. Il **ne contient pas de modèle** — il consomme une
API Ollama, locale ou distante.

```bash
p90 check 4                      # installe (ou réutilise) et vérifie
p90 check 4 --check-only         # diagnostic seul, aucune écriture
p90 check 4 --launch             # installe si besoin, puis lance l'application
p90 check 4 --server http://192.168.1.38:11434
```

## Ce que fait le script

1. Vérifie la persistance (sans elle, l'installation disparaît au redémarrage).
2. Vérifie qu'un serveur Ollama répond et détecte le modèle disponible.
3. Trouve la session graphique (`DISPLAY`, y compris via SSH) et les
   bibliothèques Electron (GTK3, NSS, ALSA, GBM).
4. Contrôle l'espace libre (380 Mo exigés : 297 Mo mesurés + marge).
5. Télécharge l'archive officielle, **vérifie son SHA-256**, extrait, puis
   remplace l'installation de façon atomique.
6. Crée le lien `~/.local/bin/hollama`, l'icône et un raccourci de bureau.
7. Lance l'application si `--launch` est demandé.

## Installation sans root

Tout est installé dans le compte utilisateur — aucun `sudo` n'est nécessaire :

| Élément | Chemin |
|---|---|
| Application | `~/.local/opt/hollama` (297 Mo) |
| Binaire | `~/.local/bin/hollama` (lien) |
| Icône | `~/.local/share/icons/hicolor/64x64/apps/hollama.png` |
| Raccourci | `~/.local/share/applications/hollama.desktop` |
| Configuration | `~/.config/hollama` |

## Points vérifiés qui diffèrent des attentes

- **Pas de somme de contrôle officielle Linux.** `latest.yml` de la publication
  ne couvre que l'archive Windows. L'empreinte SHA-256 de l'archive Linux est
  donc relevée puis **épinglée dans le script** ; toute substitution est
  détectée. C'est moins fort qu'un checksum signé par l'éditeur, mais ce n'est
  pas un contrôle absent.
- **Le binaire ne répond pas à `--version`.** Il lance l'application
  (Electron). Le script lit la version dans la configuration de l'application,
  sans démarrer de processus graphique.
- **Aucune icône hors de `app.asar`.** `resources/` ne contient que
  `app.asar` et `app-update.yml`. Le script extrait `build/client/favicon.png`
  du bundle et **vérifie la signature PNG** avant de l'installer.

## Restriction des téléchargements

Hollama sait télécharger des modèles (`/api/pull`) : une restriction posée
dans l'interface serait contournée par un simple `curl`. **Le filtrage doit
être fait côté serveur Ollama** (étape 3). Cette étape ne met en place aucune
restriction applicative et ne prétend pas le faire.

## Codes de retour

| Code | Sens |
|------|------|
| 0 (PASS) | Hollama installé (ou réutilisé), serveur et modèle détectés |
| 1 (FAIL) | erreur bloquante réelle (téléchargement, empreinte, extraction) |
| 2 (BLOCKED) | prérequis manquant : persistance, serveur Ollama, session graphique, espace |

BLOCKED n'est pas un FAIL : rien n'est cassé, il manque un prérequis. Le script
le dit explicitement au lieu de continuer.

## Ce que le script ne teste pas

Il vérifie que l'application est installée et démarre, **pas** qu'une
conversation aboutit. Ce contrôle passe par l'interface (saisie, envoi,
réponse) et relève d'une validation manuelle, ou d'un pilotage par l'interface
de débogage de l'application.
