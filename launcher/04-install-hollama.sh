#!/usr/bin/env bash
# =============================================================================
# launcher/04-install-hollama.sh — Point 4 : installer / lancer Hollama
#
# Code retour : 0 = PASS · 1 = FAIL · 2 = BLOCKED
#
# Hollama est un client graphique (Electron) pour Ollama. Cette étape l'installe
# dans le compte de l'utilisateur, sans root : ~/.local/opt/hollama.
#
# Principe : le modèle reste sur le serveur. Hollama ne fait que consommer une
# API Ollama (locale par défaut, distante en option, modifiable à chaud).
#
# Idempotent : une seconde exécution réutilise l'installation si la version et
# l'empreinte correspondent ; sinon elle réinstalle proprement.
#
# Écritures strictement limitées à :
#   - ~/.local/opt/hollama (application),
#   - ~/.local/bin/hollama (lien),
#   - ~/.local/share/applications/hollama.desktop (raccourci),
#   - ~/.config/hollama (état de l'application).
# Aucun disque interne, aucun partitionnement, aucun GRUB/EFI, aucun redémarrage,
# aucun nouveau modèle, aucun Docker.
#
# Options :
#   --json            sortie machine
#   --check-only      diagnostic complet, AUCUNE écriture
#   --launch          lance Hollama après installation
#   --server <url>    serveur Ollama à préconfigurer (défaut http://127.0.0.1:11434)
# =============================================================================

set -uo pipefail

JSON=0
CHECK_ONLY=0
LAUNCH=0
SERVER_URL="http://127.0.0.1:11434"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)       JSON=1 ;;
        --check-only) CHECK_ONLY=1 ;;
        --launch)     LAUNCH=1 ;;
        --server)     SERVER_URL="${2:-}"; shift ;;
        -h|--help)    sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            echo "Option inconnue : $1" >&2; exit 1 ;;
    esac
    shift
done

# --- Paramètres (surchargables pour les tests) -------------------------------
HVER="${P90_HOLLAMA_VERSION:-0.37.0}"
# Empreinte relevée sur l'archive officielle le 2026-11-05. La publication
# Linux ne fournit pas de somme de contrôle (latest.yml ne couvre que Windows) :
# on épingle donc localement, ce qui permet de détecter toute substitution.
HSHA="${P90_HOLLAMA_SHA256:-1ed38ed090339238c4c602a4e46a234aa5fbd31df66eac24dcc8f8756fabc921}"
APP_DIR="$HOME/.local/opt/hollama"
BIN="$APP_DIR/hollama"
LINK="$HOME/.local/bin/hollama"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP="$DESKTOP_DIR/hollama.desktop"
# Taille extraite mesurée : 297 Mo. Marge exigée pour ne pas saturer la clé.
NEED_MB="${P90_HOLLAMA_NEED_MB:-380}"
ARCH="linux-x64"
URL="https://github.com/fmaclen/hollama/releases/download/${HVER}/Hollama_${HVER}-${ARCH}.tar.gz"

RESULT=PASS
declare -a LINES=() PROBL=()
APP_MB=""; FREE_MB=""; MODEL=""; VER_INSTALLED=""; LAUNCHED=""

say()  { LINES+=("$1"); }
fail() { PROBL+=("$1"); RESULT=FAIL; }
block(){ PROBL+=("$1"); RESULT=BLOCKED; }
warn() { PROBL+=("$1"); [[ "$RESULT" == "PASS" ]] && RESULT=BLOCKED || true; }

