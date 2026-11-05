#!/usr/bin/env bash
# =============================================================================
# modules/A1-ollama.sh — Module A1 : Ollama dans le terminal
#
# Objectif pédagogique : découvrir un LLM exécuté localement, sans cloud.
#
# Interface : install | check | launch | repair
# =============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/install.sh"

MODULE_ID="A1-ollama"
OLLAMA_PORT="${P90_OLLAMA_PORT:-11434}"
# Modèles placés sur la clé (persistance), jamais dans le dépôt
export OLLAMA_MODELS="${P90_DATA_DIR}/models"

# --- Nombre réel de modèles installés (hors en-tête) ---
_ollama_model_count() {
    ollama list 2>/dev/null | tail -n +2 | grep -c . || true
}

# --- Le service répond-il localement ? ---
_ollama_api_up() {
    curl -fsS --max-time 3 "http://127.0.0.1:${OLLAMA_PORT}/api/tags" >/dev/null 2>&1
}

# --- Télécharger un modèle, après confirmation explicite ---
_pull_model() {
    local model="$1"
    [[ -n "$model" ]] || return 1

    if ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -qx "$model"; then
        p90_info "Modèle déjà présent : ${model}"
        return 0
    fi

    echo ""
    echo "Modèle proposé : ${model}"
    echo "Téléchargement de plusieurs centaines de Mo à quelques Go."
    read -r -p "Télécharger maintenant ? (o/N) " reponse
    case "${reponse,,}" in
        o|oui|y|yes) ;;
        *) p90_info "Téléchargement annulé."; return 1 ;;
    esac

    ollama pull "$model" || {
        p90_msg_erreur_pedago 3
        p90_err "Échec du téléchargement de ${model}."
        return 1
    }
    p90_ok "Modèle ${model} installé dans ${OLLAMA_MODELS}."
}

# =============================================================================
install_ollama() {
    echo "=== Module A1 : Installation d'Ollama ==="

    local ram_pair ram_total
    ram_pair="$(p90_check_ram)"
    ram_total="${ram_pair%%|*}"
    if [[ ! "$ram_total" =~ ^[0-9]+$ ]]; then
        p90_warn "RAM indéterminée ; vérification de la RAM ignorée."
        ram_total=0
    fi

    if (( ram_total > 0 && ram_total < 1024 )); then
        p90_msg_erreur_pedago 1
        mark_broken "$MODULE_ID" "RAM insuffisante (${ram_total} Mo)"
        return 1
    fi
    (( ram_total > 0 )) && p90_info "RAM détectée : ${ram_total} Mo"

    # --- Déjà installé ? ---
    if command -v ollama >/dev/null 2>&1; then
        p90_ok "Ollama est déjà installé : $(ollama --version 2>/dev/null | head -1)"
    else
        p90_info "Ollama est absent."
        echo "L'installation officielle télécharge puis exécute un script."
        echo "Source : https://ollama.com/install.sh"
        echo "Elle nécessite les droits administrateur (sudo)."
        read -r -p "Installer Ollama maintenant ? (o/N) " reponse
        case "${reponse,,}" in
            o|oui|y|yes) ;;
            *) p90_info "Installation annulée par l'utilisateur."; return 1 ;;
        esac

        if ! curl -fsSL --max-time 60 https://ollama.com/install.sh -o /tmp/p90-ollama-install.sh; then
            p90_msg_erreur_pedago 3
            p90_err "Téléchargement du script d'installation impossible."
            mark_broken "$MODULE_ID" "téléchargement impossible"
            return 1
        fi
        # Le script officiel est exécuté après accord explicite de l'utilisateur
        sudo sh /tmp/p90-ollama-install.sh || {
            p90_err "Installation d'Ollama échouée (sudo refusé ou script en erreur)."
            mark_broken "$MODULE_ID" "installation échouée"
            return 1
        }
        rm -f /tmp/p90-ollama-install.sh

        command -v ollama >/dev/null 2>&1 || {
            p90_err "Ollama n'est pas dans le PATH après installation."
            mark_broken "$MODULE_ID" "binaire absent après installation"
            return 1
        }
    fi

    # --- Service ---
    if ! _ollama_api_up; then
        p90_info "Démarrage du service Ollama…"
        if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl enable --now ollama >/dev/null 2>&1 || true
        fi
        _ollama_api_up || {
            p90_warn "Le service n'a pas répondu immédiatement ; lancement en arrière-plan."
            nohup ollama serve >"${P90_DATA_DIR}/logs/ollama.log" 2>&1 &
            sleep 3
        }
    fi

    if _ollama_api_up; then
        p90_ok "Service Ollama opérationnel sur 127.0.0.1:${OLLAMA_PORT}"
    else
        p90_warn "Service Ollama non joignable pour l'instant (démarrage différé)."
    fi

    # --- Un seul modèle proposé, adapté à la RAM ---
    local suggested
    suggested="$(p90_suggest_model "${ram_total:-0}")"
    if [[ -n "$suggested" ]]; then
        _pull_model "$suggested" || p90_info "Aucun modèle téléchargé pour le moment."
    else
        p90_warn "RAM insuffisante pour proposer un modèle."
    fi

    if _ollama_api_up && (( $(_ollama_model_count) > 0 )); then
        mark_ready "$MODULE_ID"
        p90_ok "A1 prêt."
        return 0
    fi
    echo "installed" > "$(module_state_file "$MODULE_ID")"
    p90_info "Ollama installé ; module non encore « prêt » (modèle manquant)."
    return 0
}

