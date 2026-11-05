#!/usr/bin/env bash
# =============================================================================
# modules/A2-openwebui.sh — Module A2 : OpenWebUI et découverte du réseau
#
# Interface : install | check | launch | repair
# =============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/install.sh"

MODULE_ID="A2-openwebui"
OPENWEBUI_PORT="${P90_OPENWEBUI_PORT:-3000}"
COMPOSE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/compose/openwebui.yaml"
COMPOSE_DST="${P90_DATA_DIR}/modules/openwebui/docker-compose.yaml"

_ensure_compose() {
    mkdir -p "$(dirname "$COMPOSE_DST")"
    if [[ ! -f "$COMPOSE_DST" ]] || ! cmp -s "$COMPOSE_SRC" "$COMPOSE_DST"; then
        cp "$COMPOSE_SRC" "$COMPOSE_DST" || {
            p90_err "Impossible de copier la configuration Compose."
            return 1
        }
        p90_info "Configuration Compose synchronisée."
    fi
    return 0
}

_compose() {
    docker compose -f "$COMPOSE_DST" "$@"
}

# --- Conteneurs réellement actifs (pas de grep sur du texte libre) ---
_running_services() {
    _compose ps --status running --services 2>/dev/null | grep -c . || true
}

# --- OpenWebUI répond-il ? ---
_webui_up() {
    curl -fsS --max-time 4 "http://127.0.0.1:${OPENWEBUI_PORT}/" >/dev/null 2>&1
}

# =============================================================================
install_openwebui() {
    echo "=== Module A2 : Installation d'OpenWebUI ==="

    if ! command -v docker >/dev/null 2>&1; then
        p90_msg_erreur_pedago 2
        p90_err "Docker est requis mais absent."
        mark_broken "$MODULE_ID" "docker absent"
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        p90_err "Le démon Docker ne répond pas (service arrêté ? droits insuffisants ?)."
        mark_broken "$MODULE_ID" "démon docker injoignable"
        return 1
    fi
    p90_ok "Docker détecté et opérationnel."

    _ensure_compose || return 1

    echo ""
    echo "Ce module va télécharger les images OpenWebUI et Ollama (plusieurs Go)"
    echo "puis démarrer deux conteneurs. Les données sont placées sur la clé USB :"
    echo "  ${P90_DATA_DIR}"
    read -r -p "Démarrer l'installation ? (o/N) " reponse
    case "${reponse,,}" in
        o|oui|y|yes) ;;
        *) p90_info "Installation annulée."; return 1 ;;
    esac

    export P90_DATA_DIR
    p90_info "Téléchargement et démarrage… (peut prendre plusieurs minutes)"
    if ! _compose up -d; then
        p90_err "Échec de 'docker compose up'."
        mark_broken "$MODULE_ID" "échec du démarrage"
        return 1
    fi

    # Attente bornée : 60 s maximum
    for _ in $(seq 1 30); do
        _webui_up && break
        sleep 2
    done

    if _webui_up; then
        mark_ready "$MODULE_ID"
        p90_ok "OpenWebUI répond sur http://localhost:${OPENWEBUI_PORT}"
        local ip; ip="$(p90_local_ip)"
        [[ -n "$ip" ]] && p90_info "Accès réseau : http://${ip}:${OPENWEBUI_PORT}"
        return 0
    fi

    p90_warn "Les conteneurs tournent mais l'interface ne répond pas encore."
    p90_info "Vérifiez avec : p90 check A2-openwebui"
    echo "installed" > "$(module_state_file "$MODULE_ID")"
    return 0
}

# =============================================================================
check_openwebui() {
    if [[ ! -f "$COMPOSE_DST" ]]; then
        echo "❌ Configuration Compose absente (module non installé)."
        return 1
    fi

    local running; running="$(_running_services)"
    if [[ ! "$running" =~ ^[0-9]+$ ]] || (( running == 0 )); then
        echo "❌ Aucun conteneur actif."
        return 1
    fi
    echo "🟢 Conteneurs actifs : ${running}"

    if _webui_up; then
        echo "🟢 Interface : http://localhost:${OPENWEBUI_PORT}"
        local ip; ip="$(p90_local_ip)"
        [[ -n "$ip" ]] && echo "   Réseau   : http://${ip}:${OPENWEBUI_PORT}"
        mark_ready "$MODULE_ID"
        return 0
    fi
    echo "⚠️  Conteneurs actifs mais interface muette sur le port ${OPENWEBUI_PORT}"
    return 1
}

