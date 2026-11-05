# Étape 2 — Installer et tester Ollama (POC CPU)

**Objectif :** disposer d'un modèle de langage local, en français, fonctionnant
sur le PC pédagogique sans carte graphique exploitable, sans Docker et sans
connexion à un service cloud.

**Script :** `launcher/02-install-ollama.sh` — code retour `0` = PASS,
`1` = FAIL, `2` = À CONFIRMER.

**Menus :** `p90 check 2` (terminal) et le bouton *Contrôles* de l'interface
YAD appellent **le même script**. Aucune commande n'est dupliquée entre les
deux interfaces : `config/p90.conf` déclare l'étape, `lib/common.sh` la résout.

---

## 1. Résultat mesuré sur le poste de référence

| Contrôle | Valeur réelle |
|---|---|
| Persistance USB | PASS — `upperdir=/live/persist-root/upper`, fichier `antiX/rootfs` sur `/dev/sda2`, transport `usb` |
| Version Ollama | **0.3.6**, CPU uniquement |
| Service | `active` + `enabled`, écoute **127.0.0.1:11434** |
| Modèle | `qwen2.5:0.5b` (380 Mo sur disque) |
| Génération API | `2 + 2 = 4` — 8 tokens en ~188 ms |
| Vitesse | **~42 tokens/s** (i5-10210U, 8 threads, CPU seul) |
| RAM du moteur | ~820 Mo à l'exécution |
| Espace restant sur `/` | **909 Mo** |

Machine : Intel Core i5-10210U, 14 Gio de RAM, MX Linux 25.3 / Debian 13
(x86_64), session *live* persistante sur clé USB de 7,4 Go.

---

## 2. Pourquoi Ollama 0.3.6 et pas la dernière version

C'est le point le plus important de cette étape, et il est contre-intuitif.

Depuis la version **0.3.7**, Ollama publie une archive qui **embarque les moteurs
GPU** (CUDA, ROCm). L'archive pèse environ **1,5 Go compressés**, soit près de
**2 Go installés**. Le fichier de persistance `rootfs` de la clé ne fait que
3 Go au total : l'installation ne rentre pas.

La version **0.3.6** publie un **binaire unique de 559 Mo**, CPU seulement.
Elle est sortie avant Qwen 2.5 (v0.3.11) mais son moteur GGUF lit déjà ces
modèles : vérifié sur le poste, `qwen2.5:0.5b` se charge et génère.

L'empreinte SHA256 du binaire est épinglée dans le script :

```
775e0652c1dc61bde9ad98b9de743a10976ae026e4c1a230977193db3213e159
```

Le script vérifie la taille **et** cette empreinte avant toute installation.

---

## 3. Budget d'espace

| Élément | Taille |
|---|---|
| Binaire `/usr/local/bin/ollama` | 559 Mo |
| Modèles `/usr/share/ollama/.ollama/models` | 380 Mo |
| **Total** | **~940 Mo** |

Le script refuse d'installer si l'espace libre est inférieur au seuil
`P90_OLLAMA_MIN_FREE_MB` (700 Mo par défaut) — et re-contrôle ce seuil
**après** installation. Sur une clé fraîchement créée, comptez 2,5 Go libres
avant de lancer l'étape.

Le téléchargement se fait dans `/tmp` (tmpfs, en RAM) puis le fichier
temporaire est supprimé : aucune double copie sur la persistance.

**Aucune partition n'est créée, agrandie ou modifiée. `rootfs` n'est jamais
redimensionné.**

---

## 4. Ce que fait le script

1. Vérifie l'espace libre sur `/`.
2. Vérifie que la racine **écrit réellement sur la clé USB** en remontant la
   chaîne `overlay → loop → fichier porteur → disque parent → transport`.
   Transport ≠ `usb` ⇒ installation refusée.
3. Refuse de continuer si un disque interne est monté en lecture-écriture
   (protection du SSD Windows).
