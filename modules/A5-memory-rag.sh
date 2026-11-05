#!/usr/bin/env bash
# =============================================================================
# modules/A5-memory-rag.sh — Module A5 : Profils Hermes, mémoire et RAG
#
# Objectif pédagogique : distinguer un LLM, un profil d'agent, une mémoire
# persistante et une base de connaissances documentaire (RAG).
#
# Utilise d'abord les fonctions natives d'OpenWebUI et Hermes.
# Aucun serveur vectoriel externe n'est déployé par défaut.
# =============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/install.sh"

P90_PROFILES=("p90-assistant" "p90-reseau" "p90-documentation")
P90_DOCS_DIR="${P90_DATA_DIR}/documents-pedagogiques"
P90_INDEX_DIR="${P90_DATA_DIR}/index-rag"

install_memory_rag() {
    echo "=== Module A5 : Profils, mémoire et RAG ==="

    if ! command -v hermes >/dev/null 2>&1; then
        p90_err "Le module A3 (Hermes) doit être installé avant A5."
        mark_broken A5-memory-rag "dépendance A3 absente"
        return 1
    fi

    p90_info "Création des trois profils pédagogiques…"
    for prof in "${P90_PROFILES[@]}"; do
        if hermes profile list 2>/dev/null | grep -qx "$prof"; then
            p90_info "  profil $prof : déjà présent"
        else
            hermes profile create "$prof" >/dev/null 2>&1 \
                && p90_ok "  profil $prof : créé" \
                || { p90_warn "  profil $prof : création impossible"; }
        fi
    done

    p90_info "Préparation des répertoires de documents et d'index…"
    mkdir -p "$P90_DOCS_DIR" "$P90_INDEX_DIR"

    mark_ready A5-memory-rag
    p90_ok "Module A5 installé."
}

check_memory_rag() {
    local ok=true

    if ! command -v hermes >/dev/null 2>&1; then
        echo "❌ Hermes absent — A5 dépend de A3."
        return 1
    fi

    echo "--- Profils pédagogiques ---"
    local found=0
    for prof in "${P90_PROFILES[@]}"; do
        if hermes profile list 2>/dev/null | grep -qx "$prof"; then
            echo "🟢 $prof"
            found=$((found+1))
        else
            echo "❌ $prof (absent)"
            ok=false
        fi
    done
    echo "Profils présents : ${found}/${#P90_PROFILES[@]}"

    echo ""
    echo "--- Documents pédagogiques ---"
    if [[ -d "$P90_DOCS_DIR" ]]; then
        local nb
        nb=$(find "$P90_DOCS_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
        echo "🟢 ${nb} document(s) dans ${P90_DOCS_DIR}"
    else
        echo "⚠️  Répertoire de documents absent"
        ok=false
    fi

    echo ""
    echo "--- Mémoire par profil ---"
    for prof in "${P90_PROFILES[@]}"; do
        local mem_file="${HOME}/.hermes/profiles/${prof}/MEMORY.md"
        [[ -f "$mem_file" ]] && echo "🟢 ${prof} : mémoire présente" \
                             || echo "🟡 ${prof} : mémoire vide (normal au départ)"
    done

    ${ok} && { echo "A5-memory-rag prêt"; return 0; } || return 1
}

launch_memory_rag() {
    p90_info "=== Module A5 : Profils, mémoire et RAG ==="
    echo ""
    echo "Trois notions distinctes à ne pas confondre :"
    echo ""
    echo "  1. LE MODÈLE (LLM)     : le moteur de génération de texte."
    echo "  2. LE PROFIL D'AGENT   : des instructions + une mémoire + des sessions."
    echo "  3. LA BASE DE CONNAISSANCES : des documents retrouvés à la demande (RAG)."
    echo ""
    echo "--- Choisir un profil ---"
    local i=1
    for prof in "${P90_PROFILES[@]}"; do
        case "$prof" in
            p90-assistant)     desc="aide générale" ;;
            p90-reseau)        desc="explications réseau et cybersécurité" ;;
            p90-documentation) desc="lecture et analyse de documents" ;;
            *)                 desc="" ;;
        esac
        echo "  $i) ${prof} — ${desc}"
        i=$((i+1))
    done
    echo ""

    read -rp "Numéro du profil à lancer (Entrée pour annuler) : " choice
    case "$choice" in
        1) exec hermes --profile p90-assistant ;;
        2) exec hermes --profile p90-reseau ;;
        3) exec hermes --profile p90-documentation ;;
        *) echo "Annulé." ;;
    esac
}

repair_memory_rag() {
    p90_info "Réparation du module A5 (non destructive)…"

    mkdir -p "$P90_DOCS_DIR" "$P90_INDEX_DIR"

    for prof in "${P90_PROFILES[@]}"; do
        hermes profile list 2>/dev/null | grep -qx "$prof" \
            || hermes profile create "$prof" >/dev/null 2>&1 || true
    done

    mark_ready A5-memory-rag
    p90_ok "A5 vérifié et réparé (aucune donnée supprimée)."
}

case "${1:-}" in
    install)      install_memory_rag ;;
    check|status) check_memory_rag ;;
    launch)       launch_memory_rag ;;
    repair)       repair_memory_rag ;;
    *)            echo "A5-Memory-RAG | Usages : install|check|launch|repair" ;;
esac
