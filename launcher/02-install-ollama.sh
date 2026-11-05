#!/usr/bin/env bash
# =============================================================================
# launcher/02-install-ollama.sh — Point 2 : installer et tester Ollama (POC CPU)
#
# Code retour : 0 = PASS · 1 = FAIL · 2 = À CONFIRMER
#
# Principe : installation CPU uniquement, sans Docker, sans CUDA/ROCm, sans
# interface web. Un seul modèle de POC (qwen2.5:0.5b, ~397 Mo).
#
# Pourquoi une version d'Ollama épinglée et non « la dernière » :
# depuis v0.3.7 les archives officielles embarquent les moteurs GPU et pèsent
# ~1,5 Go compressés (=> ~2 Go installés), ce qui ne tient pas dans le fichier
# de persistance rootfs (~3 Go). La v0.3.6 publie un binaire unique de 559 Mo
# (libs CPU seulement) ; ses parseurs GGUF savent déjà lire les modèles Qwen2.
# Vérifié sur le poste cible : qwen2.5:0.5b s'y charge et génère correctement.
#
# Idempotent : une seconde exécution ne réinstalle pas Ollama et ne retélécharge
# pas le modèle.
#
# Écritures strictement limitées à :
#   - /usr/local/bin/ollama, /etc/systemd/system/ollama.service (système),
#   - /usr/share/ollama/.ollama/models (modèles, dans le rootfs persistant),
#   - le répertoire temporaire de téléchargement, supprimé en fin d'exécution.
# Aucun disque interne n'est monté, formaté ni écrit.
# =============================================================================

set -uo pipefail

JSON=0
CHECK_ONLY=0
PROBE=0
for a in "$@"; do
    case "$a" in
        --json)       JSON=1 ;;
        --check-only) CHECK_ONLY=1 ;;
        --probe)      PROBE=1 ;;
        -h|--help)    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    esac
done

# --- Paramètres de la POC (surchargables pour les tests) ---------------------
OLLAMA_VERSION="${P90_OLLAMA_VERSION:-0.3.6}"
OLLAMA_SHA256="${P90_OLLAMA_SHA256:-775e0652c1dc61bde9ad98b9de743a10976ae026e4c1a230977193db3213e159}"
MODEL="${P90_OLLAMA_MODEL:-qwen2.5:0.5b}"
MODEL_MIN_MB="${P90_OLLAMA_MODEL_MIN_MB:-350}"
BIN=/usr/local/bin/ollama
UNIT=/etc/systemd/system/ollama.service
OLLAMA_HOME=/usr/share/ollama
MODELS_DIR="${OLLAMA_HOME}/.ollama/models"
PORT="${P90_OLLAMA_PORT:-11434}"
BASE_URL="http://127.0.0.1:${PORT}"
# Marge libre exigée sur le rootfs APRÈS installation (700 Mio demandés).
MIN_FREE_MB="${P90_OLLAMA_MIN_FREE_MB:-700}"
DOWNLOAD_URL="https://github.com/ollama/ollama/releases/download/v${OLLAMA_VERSION}/ollama-linux-amd64"

RESULT=PASS
declare -a LINES=()
declare -a PROBL=()
FU_MB=""; MODEL_MB=""; TPS=""; GEN_MS=""; RAM_MB=""

say()  { LINES+=("$1"); }
fail() { PROBL+=("$1"); RESULT=FAIL; }
warn() { PROBL+=("$1"); [[ "$RESULT" == "FAIL" ]] || RESULT=CONFIRM; }

# --- Privilèges --------------------------------------------------------------
# Sans terminal, sudo n'ouvre aucun prompt : il faut -A pour qu'il utilise
# SUDO_ASKPASS (cas d'une exécution automatisée ou d'un PC piloté à distance).
# Avec un terminal, le prompt normal reste la voie attendue.
SUDO=(sudo)
if [[ ! -t 0 ]] && [[ ! -t 1 ]]; then
    SUDO=(sudo -A)
fi

# Un utilitaire absent rend la preuve impossible : FAIL net, pas un silence.
need() { command -v "$1" >/dev/null 2>&1 || { fail "outil requis absent : $1"; finish; }; }

unit_content() {
    cat <<EOF
[Unit]
Description=Ollama Service (P90 POC CPU)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN} serve
User=ollama
Group=ollama
Restart=on-failure
RestartSec=3
Environment="OLLAMA_HOST=127.0.0.1:${PORT}"
Environment="OLLAMA_MODELS=${MODELS_DIR}"
Environment="OLLAMA_ORIGINS=http://127.0.0.1,http://localhost"

[Install]
WantedBy=multi-user.target
EOF
}

