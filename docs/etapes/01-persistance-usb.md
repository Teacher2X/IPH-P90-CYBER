# Étape 1 — Vérifier la persistance de la clé USB

Contrôle de diagnostic **en lecture seule** sur le disque de démarrage MX.
Il répond à une seule question : *ce que j'écris dans la session survivra-t-il
au prochain démarrage ?*

## Lancer le contrôle

```bash
p90 check 1          # menu CLI
p90                  # interface graphique → bouton « Contrôles » → étape 1
```

Codes retour : `0` = PASS · `1` = FAIL · `2` = À CONFIRMER.

## Ce qui est réellement vérifié

| Contrôle | Méthode |
|---|---|
| Clé identifiée par son transport | `lsblk -dno NAME,TRAN` → seuls les disques `usb` sont retenus |
| Partition de persistance | présence d'un fichier `antiX/rootfs` ou d'un `persistence.conf` **sur la clé** |
| UUID cohérent avec le noyau | UUID de la partition **=** `puuid=` de `/proc/cmdline` |
| Racine réellement persistante | la racine est un `overlay` dont l'`upperdir` vit sur la clé |
| Fichier de persistance monté en boucle | `/sys/block/loopN/loop/backing_file` remonte au fichier, puis à sa partition |
| Espace disponible | `df -h` sur le support de l'`upperdir` |
| SSD Windows non touché | aucun disque interne n'est monté en lecture-écriture |

## Pourquoi une partition montée ne suffit pas

Une partition de persistance peut exister, être montée, et pourtant ne servir à
rien : si la racine du système n'écrit pas dedans, chaque redémarrage repart du
squashfs d'origine. Le script ne déclare donc PASS que lorsque la chaîne
complète est prouvée :

```
cmdline (persist + puuid) → partition de la clé → fichier rootfs → loop → upperdir → racine overlay
```

## Sécurité

- Aucune écriture sur un disque interne : ils sont seulement listés.
- Aucun formatage, aucun repartitionnement, aucune modification de GRUB/EFI.
- Aucune installation de logiciel (`blkid` n'est volontairement pas requis).
- Aucun redémarrage automatique.
- La sonde d'écriture (`--write-probe`) reste confinée à la partition de la clé
  et n'est pas utilisée par le menu.

## Limite connue

`PASS` prouve que la **mécanique** de persistance est en place et que des
écritures antérieures existent déjà dans l'`upperdir`. La survie d'une écriture
**nouvelle** ne se prouve qu'après un redémarrage volontaire, hors de ce
contrôle.

## Exemple de diagnostic réel

```
  Clé — /dev/sda1 : 3,4G vfat, UUID=CC6E-717F, label=MX-LIVE, montage=/run/initramfs/boot-dev
  Clé — /dev/sda2 : 4G ext3, UUID=8f65d4df-27ce-424b-a534-31daa0c38bde, label=persistence
  UUID demandé au noyau : 8f65d4df-27ce-424b-a534-31daa0c38bde
  Racine : overlay      upperdir : /live/persist-root/upper
  fichier porteur (loop) : /run/initramfs/persist-dev/antiX/rootfs
  partition portant ce fichier : /dev/sda2
  Résultat : PASS
```