# =============================================================================
check_ollama() {
    local ok=0

    if ! command -v ollama >/dev/null 2>&1; then
        echo "❌ ollama : non installé"
        return 1
    fi
    echo "🟢 ollama : $(ollama --version 2>/dev/null | head -1)"

    # Le port ne doit répondre qu'en local (jamais exposé au LAN)
    if _ollama_api_up; then
        echo "🟢 API locale : http://127.0.0.1:${OLLAMA_PORT} répond"
    else
        echo "❌ API locale injoignable sur 127.0.0.1:${OLLAMA_PORT}"
        ok=1
    fi

    local nb; nb="$(_ollama_model_count)"
    if [[ "$nb" =~ ^[0-9]+$ ]] && (( nb > 0 )); then
        echo "🟢 Modèles installés : ${nb}"
        ollama list 2>/dev/null | tail -n +2 | awk '{printf "     - %s\n", $1}'
    else
        echo "⚠️  Aucun modèle installé"
        ok=1
    fi

    echo "   Modèles stockés dans : ${OLLAMA_MODELS}"

    if (( ok == 0 )); then
        mark_ready "$MODULE_ID"
        echo "A1-ollama prêt"
        return 0
    fi
    return 1
}

# =============================================================================
launch_ollama() {
    local ram_pair ram_total suggested
    ram_pair="$(p90_check_ram)"; ram_total="${ram_pair%%|*}"
    suggested="$(p90_suggest_model "${ram_total:-0}")"

    p90_info "=== A1 : Conversation locale avec un modèle ==="
    echo "RAM détectée : ${ram_total:-?} Mo"

    if ! _ollama_api_up; then
        p90_warn "Le service Ollama ne répond pas. Lancez d'abord : p90 repair ${MODULE_ID}"
        return 1
    fi

    echo ""
    echo "  1) Utiliser le modèle recommandé (${suggested:-aucun})"
    echo "  2) Choisir un autre modèle"
    echo "  3) Lire la fiche pédagogique"
    read -r -p "Choix [1-3] : " choix

    case "${choix:-1}" in
        2)
            read -r -p "Nom du modèle (ex. qwen3:0.5b) : " model
            [[ -n "$model" ]] || { p90_err "Nom vide."; return 1; }
            _pull_model "$model" || return 1
            ;;
        3)
            local doc; doc="$(dirname "${BASH_SOURCE[0]}")/../docs/A1-ollama.md"
            [[ -f "$doc" ]] && cat "$doc" || p90_err "Fiche introuvable : $doc"
            return 0
            ;;
        *)
            [[ -n "$suggested" ]] || { p90_err "Aucun modèle recommandé pour cette RAM."; return 1; }
            _pull_model "$suggested" || return 1
            model="$suggested"
            ;;
    esac

    if command -v xfce4-terminal >/dev/null 2>&1; then
        xfce4-terminal --title="P90 — Ollama (${model})" \
            -x bash -lc "ollama run ${model}" &
        p90_ok "Terminal ouvert avec le modèle ${model}."
    else
        p90_info "xfce4-terminal absent — session directe dans ce terminal."
        ollama run "$model"
    fi
}

# =============================================================================
repair_ollama() {
    p90_info "Réparation de ${MODULE_ID} (aucune donnée supprimée)…"

    if ! command -v ollama >/dev/null 2>&1; then
        p90_info "Ollama absent : reprise de l'installation."
        install_ollama
        return $?
    fi

    if ! _ollama_api_up; then
        p90_info "Service arrêté — redémarrage."
        if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl restart ollama >/dev/null 2>&1 || true
        fi
        _ollama_api_up || { nohup ollama serve >"${P90_DATA_DIR}/logs/ollama.log" 2>&1 & sleep 3; }
    fi

    if (( $(_ollama_model_count) == 0 )); then
        local ram_pair ram_total suggested
        ram_pair="$(p90_check_ram)"; ram_total="${ram_pair%%|*}"
        suggested="$(p90_suggest_model "${ram_total:-0}")"
        if [[ -n "$suggested" ]]; then
            p90_info "Aucun modèle : proposition ${suggested}"
            _pull_model "$suggested" || p90_warn "Modèle non téléchargé."
        fi
    fi

    if check_ollama >/dev/null 2>&1; then
        mark_ready "$MODULE_ID"
        p90_ok "A1 réparé et prêt."
        return 0
    fi
    p90_warn "A1 réparé partiellement (voir p90 status)."
    return 1
}

# =============================================================================
case "${1:-}" in
    install)      install_ollama ;;
    check|status) check_ollama ;;
    launch)       launch_ollama ;;
    repair)       repair_ollama ;;
    *)            echo "A1-Ollama | Usages : install | check | launch | repair" ;;
esac
