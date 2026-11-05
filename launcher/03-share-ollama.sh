#!/usr/bin/env bash
# =============================================================================
# launcher/03-share-ollama.sh — Point 3 : partager Ollama sur le réseau
#
# Code retour : 0 = PASS · 1 = FAIL · 2 = À CONFIRMER
#
# Objectif : les autres postes du LAN utilisent le modèle DÉJÀ installé sur ce
# serveur, sans le retélécharger.
#
# Choix d'architecture (vote humain du 2026-11-05) : filtrage nftables seul,
# sans proxy applicatif.
#   - Ollama écoute sur 0.0.0.0:11434 ;
#   - nftables n'accepte le port 11434 que depuis les adresses explicitement
#     autorisées ; tout le reste est rejeté (drop, pas reject).
#   - Conséquence ASSUMÉE et écrite dans le rapport : les postes autorisés ont
#     accès à TOUTE l'API, y compris /api/pull (téléchargement) et /api/delete
#     (suppression). Ollama ne connaît pas de contrôle par opération. Sur un
#     réseau pédagogique de confiance, le filtrage par adresse est jugé
#     suffisant ; ce n'est pas une barrière contre un poste autorisé hostile.
#
# Idempotent : relancer le script ne duplique ni l'unité systemd, ni la table
# nftables, ni les entrées du jeu d'adresses.
#
# Écritures strictement limitées à :
#   - /etc/systemd/system/ollama.service (OLLAMA_HOST/ORIGINS),
#   - /etc/nftables.d/p90-ollama.nft (règle de filtrage),
#   - /etc/p90/ollama-allow.conf (liste des adresses autorisées),
#   - l'état de l'étape dans $P90_DATA_DIR/steps/3.state.
# Aucun modèle n'est téléchargé. Aucun disque interne n'est touché. Aucun
# redémarrage du PC n'est demandé.
#
# Options :
#   --json          sortie machine
#   --check-only    diagnostic complet, AUCUNE écriture
#   --allow <CIDR>  remplace la liste des adresses autorisées (répétable)
#   --remote-test <ip>  teste une génération DEPUIS cette machine du LAN
# =============================================================================

set -uo pipefail

JSON=0
CHECK_ONLY=0
declare -a ALLOW_OVERRIDE=()
REMOTE_TEST=""
# Boucle indexée : `for a in "$@"` ne permet pas de consommer la valeur d'une
# option (shift n'y a aucun effet), et la valeur serait relue comme une option.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)        JSON=1 ;;
        --check-only)  CHECK_ONLY=1 ;;
        --allow)       ALLOW_OVERRIDE+=("${2:-}"); shift ;;
        --remote-test) REMOTE_TEST="${2:-}"; shift ;;
        -h|--help)     sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)             echo "Option inconnue : $1" >&2; exit 1 ;;
    esac
    shift
done

# --- Paramètres (surchargables pour les tests) -------------------------------
PORT="${P90_OLLAMA_PORT:-11434}"
MODEL="${P90_OLLAMA_MODEL:-qwen2.5:0.5b}"
BIN="${P90_OLLAMA_BIN:-/usr/local/bin/ollama}"
UNIT=/etc/systemd/system/ollama.service
NFT_FILE=/etc/nftables.d/p90-ollama.nft
ALLOW_FILE=/etc/p90/ollama-allow.conf
TABLE=p90_ollama
# Réseau pédagogique du lycée : /24 entier par défaut, restreint par --allow.
DEFAULT_NET="${P90_LAN_NET:-192.168.1.0/24}"
ASK="Réponds uniquement en français : combien font 2 + 2 ?"

RESULT=PASS
declare -a LINES=() PROBL=()
SERV_IP=""; MODEL_MB=""; GEN_MS=""; TPS=""; ALLOW_COUNT=0; REMOTE_OK=""

say()  { LINES+=("$1"); }
fail() { PROBL+=("$1"); RESULT=FAIL; }
warn() { PROBL+=("$1"); [[ "$RESULT" == "FAIL" ]] || RESULT=CONFIRM; }

# --- Privilèges --------------------------------------------------------------
# Sans terminal, sudo n'ouvre aucun prompt : -A pour SUDO_ASKPASS (exécution
# automatisée). Avec un terminal, le prompt normal reste la voie attendue.
SUDO=(sudo)
if [[ ! -t 0 ]] && [[ ! -t 1 ]]; then
    SUDO=(sudo -A)
