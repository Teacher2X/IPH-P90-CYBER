# RAPPORT FINAL — P90 Launcher

**Date :** 4 novembre 2026
**Dépôt local :** `/opt/data/p90-launcher`
**Dépôt Gitea :** `https://git.olinguito.jarvis.papapingouinbe.duckdns.org/olinguito/p90-launcher` (privé)
**Version :** 0.1.0
**Commits :** 11 (branche `main`, poussés)

---

## 1. Arborescence réelle

29 fichiers versionnés, 11 commits. Aucun fichier de données utilisateur n'est suivi.

```
p90-launcher/
├── .gitignore
├── README.md
├── VERSION                          # 0.1.0
├── bootstrap.sh                     # installation initiale (Gitea)
├── config/
│   ├── p90.conf                     # Bash valide, ports, modèles, sécurité
│   └── modules.json                 # catalogue des 5 modules
├── launcher/
│   ├── p90                          # commande principale
│   ├── gui.sh                       # interface YAD (yad --list)
│   ├── diagnose.sh                  # diagnostic détaillé
│   └── p90.desktop                  # raccourci bureau
├── lib/
│   ├── common.sh                    # chemins, config, logs, helpers
│   ├── checks.sh                    # RAM, CPU, disque, réseau
│   ├── install.sh                   # états de modules, garde-fous
│   └── update.sh                    # mises à jour depuis Gitea
├── modules/
│   ├── A1-ollama.sh
│   ├── A2-openwebui.sh
│   ├── A3-hermes.sh
│   ├── A4-whatsapp.sh
│   └── A5-memory-rag.sh
├── compose/
│   ├── openwebui.yaml               # OpenWebUI + Ollama (11434 non publié)
│   └── waha.yaml                    # WAHA local 127.0.0.1 seulement
├── docs/
│   ├── enseignant.md
│   ├── A1-ollama.md
│   ├── A2-openwebui.md
│   ├── A3-hermes.md
│   ├── A4-whatsapp.md
│   └── A5-memory-rag.md
└── tests/
    ├── run-tests.sh                 # 126 contrôles statiques
    └── CHECKLIST-USB.md             # validation manuelle sur clé
```

---

## 2. État précis de A1 à A5

Chaque module expose bien les quatre actions demandées — `install`, `check`
(diagnostic), `launch` (lancement), `repair` (réparation) — vérifié
automatiquement par les tests pour les cinq modules.

| Module | install | check | launch | repair | Preuve d'exécution réelle |
|---|---|---|---|---|---|
| **A1 Ollama** | ✅ code | ✅ code | ✅ code | ✅ code | Exécuté : détecte l'absence d'Ollama, propose l'installation, **s'arrête sans rien modifier** faute de confirmation |
| **A2 OpenWebUI** | ✅ code | ✅ code | ✅ code | ✅ code | Exécuté : détecte l'absence du démon Docker et s'arrête proprement (`broken\|démon docker injoignable`) |
| **A3 Hermes** | ✅ code | ✅ code | ✅ code | ✅ code | Exécuté : dépendance A1 vérifiée avant toute action |
| **A4 WhatsApp** | ✅ code | ✅ code | ✅ code | ✅ code | Exécuté : refus explicite sans Docker ; Compose validé séparément |
| **A5 Mémoire/RAG** | ✅ code | ✅ code | ✅ code | ✅ code | Exécuté : dépendance A3 vérifiée (`dépendance A3 absente`) |

**Ce qui n'est PAS prouvé :** aucune installation réelle de Ollama, Hermes,
ni démarrage de conteneur n'a été effectuée — ces opérations étaient
explicitement interdites par la mission. Les chemins nominaux (téléchargement
d'un modèle, réponse d'OpenWebUI, appairage WhatsApp) restent **non testés**.

---

## 3. Tests exécutés et résultats

### 3.1 Suite automatisée — `bash tests/run-tests.sh`

```
PASS : 126   FAIL : 0   SKIP : 0
```

