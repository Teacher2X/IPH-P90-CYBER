#!/usr/bin/env bash
# =============================================================================
# launcher/01-usb-persistence.sh — Point 1 : persistance de la clé USB
#
# Code retour : 0 = PASS · 1 = FAIL · 2 = À CONFIRMER
#
# Principe : aucun nom de disque codé en dur. La clé est identifiée par son
# TRANSPORT (usb), puis ses UUID sont lus depuis `lsblk -P` — blkid est absent
# de la session live MX et on n'installe rien. Tout périphérique non-USB
# (nvme/sata/…) est uniquement LU : jamais monté, jamais écrit.
#
# LECTURE SEULE, sauf --write-probe qui confine une sonde à la partition de
# persistance de la clé USB.
# =============================================================================

set -uo pipefail

JSON=0
WRITE_PROBE=0
for a in "$@"; do
    case "$a" in
        --json)        JSON=1 ;;
        --write-probe) WRITE_PROBE=1 ;;
        -h|--help)     sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    esac
done

RESULT=PASS
declare -a LINES=()
declare -a PROBL=()
USB_DISKS=()
INTERNAL=()
PERSIST_PART=""; PERSIST_KIND=""; PERSIST_UUID=""
BOOT_PART=""; BOOT_UUID=""
ROOT_OVERLAY=0; UPPER_DIR=""; AVAIL=""

say()  { LINES+=("$1"); }
fail() { PROBL+=("$1"); RESULT=FAIL; }
warn() { PROBL+=("$1"); [[ "$RESULT" == "FAIL" ]] || RESULT=CONFIRM; }

finish() {
    local code first=1 p l
    case "$RESULT" in PASS) code=0 ;; FAIL) code=1 ;; *) code=2 ;; esac

    if (( JSON == 1 )); then
        printf '{"result":"%s","usb_detected":%s,"persist_part":"%s","persist_kind":"%s",' \
            "$RESULT" "$( (( ${#USB_DISKS[@]} > 0 )) && echo true || echo false )" \
            "$PERSIST_PART" "$PERSIST_KIND"
        printf '"persist_uuid":"%s","boot_part":"%s","boot_uuid":"%s","root_overlay":%s,' \
            "$PERSIST_UUID" "$BOOT_PART" "$BOOT_UUID" "$( ((ROOT_OVERLAY)) && echo true || echo false )"
        printf '"upperdir":"%s","avail":"%s","internal":"%s","problems":[' \
            "${UPPER_DIR:-}" "${AVAIL:-}" "${INTERNAL[*]:-}"
        for p in "${PROBL[@]:-}"; do
            [[ -z "$p" ]] && continue
            (( first )) || printf ','
            first=0
            printf '"%s"' "${p//\"/\\\"}"
        done
        printf ']}\n'
        exit "$code"
    fi

    echo "==================================================================="
    echo "  1 — Vérifier la persistance de la clé USB"
    echo "==================================================================="
    for l in "${LINES[@]:-}"; do [[ -n "${l:-}" ]] && echo "  $l"; done
    echo "-------------------------------------------------------------------"
    echo "  Résultat              : $RESULT"
    echo "  Clé USB détectée      : $( (( ${#USB_DISKS[@]} > 0 )) && echo OUI || echo NON )"
    echo "  Partition persistance : $( [[ -n "$PERSIST_PART" ]] && echo "OUI  ($PERSIST_PART — $PERSIST_KIND)" || echo NON )"
    echo "  Persistance active    : $( case "$RESULT" in PASS) echo OUI ;; FAIL) echo NON ;; *) echo "À CONFIRMER" ;; esac )"
    echo "  Espace disponible     : ${AVAIL:-inconnu}"
    echo "  SSD Windows préservé  : $( (( ${#INTERNAL[@]} > 0 )) && echo "aucun montage, aucune écriture sur ${INTERNAL[*]}" || echo "aucun disque interne vu" )"
    if (( ${#PROBL[@]} > 0 )); then
        echo "-------------------------------------------------------------------"
        for p in "${PROBL[@]}"; do echo "  ! $p"; done
    fi
    echo "==================================================================="
    exit "$code"
}

# --- 0. Outils indispensables (blkid volontairement absent) ------------------
for t in lsblk findmnt awk df; do
    command -v "$t" >/dev/null 2>&1 || { echo "FAIL: outil manquant : $t"; exit 1; }
done

# --- 1. Disques USB et internes, d'après le TRANSPORT ------------------------
while read -r name tran; do
    [[ -z "$name" ]] && continue
    case "$tran" in
        usb) USB_DISKS+=("/dev/$name") ;;
        "")  [[ "$name" == loop* || "$name" == sr* ]] || INTERNAL+=("/dev/$name") ;;
        *)   [[ "$name" == loop* ]] || INTERNAL+=("/dev/$name") ;;
    esac
done < <(lsblk -dno NAME,TRAN 2>/dev/null)

say "Disques USB : ${USB_DISKS[*]:-aucun}"
say "Disques internes (lecture seule) : ${INTERNAL[*]:-aucun}"

