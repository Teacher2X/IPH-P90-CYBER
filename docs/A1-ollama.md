# A1 — Ollama dans le terminal

## Ce que tu vas comprendre

Un modèle d'IA, ce n'est pas magique : c'est un **programme** qui devine la
suite d'un texte. Pour tourner, il a besoin d'un **moteur** (Ollama) qui charge
le modèle en mémoire et répond aux questions.

Trois choses différentes :

| Élément | Rôle | Analogie |
|---|---|---|
| Le **modèle** (ex. `qwen3:8b`) | le "cerveau", des milliards de nombres | le livre |
| Le **moteur** (Ollama) | fait tourner le modèle | la lampe de lecture |
| L'**interface** | là où tu écris | tes yeux et ta main |

Ici, l'interface est le **terminal** : pas de navigateur, pas d'Internet après
installation.

## Pourquoi local ?

- Aucune donnée ne part sur Internet.
- Ça fonctionne sans connexion (après le téléchargement du modèle).
- C'est lent sur un petit PC : c'est normal, tout se passe sur ton processeur.

## Utilisation

```bash
p90 install A1-ollama        # installer
p90 repair A1-ollama         # vérifier / réparer
```

Puis dans la GUI, bouton **Lancer** : un terminal XFCE s'ouvre avec une
conversation prête.

## Choisir un modèle selon la RAM

| RAM du PC | Modèle proposé | Remarque |
|---|---|---|
| 16 Go et + | `qwen3:32b` | meilleur, plus lent |
| 8 Go | `qwen3:8b` | recommandé en classe |
| 4 Go | `qwen3:0.5b` | très léger, réponses simples |
| < 4 Go | aucun | mode dégradé, pas d'IA locale |

Vérifie ta RAM : `free -h`.

## Où sont les modèles ?

Dans `~/.p90-data/models`, sur la **clé USB**. Ils survivent au redémarrage.
Ils ne sont pas retéléchargés à chaque démarrage.

## Sécurité

Le port `11434` d'Ollama **n'est pas ouvert** sur le réseau. Seul ton
ordinateur peut parler au moteur.

## À toi de jouer

1. Demande à l'IA : *« Explique-moi ce qu'est un fichier dans Linux. »*
2. Puis : *« Donne-moi la commande pour lister les fichiers cachés. »*
3. Compare la longueur des deux réponses. Pourquoi la seconde est-elle plus
   courte ?

## Si ça ne marche pas

| Symptôme | Cause probable | Solution |
|---|---|---|
| `ollama: command not found` | non installé | `p90 repair A1-ollama` |
| Le service ne répond pas | moteur arrêté | `ollama serve` |
| « aucun modèle disponible » | rien de téléchargé | relancer Lancer, accepter le téléchargement |
| Très lent | RAM insuffisante | fermer le navigateur, choisir un modèle plus petit |
