# P90 Launcher — Environnement Pédagogique Modulaire

**Cible :** Xubuntu LTS 64 bits, installation sur clé USB persistante  
**Public :** élèves de 15 à 18 ans, débutants en Linux, réseaux et intelligence artificielle  
**Principe :** simplicité, stabilité, interface graphique, maintenance minimale

## Vue d'ensemble

P90 Launcher installe et gère cinq modules pédagogiques indépendants sur une clé USB :

| # | Module | Description |
|---|--------|-------------|
| A1 | Ollama terminal | Assistant IA local dans le terminal |
| A2 | OpenWebUI et réseau | Chat web + découverte du réseau local |
| A3 | Hermes Agent | Agent capable d'exécuter des actions |
| A4 | WhatsApp | Pont de communication WhatsApp ↔ IA |
| A5 | Profils, mémoire et RAG | Profillings, mémoire durable, recherche documentaire |

## Installation

```bash
# Depuis le dépôt GitHub officiel (source de vérité)
curl -fsSL https://raw.githubusercontent.com/Teacher2X/IPH-P90-CYBER/main/bootstrap.sh \
  | P90_REPO_URL=https://github.com/Teacher2X/IPH-P90-CYBER.git bash
```

Ou, si le dépôt est déjà cloné :

```bash
cd IPH-P90-CYBER && bash install.sh
```

Après installation, lancer le lanceur graphique :

```bash
p90
```

## Commandes

| Commande | Description |
|----------|-------------|
| `p90` | Ouvrir l'interface graphique |
| `p90 status` | Afficher l'état des modules |
| `p90 doctor` | Rapport complet de diagnostic (portable en .txt) |
| `p90 update` | Vérifier les mises à jour disponibles |
| `p90 repair A1` | Réparer le module A1 |
| `p90 install A2` | Installer un module spécifique |

## Structure du dépôt

```
p90-launcher/
├── README.md          # Ce fichier
├── bootstrap.sh       # Script d'installation initiale
├── VERSION            # Version courante
├── config/            # Configurations partagées
│   ├── p90.conf       # Configuration principale P90
│   └── modules.json   # Descriptions des modules
├── launcher/          # Lanceur et utilitaires
│   ├── p90            # Commande principale (appelé par les sous-commandes)
│   ├── gui.sh         # Interface graphique YAD
│   ├── diagnose.sh    # Diagnostic système
│   └── p90.desktop    # Raccourci bureau
├── lib/               # Bibliothèques de fonctions
│   ├── common.sh      # Fonctions partagées
│   ├── checks.sh      # Vérifications (RAM, CPU, réseau)
│   ├── install.sh     # Gestion d'installation
│   └── update.sh      # Gestion des mises à jour
├── modules/           # Scripts par module pédagogique
│   ├── A1-ollama.sh
│   ├── A2-openwebui.sh
│   ├── A3-hermes.sh
│   ├── A4-whatsapp.sh
│   └── A5-memory-rag.sh
├── compose/           # Fichiers Docker Compose par module
│   ├── openwebui.yaml
│   └── waha.yaml
├── docs/              # Documentation pédagogique
│   ├── enseignant.md
│   ├── A1-ollama.md
│   ├── A2-openwebui.md
│   ├── A3-hermes.md
│   ├── A4-whatsapp.md
│   └── A5-memory-rag.md
├── tests/             # Tests automatique et checklist
└── .gitignore
```

## Sécurité

- Aucune exécution en root permanente
- Aucun secret stocké dans Git
- Port 11434 (Ollama) non exposé au LAN
- Dashboard WAHA en écoute locale uniquement (127.0.0.1)
- Authentification activée par défaut (OpenWebUI, WAHA)
- Actions destructrices protégées par confirmation
- Versions figées — pas de mise à jour automatique
- **Ne jamais intervenir sur les disques internes ni repartitionner un périphérique** :
  P90 travaille exclusivement dans `${P90_DATA_DIR}`, sur la clé USB
- **Aucun redémarrage système imposé** sans confirmation explicite de l'enseignant

## Mise à jour

```bash
p90 update          # Vérifier les versions disponibles
p90 repair A1       # Réparer un module sans perdre les données
```

Publication vers GitHub : **transfert manuel**, jamais automatique.
GitHub (`Teacher2X/IPH-P90-CYBER`) est la source de vérité ; Gitea n'est qu'une POC historique, en lecture seule.

```bash
cd /opt/p90-launcher
git remote add github https://github.com/<compte>/<depot>.git
git push github main --tags
```

---

**Développé pour l'enseignement** — Xubuntu LTS, clé USB persistante, enseignant unique.  
**Licence :** voir les licences des projets utilisés (Ollama, OpenWebUI, Hermes Agent, WAHA).