| Section | Contenu |
|---|---|
| 1. Syntaxe | `bash -n` sur les 13 scripts |
| 2. ShellCheck | ShellCheck 0.10.0, sévérité `error`, tous les scripts |
| 3. Arborescence | 26 fichiers attendus présents |
| 4. Interface modules | 4 fonctions × 5 modules + dispatch = 40 contrôles |
| 5. Documentation | 5 fiches non vides (> 20 lignes) |
| 6. Secrets | 5 motifs de clés + 4 fichiers sensibles |
| 7. Données | `.gitignore` couvre `.p90-data`, `.state`, `models`, `waha-session` |
| 8. Configuration | Bash valide, JSON valide, 5 modules déclarés, **cohérence des ports conf ↔ Compose** |
| 9. Persistance | volumes Compose hors du dépôt |
| 10. Idempotence | garde-fous de réinstallation |
| 11. Sécurité | 11434 non publié, `WEBUI_AUTH=true`, WAHA en 127.0.0.1, export GitHub manuel |

### 3.2 ShellCheck — warnings

**0 warning** en sévérité `warning` après corrections (hors directives justifiées).

### 3.3 Validation Docker Compose (sans démarrer de service)

```
docker compose -f compose/openwebui.yaml config          → VALIDE
docker compose -f compose/waha.yaml config (sans mdp)    → REFUSÉ (attendu)
docker compose -f compose/waha.yaml config (avec mdp)    → VALIDE
```

Le refus sans mot de passe est le comportement voulu (`${P90_WAHA_PASSWORD:?}`).

### 3.4 Tests fonctionnels du lanceur — exécutés

| Commande | Résultat observé |
|---|---|
| `p90 version` | `P90 Launcher v0.1.0` |
| `p90 status` | 5 modules, états lus depuis les fichiers `.state` |
| `p90 doctor` | rapport complet : RAM 31265 Mo, CPU 13th Gen i5-13500T, disque 236 Go, réseau, dépendances |
| `p90 doctor --file /tmp/p90-rapport.txt` | fichier de 45 lignes écrit |
| `p90 install A9-faux` | `[ERR] Module inconnu` + code retour 1 |
| `p90 install A1` | résolution `A1` → `A1-ollama`, puis arrêt sans mutation |
| `p90` sans YAD | message explicite + repli sur `p90 status` |
| `diagnose.sh` | rapport complet, IP détectée (172.28.0.4) |
| `bootstrap.sh` sans URL | échec propre, aucune donnée touchée |
| `p90 update` sans URL | `Aucune source de mise à jour configurée` |

### 3.5 Persistance des données (priorité 7)

Test concret avec `P90_DATA_DIR=/tmp/usbtest` :

- répertoires créés : `models/`, `sessions/`, `db/`, `modules/`, `logs/` ;
- les données sont **hors du répertoire de code** (volumes distincts vérifiés avec `df`) ;
- un état de module écrit dans le volume de données est relu correctement par `p90 status`.

### 3.6 Clone frais

`git clone` du dépôt local → **126 PASS / 0 FAIL** dans le clone, lanceur
opérationnel sans aucun fichier externe. Le dépôt est autonome.

---

## 4. Bugs corrigés

### Bloquants

| # | Fichier | Bug | Effet |
|---|---|---|---|
| 1 | `launcher/gui.sh` | `${'\n'}` — syntaxe Bash invalide | le fichier ne se parsait pas |
| 2 | `launcher/gui.sh` | tous les boutons agissaient sur `A1-ollama` en dur | l'interface ignorait le module sélectionné |
| 3 | `config/p90.conf` | sections `[general]`, `[user]` chargées par `source` | `command not found` à chaque exécution |
| 4 | `lib/common.sh` | `config/p90.conf` **jamais chargé** | toute la configuration était ignorée |
| 5 | `modules/A4-whatsapp.sh` | `docker compose -C` | option inexistante → commande toujours en échec |
| 6 | `lib/checks.sh` | `df -BM` mal parsé | affichait `1-blocks` au lieu des tailles |
| 7 | `launcher/diagnose.sh` | `checks.sh` sourcé avant `common.sh` | échec sous `set -e` |

### Fonctionnels

