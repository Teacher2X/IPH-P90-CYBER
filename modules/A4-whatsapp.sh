#!/usr/bin/env bash
# =============================================================================
# modules/A4-whatsapp.sh — Module A4 : Pont WhatsApp via WAHA (FACULTATIF)
#
# Objectif pédagogique : envoyer un message à un assistant IA depuis WhatsApp
# et recevoir sa réponse.
#
# ⚠ Module expérimental. Utiliser un compte de démonstration DÉDIÉ.
#   WhatsApp peut bloquer le numéro utilisé. Aucun envoi en masse.
#
# Interface : install | check | launch | repair | stop
# =============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/install.sh"

MODULE_ID="A4-whatsapp"
WAHA_PORT="${P90_WAHA_PORT:-3001}"
COMPOSE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/compose/waha.yaml"
COMPOSE_DST="${P90_DATA_DIR}/modules/waha/docker-compose.yaml"

_compose() {
    docker compose -f "$COMPOSE_DST" "$@"
}

_waha_up() {
    curl -fsS --max-time 4 "http://127.0.0.1:${WAHA_PORT}/health" >/dev/null 2>&1
}

prepare_compose() {
    mkdir -p "$(dirname "$COMPOSE_DST")"
    if [[ ! -f "$COMPOSE_SRC" ]]; then
        p90_err "Fichier Compose manquant : ${COMPOSE_SRC}"
        return 1
    fi
    if [[ ! -f "$COMPOSE_DST" ]] || ! cmp -s "$COMPOSE_SRC" "$COMPOSE_DST"; then
        cp "$COMPOSE_SRC" "$COMPOSE_DST" || return 1
        p90_info "Configuration Compose WAHA synchronisée."
    fi
    return 0
}

# =============================================================================
install_whatsapp() {
    echo "=== Module A4 : Pont WhatsApp via WAHA (module facultatif) ==="
    echo ""
    echo "⚠  AVERTISSEMENTS"
    echo "   • WAHA n'est pas une solution officielle WhatsApp."
    echo "   • Le numéro utilisé peut être bloqué par WhatsApp."
    echo "   • Utiliser un compte de DÉMONSTRATION dédié, jamais un compte personnel."
    echo "   • Aucun envoi en masse ; un seul contact de test autorisé."
    echo ""

    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        p90_err "Docker est requis et doit être opérationnel."
        mark_broken "$MODULE_ID" "docker indisponible"
        return 1
    fi

    # Mot de passe obligatoire : jamais de valeur par défaut publiée
    if [[ -z "${P90_WAHA_PASSWORD:-}" ]]; then
        p90_err "La variable P90_WAHA_PASSWORD doit être définie avant l'installation."
        echo "    Exemple : export P90_WAHA_PASSWORD=\"\$(openssl rand -base64 18)\""
        mark_broken "$MODULE_ID" "mot de passe manquant"
        return 1
    fi

    read -r -p "Confirmer l'usage d'un compte de démonstration dédié ? (o/N) " rep
    case "${rep,,}" in
        o|oui|y|yes) ;;
        *) p90_info "Installation annulée."; return 1 ;;
    esac

    prepare_compose || return 1
    export P90_DATA_DIR P90_WAHA_PASSWORD

    if ! _compose up -d; then
        p90_err "Échec du démarrage de WAHA."
        mark_broken "$MODULE_ID" "démarrage échoué"
        return 1
    fi

    for _ in $(seq 1 30); do _waha_up && break; sleep 2; done

    if _waha_up; then
        mark_ready "$MODULE_ID"
        p90_ok "WAHA opérationnel sur http://127.0.0.1:${WAHA_PORT}"
        p90_info "Ouvrez le dashboard puis scannez le QR code avec le téléphone de démonstration."
        return 0
    fi
    p90_warn "Conteneur démarré, API encore muette. Réessayez : p90 check ${MODULE_ID}"
    return 0
}