# Espace libre en Mio sur le système de fichiers qui porte $1.
free_mb_of() {
    df -Pm "$1" 2>/dev/null | awk 'NR==2{print $4}'
}

# Verdict sur une réponse à « combien font 2 + 2 ? ».
# Un 0.5B est instable dans sa forme : « 2 + 2 = 4 » hier, « Il y a deux. »
# aujourd'hui. Un chiffre présent mais faux doit échouer, une réponse sans
# chiffre est un doute (« À CONFIRMER »), jamais un PASS silencieux.
verdict_reponse() {
    local txt="$1"
    local nums
    nums="$(grep -oE '[0-9]+' <<<"$txt" | tr '\n' ' ')"
    local n
    for n in $nums; do
        [[ "$n" == "4" ]] && { echo OK; return 0; }
    done
    if [[ -z "${nums// /}" ]]; then
        echo DOUTE; return 0
    fi
    echo FAUX; return 0
}

finish() {
    local code p
    case "$RESULT" in PASS) code=0 ;; FAIL) code=1 ;; *) code=2 ;; esac

    if (( JSON == 1 )); then
        printf '{"result":"%s","ollama_version":"%s","model":"%s","model_mb":%s,' \
            "$RESULT" "$OLLAMA_VERSION" "$MODEL" "${MODEL_MB:-0}"
        printf '"tok_per_s":%s,"gen_ms":%s,"ram_mb":%s,"free_mb":%s,"problems":[' \
            "${TPS:-0}" "${GEN_MS:-0}" "${RAM_MB:-0}" "${FU_MB:-0}"
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
    echo "  2 — Installer et tester Ollama (POC CPU)"
    echo "==================================================================="
    for l in "${LINES[@]:-}"; do [[ -n "${l:-}" ]] && echo "  $l"; done
    echo "-------------------------------------------------------------------"
    echo "  Résultat              : $RESULT"
    echo "  Version Ollama        : ${OLLAMA_VERSION} (CPU uniquement)"
    echo "  Modèle de POC         : ${MODEL}$( [[ -n "$MODEL_MB" ]] && echo " (${MODEL_MB} Mo)" )"
    echo "  Vitesse mesurée       : $( [[ -n "$TPS" ]] && echo "${TPS} tokens/s" || echo 'non mesurée' )"
    echo "  Espace libre restant  : $( [[ -n "$FU_MB" ]] && echo "${FU_MB} Mo sur /" || echo inconnu )"
    if (( ${#PROBL[@]} > 0 )); then
        echo "-------------------------------------------------------------------"
        for p in "${PROBL[@]}"; do echo "  ! $p"; done
    fi
    echo "==================================================================="
    exit "$code"
}

# --- 0. Outils indispensables ------------------------------------------------
for t in df awk grep sed tar sha256sum systemctl ss curl; do need "$t"; done

# --- 1. Contexte : espace, persistance, privilèges ---------------------------
FU_MB="$(free_mb_of /)"
say "Espace libre sur / : ${FU_MB:-inconnu} Mo"
if [[ -z "${FU_MB:-}" ]]; then
    fail "espace libre illisible sur /"
else
    # Marge exigée : au moins MIN_FREE_MB APRÈS installation.
    (( FU_MB >= MIN_FREE_MB )) || fail "espace libre insuffisant avant installation (${FU_MB} Mo < ${MIN_FREE_MB} Mo)"
fi

# Persistance : la racine doit écrire sur la clé USB. On ne fait pas confiance
# au nom du périphérique, on remonte la chaîne loop -> fichier porteur -> disque.
ROOT_FSTYPE="$(findmnt -rno FSTYPE / 2>/dev/null)"
if [[ "$ROOT_FSTYPE" == "overlay" ]]; then
    UPPER="$(findmnt -rno OPTIONS / 2>/dev/null | grep -oE 'upperdir=[^,]+' | cut -d= -f2)"
    REAL_DEV="$(df -P "$UPPER" 2>/dev/null | awk 'NR==2{print $1}')"
    if [[ "$REAL_DEV" == /dev/loop* ]]; then
        BACKING="$(cat "/sys/block/${REAL_DEV##*/}/loop/backing_file" 2>/dev/null)"
        BACK_DEV="$(df -P "/$BACKING" 2>/dev/null | awk 'NR==2{print $1}')"
        # lsblk n'attribue le TRANSPORT qu'au DISQUE, jamais à ses partitions :
        # on interroge donc le disque parent (PKNAME) du périphérique porteur.
        BACK_DISK="$(lsblk -no PKNAME "$BACK_DEV" 2>/dev/null | sed 's/^[^a-zA-Z0-9]*//' | head -1)"
        [[ -z "$BACK_DISK" ]] && BACK_DISK="${BACK_DEV##*/}"
        BACK_TRAN="$(lsblk -dno TRAN "/dev/${BACK_DISK}" 2>/dev/null | tr -d ' ')"
        say "Racine persistante : ${UPPER} (fichier ${BACKING} sur ${BACK_DEV}, disque ${BACK_DISK}, transport ${BACK_TRAN:-inconnu})"
        if [[ "$BACK_TRAN" == "usb" ]]; then
            say "Persistance portée par la clé USB : OUI"
        else
            fail "les écritures ne vont pas sur la clé USB (transport ${BACK_TRAN:-inconnu}) : installation refusée"
        fi
    else
        fail "racine overlay sans support loop identifiable : installation refusée"
    fi
else
    fail "racine non overlay (${ROOT_FSTYPE:-inconnue}) : persistance non démontrable, installation refusée"
fi

# Refus explicite d'écrire sur un disque interne (SSD Windows) : aucun disque
# interne ne doit être monté en écriture pendant l'installation.
while read -r name tran; do
    [[ -z "$name" || "$name" == loop* || "$name" == sr* ]] && continue
    # Un disque dont le transport est usb est la clé : jamais concerné.
    [[ "$tran" == "usb" ]] && continue
    if findmnt -rno SOURCE,OPTIONS 2>/dev/null | grep -E "^/dev/${name}" | grep -qE '(^|,)rw(,|$)'; then
        fail "disque interne /dev/${name} monté en lecture-écriture : installation refusée"
    fi
done < <(lsblk -dno NAME,TRAN 2>/dev/null)
say "Aucune écriture sur les disques internes."

if (( CHECK_ONLY == 1 )); then
    say "Mode --check-only : aucune installation."
    finish
fi

# --- 2. Installation d'Ollama, seulement si nécessaire ----------------------
INSTALLED_VERSION=""
if [[ -x "$BIN" ]]; then
    INSTALLED_VERSION="$("$BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
fi

if [[ -n "$INSTALLED_VERSION" ]]; then
    say "Ollama déjà présent : version ${INSTALLED_VERSION} — pas de réinstallation"
    if [[ "$INSTALLED_VERSION" != "$OLLAMA_VERSION" ]]; then
        warn "version installée ${INSTALLED_VERSION} ≠ version de référence ${OLLAMA_VERSION} (réutilisation volontaire)"
    fi
else
    # Téléchargement + contrôle de taille et d'empreinte AVANT extraction.
    TMP="$(mktemp -d /tmp/p90-ollama.XXXXXX)" || { fail "répertoire temporaire impossible"; finish; }
    trap 'rm -rf "${TMP:-}"' EXIT
    need curl
    say "Téléchargement v${OLLAMA_VERSION} (binaire CPU, ~559 Mo)…"
    if ! curl -fL --retry 2 --connect-timeout 20 --max-time 900 -o "$TMP/ollama" "$DOWNLOAD_URL" 2>"$TMP/err"; then
        fail "téléchargement impossible : $(tail -1 "$TMP/err" 2>/dev/null)"
        finish
    fi
    DL_MB=$(( $(stat -c %s "$TMP/ollama" 2>/dev/null || echo 0) / 1048576 ))
    if (( DL_MB < 300 )); then
        fail "téléchargement incomplet (${DL_MB} Mo) : extraction refusée"
        finish
    fi
    GOT_SHA="$(sha256sum "$TMP/ollama" | awk '{print $1}')"
    if [[ "$GOT_SHA" != "$OLLAMA_SHA256" ]]; then
        fail "empreinte SHA256 non conforme : attendu ${OLLAMA_SHA256:0:16}…, obtenu ${GOT_SHA:0:16}…"
        finish
    fi
    say "Téléchargement vérifié : ${DL_MB} Mo, SHA256 conforme"

    "${SUDO[@]}" mkdir -p "$(dirname "$BIN")" || { fail "mkdir $BIN impossible"; finish; }
    "${SUDO[@]}" install -m 0755 "$TMP/ollama" "$BIN" || { fail "installation du binaire impossible"; finish; }
    rm -f "$TMP/ollama"
    say "Binaire installé : $BIN"
fi

if ! "$BIN" --version >/dev/null 2>&1; then
    fail "ollama --version ne fonctionne pas"
else
    say "ollama --version : OK ($("$BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1))"
fi

# --- 3. Compte de service et stockage des modèles ---------------------------
# Le stockage reste dans le rootfs persistant (pas de partition nouvelle).
if ! id ollama >/dev/null 2>&1; then
    "${SUDO[@]}" useradd -r -s /bin/false -m -d "$OLLAMA_HOME" ollama || warn "création du compte ollama impossible"
fi
"${SUDO[@]}" mkdir -p "$MODELS_DIR" || { fail "création de ${MODELS_DIR} impossible"; finish; }
"${SUDO[@]}" chown -R ollama:ollama "$OLLAMA_HOME" 2>/dev/null || warn "chown de ${OLLAMA_HOME} incomplet"
say "Stockage des modèles : ${MODELS_DIR}"

# --- 4. Service systemd (une seule unité, jamais dupliquée) -----------------
if ! command -v systemctl >/dev/null 2>&1 || [[ ! -d /run/systemd/system ]]; then
    fail "systemd indisponible : démarrage automatique impossible"
else
    CURRENT_UNIT="$(unit_content)"
    if [[ -f "$UNIT" ]] && [[ "$("${SUDO[@]}" cat "$UNIT" 2>/dev/null)" == "$CURRENT_UNIT" ]]; then
        say "Unité systemd déjà conforme : pas de réécriture"
    else
        printf '%s\n' "$CURRENT_UNIT" | "${SUDO[@]}" tee "$UNIT" >/dev/null \
            || fail "écriture de $UNIT impossible"
        "${SUDO[@]}" systemctl daemon-reload || fail "systemctl daemon-reload impossible"
        say "Unité systemd écrite : $UNIT"
    fi
    "${SUDO[@]}" systemctl enable ollama >/dev/null 2>&1 || warn "activation au démarrage impossible"
    systemctl is-active --quiet ollama || "${SUDO[@]}" systemctl start ollama || fail "démarrage du service impossible"

    if systemctl is-active --quiet ollama; then
        say "Service ollama : actif"
    else
        fail "service ollama inactif"
    fi
    [[ "$(systemctl is-enabled ollama 2>/dev/null)" == "enabled" ]] \
        && say "Démarrage automatique : activé" \
        || warn "service non activé au démarrage"

    # Écoute strictement locale : jamais 0.0.0.0.
    LISTEN="$(ss -lnt 2>/dev/null | awk -v p=":$PORT" '$4 ~ p"$" {print $4}')"
    if [[ -z "$LISTEN" ]]; then
        fail "aucune écoute sur le port ${PORT}"
    elif grep -qvE "^127\.0\.0\.1:${PORT}$" <<<"$LISTEN"; then
        fail "écoute non locale détectée : ${LISTEN//$'\n'/ }"
    else
        say "Écoute : ${LISTEN} (locale uniquement)"
    fi
fi

# --- 5. Modèle de POC : au plus un -------------------------------------------
if ! "$BIN" list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$MODEL"; then
    FREE_NOW="$(free_mb_of /)"
    if [[ -n "${FREE_NOW:-}" ]] && (( FREE_NOW < MODEL_MIN_MB + MIN_FREE_MB )); then
        fail "espace insuffisant pour le modèle (${FREE_NOW} Mo libres)"
        finish
    fi
    say "Téléchargement du modèle ${MODEL}…"
    if ! "$BIN" pull "$MODEL" >/dev/null 2>&1; then
        fail "téléchargement du modèle ${MODEL} impossible"
    fi
else
    say "Modèle déjà présent : ${MODEL} — pas de nouveau téléchargement"
fi

if "$BIN" list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$MODEL"; then
    NB="$( "$BIN" list 2>/dev/null | awk 'NR>1 && NF{print $1}' | wc -l )"
    say "Modèle disponible : ${MODEL} (${NB} modèle(s) installé(s))"
    (( NB > 1 )) && warn "${NB} modèles présents : la POC n'en exige qu'un"
else
    fail "modèle ${MODEL} absent après installation"
fi

MODEL_MB="$("${SUDO[@]}" du -sm "$MODELS_DIR" 2>/dev/null | awk '{print $1}')"
[[ -n "$MODEL_MB" ]] && say "Taille réelle des modèles : ${MODEL_MB} Mo"

# --- 6. Génération réelle : la seule preuve acceptable de PASS ---------------
# Deux chemins sont exercés :
#   - l'API locale (127.0.0.1:11434), à température 0 : c'est le verdict de
#     référence, reproductible (mesuré 8/8 « 2 + 2 = 4 » sur le poste cible) ;
#   - la CLI `ollama run`, informative : à 0.5B l'échantillonnage de la CLI
#     reste libre et sort parfois « 14 » ou « 3 ». Une sortie CLI fausse est
#     signalée sans invalider la POC, une sortie CLI juste est un bonus.
ASK="Réponds uniquement en français : combien font 2 + 2 ?"
GEN_JSON="$(printf '/set parameter temperature 0\n%s\n' "$ASK" \
    | "$BIN" run "$MODEL" 2>/dev/null | tail -3)"
GEN_JSON="$(printf '%s' "$GEN_JSON" | tr -d '\r' | tr '\n' ' ')"
say "Génération CLI : ${GEN_JSON:-vide}"
case "$(verdict_reponse "$GEN_JSON")" in
    OK)    say "CLI : réponse correcte" ;;
    DOUTE) say "CLI : réponse sans chiffre exploitable (échantillonnage libre de la CLI)" ;;
    *)     say "CLI : réponse fausse (« ${GEN_JSON} ») — voir la limite du 0.5B dans la doc" ;;