| # | Fichier | Bug | Effet |
|---|---|---|---|
| 8 | `modules/A1-ollama.sh` | `ollama list \| wc -l` compte l'en-tête | l'absence de modèle n'était jamais détectée |
| 9 | `modules/A1-ollama.sh` | `check` démarrait le service | un diagnostic modifiait l'état |
| 10 | `modules/A1-ollama.sh` | `curl \| sh` sans confirmation | exécution silencieuse d'un script distant |
| 11 | `modules/A2-openwebui.sh` | `curl localhost:11434` | Ollama tourne dans Docker, invisible depuis l'hôte |
| 12 | `modules/A2-openwebui.sh` | `$YAD_BIN` vide si YAD absent | commande vide exécutée |
| 13 | `modules/A2-openwebui.sh` | `sleep 5` + `grep -qi up` | faux positifs/négatifs de démarrage |
| 14 | `modules/A3-hermes.sh` | `--workspace`, `--profile` sur `chat` | options CLI inexistantes |
| 15 | `modules/A3-hermes.sh` | `ready` marqué même moteur injoignable | état mensonger |
| 16 | `modules/A4-whatsapp.sh` | image `soybeanlolo/whatsapp-api-chain` | image non identifiée, non vérifiable |
| 17 | `modules/A4-whatsapp.sh` | `docker ps \| grep` | détection fragile |
| 18 | `lib/update.sh` | source = **GitHub** | contredisait « Gitea source de vérité » |
| 19 | `lib/update.sh` | `diff` sur chemin relatif | échec hors de la racine |
| 20 | `bootstrap.sh` | clone depuis **GitHub** | dépôt cible incorrect |
| 21 | `bootstrap.sh` | `[[ "${BASH_VERSINFO[0]}" && ... ]]` | test toujours vrai |
| 22 | `bootstrap.sh` | `[[ $? == 0 ]]` après un pipe | teste le mauvais code retour |
| 23 | `config/p90.conf` | `P90_WAHA_PORT=8080` | incohérent avec le Compose (3001) |
| 24 | `config/modules.json` | coquille « Assistan IA » | faute visible dans l'interface |
| 25 | `modules/\n` | fichier parasite (nom littéral avec saut de ligne) | artefact supprimé |

---

## 5. Fonctionnalités non testées

À ne pas considérer comme validées :

- Installation réelle d'Ollama et téléchargement d'un modèle.
- Réponse effective d'OpenWebUI et création de comptes.
- Installation de Hermes et usage réel des outils par l'agent.
- Appairage WhatsApp, envoi/réception d'un message, persistance de session.
- Création effective des profils Hermes et recherche documentaire (RAG).
- Interface YAD : **aucun test visuel** — YAD n'est pas installé sur la machine
  de développement. Seule la dégradation propre en son absence est vérifiée.
- Angry IP Scanner : détection prévue, jamais lancé.
- `p90 update --apply` contre un dépôt Gitea réel : chemins d'URL non éprouvés
  de bout en bout (`raw/branch/main/...`).
- Comportement sur ARM64 et sur machine à 4 Go de RAM.
- **Aucun test sur clé USB réelle.**

---

## 6. Commit Git final

```
8ecf387  test: suite automatisée et checklist de validation USB
42b18ee  docs: documentation enseignant et fiches pédagogiques A1-A5
bde0d64  feat(bootstrap): installation initiale depuis Gitea
c198fcc  feat(compose): fichiers Docker Compose A2 et A4
661e50d  feat(A2-A5): modules OpenWebUI, Hermes, WhatsApp et mémoire/RAG
d82415a  feat(A1): Ollama dans le terminal
f00a970  feat(config): configuration principale et catalogue des modules
8dce1df  feat(launcher): commande p90, interface YAD et diagnostic
4760c32  feat(lib): gestion d'installation et mises à jour depuis Gitea
b404285  feat(lib): socle commun, chargement de configuration et vérifications
d4d8eb1  chore: initialisation du dépôt P90 Launcher
```

Arbre de travail propre (`git status` vide). Aucun secret versionné, aucun
fichier de données utilisateur suivi.

---

## 7. État de publication Gitea

**Publié et vérifié côté serveur.**