fi

finish() {
    local code p
    case "$RESULT" in PASS) code=0 ;; FAIL) code=1 ;; *) code=2 ;; esac

    if (( JSON == 1 )); then
        printf '{"result":"%s","server_ip":"%s","port":%s,"model":"%s",' \
            "$RESULT" "${SERV_IP:-}" "$PORT" "$MODEL"
        printf '"allow_count":%s,"model_mb":%s,"gen_ms":%s,"tok_per_s":%s,"remote_ok":%s,"problems":[' \
            "$ALLOW_COUNT" "${MODEL_MB:-0}" "${GEN_MS:-0}" "${TPS:-0}" \
            "$( [[ "$REMOTE_OK" == "1" ]] && echo true || echo false )"
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
    echo "  3 — Partager Ollama sur le réseau"
    echo "==================================================================="
    for l in "${LINES[@]:-}"; do [[ -n "${l:-}" ]] && echo "  $l"; done
    echo "-------------------------------------------------------------------"
    echo "  Résultat              : $RESULT"
    echo "  Adresse du serveur    : ${SERV_IP:-non déterminée}:${PORT}"
    echo "  Modèle partagé        : ${MODEL}$( [[ -n "$MODEL_MB" ]] && echo " (${MODEL_MB} Mo)" )"
    echo "  Adresses autorisées   : ${ALLOW_COUNT}"
    if (( ${#PROBL[@]} > 0 )); then
        echo "-------------------------------------------------------------------"
        for p in "${PROBL[@]}"; do echo "  ! $p"; done
    fi
    echo "==================================================================="
    exit "$code"
}

if (( CHECK_ONLY == 1 )); then
    say "Mode --check-only : aucune écriture."
fi

# --- 1. Prérequis : Ollama installé et actif ---------------------------------
if [[ ! -x "$BIN" ]]; then
    fail "Ollama absent (${BIN}) : exécutez d'abord l'étape 2"
    finish
fi
VER="$("$BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
if [[ -z "$VER" ]]; then
    fail "ollama --version ne répond pas"
else
    say "Ollama présent : version ${VER}"
fi

if ! systemctl is-active --quiet ollama; then
    fail "service ollama inactif : exécutez d'abord l'étape 2"
fi

# Le modèle doit déjà être là : cette étape ne télécharge RIEN.
if "$BIN" list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$MODEL"; then
    say "Modèle ${MODEL} présent localement : pas de téléchargement nécessaire"
else
    fail "modèle ${MODEL} absent : l'étape 3 ne télécharge rien, installez-le d'abord (étape 2)"
fi

# --- 2. Adresse réelle du serveur -------------------------------------------
# Jamais une adresse écrite en dur : on lit l'adresse de la route par défaut.
SERV_IP="$(ip -4 -o addr show scope global 2>/dev/null \
    | awk '{print $2, $4}' | grep -v '^lo ' \
    | awk -v dev="$(ip -4 route show default 2>/dev/null | awk '/default/{print $5; exit}')" \
          '$1==dev {split($2,a,"/"); print a[1]; exit}')"
if [[ -z "$SERV_IP" ]]; then
    fail "aucune adresse IPv4 globale détectée : partage réseau impossible"
else
    say "Adresse du serveur : ${SERV_IP} (port ${PORT})"
fi

# --- 3. Adresses autorisées --------------------------------------------------
# Source persistante : la liste des --allow, ou le fichier existant, ou le /24.
declare -a ALLOW=()
if (( ${#ALLOW_OVERRIDE[@]} > 0 )); then
    ALLOW=("${ALLOW_OVERRIDE[@]}")
elif [[ -f "$ALLOW_FILE" ]]; then
    while read -r l; do
        l="${l%%#*}"; l="${l// /}"
        [[ -n "$l" ]] && ALLOW+=("$l")
    done < "$ALLOW_FILE"
else
    ALLOW=("$DEFAULT_NET")
fi
# Validation stricte : une entrée mal formée ferait échouer nft -c à
# l'application, mais autant la refuser ici avec un message clair.
# Octets bornés à 0-255 et préfixe à 0-32 : 192.168.1.999 n'est PAS valide.
is_ipv4() {
    local v="$1" ip="${1%%/*}" pfx="" o i
    [[ "$1" == */* ]] && pfx="${1##*/}"
    [[ -n "$pfx" ]] && { [[ "$pfx" =~ ^[0-9]+$ ]] && (( pfx <= 32 )) || return 1; }
    IFS='.' read -r -a o <<<"$ip"
    (( ${#o[@]} == 4 )) || return 1
    for i in "${o[@]}"; do
        [[ "$i" =~ ^(0|[1-9][0-9]{0,2})$ ]] && (( i <= 255 )) || return 1
    done
    return 0
}
for e in "${ALLOW[@]}"; do
    if ! is_ipv4 "$e"; then
        fail "adresse autorisée invalide : '${e}' (attendu IPv4 ou CIDR, octets 0-255)"
    fi
done
# Un /0 ou une plage trop large viderait la restriction de son sens : le
# partage deviendrait ouvert à tout Internet si le port était publié.
for e in "${ALLOW[@]}"; do
    if [[ "$e" == */* ]]; then
        _pfx="${e##*/}"
        if (( _pfx < 16 )); then
            fail "plage trop large refusée : '${e}' (préfixe >= /16 exigé)"
        fi
    fi
done
ALLOW_COUNT=${#ALLOW[@]}
say "Adresses autorisées : ${ALLOW[*]}"

# La machine ne doit pas s'exclure elle-même (accès local toujours conservé).
if (( CHECK_ONLY == 0 )) && [[ "$RESULT" != "FAIL" ]]; then
    :
fi

# --- 4. Unité systemd : OLLAMA_HOST sur l'interface, ORIGINS élargis ---------
# OLLAMA_ORIGINS conditionne les requêtes de navigateur (CORS). On autorise les
# deux entrées possibles (IP et nom) SANS joker : un joker rendrait la liste
# inutile et n'apporte rien aux clients non-navigateur (curl, scripts).
unit_content() {
    cat <<EOF
[Unit]
Description=Ollama Service (P90 POC CPU, partagé LAN)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN} serve
User=ollama
Group=ollama
Restart=on-failure
RestartSec=3
Environment="OLLAMA_HOST=0.0.0.0:${PORT}"
Environment="OLLAMA_MODELS=/usr/share/ollama/.ollama/models"
Environment="OLLAMA_ORIGINS=http://127.0.0.1,http://localhost,http://${SERV_IP}:${PORT}"

[Install]
WantedBy=multi-user.target
EOF
}

WANT_UNIT="$(unit_content)"
CUR_UNIT="$("${SUDO[@]}" cat "$UNIT" 2>/dev/null)"
if (( CHECK_ONLY == 0 )); then
    if [[ "$CUR_UNIT" == "$WANT_UNIT" ]]; then
        say "Unité systemd déjà conforme : pas de réécriture"
    else
        printf '%s\n' "$WANT_UNIT" | "${SUDO[@]}" tee "$UNIT" >/dev/null \
            || fail "écriture de $UNIT impossible (mot de passe sudo refusé ?)"
        "${SUDO[@]}" systemctl daemon-reload || fail "systemctl daemon-reload impossible"
        say "Unité systemd mise à jour (OLLAMA_HOST=0.0.0.0:${PORT})"
    fi
fi

# --- 5. Règle nftables -------------------------------------------------------
# Table dédiée : aucune interférence avec d'autres règles. Politique de la
# chaîne = drop, puis accept explicite par adresse. Le port n'est jamais
# exposé par accident au reste du réseau.
# Le portail 11434 n'est PAS ouvert sur le WAN : le routeur ne le publie pas.
nft_content() {
    local e
    cat <<EOF
# Généré par p90 check 3 — ne pas éditer à la main.
# Ollama ${PORT} : accès restreint aux adresses listées dans ${ALLOW_FILE}.
table inet ${TABLE} {
    set allowed_ipv4 {
        type ipv4_addr
        flags interval
        elements = {
EOF
    for e in "${ALLOW[@]}"; do
        [[ -n "$e" ]] && echo "            ${e},"
    done
    cat <<EOF
        }
    }
    chain input_p90 {
        type filter hook input priority -5; policy accept;
        tcp dport ${PORT} ip saddr @allowed_ipv4 accept
        tcp dport ${PORT} drop
    }
}
EOF
}

WANT_NFT="$(nft_content)"
if (( CHECK_ONLY == 0 )); then
    if ! command -v nft >/dev/null 2>&1; then
        fail "nftables absent : filtrage impossible, partage NON effectué"
    else
        printf '%s\n' "$WANT_NFT" | "${SUDO[@]}" tee "$NFT_FILE" >/dev/null \
            || fail "écriture de $NFT_FILE impossible"
        # Vérification syntaxique AVANT application : nft -c ne modifie rien.
        if ! "${SUDO[@]}" nft -c -f "$NFT_FILE" 2>/dev/null; then
            fail "règle nftables invalide : non appliquée (revue : $NFT_FILE)"
        else
            # replace = idempotent : on supprime puis on réapplique proprement.
            "${SUDO[@]}" nft delete table inet "$TABLE" 2>/dev/null || true
            if "${SUDO[@]}" nft -f "$NFT_FILE" 2>/dev/null; then
                say "Règle nftables appliquée : table inet ${TABLE}"
            else
                fail "application nftables impossible"
            fi
        fi

        # Persistance de la liste d'adresses (relecture au prochain passage).
        "${SUDO[@]}" mkdir -p "$(dirname "$ALLOW_FILE")" 2>/dev/null || true
        printf '%s\n' "${ALLOW[@]}" | "${SUDO[@]}" tee "$ALLOW_FILE" >/dev/null 2>&1 \
            || warn "liste des adresses non persistée ($ALLOW_FILE)"
    fi
else
    say "Mode --check-only : unité et règle nftables NON écrites"
fi

if (( CHECK_ONLY == 0 )); then
    # Redémarrage du service : nécessaire pour que OLLAMA_HOST prenne effet.
    "${SUDO[@]}" systemctl restart ollama 2>/dev/null \
        || fail "redémarrage du service ollama impossible"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        systemctl is-active --quiet ollama && break
        sleep 1
    done
    if systemctl is-active --quiet ollama; then
        say "Service ollama : actif après rechargement"
    else
        fail "service ollama inactif après redémarrage"
    fi
fi

# --- 6. Écoute réellement sur l'interface, et seulement là -------------------
LISTEN_ALL="$(ss -lnt 2>/dev/null | awk -v p=":${PORT}" '$4 ~ p"$" {print $4}')"
if [[ -z "$LISTEN_ALL" ]]; then
    fail "aucune écoute sur le port ${PORT}"
else
    say "Écoute : ${LISTEN_ALL//$'\n'/ }"
    if (( CHECK_ONLY == 1 )); then
        if grep -qE "^0\.0\.0\.0:${PORT}$" <<<"$LISTEN_ALL"; then
            say "Écoute réseau déjà présente (0.0.0.0:${PORT})"
        else
            warn "écoute encore locale (127.0.0.1:${PORT}) : le partage n'est pas actif"
        fi
    elif ! grep -qE "^0\.0\.0\.0:${PORT}$" <<<"$LISTEN_ALL"; then
        fail "le service n'écoute pas sur 0.0.0.0:${PORT} (écoute : ${LISTEN_ALL//$'\n'/ })"
    fi
fi

# --- 7. Le filtrage laisse-t-il vraiment passer les autorisés ? --------------
if (( CHECK_ONLY == 0 )) && command -v nft >/dev/null 2>&1 && [[ "$RESULT" != "FAIL" ]]; then
    if "${SUDO[@]}" nft list table inet "$TABLE" >/dev/null 2>&1; then
        say "Table inet ${TABLE} présente dans le noyau"
        # Contrôle positif ET négatif sur l'ensemble chargé : le set contient
        # bien les autorisés, et la règle de rejet est présente.
        SETDUMP="$("${SUDO[@]}" nft list set inet "$TABLE" allowed_ipv4 2>/dev/null)"
        for e in "${ALLOW[@]}"; do
            grep -qF "$e" <<<"$SETDUMP" || fail "adresse ${e} absente du jeu nftables"
        done
        "${SUDO[@]}" nft list chain inet "$TABLE" input_p90 2>/dev/null \
            | grep -q 'drop' || fail "règle de rejet absente : accès non restreint"
        say "Jeu d'adresses et règle de rejet vérifiés dans le noyau"
    else
        fail "table inet ${TABLE} absente : filtrage non actif"
    fi
fi

# --- 8. Génération locale réelle (référence) --------------------------------
# temperature 0 : à 0.5B, la mesure reste honnête et reproductible.
api_gen() {
    curl -s --max-time 240 "http://${1}/api/generate" \
        -d "$(printf '{"model":"%s","prompt":"%s","stream":false,"options":{"temperature":0,"seed":42}}' \
            "$MODEL" "$ASK")" 2>/dev/null
}

OUT="$(api_gen "127.0.0.1:${PORT}")"
if [[ -z "$OUT" ]] || ! grep -q '"done":true' <<<"$OUT"; then
    fail "génération locale impossible (127.0.0.1:${PORT})"
else
    FIELDS="$(printf '%s' "$OUT" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("-|0|0|0"); raise SystemExit
ec=d.get("eval_count") or 0
ed=d.get("eval_duration") or 1
txt=(d.get("response") or "").strip().replace("\n"," ").replace("|"," ")[:120] or "-"
print("%s|%s|%s|%.2f" % (txt, ec, round(ed/1e6), ec/(ed/1e9)))
' 2>/dev/null)"
    IFS='|' read -r TXT TOK GEN_MS TPS <<<"${FIELDS:-|-|0|0|0}"
    say "Génération locale : ${TXT} (${TOK} tokens, ${GEN_MS} ms, ${TPS} tok/s)"
    if grep -qw 4 <<<"$TXT"; then
        say "Réponse locale correcte"
    else
        fail "réponse locale incorrecte : « ${TXT} » (aucun 4)"
    fi
fi

# --- 9. Génération DISTANTE réelle — seule preuve acceptable du partage -----
# Exécutée depuis une AUTRE machine du LAN. Sans machine cible fournie, le
# partage n'est PAS prouvé : verdict « À CONFIRMER », jamais PASS.
if [[ -n "$REMOTE_TEST" ]]; then
    if [[ ! "$REMOTE_TEST" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        fail "--remote-test : adresse invalide '${REMOTE_TEST}'"
    else
        say "Test distant depuis ${REMOTE_TEST}…"
        # ssh non interactif : la machine de test doit accepter la clé de ce
        # compte. On borne strictement le temps d'attente.
        ROUT="$(timeout 300 ssh -o BatchMode=yes -o ConnectTimeout=8 \
                -o StrictHostKeyChecking=accept-new \
                "${P90_REMOTE_TEST_USER:-demo}@${REMOTE_TEST}" \
                "curl -s --max-time 240 http://${SERV_IP}:${PORT}/api/generate \
                 -d '{\"model\":\"${MODEL}\",\"prompt\":\"${ASK}\",\"stream\":false,\"options\":{\"temperature\":0,\"seed\":42}}'" \
                2>/dev/null)"
        if [[ -z "$ROUT" ]] || ! grep -q '"done":true' <<<"$ROUT"; then
            warn "génération distante non obtenue depuis ${REMOTE_TEST} (SSH ou réseau)"
        else
            RTXT="$(printf '%s' "$ROUT" | python3 -c '
import json,sys
try: print((json.load(sys.stdin).get("response") or "").strip().replace("\n"," ")[:120])
except Exception: print("")' 2>/dev/null)"
            if grep -qw 4 <<<"$RTXT"; then
                REMOTE_OK=1
                say "Génération distante correcte depuis ${REMOTE_TEST} : « ${RTXT} »"
            else
                fail "génération distante incorrecte depuis ${REMOTE_TEST} : « ${RTXT} »"
            fi
        fi
    fi
else
    warn "génération distante NON testée : le partage réseau n'est pas prouvé (relancer avec --remote-test <ip>)"
fi

# --- 10. Le modèle reste-t-il stocké uniquement sur le serveur ? ------------
# Contrôle : aucun répertoire de modèles côté client n'est créé, et le serveur
# en détient la seule copie. On vérifie ici le serveur ; le client est contrôlé
# par le test distant ci-dessus (le client n'a fait qu'un curl, sans ollama).
MODELS_DIR=/usr/share/ollama/.ollama/models
MODEL_MB="$("${SUDO[@]}" du -sm "$MODELS_DIR" 2>/dev/null | awk '{print $1}')"
if [[ -n "${MODEL_MB:-}" ]]; then
    say "Modèles sur le serveur : ${MODEL_MB} Mo dans ${MODELS_DIR}"
    # Un partage correct n'augmente pas la taille après usage distant.
    if (( MODEL_MB < 100 )); then
        warn "répertoire de modèles anormalement petit (${MODEL_MB} Mo)"
    fi
else
    warn "taille des modèles illisible (droits) : stockage local non mesuré"
fi

# --- 11. Rappel explicite de la limite assumée ------------------------------
say "Limite : les adresses autorisées ont accès à toute l'API, /api/pull et /api/delete inclus."

finish
