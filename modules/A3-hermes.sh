#!/usr/bin/env bash
# =============================================================================
# modules/A3-hermes.sh — Module A3 : Hermes Agent (agent à outils)
#
# Objectif pédagogique : distinguer un chatbot (produit du texte) d'un agent
# (peut appeler des outils : lire un fichier, en créer, calculer).
#
# Interface : install | check | launch | repair
# =============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/install.sh"

MODULE_ID="A3-hermes"
HERMES_WORKSPACE="${P90_DATA_DIR}/hermes-workspace"
HERMES_PROFILE="p90-assistant"
OLLAMA_PORT="${P90_OLLAMA_PORT:-11434}"

# Chemins d'installation utilisateur possibles
_hermes_bin() {
    command -v hermes 2>/dev/null \
        || { [[ -x "${HOME}/.local/bin/hermes" ]] && echo "${HOME}/.local/bin/hermes"; } \
        || true
}

_ollama_up() {
    curl -fsS --max-time 3 "http://127.0.0.1:${OLLAMA_PORT}/api/tags" >/dev/null 2>&1
}

# =============================================================================
install_hermes() {
    echo "=== Module A3 : Installation de Hermes Agent ==="

    if ! command -v python3 >/dev/null 2>&1; then
        p90_err "Python 3 est requis."
        mark_broken "$MODULE_ID" "python3 absent"
        return 1
    fi

    # A3 s'appuie sur A1 (moteur local)
    if ! command -v ollama >/dev/null 2>&1; then
        p90_msg_erreur_pedago 2
        p90_err "A3 dépend de A1 (Ollama). Installez d'abord : p90 install A1-ollama"
        mark_broken "$MODULE_ID" "dépendance A1 absente"
        return 1
    fi

    if [[ -n "$(_hermes_bin)" ]]; then
        p90_ok "Hermes déjà présent : $(_hermes_bin)"
    else
        echo ""
        echo "Installation de Hermes Agent (paquet utilisateur, sans root)."
        echo "Source : paquet Python 'hermes-agent'."
        read -r -p "Installer maintenant ? (o/N) " rep
        case "${rep,,}" in
            o|oui|y|yes) ;;
            *) p90_info "Installation annulée."; return 1 ;;
        esac

        if command -v pip3 >/dev/null 2>&1; then
            pip3 install --user hermes-agent || {
                p90_err "Échec de l'installation (pip3)."
                mark_broken "$MODULE_ID" "pip3 échoué"
                return 1
            }
        elif command -v pipx >/dev/null 2>&1; then
            pipx install hermes-agent || {
                p90_err "Échec de l'installation (pipx)."
                mark_broken "$MODULE_ID" "pipx échoué"
                return 1
            }
        else
            p90_err "Ni pip3 ni pipx disponibles."
            p90_info "Installez : sudo apt install python3-pip"
            mark_broken "$MODULE_ID" "pip3/pipx absents"
            return 1
        fi

        [[ -n "$(_hermes_bin)" ]] || {
            p90_err "Hermes installé mais introuvable (vérifiez ${HOME}/.local/bin)."
            mark_broken "$MODULE_ID" "binaire absent après installation"
            return 1
        }
    fi

    mkdir -p "$HERMES_WORKSPACE"

    if ! _ollama_up; then
        p90_warn "Ollama ne répond pas : le modèle ne sera pas configurable."
        p90_info "Lancez : p90 repair A1-ollama"
    else
        local ram_pair ram_total suggested
        ram_pair="$(p90_check_ram)"; ram_total="${ram_pair%%|*}"
        suggested="$(p90_suggest_model "${ram_total:-0}")"
        if [[ -n "$suggested" ]]; then
            p90_info "Modèle local recommandé pour A3 : ${suggested}"
            echo "Pour l'utiliser dans Hermes :"
            echo "  hermes --profile ${HERMES_PROFILE} --model ${suggested}"
        fi
    fi

    p90_ok "A3 installé. Espace de travail : ${HERMES_WORKSPACE}"
    echo "installed" > "$(module_state_file "$MODULE_ID")"
    return 0
}

