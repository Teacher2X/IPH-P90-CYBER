#!/usr/bin/env bash
# =============================================================================
# lib/install.sh — Gestion d'installation des modules P90
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# --- Créer tous les répertoires de données (idempotent) ---
install_data_dirs() {
    p90_ensure_data_dir
    mkdir -p "${P90_DATA_DIR}/models"
    mkdir -p "${P90_DATA_DIR}/sessions"
    mkdir -p "${P90_DATA_DIR}/db"
    mkdir -p "${P90_DATA_DIR}/modules"
    mkdir -p "${P90_DATA_DIR}/logs"
    p90_info "Répertoires de données initialisés sous ${P90_DATA_DIR}"
}

# --- Fichier d'état d'un module ---
module_state_file() {
    echo "${P90_DATA_DIR}/modules/${1}.state"
}

module_state() {
    local f; f="$(module_state_file "$1")"
    if [[ -f "$f" ]]; then cat "$f"; else echo "absent"; fi
}

# --- Installer un module par son identifiant complet (ex: A1-ollama) ---
install_module() {
    local module_id="${1:-}"
    [[ -n "$module_id" ]] || { p90_err "install_module : identifiant manquant"; return 1; }

    local root="${P90_INSTALL_DIR:-$(dirname "${BASH_SOURCE[0]}")/..}"
    local module_path="${root}/modules/${module_id}.sh"
    if [[ ! -f "$module_path" ]]; then
        p90_err "Module introuvable : ${module_path}"
        return 1
    fi

    # Garde-fou de réinstallation : l'état prime sur une réinstallation aveugle
    local current; current="$(module_state "$module_id")"
    case "$current" in
        ready|installed)
            p90_info "Module ${module_id} déjà installé (état : ${current})."
            p90_info "Pour vérifier ou réparer : p90 repair ${module_id}"
            return 0
            ;;
    esac

    # Exécution dans un sous-shell : isole les variables du module
    if bash "$module_path" install; then
        local sf; sf="$(module_state_file "$module_id")"
        [[ -f "$sf" ]] || echo "installed" > "$sf"
        p90_ok "Module ${module_id} installé."
        return 0
    else
        local sf; sf="$(module_state_file "$module_id")"
        echo "broken|installation échouée" > "$sf"
        p90_err "Échec de l'installation de ${module_id}."
        return 1
    fi
}

# --- Marquer un module comme prêt ---
mark_ready() {
    mkdir -p "${P90_DATA_DIR}/modules"
    echo "ready" > "$(module_state_file "$1")"
}

# --- Marquer un module comme défaillant ---
mark_broken() {
    mkdir -p "${P90_DATA_DIR}/modules"
    echo "broken|${2:-raison inconnue}" > "$(module_state_file "$1")"
}
