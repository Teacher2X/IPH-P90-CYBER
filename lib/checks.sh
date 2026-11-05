#!/usr/bin/env bash
# =============================================================================
# lib/checks.sh — Vérifications système
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

check_ram() {
    local result
    result=$(p90_check_ram)
    if [[ "$result" == "inconnu" ]]; then
        echo "RAM : inconnu"
    else
        local total=${result%%|*}
        local avail=${result##*|}
        echo "RAM totale : ${total} Mo"
        echo "RAM disponible : ${avail} Mo"
    fi
}

check_cpu() {
    local result
    result=$(p90_check_cpu)
    if [[ "$result" == *"inconnu"* ]]; then
        echo "CPU : inconnu"
    else
        local model=${result%%|*}
        local cores=${result##*|}
        echo "Processeur : $model"
        echo "Cœurs : $cores"
    fi
}

check_disk() {
    local result
    result=$(p90_check_disk)
    if [[ "$result" == "inconnu" ]]; then
        echo "Disque : inconnu"
    else
        IFS='|' read -r total used avail pct where <<< "$result"
        echo "Espace total     : $total"
        echo "Espace utilisé   : $used"
        echo "Espace disponible: $avail"
        echo "Taux d'utilisation: $pct"
        [[ -n "${where:-}" ]] && echo "Sur volume      : $where"
    fi
}

check_network() {
    local result
    if p90_check_network >/dev/null 2>&1; then
        echo "Réseau : connexion locale OK"
    else
        echo "Réseau : inconnu"
    fi
}