# =============================================================================
check_whatsapp() {
    if [[ ! -f "$COMPOSE_DST" ]]; then
        echo "❌ Module non installé (configuration Compose absente)."
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Démon Docker injoignable."
        return 1
    fi

    local running
    running="$(_compose ps --status running --services 2>/dev/null | grep -c . || true)"
    if [[ ! "$running" =~ ^[0-9]+$ ]] || (( running == 0 )); then
        echo "❌ Conteneur WAHA arrêté."
        return 1
    fi
    echo "🟢 Conteneur WAHA actif"

    if _waha_up; then
        echo "🟢 API : http://127.0.0.1:${WAHA_PORT}"
        echo "   Accès réseau : NON (écoute 127.0.0.1 uniquement) ✅"
        mark_ready "$MODULE_ID"
        return 0
    fi
    echo "⚠️  Conteneur actif, API non joignable."
    return 1
}

# =============================================================================
launch_whatsapp() {
    p90_info "=== A4 : WhatsApp ↔ IA ==="
    echo ""
    echo "Chaîne technique :"
    echo "   WhatsApp  →  WAHA (API HTTP)  →  Hermes / Ollama  →  réponse"
    echo ""
    echo "Sécurité :"
    echo "   • dashboard accessible uniquement en local (127.0.0.1)"
    echo "   • sessions stockées sur la clé USB"
    echo "   • arrêt immédiat possible (p90 repair A4 ou stop)"
    echo ""

    if ! _waha_up; then
        p90_warn "WAHA ne répond pas. Lancez : p90 repair ${MODULE_ID}"
        return 1
    fi

    echo "Dashboard : http://localhost:${WAHA_PORT}"
    local r
    read -r -p "Ouvrir le dashboard ? (o/N) " r
    case "${r,,}" in
        o|oui|y)
            if command -v xdg-open >/dev/null 2>&1; then
                xdg-open "http://localhost:${WAHA_PORT}" >/dev/null 2>&1 &
                p90_ok "Navigateur lancé."
            else
                p90_info "Ouvrez manuellement : http://localhost:${WAHA_PORT}"
            fi
            ;;
        *) p90_info "Dashboard non ouvert." ;;
    esac
}

# =============================================================================
repair_whatsapp() {
    p90_info "Réparation de ${MODULE_ID}…"

    if [[ ! -f "$COMPOSE_DST" ]]; then
        p90_info "Module non installé : reprise de l'installation."
        install_whatsapp
        return $?
    fi
    if [[ -z "${P90_WAHA_PASSWORD:-}" ]]; then
        p90_err "P90_WAHA_PASSWORD non défini : impossible de démarrer WAHA."
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        p90_err "Docker injoignable."
        return 1
    fi

    export P90_DATA_DIR P90_WAHA_PASSWORD
    _compose up -d --no-recreate 2>/dev/null || _compose up -d || {
        p90_err "Redémarrage impossible."
        return 1
    }

    for _ in $(seq 1 20); do _waha_up && break; sleep 2; done

    if check_whatsapp >/dev/null 2>&1; then
        p90_ok "A4 réparé."
        p90_info "Session conservée sur ${P90_DATA_DIR} (pas de nouveau QR code si déjà appairé)."
        return 0
    fi
    p90_warn "A4 relancé mais API muette."
    return 1
}

# =============================================================================
stop_whatsapp() {
    if [[ -f "$COMPOSE_DST" ]] && docker info >/dev/null 2>&1; then
        _compose down >/dev/null 2>&1 && p90_ok "WAHA arrêté." || p90_warn "Arrêt incomplet."
    else
        p90_info "Rien à arrêter."
    fi
    # État explicite : arrêté volontairement, ce n'est pas une panne
    echo "stopped|arrêt volontaire" > "$(module_state_file "$MODULE_ID")"
}

# =============================================================================
case "${1:-}" in
    install)      install_whatsapp ;;
    check|status) check_whatsapp ;;
    launch)       launch_whatsapp ;;
    repair)       repair_whatsapp ;;
    stop)         stop_whatsapp ;;
    *)            echo "A4-WhatsApp | Usages : install | check | launch | repair | stop" ;;
esac
