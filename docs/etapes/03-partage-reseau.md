# Étape 3 — Partager Ollama sur le réseau

Cette étape rend le modèle **déjà installé** utilisable par les autres postes du
laboratoire, sans qu'ils le téléchargent. Aucun modèle n'est récupéré ici : si
`qwen2.5:0.5b` est absent, l'étape s'arrête et renvoie vers l'étape 2.

```bash
p90 check 3                      # applique le partage
p90 check 3 --check-only         # diagnostic seul, aucune écriture
p90 check 3 --allow 192.168.1.10 --allow 192.168.1.11
p90 check 3 --remote-test 192.168.1.20   # prouve une génération distante
```

## Ce que fait le script

1. Vérifie qu'Ollama est installé, actif, et que le modèle est présent.
2. Lit l'adresse réelle du serveur (route par défaut) — jamais une IP en dur.
3. Valide la liste des adresses autorisées (IPv4/CIDR, octets 0–255,
   préfixe ≥ /16 ; `0.0.0.0/0` est refusé).
4. Écrit l'unité `systemd` avec `OLLAMA_HOST=0.0.0.0:11434` et des
   `OLLAMA_ORIGINS` explicites (sans joker).
5. Écrit et applique une table nftables dédiée : `accept` pour les adresses
   autorisées, `drop` pour tout le reste sur le port 11434.
6. Redémarre le service et contrôle l'écoute réelle.
7. Mesure une génération locale (référence, `temperature 0`).
8. Si `--remote-test` est fourni, exécute une génération **depuis l'autre
   machine** : c'est la seule preuve acceptable du partage.

## Limite assumée — à connaître

Ollama **ne sait pas restreindre les opérations** : il n'existe pas de droit
distinct pour `/api/pull` (téléchargement) ou `/api/delete` (suppression).
Le filtrage nftables agit par **adresse source**, pas par action. Un poste
autorisé accède donc à toute l'API, y compris ces deux routes.

C'est un choix explicite pour un réseau pédagogique de confiance : il empêche
un poste non listé d'utiliser le modèle, mais il ne protège pas contre un poste
autorisé mal utilisé. Pour un contrôle par opération, il faudrait un proxy
applicatif (nginx/caddy) qui n'expose que `/api/generate`, `/api/chat`,
`/api/tags`, `/api/version` et `/api/ps` — hors périmètre de cette étape.

## Ne jamais exposer sur Internet

Le port 11434 ne doit pas être publié par le routeur (pas de NAT/port-forward).
La restriction nftables est une défense en profondeur pour le LAN, pas une
authentification : une API Ollama ouverte sur Internet est un service ouvert.

## Idempotence

Relancer l'étape ne crée ni doublon d'unité, ni table imbriquée, ni entrée
répétée : l'unité n'est réécrite que si son contenu diffère, et la table est
remplacée proprement (`nft delete table` puis `nft -f`).

## Codes de retour

| Code | Sens |
|------|------|
| 0 (PASS) | partage actif **et** génération distante réussie |
| 1 (FAIL) | erreur réelle (modèle absent, nftables indisponible, réponse fausse) |
| 2 (À CONFIRMER) | configuration faite mais preuve réseau incomplète (pas de test distant) |

Un PASS sans `--remote-test` est impossible par construction : le script
signale explicitement qu'il n'a pas prouvé le partage.

## Prérequis d'application

L'écriture de `/etc/systemd/system/ollama.service` et de `/etc/nftables.d/`
exige un mot de passe `sudo` **interactif** : sur ce poste, les règles
NOPASSWD de MX Live sont affichées mais inopérantes (constat P02A). L'étape
doit donc être lancée depuis un terminal, avec l'utilisateur `demo`.