if (( ${#USB_DISKS[@]} == 0 )); then
    fail "aucun disque de transport usb visible"
    finish
fi

is_on_usb() {
    local dev="$1" d
    [[ -z "$dev" || "$dev" == "-" ]] && return 1
    # lsblk -s remonte la chaîne ENFANTS → PARENT. Le mode arbre préfixe les
    # noms par des caractères de dessin (└─) : on nettoie avant comparaison.
    local chips
    chips="$(lsblk -sno NAME "$dev" 2>/dev/null | sed 's/^[^a-zA-Z0-9]*//' | tr -d ' \r')"
    for d in "${USB_DISKS[@]}"; do
        grep -qx "${d##*/}" <<<"$chips" && return 0
    done
    return 1
}

# --- 2. Partitions de la clé : UUID, type, point de montage ------------------
# lsblk n'indique le TRANSPORT que sur le disque, jamais sur ses partitions :
# on l'hérite donc du disque parent (colonne PKNAME). Une ligne par partition :
#   dev|tran|uuid|label|fstype|size
mapfile -t DEV_ROWS < <(lsblk -P -o NAME,TYPE,TRAN,PKNAME,UUID,LABEL,FSTYPE,SIZE 2>/dev/null |
    tr -d '\r' | awk '
    {
        name=""; type=""; tran=""; pk=""; uuid=""; label=""; fstype=""; size=""
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^NAME=/)   { v=$i; sub(/^NAME="/,"",v);   sub(/"$/,"",v); name=v }
            else if ($i ~ /^TYPE=/)   { v=$i; sub(/^TYPE="/,"",v);   sub(/"$/,"",v); type=v }
            else if ($i ~ /^TRAN=/)   { v=$i; sub(/^TRAN="/,"",v);   sub(/"$/,"",v); tran=v }
            else if ($i ~ /^PKNAME=/) { v=$i; sub(/^PKNAME="/,"",v); sub(/"$/,"",v); pk=v }
            else if ($i ~ /^UUID=/)   { v=$i; sub(/^UUID="/,"",v);   sub(/"$/,"",v); uuid=v }
            else if ($i ~ /^LABEL=/)  { v=$i; sub(/^LABEL="/,"",v);  sub(/"$/,"",v); label=v }
            else if ($i ~ /^FSTYPE=/) { v=$i; sub(/^FSTYPE="/,"",v); sub(/"$/,"",v); fstype=v }
            else if ($i ~ /^SIZE=/)   { v=$i; sub(/^SIZE="/,"",v);   sub(/"$/,"",v); size=v }
        }
        if (type == "part") {
            gsub(/\|/, "-", label)
            printf "/dev/%s|%s|%s|%s|%s|%s\n", name, pk, tran, uuid, label, fstype "|" size
        }
    }')

# Transport effectif du disque parent (TRAN vide sur les partitions).
disk_tran() {
    local pk="$1"
    lsblk -dno TRAN "/dev/$pk" 2>/dev/null | tr -d ' \r'
}

declare -A MP_OF=()
# findmnt -rno sépare par ESPACE : on lit les deux premiers champs.
while read -r src mp _rest; do
    [[ "$src" == /dev/* ]] && MP_OF["$src"]="$mp"
done < <(findmnt -rno SOURCE,TARGET 2>/dev/null)

for row in "${DEV_ROWS[@]:-}"; do
    [[ -z "${row:-}" ]] && continue
    # Champs : dev|parent|tran_partition|uuid|label|fstype|size
    IFS='|' read -r dev parent _tran uuid label fstype size <<<"$row"
    [[ -z "$dev" ]] && continue
    # Le transport vient du DISQUE parent, jamais du nom du device.
    tran="$(disk_tran "$parent")"
    [[ -z "$tran" ]] && tran="$_tran"
    [[ "$tran" == "usb" ]] || continue
    is_on_usb "$dev" || continue
    mp="${MP_OF[$dev]:-}"
    say "Clé — $dev : $size $fstype, UUID=${uuid:-aucun}, label=${label:-—}, montage=${mp:-aucun}"

    if [[ -n "$mp" && -f "$mp/antiX/rootfs" ]]; then
        PERSIST_PART="$dev"; PERSIST_KIND="fichier antiX/rootfs"; PERSIST_UUID="$uuid"
    elif [[ -n "$mp" && -f "$mp/persistence.conf" ]]; then
        PERSIST_PART="$dev"; PERSIST_KIND="persistence.conf";      PERSIST_UUID="$uuid"
    elif [[ -n "$mp" && -d "$mp/antiX" && -z "$BOOT_PART" ]]; then
        BOOT_PART="$dev"; BOOT_UUID="$uuid"
    fi
done

[[ -n "$BOOT_PART" ]] && say "Partition de démarrage : $BOOT_PART (UUID $BOOT_UUID)"
if [[ -z "$PERSIST_PART" ]]; then
    fail "aucune partition de persistance (antiX/rootfs ou persistence.conf) montée sur la clé"
elif [[ -z "$PERSIST_UUID" ]]; then
    warn "partition de persistance sans UUID lisible"
fi

# --- 3. La racine écrit-elle réellement sur la clé ? ------------------------
CMDLINE="$(cat /proc/cmdline 2>/dev/null)"
say "Cmdline : ${CMDLINE:0:160}"
[[ "$CMDLINE" == *persist* ]] || warn "aucune option persist dans la cmdline"

CMDLINE_UUID="$(printf '%s' "$CMDLINE" | grep -oE '(^| )p?uuid=[^ ]+' | head -1 | cut -d= -f2)"
[[ -n "$CMDLINE_UUID" ]] && say "UUID demandé au noyau : $CMDLINE_UUID"
if [[ -n "$PERSIST_UUID" && -n "$CMDLINE_UUID" && "$PERSIST_UUID" != "$CMDLINE_UUID" ]]; then
    fail "UUID de persistance ($PERSIST_UUID) ≠ UUID demandé au noyau ($CMDLINE_UUID)"
fi

ROOT_OPTS="$(findmnt -rno FSTYPE,OPTIONS / 2>/dev/null)"
ROOT_FSTYPE="${ROOT_OPTS%% *}"
say "Racine : ${ROOT_FSTYPE:-inconnue}"
if [[ "$ROOT_FSTYPE" == "overlay" ]]; then
    ROOT_OVERLAY=1
    UPPER_DIR="$(printf '%s' "$ROOT_OPTS" | grep -oE 'upperdir=[^,]+' | cut -d= -f2)"
    say "upperdir : ${UPPER_DIR:-introuvable}"
    if [[ -z "$UPPER_DIR" ]]; then
        fail "racine overlay sans upperdir : persistance indémontrable"
    else
        REAL="$(df -P "$UPPER_DIR" 2>/dev/null | awk 'NR==2{print $1}')"
        say "support de l'upperdir : ${REAL:-inconnu}"
        # Un fichier de persistance MX est monté en boucle : le device vu par df
        # est /dev/loopN. On remonte au fichier porteur pour juger du support.
        if [[ "$REAL" == /dev/loop* ]]; then
            BACKING="$(cat "/sys/block/${REAL##*/}/loop/backing_file" 2>/dev/null)"
            say "fichier porteur (loop) : ${BACKING:-inconnu}"
            # Le fichier doit vivre sur une partition de la clé USB.
            BACK_DEV="$(df -P "$BACKING" 2>/dev/null | awk 'NR==2{print $1}')"
            say "partition portant ce fichier : ${BACK_DEV:-inconnu}"
            if is_on_usb "$BACK_DEV"; then
                PERSIST_ON_USB=1
            else
                fail "le fichier porteur ($BACKING) n'est pas sur la clé USB"
            fi
            # Cohérence : le fichier porteur doit être celui de PERSIST_PART.
            if [[ -n "$PERSIST_PART" && "$BACK_DEV" != "$PERSIST_PART" ]]; then
                fail "le fichier porteur est sur $BACK_DEV, pas sur la partition de persistance $PERSIST_PART"
            fi
        elif is_on_usb "$REAL"; then
            PERSIST_ON_USB=1
        else
            fail "l'upperdir ($REAL) n'est PAS sur la clé USB : les écritures ne survivront pas"
        fi
        say "persistance portée par la clé : $( (( ${PERSIST_ON_USB:-0} )) && echo OUI || echo NON )"
        AVAIL="$(df -h "$UPPER_DIR" 2>/dev/null | awk 'NR==2{print $4" dispo / "$2" ("$5" utilisé)"}')"
        n="$(find "$UPPER_DIR" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)"
        say "upperdir : $n entrée(s) déjà présentes"
        (( n == 0 )) && warn "upperdir vide : première session, aucune écriture antérieure prouvée"
    fi
else
    warn "racine non overlay ($ROOT_FSTYPE) : persistance non démontrable par cette méthode"
fi

# --- 4. Sonde d'écriture facultative, sur la clé uniquement ------------------
if (( WRITE_PROBE == 1 )); then
    if [[ -n "$UPPER_DIR" && -d "$UPPER_DIR" ]]; then
        probe="$(dirname "$UPPER_DIR")/p90-persist-probe"
        if printf '%s %s\n' "$(date -Is)" "$$" >"$probe" 2>/dev/null; then
            say "sonde écrite : $probe"
            warn "redémarrage requis pour prouver la survie de la sonde"
        else
            fail "sonde impossible : droits insuffisants ou partition en lecture seule"
        fi
    else
        fail "sonde impossible : upperdir inconnu"
    fi
fi

# --- 5. Contrôle SSD : aucun disque interne monté en écriture ---------------
for d in "${INTERNAL[@]}"; do
    if findmnt -rno SOURCE,OPTIONS 2>/dev/null | grep -E "^${d}" | grep -qE '(^|,)rw(,|$)'; then
        fail "$d (interne) est monté en lecture-écriture"
    fi
done
say "Aucune opération d'écriture effectuée sur les disques internes."

finish
