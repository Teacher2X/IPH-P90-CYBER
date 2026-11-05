#!/usr/bin/env bash
# =============================================================================
# lib/common.sh — Fonctions partagées par tous les scripts P90 Launcher
# =============================================================================
# Ne pas appeler directement. Sourcez-le depuis les autres scripts :
#   source "$(dirname "$0")/../lib/common.sh"
# =============================================================================

set -euo pipefail

# --- Chemins ---
# Racine du code : déduite du fichier appelant si P90_INSTALL_DIR n'est pas fixé.
if [[ -z "${P90_INSTALL_DIR:-}" ]]; then
    _p90_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd || echo "")"
    P90_INSTALL_DIR="${_p90_self_dir:-/opt/p90-launcher}"
    unset _p90_self_dir
fi
export P90_INSTALL_DIR
P90_DATA_DIR="${P90_DATA_DIR:-${HOME}/.p90-data}"
export P90_DATA_DIR
P90_CONFIG_DIR="${P90_CONFIG_DIR:-${P90_INSTALL_DIR}/config}"

# --- Chargement du fichier de configuration (les variables déjà définies gagnent) ---
if [[ -f "${P90_CONFIG_DIR}/p90.conf" ]]; then
    # Sauvegarde des surcharges d'environnement
    _p90_saved_data_dir="${P90_DATA_DIR:-}"
    _p90_saved_update_url="${P90_UPDATE_URL:-}"
    # shellcheck disable=SC1090,SC1091
    source "${P90_CONFIG_DIR}/p90.conf"
    # Restauration des surcharges explicites
    [[ -n "${_p90_saved_data_dir}" ]] && P90_DATA_DIR="${_p90_saved_data_dir}"
    [[ -n "${_p90_saved_update_url}" ]] && P90_UPDATE_URL="${_p90_saved_update_url}"
    unset _p90_saved_data_dir _p90_saved_update_url
    export P90_DATA_DIR
fi

P90_VERSION="0"
if [[ -f "${P90_INSTALL_DIR}/VERSION" ]]; then
    P90_VERSION="$(tr -d '[:space:]' < "${P90_INSTALL_DIR}/VERSION")"
fi
# Utilisé par launcher/* et les modules via l'environnement
export P90_VERSION

# --- Couleurs et formatage ---
P90_RED='\033[0;31m'
P90_GREEN='\033[0;32m'
P90_YELLOW='\033[1;33m'
P90_CYAN='\033[0;36m'
P90_BOLD='\033[1m'
export P90_BOLD
P90_DIM='\033[2m'
P90_RESET='\033[0m'

# --- Logging ---
_p90_log_level=0  # 0=défaut, 1=verbose
p90_debug() {
    [[ $_p90_log_level -ge 1 ]] || return 0
    echo -e "${P90_DIM}[DEBUG] ${1}${P90_RESET}" >&2
}

p90_info() {
    echo -e "${P90_CYAN}[INFO] ${1}${P90_RESET}"
}

p90_ok() {
    echo -e "${P90_GREEN}[OK] ${1}${P90_RESET}"
}

p90_warn() {
    echo -e "${P90_YELLOW}[WARN] ${1}${P90_RESET}" >&2
}

p90_err() {
    echo -e "${P90_RED}[ERR]  ${1}${P90_RESET}" >&2
}

# --- Messages pédagogiques ---
p90_msg_erreur_pedago() {
    local code="$1"
    shift
    local message="$*"
    case "$code" in
        1) message="Le module '$(basename "$0" .sh)' nécessite RAM >= 4Go.
   Vérifiez avec : free -h
   Solution : fermer des applications lourdes (navigateur, IDE)" ;;
        2) message="Le module a besoin de Docker.
   Docker n'est pas disponible dans votre session.
   Demandez à l'enseignant ou utilisez un autre PC." ;;
        3) message="Connexion réseau impossible.
   Vérifiez que le câble Wi-Fi/Ethernet est branché.
   Certains modules nécessitent internet juste pour l'installation." ;;
        4) message="Ce module nécessite des privilèges administrateur.
   Entrez votre mot de passe lorsque demandé.
   Le script ne modifie pas le système en root sans votre accord." ;;
        *) message="$message" ;;
    esac
    echo -e "${P90_RED}✖ Erreur : ${message}${P90_RESET}" >&2
}

# --- Checks système --
p90_check_ram() {
    local mem_total_kb available_kb
    mem_total_kb=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    available_kb=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')

    if [[ -n "$mem_total_kb" && -n "$available_kb" ]]; then
        local mem_total_mb=$((mem_total_kb / 1024))
        local avail_mb=$((available_kb / 1024))
        echo "${mem_total_mb}|${avail_mb}"
        return 0
    fi
    echo "inconnu"
    return 1
}

p90_check_cpu() {
    local cores=1
    if [[ -f /proc/cpuinfo ]]; then
        cores=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
    fi
    local model=""
    if command -v lscpu &>/dev/null; then
        model=$(lscpu | grep 'Model name' | cut -d: -f2 | xargs 2>/dev/null || true)
    elif command -v arch &>/dev/null; then
        model="$(uname -m)"
    fi
    echo "${model:-Un connu}|${cores}"
}