# =============================================================================
launch_openwebui() {
    p90_info "=== A2 : OpenWebUI et réseau ==="

    if ! _webui_up; then
        p90_warn "OpenWebUI ne répond pas."
        p90_info "Démarrez-le avec : p90 repair ${MODULE_ID}"
        return 1
    fi

    local ip; ip="$(p90_local_ip)"
    echo "Adresse IP locale : ${ip:-inconnue}"
    echo "URL locale        : http://localhost:${OPENWEBUI_PORT}"
    [[ -n "$ip" ]] && echo "URL réseau        : http://${ip}:${OPENWEBUI_PORT}"
    echo ""

    local open=1
    if command -v yad >/dev/null 2>&1; then
        yad --title="A2 — OpenWebUI" \
            --text="Ouvrir l'interface dans le navigateur ?\n\nLocal  : http://localhost:${OPENWEBUI_PORT}\nRéseau : http://${ip:-—}:${OPENWEBUI_PORT}" \
            --button="Ouvrir:0" --button="Plus tard:1" >/dev/null 2>&1 && open=0 || open=1
    else
        read -r -p "Ouvrir dans le navigateur ? (o/N) " r
        case "${r,,}" in o|oui|y) open=0 ;; *) open=1 ;; esac
    fi

    if (( open == 0 )); then
        if command -v xdg-open >/dev/null 2>&1; then
            xdg-open "http://localhost:${OPENWEBUI_PORT}" >/dev/null 2>&1 &
            p90_ok "Navigateur lancé."
        else
            p90_info "Ouvrez manuellement : http://localhost:${OPENWEBUI_PORT}"
        fi
    fi

    # Angry IP Scanner : outil pédagogique d'inventaire du réseau
    echo ""
    if command -v angry-ip >/dev/null 2>&1 || command -v ipscan >/dev/null 2>&1; then
        local bin; bin="$(command -v angry-ip 2>/dev/null || command -v ipscan)"
        p90_info "Angry IP Scanner disponible."
        echo "⚠  Ne scanner QUE le sous-réseau de la salle de classe."
        echo "   Réseau proposé : ${ip%.*}.0/24"
        read -r -p "Lancer un scan de ce sous-réseau ? (o/N) " r
        case "${r,,}" in
            o|oui|y) "$bin" >/dev/null 2>&1 & p90_ok "Scanner lancé." ;;
            *) p90_info "Scan non lancé." ;;
        esac
    else
        p90_info "Angry IP Scanner non installé (apt install angryip) — facultatif."
    fi
}

# =============================================================================
repair_openwebui() {
    p90_info "Réparation de ${MODULE_ID} (données conservées)…"

    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        p90_err "Docker indisponible : impossible de réparer A2."
        mark_broken "$MODULE_ID" "docker indisponible"
        return 1
    fi

    _ensure_compose || return 1
    export P90_DATA_DIR

    p90_info "Redémarrage des conteneurs sans recréation des volumes…"
    if ! _compose up -d --no-recreate 2>/dev/null; then
        p90_warn "Reprise avec recréation des conteneurs (volumes intacts)."
        _compose up -d --force-recreate || {
            p90_err "Échec du redémarrage."
            mark_broken "$MODULE_ID" "redémarrage échoué"
            return 1
        }
    fi

    for _ in $(seq 1 20); do _webui_up && break; sleep 2; done

    if check_openwebui >/dev/null 2>&1; then
        p90_ok "A2 réparé."
        return 0
    fi
    p90_warn "A2 : conteneurs relancés mais interface encore muette."
    return 1
}

# =============================================================================
case "${1:-}" in
    install)      install_openwebui ;;
    check|status) check_openwebui ;;
    launch)       launch_openwebui ;;
    repair)       repair_openwebui ;;
    *)            echo "A2-OpenWebUI | Usages : install | check | launch | repair" ;;
esac