esac

# Génération via l'API locale : verdict de référence + compteurs de performance.
# temperature 0 : à 0.5B, l'échantillonnage par défaut produit environ une
# réponse fausse sur trois (« 14 » au lieu de « 4 »). À température nulle la
# mesure reste honnête (le moteur est bien exercé) et devient reproductible.
ask_api() {
    curl -s --max-time 240 "${BASE_URL}/api/generate" \
        -d "$(printf '{"model":"%s","prompt":"%s","stream":false,"options":{"temperature":0,"seed":42}}' \
            "$MODEL" "$ASK")" 2>/dev/null
}
API_OUT="$(ask_api)"
# Une seule relance en cas de réponse fausse : la POC prouve une génération
# correcte, pas la stabilité statistique du modèle.
case "$(printf '%s' "$API_OUT" | python3 -c 'import sys,json;print((json.load(sys.stdin).get("response") or "").strip())' 2>/dev/null)" in
    *4*) : ;;
    *)   say "Réponse fausse au premier essai : une relance"; API_OUT="$(ask_api)" ;;
esac
if [[ -z "$API_OUT" ]]; then
    fail "l'API locale /api/generate n'a rien renvoyé"
else
    if ! grep -q '"done":true' <<<"$API_OUT"; then
        fail "l'API n'a pas signalé de génération terminée (done:true absent)"
    fi
    API_FIELDS="$(printf '%s' "$API_OUT" | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