# =============================================================================
check_hermes() {
    local ok=0
    local bin; bin="$(_hermes_bin)"

    if [[ -z "$bin" ]]; then
        echo "❌ Hermes CLI introuvable"
        return 1
    fi
    echo "🟢 Hermes CLI : ${bin}"

    if _ollama_up; then
        echo "🟢 Moteur Ollama joignable sur 127.0.0.1:${OLLAMA_PORT}"
    else
        echo "❌ Moteur Ollama injoignable → A3 ne peut pas fonctionner"
        ok=1
    fi

    if [[ -d "$HERMES_WORKSPACE" ]]; then
        echo "🟢 Espace de travail : ${HERMES_WORKSPACE}"
    else
        echo "⚠️  Espace de travail absent"
        ok=1
    fi

    if [[ -d "${HOME}/.hermes/profiles/${HERMES_PROFILE}" ]]; then
        echo "🟢 Profil pédagogique : ${HERMES_PROFILE}"
    else
        echo "🟡 Profil ${HERMES_PROFILE} non encore créé (voir module A5)"
    fi

    if (( ok == 0 )); then
        mark_ready "$MODULE_ID"
        echo "A3-hermes prêt"
        return 0
    fi
    return 1
}

# =============================================================================
launch_hermes() {
    p90_info "=== A3 : Hermes Agent — du chatbot à l'agent ==="
    echo ""

    local bin; bin="$(_hermes_bin)"
    if [[ -z "$bin" ]]; then
        p90_err "Hermes absent. Lancez : p90 install ${MODULE_ID}"
        return 1
    fi
    if ! _ollama_up; then
        p90_err "Ollama ne répond pas. Lancez : p90 repair A1-ollama"
        return 1
    fi

    mkdir -p "$HERMES_WORKSPACE"

    echo "Trois expériences à mener :"
    echo "  1) Une question simple         → aucun outil n'est appelé"
    echo "  2) Résumer docs/A1-ollama.md   → un outil de lecture est utilisé"
    echo "  3) Créer note.txt ici          → un outil d'écriture est utilisé"
    echo ""
    echo "Espace de travail : ${HERMES_WORKSPACE}"
    echo "L'agent n'a le droit d'agir que dans cet espace."
    echo ""

    read -r -p "Ouvrir la session Hermes ? (o/N) " rep
    case "${rep,,}" in
        o|oui|y|yes) ;;
        *) p90_info "Annulé."; return 0 ;;
    esac

    cd "$HERMES_WORKSPACE" || { p90_err "Espace de travail inaccessible."; return 1; }
    exec "$bin" --profile "$HERMES_PROFILE"
}

# =============================================================================
repair_hermes() {
    p90_info "Réparation de ${MODULE_ID} (aucune donnée supprimée)…"

    local bin; bin="$(_hermes_bin)"
    if [[ -z "$bin" ]]; then
        p90_info "Hermes absent : reprise de l'installation."
        install_hermes
        return $?
    fi

    mkdir -p "$HERMES_WORKSPACE"

    if ! _ollama_up; then
        p90_info "Ollama injoignable : tentative de démarrage du service."
        if command -v ollama >/dev/null 2>&1; then
            if command -v systemctl >/dev/null 2>&1; then
                sudo systemctl start ollama >/dev/null 2>&1 || true
            fi
            _ollama_up || { nohup ollama serve >"${P90_DATA_DIR}/logs/ollama.log" 2>&1 & sleep 3; }
        else
            p90_warn "Ollama n'est pas installé : A3 reste dépendant de A1."
        fi
    fi

    if check_hermes >/dev/null 2>&1; then
        p90_ok "A3 réparé et prêt."
        return 0
    fi
    p90_warn "A3 : réparation partielle (voir p90 check A3-hermes)."
    return 1
}

# =============================================================================
case "${1:-}" in
    install)      install_hermes ;;
    check|status) check_hermes ;;
    launch)       launch_hermes ;;
    repair)       repair_hermes ;;
    *)            echo "A3-Hermes | Usages : install | check | launch | repair" ;;
esac