4. Réutilise `/usr/local/bin/ollama` s'il est déjà présent et fonctionnel.
5. Sinon : télécharge, contrôle taille + SHA256, installe.
6. Crée le compte de service `ollama` et le répertoire de modèles.
7. Écrit `/etc/systemd/system/ollama.service` **seulement si le contenu
   diffère** (pas de réécriture inutile), active et démarre le service.
8. Vérifie que l'écoute est strictement locale.
9. Télécharge `qwen2.5:0.5b` **si absent** (jamais deux fois).
10. Génère réellement une réponse, via la CLI puis via l'API.
11. Contrôle la marge d'espace restante.

---

## 5. Idempotence

Une seconde exécution ne réinstalle pas Ollama et ne retélécharge pas le
modèle. Vérifié sur le poste par trois exécutions consécutives : les trois
affichent `Ollama déjà présent`, `Modèle déjà présent`, et **PASS**.

---

## 6. Limite connue du modèle 0.5B

Le modèle `qwen2.5:0.5b` est **instable à l'échantillonnage par défaut**.
Interrogé six fois de suite sur « combien font 2 + 2 ? », il a répondu :

```
2 + 2 = 4     2 + 2 = 4     2 + 2 = 4
2 + 2 = 4     2 + 2 = 4     14
```

À **température 0**, la réponse devient reproductible (8 essais sur 8 ont donné
`2 + 2 = 4`). C'est cette mesure que le script utilise comme **verdict de
référence**.

La CLI `ollama run` n'accepte pas d'option de température en ligne de commande
et conserve son échantillonnage libre : sa sortie est donc **affichée à titre
informatif**, et une réponse fausse en CLI est signalée sans invalider la POC.
Ce n'est pas un défaut d'installation.

> Pour un usage en classe, préférer l'API locale ou OpenWebUI (module A2), qui
> permettent de fixer la température.

---

## 7. Tenue après redémarrage

Le service est `enabled`, donc il doit redémarrer avec la session — **mais ce
point n'a pas été testé** : aucun redémarrage n'a été effectué (consigne de
sécurité). À vérifier manuellement lors de la prochaine session :

```bash
systemctl is-active ollama
ollama list
```

Ne pas considérer la persistance du service comme prouvée tant que ce test
n'a pas été fait.

---

## 8. Vérification manuelle

```bash
# État général
ollama --version
systemctl is-active ollama
systemctl is-enabled ollama
ss -lnt | grep 11434          # doit afficher 127.0.0.1:11434 uniquement

# Modèles
ollama list
ollama ps

# Génération reproductible
curl -s http://127.0.0.1:11434/api/generate \
  -d '{"model":"qwen2.5:0.5b","prompt":"Réponds uniquement en français : combien font 2 + 2 ?","stream":false,"options":{"temperature":0}}'

# Espace
df -h /
```

Ou simplement :

```bash
p90 check 2
```

---

## 9. Résolution de problèmes

| Symptôme | Cause probable | Solution |
|---|---|---|
| `les écritures ne vont pas sur la clé USB` | session non persistante | redémarrer l'USB avec l'option `persist` |
| `espace libre insuffisant` | rootfs saturé | libérer de la place ; le script ne supprime rien |
| `empreinte SHA256 non conforme` | téléchargement altéré | relancer ; le script ne réutilise jamais un fichier douteux |
| `aucune écoute sur le port 11434` | service arrêté | `sudo systemctl status ollama` |
| `écoute non locale détectée` | `OLLAMA_HOST` modifié | retirer la variable, redémarrer le service |
| Réponse CLI fausse | échantillonnage du 0.5B | normal — voir §6 |

---

## 10. Sécurité

- Aucun formatage, aucun repartitionnement, aucune modification EFI/GRUB.
- Aucune écriture sur le SSD interne : le script refuse de continuer si un
  disque interne est monté en lecture-écriture.
- Le périphérique n'est jamais identifié par son nom (`/dev/sda`) mais par son
  transport et sa chaîne de montage.
- Aucun redémarrage automatique.
- Ollama n'écoute que sur `127.0.0.1` : jamais exposé au réseau pédagogique.