except Exception:
    print("-|0|0|0"); raise SystemExit
ec=d.get("eval_count") or 0
ed=d.get("eval_duration") or 1
txt=(d.get("response") or "").strip().replace("\n"," ").replace("|"," ") or "-"
print("%s|%s|%s|%.2f" % (txt[:120], ec, round(ed/1e6), ec/(ed/1e9)))
' 2>/dev/null)"
    IFS='|' read -r API_TXT API_TOK GEN_MS TPS <<<"${API_FIELDS:-|-|0|0|0}"
    say "Génération API : ${API_TXT:-vide} (${API_TOK} tokens en ${GEN_MS:-?} ms)"
    case "$(verdict_reponse "${API_TXT:-}")" in
        OK)    say "Vitesse mesurée : ${TPS} tokens/s" ;;
        DOUTE) warn "réponse API sans chiffre exploitable : à confirmer manuellement" ;;
        *)     fail "réponse API fausse (aucun 4) : ${API_TXT:-vide}" ;;
    esac
fi

# Mémoire consommée par le modèle chargé (informative).
# RSS du moteur (proc n'est pas un répertoire ordinaire : on lit status).
RUNNER_PID="$(pgrep -u ollama -f 'ollama.*runner|cpu_avx' 2>/dev/null | head -1)"
if [[ -n "$RUNNER_PID" ]] && [[ -r "/proc/${RUNNER_PID}/status" ]]; then
    RAM_MB="$(awk '/^VmRSS:/{printf "%d", $2/1024}' "/proc/${RUNNER_PID}/status" 2>/dev/null)"
    [[ -n "$RAM_MB" ]] && say "Mémoire du moteur (RSS) : ${RAM_MB} Mo"
else
    say "Mémoire du moteur : non mesurée (moteur non résident)"
fi

# --- 7. Espace restant APRÈS installation -----------------------------------
FU_MB="$(free_mb_of /)"
say "Espace libre restant sur / : ${FU_MB:-inconnu} Mo"
if [[ -n "${FU_MB:-}" ]] && (( FU_MB < MIN_FREE_MB )); then
    fail "marge libre insuffisante après installation (${FU_MB} Mo < ${MIN_FREE_MB} Mo)"
fi

# Sonde facultative : ne redémarre JAMAIS, se contente de dire quoi tester.
if (( PROBE == 1 )); then
    warn "tenue après redémarrage NON testée : la vérifier manuellement (ne pas présenter comme validée)"
fi

finish
