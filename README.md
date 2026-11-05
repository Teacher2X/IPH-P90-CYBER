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
| `p90 check` | Lister les contrôles d'installation numérotés |
| `p90 check 1` | Vérifier la persistance de la clé USB |
| `p90 check 2` | Installer et tester Ollama (POC CPU) |
| `p90 check 3` | Partager Ollama sur le réseau (LAN) |

## Étapes d'installation validées

Chaque étape est un script autonome de `launcher/`, exécuté à l'identique par le
menu terminal (`p90 check N`) et par l'interface graphique (bouton *Contrôles*).
Une seule source déclare les étapes : `config/p90.conf`.

| # | Étape | Script | Fiche | État |
|---|-------|--------|-------|------|
| 1 | Persistance de la clé USB | `launcher/01-usb-persistence.sh` | [docs/etapes/01-persistance-usb.md](docs/etapes/01-persistance-usb.md) | validée sur clé USB |
| 2 | Ollama + modèle POC (CPU) | `launcher/02-install-ollama.sh` | [docs/etapes/02-ollama-poc.md](docs/etapes/02-ollama-poc.md) | validée sur poste réel |
| 3 | Partage Ollama sur le réseau | `launcher/03-share-ollama.sh` | [docs/etapes/03-partage-reseau.md](docs/etapes/03-partage-reseau.md) | script validé, application à faire |

### Étape 2 en bref

Ollama **0.3.6** (binaire CPU de 559 Mo), modèle **`qwen2.5:0.5b`** (380 Mo),
service `systemd` actif sur `127.0.0.1:11434`, génération mesurée à
**~42 tokens/s** sur i5-10210U.

```bash
p90 check 2
```

> **Limites du stockage USB.** Le fichier de persistance `rootfs` ne fait que
> 3 Go. L'étape 2 consomme ~940 Mo ; il reste ~909 Mo libres après
> installation. La version 0.3.6 est **épinglée volontairement** : depuis 0.3.7,
> l'archive officielle embarque les moteurs GPU et pèse ~1,5 Go compressés
> (~2 Go installés), ce qui ne tient pas sur la clé. Aucune partition n'est
> créée, agrandie ou modifiée par le script.
>
> **Limite du modèle 0.5B.** À l'échantillonnage par défaut, `qwen2.5:0.5b`
> répond faux environ une fois sur trois sur un calcul simple (« 14 » au lieu
> de « 4 »). À température 0 la réponse est reproductible : c'est la mesure
> retenue comme verdict. Détail dans la fiche de l'étape.

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
│   ├── 01-usb-persistence.sh   # Étape 1 : persistance de la clé USB
│   ├── 02-install-ollama.sh    # Étape 2 : Ollama + modèle POC (CPU)
│   ├── 03-share-ollama.sh      # Étape 3 : partage Ollama sur le LAN
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
│   ├── etapes/        # Une fiche par étape d'installation
│   │   ├── 01-persistance-usb.md
│   │   ├── 02-ollama-poc.md
│   │   └── 03-partage-reseau.md
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