finish() {
    local code p
    case "$RESULT" in PASS) code=0 ;; BLOCKED) code=2 ;; *) code=1 ;; esac

    if (( JSON == 1 )); then
        printf '{"result":"%s","version":"%s","app_mb":%s,"free_mb":%s,' \
            "$RESULT" "$HVER" "${APP_MB:-0}" "${FREE_MB:-0}"
        printf '"server":"%s","model":"%s","launched":%s,"problems":[' \
            "$SERVER_URL" "${MODEL:-}" "$( [[ "$LAUNCHED" == "1" ]] && echo true || echo false )"
        local first=1
        for p in "${PROBL[@]:-}"; do
            [[ -z "${p:-}" ]] && continue
            (( first )) || printf ','
            first=0
            printf '"%s"' "${p//\"/\\\"}"
        done
        printf ']}\n'
        exit "$code"
    fi

    echo "==================================================================="
    echo "  4 — Installer / lancer Hollama (client IA distant)"
    echo "==================================================================="
    for l in "${LINES[@]:-}"; do [[ -n "${l:-}" ]] && echo "  $l"; done
    echo "-------------------------------------------------------------------"
    echo "  Résultat              : $RESULT"
    echo "  Hollama               : ${HVER} dans ${APP_DIR}"
    echo "  Taille de l'app       : $( [[ -n "$APP_MB" ]] && echo "${APP_MB} Mo" || echo inconnue )"
    echo "  Espace libre restant  : $( [[ -n "$FREE_MB" ]] && echo "${FREE_MB} Mo sur /" || echo inconnu )"
    echo "  Serveur Ollama        : ${SERVER_URL}"
    echo "  Modèle servi          : ${MODEL:-inconnu}"
    if (( ${#PROBL[@]} > 0 )); then
        echo "-------------------------------------------------------------------"
        for p in "${PROBL[@]}"; do echo "  ! $p"; done
    fi
    echo "==================================================================="
    exit "$code"
}

(( CHECK_ONLY == 1 )) && say "Mode --check-only : aucune écriture."

# --- 1. Prérequis ------------------------------------------------------------
free_mb_of() { df -Pm "$1" 2>/dev/null | awk 'NR==2{print $4}'; }
FREE_MB="$(free_mb_of "$HOME")"
[[ -n "$FREE_MB" ]] && say "Espace libre : ${FREE_MB} Mo sur $HOME"

# Persistance : l'application doit vivre sur la clé USB persistante, sinon elle
# disparaît au redémarrage — ce qui viderait l'étape de son sens.
if grep -qoE 'persist=[^ ]*' /proc/cmdline 2>/dev/null; then
    say "Persistance active : $(grep -oE 'persist=[^ ]*' /proc/cmdline | head -1)"
else
    block "aucune persistance détectée dans /proc/cmdline : l'installation serait perdue au redémarrage"
fi

# --- 2. Ollama doit répondre (le client ne sert à rien sans serveur) ---------
OLLAMA_URL="${SERVER_URL%/}"
if curl -fsS -m 6 "${OLLAMA_URL}/api/version" >/dev/null 2>&1; then
    say "Serveur Ollama joignable : ${OLLAMA_URL}"
    MODEL="$(curl -fsS -m 6 "${OLLAMA_URL}/api/tags" 2>/dev/null \
        | python3 -c 'import sys,json;d=json.load(sys.stdin);m=d.get("models") or [];print(m[0]["name"] if m else "")' 2>/dev/null)"
    if [[ -n "$MODEL" ]]; then
        say "Modèle détecté sur le serveur : ${MODEL}"
    else
        block "serveur Ollama joignable mais aucun modèle installé : voyez l'étape 2"
    fi
else
    block "serveur Ollama injoignable à ${OLLAMA_URL} : installez-le d'abord (étape 2)"
fi

# --- 3. Session graphique ----------------------------------------------------
# Une application Electron exige un serveur X accessible ET un bus de session.
if [[ -z "${DISPLAY:-}" ]]; then
    # Contexte SSH : on tente la session locale de l'utilisateur, sans l'inventer.
    if [[ -S /tmp/.X11-unix/X0 ]]; then
        export DISPLAY=:0
        [[ -z "${XAUTHORITY:-}" && -f "$HOME/.Xauthority" ]] && export XAUTHORITY="$HOME/.Xauthority"
        say "Session graphique trouvée : DISPLAY=:0 (héritée de la session locale)"
    else
        block "aucune session graphique (DISPLAY absent, /tmp/.X11-unix/X0 absent)"
    fi
else
    say "Session graphique : DISPLAY=${DISPLAY}"
fi
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && [[ -S "/run/user/$(id -u)/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

# Dépendances Electron (GTK/NSS...). On interroge la bibliothèque elle-même :
# `ldconfig -p` dépend d'un cache qui peut être vide dans une session SSH, ce
# qui produit de faux « manquant » (constaté).
missing=""
for so in libgtk-3.so.0 libnss3.so libasound.so.2 libgbm.so.1; do
    python3 -c "import ctypes;ctypes.CDLL('$so')" >/dev/null 2>&1 \
        || missing="$missing $so"
done
if [[ -n "$missing" ]]; then
    block "bibliothèques Electron absentes :${missing} (paquet graphique incomplet)"
else
    say "Dépendances Electron : présentes (GTK3, NSS, ALSA, GBM)"
fi

# --- 4. Espace : refus explicite plutôt que clé pleine -----------------------
if [[ -n "$FREE_MB" ]] && (( FREE_MB < NEED_MB )); then
    if [[ -d "$APP_DIR" ]]; then
        warn "espace faible (${FREE_MB} Mo < ${NEED_MB} Mo) mais Hollama déjà installé"
    else
        block "espace insuffisant : ${FREE_MB} Mo libres, ${NEED_MB} Mo requis"
    fi
fi

# --- 5. Installation (ou réutilisation) --------------------------------------
installed_ver() {
    [[ -x "$BIN" ]] || { echo ""; return; }
    # Le binaire Electron ne répond pas à --version (il démarre l'application) :
    # on lit la version dans la configuration écrite par l'application elle-même
    # puis dans les ressources, sans lancer de processus graphique.
    local cfg="$HOME/.config/hollama/Local Storage/leveldb"
    local v=""
    if [[ -d "$cfg" ]]; then
        v="$(strings "$cfg"/*.log 2>/dev/null \
             | grep -o '"currentVersion":"[0-9.]*"' | head -1 | cut -d'"' -f4)"
    fi
    if [[ -z "$v" ]]; then
        v="$(grep -aoE '"version":"[0-9]+\.[0-9]+\.[0-9]+"' "$APP_DIR/resources/app.asar" 2>/dev/null \
             | head -1 | cut -d'"' -f4)"
    fi
    echo "$v"
}

if [[ -x "$BIN" ]]; then
    VER_INSTALLED="$(installed_ver)"
    APP_MB="$(du -sm "$APP_DIR" 2>/dev/null | awk '{print $1}')"
    if [[ "$VER_INSTALLED" == "$HVER" ]]; then
        say "Hollama déjà installé (${VER_INSTALLED}, ${APP_MB} Mo) : pas de réinstallation"
    else
        say "Hollama présent (${VER_INSTALLED:-version inconnue}) : mise à jour vers ${HVER}"
    fi
fi

if (( CHECK_ONLY == 0 )); then
    if [[ "$VER_INSTALLED" != "$HVER" ]]; then
        command -v curl >/dev/null 2>&1 || fail "curl absent"
        command -v tar  >/dev/null 2>&1 || fail "tar absent"
        if [[ "$RESULT" != "FAIL" ]]; then
            TMP="$(mktemp -d "${TMPDIR:-/tmp}/p90-hollama.XXXXXX")" || { fail "répertoire temporaire impossible"; finish; }
            trap 'rm -rf "${TMP:-}"' EXIT
            say "Téléchargement ${HVER} (~126 Mo)…"
            if ! curl -fsSL --retry 2 --connect-timeout 20 --max-time 900 \
                    -o "$TMP/h.tar.gz" "$URL" 2>"$TMP/err"; then
                fail "téléchargement impossible : $(tail -1 "$TMP/err" 2>/dev/null)"
                finish
            fi
            GOT="$(sha256sum "$TMP/h.tar.gz" | awk '{print $1}')"
            if [[ "$GOT" != "$HSHA" ]]; then
                fail "empreinte SHA256 non conforme (attendu ${HSHA:0:16}…, obtenu ${GOT:0:16}…)"
                finish
            fi
            say "Archive vérifiée : SHA256 conforme"

            mkdir -p "$APP_DIR.new"
            rm -rf "${APP_DIR:?}.new"; mkdir -p "${APP_DIR}.new"
            if ! tar xzf "$TMP/h.tar.gz" -C "${APP_DIR}.new" --strip-components=1; then
                fail "extraction impossible"
                finish
            fi
            chmod +x "${APP_DIR}.new/hollama"
            APP_MB="$(du -sm "${APP_DIR}.new" 2>/dev/null | awk '{print $1}')"
            # Remplacement atomique : l'ancienne version n'est retirée qu'une fois
            # la nouvelle extraite, pour ne jamais laisser d'installation partielle.
            rm -rf "$APP_DIR"
            mv "${APP_DIR}.new" "$APP_DIR"
            say "Installation terminée : ${APP_MB} Mo dans ${APP_DIR}"
        fi
    fi

    mkdir -p "$(dirname "$LINK")"
    ln -sfn "$BIN" "$LINK"
    say "Lien créé : ${LINK}"

    # --- 6. Lanceur graphique ------------------------------------------------
    # L'archive officielle ne contient AUCUNE icône hors de app.asar (vérifié :
    # resources/ n'a que app.asar et app-update.yml). On l'extrait du bundle
    # plutôt que de pointer vers un fichier inexistant — un Exec valide avec une
    # Icon fantôme donne un raccourci sans image.
    # L'icône embarquée mesure 62x64 : on la place dans le thème à sa taille
    # réelle plutôt que de prétendre à du 256x256.
    ICON_DIR="$HOME/.local/share/icons/hicolor/64x64/apps"
    ICON="$ICON_DIR/hollama.png"
    if (( CHECK_ONLY == 0 )); then
        mkdir -p "$ICON_DIR"
        python3 - "$APP_DIR/resources/app.asar" "$ICON" <<'PYEOF' 2>/dev/null || true
import json, struct, sys
src, dst = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()
# Format asar (pickle) : [0]=4, [4]=header_size, [8]=json_len, [12]=?_,
# le JSON commence à 16 et les données à 8+header_size. Utiliser 16+json_len
# décale la lecture de 4 octets (PNG amputé de sa signature).
_h, hs, _j, js = struct.unpack('<4I', d[:16])
hdr = json.loads(d[16:16 + js].decode('utf-8', errors='replace'))
base = 8 + hs
node = hdr
for part in 'build/client/favicon.png'.split('/'):
    node = node['files'][part]
off = int(node['offset']); size = int(node['size'])
blob = d[base + off:base + off + size]
# Ne pas installer un fichier corrompu : on vérifie la signature PNG.
if blob[:8] == b'\x89PNG\r\n\x1a\n':
    open(dst, 'wb').write(blob)
else:
    raise SystemExit(1)
PYEOF
        if [[ -s "$ICON" ]]; then
            say "Icône extraite : ${ICON}"
        else
            warn "icône non extraite : le raccourci utilisera l'icône par défaut"
        fi
    fi

    mkdir -p "$DESKTOP_DIR"
    # Une seule catégorie principale (Education) : plusieurs catégories
    # principales font apparaître l'application en double dans le menu.
    cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Hollama
Name[fr]=Hollama
Comment=Client IA — conversation avec un serveur Ollama
Comment[fr]=Client IA — conversation avec un serveur Ollama
Exec=${BIN} %U
Icon=${ICON}
Terminal=false
Categories=Education;
StartupWMClass=hollama
EOF
    chmod +x "$DESKTOP"
    say "Raccourci créé : ${DESKTOP}"
    command -v update-desktop-database >/dev/null 2>&1 \
        && update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

FREE_MB="$(free_mb_of "$HOME")"
say "Espace libre après installation : ${FREE_MB:-inconnu} Mo"

# --- 7. Lancement (facultatif) ----------------------------------------------
if (( CHECK_ONLY == 0 )) && (( LAUNCH == 1 )); then
    if [[ -z "${DISPLAY:-}" ]]; then
        block "lancement demandé mais aucune session graphique"
    elif pgrep -f "local/opt/hollama/hollama" >/dev/null 2>&1; then
        say "Hollama déjà en cours d'exécution"
        LAUNCHED=1
    else
        setsid "$BIN" --no-sandbox </dev/null >"${TMPDIR:-/tmp}/hollama.log" 2>&1 &
        disown 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
            sleep 1
            pgrep -f "local/opt/hollama/hollama" >/dev/null 2>&1 && { LAUNCHED=1; break; }
        done
        if [[ "$LAUNCHED" == "1" ]]; then
            say "Hollama lancé sur ${DISPLAY}"
        else
            fail "Hollama ne démarre pas (voir ${TMPDIR:-/tmp}/hollama.log)"
        fi
    fi
fi

# --- 8. Rappels de cadre -----------------------------------------------------
say "Le modèle n'est PAS téléchargé par Hollama : il reste sur le serveur Ollama."
say "Hollama peut télécharger des modèles : la restriction doit être faite côté serveur (étape 3)."

finish
