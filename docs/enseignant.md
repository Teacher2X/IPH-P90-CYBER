# P90 Launcher — Guide de l'enseignant

Environnement pédagogique modulaire pour élèves de 15 à 18 ans débutant en
Linux, réseaux et intelligence artificielle.

## 1. Principe

Une clé USB Xubuntu LTS persistante contient :

- **Le code** de P90 Launcher, installé dans `/opt/p90-launcher`.
- **Les données** de l'élève, dans `~/.p90-data` (sur la même clé).

Le code est réinstallable ; les données ne sont jamais supprimées par une
mise à jour ou une réparation.

## 2. Installation sur une clé USB

1. Installer Xubuntu LTS sur la clé en mode persistant (livesys ou installation
   complète avec `persistence` activée).
2. Démarrer la clé, ouvrir un terminal, lancer :

   ```bash
   curl -fsSL https://raw.githubusercontent.com/Teacher2X/IPH-P90-CYBER/main/bootstrap.sh | bash
   ```

3. Redémarrer le terminal, puis taper `p90`.

Le bootstrap vérifie le système, récupère le code, crée les répertoires de
données et installe le raccourci de bureau.

## 3. Commandes

| Commande | Effet |
|---|---|
| `p90` | Ouvre l'interface graphique YAD |
| `p90 status` | État des cinq modules |
| `p90 doctor` | Diagnostic matériel/réseau/modules, exportable |
| `p90 doctor --file rapport.txt` | Diagnostic enregistré dans un fichier |
| `p90 update` | Vérifie les mises à jour disponibles |
| `p90 update --apply` | Applique la mise à jour validée |
| `p90 repair A1` | Répare un module sans toucher aux données |
| `p90 install A2` | Installe un module en ligne de commande |

## 4. Les cinq modules

| Module | Contenu | Dépendance |
|---|---|---|
| **A1** | Ollama + modèle Qwen dans le terminal | — |
| **A2** | OpenWebUI (Docker) + découverte réseau | Docker, A1 |
| **A3** | Hermes Agent (agent à outils) | A1 |
| **A4** | Pont WhatsApp via WAHA (**facultatif**) | Docker, A3 |
| **A5** | Profils Hermes, mémoire, RAG | A3 |

## 5. Ordre recommandé

1. **A1** — l'élève découvre d'abord un LLM sans interface graphique.
2. **A2** — il ajoute une interface web et comprend l'adresse IP.
3. **A3** — il distingue chatbot et agent capable d'agir.
4. **A5** — il constate que profil, mémoire et documents sont trois choses.
5. **A4** — démonstration facultative, seulement avec un compte dédié.

## 6. Sécurité — points de vigilance

- **Jamais** d'exécution permanente en root.
- **Jamais** de mot de passe dans la mémoire de l'agent ou dans Git.
- Le port **11434 d'Ollama n'est pas exposé** au LAN.
- OpenWebUI écoute sur `0.0.0.0:3000` : la restriction réseau se fait par
  **règle de pare-feu** sur le réseau pédagogique, pas par l'authentification
  seule.
- Le dashboard WAHA n'écoute que sur `127.0.0.1`.
- Aucun redémarrage système sans confirmation.

## 7. Diagnostic en cas de problème

```bash
p90 doctor --file /tmp/rapport.txt
```

Le rapport contient : RAM, processeur, disque, réseau, état des modules.
À lire avec l'élève : c'est un support pédagogique en soi.

## 8. Mise à jour

GitHub (Teacher2X/IPH-P90-CYBER) est la source de vérité. Les élèves ne reçoivent qu'une version
explicitement validée (tag Git). Aucune mise à jour n'est automatique.

Procédure de publication vers GitHub : voir `docs/enseignant.md` §9 du dépôt
et le fichier `PUBLICATION-GITHUB.md`. Le transfert est **manuel**.

## 9. Export manuel vers GitHub

```bash
# Depuis un clone du dépôt GitHub
git remote add github https://github.com/<compte>/<depot>.git
git push github --tags main
```

Gitea n'est plus qu'une POC historique : il n'est plus alimenté et ne doit pas être utilisé.
