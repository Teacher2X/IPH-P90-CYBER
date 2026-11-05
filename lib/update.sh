#!/usr/bin/env bash
# =============================================================================
# lib/update.sh — Gestion des mises à jour (source : GitHub officiel)
#
# Règles :
#   - La source de vérité est le dépôt GitHub Teacher2X/IPH-P90-CYBER.
#   - Gitea n'est plus qu'une POC historique : n'y pousser aucune évolution.
#   - Les versions sont figées : une mise à jour est explicite, jamais auto.
#   - Seul le CODE est remplacé. Les données utilisateur ne sont jamais touchées.
# =============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# URL de base configurable (renseignée dans config/p90.conf)
_update_base() {
    local base="${P90_UPDATE_URL:-}"
    if [[ -z "$base" ]]; then
        local conf="${P90_INSTALL_DIR:-$(dirname "${BASH_SOURCE[0]}")/..}/config/p90.conf"
        if [[ -f "$conf" ]]; then
            # shellcheck disable=SC1090
            source "$conf"
            base="${P90_UPDATE_URL:-}"
        fi
    fi
    printf '%s' "$base"
}

# --- Vérifier la version disponible (lecture seule) ---
check_update_remote() {
    local current="${P90_VERSION:-inconnue}"
    local base
    base="$(_update_base)"

    if [[ -z "$base" ]]; then
        p90_err "Aucune source de mise à jour configurée (P90_UPDATE_URL)."
        p90_info "Renseignez P90_UPDATE_URL dans config/p90.conf (URL GitHub du dépôt)."
        echo "not-configured"
        return 1
    fi

    local remote_version
    if ! remote_version=$(curl -fsSL --connect-timeout 10 --max-time 15 \
            "${base}/raw/branch/main/VERSION" 2>/dev/null | tr -d '[:space:]'); then
        p90_err "Vérification impossible (hors ligne ou dépôt injoignable)."
        echo "offline"
        return 1
    fi

    if [[ -z "$remote_version" ]]; then
        p90_err "Réponse vide de la source de mise à jour."
        echo "error"
        return 1
    fi

    if [[ "$current" != "$remote_version" ]]; then
        echo "available"
        echo "  Version installée  : $current"
        echo "  Version disponible : $remote_version"
        echo "  Pour appliquer : p90 update --apply"
        return 0
    fi
    echo "up-to-date"
    echo "  Version installée : $current — à jour."
    return 0
}

# --- Appliquer la mise à jour (code seulement) ---
apply_update() {
    local base
    base="$(_update_base)"
    if [[ -z "$base" ]]; then
        p90_err "Aucune source de mise à jour configurée."
        return 1
    fi

    local root="${P90_INSTALL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    p90_info "Mise à jour depuis : ${base}"
    echo "Les données utilisateur (${P90_DATA_DIR}) ne seront pas modifiées."
    read -r -p "Confirmer la mise à jour ? (o/N) " rep
    case "${rep,,}" in
        o|oui|y|yes) ;;
        *) p90_info "Mise à jour annulée."; return 1 ;;
    esac

    # Uniquement des fichiers de CODE
    local files_to_update=(
        "VERSION"
        "bootstrap.sh"
        "config/p90.conf"
        "config/modules.json"
        "lib/common.sh"
        "lib/checks.sh"
        "lib/install.sh"
        "lib/update.sh"
        "launcher/p90"
        "launcher/gui.sh"
        "launcher/diagnose.sh"
        "launcher/01-usb-persistence.sh"
        "modules/A1-ollama.sh"
        "modules/A2-openwebui.sh"
        "modules/A3-hermes.sh"
        "modules/A4-whatsapp.sh"
        "modules/A5-memory-rag.sh"
        "compose/openwebui.yaml"
        "compose/waha.yaml"
    )

    local failed=0 updated=0
    local f
    for f in "${files_to_update[@]}"; do
        local target tmp
        target="${root}/${f}"
        tmp="${root}/tmp_update_$(basename "$f")"

        if ! curl -fsSL --connect-timeout 10 --max-time 30 \
                "${base}/raw/branch/main/${f}" -o "$tmp" 2>/dev/null; then
            p90_warn "  ${f} : non récupéré (hors ligne ?)"
            rm -f "$tmp"
            failed=$((failed+1))
            continue
        fi

        # Fichier vide ou erreur HTML : on ne remplace pas
        if [[ ! -s "$tmp" ]] || head -c 100 "$tmp" | grep -qi '<html'; then
            p90_warn "  ${f} : contenu invalide, ignoré."
            rm -f "$tmp"
            failed=$((failed+1))
            continue
        fi

        if [[ -f "$target" ]] && cmp -s "$target" "$tmp"; then
            p90_info "  ${f} : déjà à jour."
            rm -f "$tmp"
            continue
        fi

        # Sauvegarde puis remplacement
        if [[ -f "$target" ]]; then
            cp "$target" "${target}.bak.${P90_VERSION:-old}" || {
                p90_warn "  ${f} : sauvegarde impossible, fichier laissé tel quel."
                rm -f "$tmp"
                failed=$((failed+1))
                continue
            }
        fi
        mv "$tmp" "$target" && chmod +x "$target" 2>/dev/null
        p90_ok "  ${f} : mis à jour."
        updated=$((updated+1))
    done

    # Recharge la version depuis le disque
    if [[ -f "${root}/VERSION" ]]; then
        P90_VERSION="$(tr -d '[:space:]' < "${root}/VERSION")"
    fi

    echo ""
    p90_info "Fichiers mis à jour : ${updated}   échecs : ${failed}"
    if (( failed > 0 )); then
        p90_warn "Mise à jour partielle. Version courante : ${P90_VERSION}"
        return 1
    fi
    p90_ok "Mise à jour terminée. Version courante : ${P90_VERSION}"
    return 0
}