| Élément | Valeur |
|---|---|
| URL | `https://git.olinguito.jarvis.papapingouinbe.duckdns.org/olinguito/p90-launcher` |
| Visibilité | **privé** |
| Branche par défaut | `main` |
| Commits sur le serveur | **11** (relus via l'API, pas seulement l'écho de `git push`) |
| Fichiers sur le serveur | **29** (arbre relu via l'API) |
| Identifiants | retirés de `.git/config` après le push |

**GitHub : non publié**, conformément à la consigne. Transfert manuel :

```bash
cd /opt/data/p90-launcher
git remote add github https://github.com/<compte>/<depot>.git
git push github main --tags
```

---

## 8. Instructions de déploiement sur clé USB

### 8.1 Préparer la clé

1. Installer **Xubuntu LTS 64 bits** sur la clé avec persistance active.
2. Démarrer sur la clé et ouvrir un terminal.
3. Vérifier l'espace disponible : `df -h /` (compter ~10 Go pour les modèles).

### 8.2 Installer P90

```bash
export P90_REPO_URL="https://git.olinguito.jarvis.papapingouinbe.duckdns.org/olinguito/p90-launcher.git"
curl -fsSL "https://git.olinguito.jarvis.papapingouinbe.duckdns.org/olinguito/p90-launcher/raw/branch/main/bootstrap.sh" | bash
```

Le dépôt étant privé, Git demandera des identifiants. Alternatives :

- clé SSH enregistrée dans Gitea, et `P90_REPO_URL=git@git...:olinguito/p90-launcher.git` ;
- ou copie locale : `git clone <url> /opt/p90-launcher && bash /opt/p90-launcher/bootstrap.sh`.

### 8.3 Vérifier l'installation

```bash
source ~/.bashrc          # active la commande p90
p90 version
p90 doctor --file ~/Desktop/p90-diagnostic.txt
```

### 8.4 Lancer

```bash
p90                       # interface graphique YAD
p90 install A1-ollama     # premier module
```

### 8.5 Renseigner la source de mise à jour

Éditer `config/p90.conf` et renseigner :

```bash
P90_UPDATE_URL="https://git.olinguito.jarvis.papapingouinbe.duckdns.org/olinguito/p90-launcher"
```

Sans cette valeur, `p90 update` indique proprement qu'aucune source n'est
configurée.

### 8.6 Valider sur la clé

Suivre `tests/CHECKLIST-USB.md`, section par section. C'est la seule procédure
qui autorise un verdict PASS fonctionnel.

---

## 9. Verdict

### **PARTIAL**

**Justification.**

Ce qui est **prouvé** :

- arborescence complète et conforme (29 fichiers, aucun manquant) ;
- 126 contrôles statiques passent, 0 échec, **aucun SKIP** ;
- ShellCheck 0.10.0 : aucune erreur, aucun warning ;
- les deux fichiers Compose sont valides, la contrainte « Ollama non exposé
  au LAN » est vérifiée, le refus sans mot de passe WAHA fonctionne ;
- le lanceur fonctionne réellement : `version`, `status`, `doctor`, `--file`,
  résolution de module, gestion des erreurs, dégradation sans YAD ;
- 25 bugs corrigés, dont 7 bloquants qui rendaient l'interface et la
  configuration inutilisables ;
- persistance des données démontrée hors du répertoire de code ;
- dépôt publié sur Gitea et **vérifié côté serveur** (11 commits, 29 fichiers) ;
- un clone frais repasse les 126 tests.

Ce qui **interdit un PASS** :

- aucune installation réelle n'a été exécutée (Ollama, Hermes, conteneurs) :
  les chemins nominaux des cinq modules ne sont pas éprouvés ;
- l'interface YAD n'a jamais été affichée : la mise en page et les retours
  utilisateur ne sont pas vérifiés ;
- **aucun test sur clé USB réelle** — c'est la limite explicite du cahier des
  charges : une validation statique ne constitue pas une validation fonctionnelle.

Le passage à **PASS** exige l'exécution de `tests/CHECKLIST-USB.md` sur une clé
Xubuntu réelle avec un PC cible.