p90_check_disk() {
    # Cible : le répertoire de données (sur la clé USB), sinon $HOME.
    local target="${P90_DATA_DIR:-$HOME}"
    [[ -d "$target" ]] || target="$HOME"
    [[ -d "$target" ]] || target="."

    local df_out
    df_out=$(df -PBM "$target" 2>/dev/null | tail -1) || { echo "inconnu"; return 1; }

    local total_mb used_mb avail_mb use_pct
    total_mb=$(printf '%s\n' "$df_out" | awk '{v=$2; gsub(/M/,"",v); print v}')
    used_mb=$(printf '%s\n'  "$df_out" | awk '{v=$3; gsub(/M/,"",v); print v}')
    avail_mb=$(printf '%s\n' "$df_out" | awk '{v=$4; gsub(/M/,"",v); print v}')
    use_pct=$(printf '%s\n'  "$df_out" | awk '{print $5}')

    # Validation : 4 valeurs numériques attendues
    if [[ ! "$total_mb" =~ ^[0-9]+$ || ! "$avail_mb" =~ ^[0-9]+$ ]]; then
        echo "inconnu"
        return 1
    fi
    echo "${total_mb}M|${used_mb}M|${avail_mb}M|${use_pct}|${target}"
    return 0
}

# --- Détection d'adresse IP locale (utilisable hors conteneur et sur poste) ---
p90_local_ip() {
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip=$(ip -4 -o addr show scope global 2>/dev/null \
             | awk '{print $4}' | cut -d/ -f1 | head -1)
    fi
    if [[ -z "$ip" ]] && command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    printf '%s' "$ip"
}

p90_check_network() {
    if ping -c1 -W2 127.0.0.1 &>/dev/null; then
        echo "loopback:ok"
    fi
}

# --- Privilèges ---
p90_sudo_if_required() {
    # Appelle sudo uniquement si nécessaire (exit code 0 par défaut)
    if [[ $(id -u) -ne 0 ]]; then
        command sudo "$@" 2>/dev/null || return $?
    else
        "$@"
    fi
}

p90_check_root() {
    if [[ $(id -u) -eq 0 ]]; then
        p90_warn "Exécution en root détectée. Préférer l'exécution en mode utilisateur."
    fi
}

# --- Vérifier dépendances ---
p90_dependency_exists() {
    command -v "$1" &>/dev/null
}

p90_dependency_or_exit() {
    local dep="$1"
    local hint="${2:-}"
    [[ -n "$hint" ]] || hint="Installez-le : apt install ${dep}"
    if ! command -v "$dep" &>/dev/null; then
        p90_msg_erreur_pedago "3"
        return 1
    fi
}

# --- Séléctionne un modèle LLM adapté à la RAM ---
p90_suggest_model() {
    local ram_mb="$1"
    if (( ram_mb >= 16384 )); then
        echo "qwen3:32b"  # Modèle large
    elif (( ram_mb >= 8192 )); then
        echo "qwen3:8b"   # Modèle moyen (recommandé)
    elif (( ram_mb >= 4096 )); then
        echo "qwen3:0.5b" # Modèle très léger
    else
        echo ""           # Pas de modèle adapté
    fi
}

# --- Lecture de configuration ---
p90_conf_get() {
    local key="$1"
    local file="${P90_CONFIG_DIR}/p90.conf"
    if [[ -f "$file" ]]; then
        grep "^${key}=" "$file" | cut -d= -f2- | tr -d '[:space:]'
    fi
}

# --- Interface graphique (YAD si disponible) ---
p90_gui_available() {
    command -v yad &>/dev/null
}

# --- Portabilité des données --
# Les données persistent sur la clé USB. Elles sont stockées hors du répertoire de code.
p90_ensure_data_dir() {
    if [[ ! -d "${P90_DATA_DIR}" ]]; then
        mkdir -p "${P90_DATA_DIR}"
        p90_info "Répertoire de données créé : ${P90_DATA_DIR}"
    fi
}

# --- Étapes d'installation (source unique : config/p90.conf) ---
# Renvoie une ligne par étape : numéro|script|libellé. Le menu terminal et le
# menu YAD consomment tous deux cette fonction : impossible qu'ils divergent.
p90_check_steps() {
    local entry
    for entry in ${P90_CHECK_STEPS+"${P90_CHECK_STEPS[@]}"}; do
        [[ -n "$entry" ]] && printf '%s\n' "$entry"
    done
}

# Script d'une étape, ou échec si le numéro est inconnu.
p90_check_script_of() {
    local want="$1" num script label
    while IFS='|' read -r num script label; do
        [[ "$num" == "$want" ]] && { printf '%s' "$script"; return 0; }
    done < <(p90_check_steps)
    return 1
}

# --- Gestion du mode VERBOSITÉ ---
if [[ -n "${P90_VERBOSE:-}" ]]; then
    _p90_log_level=1
fi
