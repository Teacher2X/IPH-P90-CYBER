#!/usr/bin/env bash
# =============================================================================
# launcher/diagnose.sh — Diagnostic système détaillé
#
# Sortie lisible par un enseignant et exploitable en cours avec les élèves.
#   launcher/diagnose.sh            → affichage
#   launcher/diagnose.sh > f.txt    → export texte
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# common.sh d'abord : checks.sh en dépend
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../lib/checks.sh"

_hdr() { echo "============================================================"; }

_hdr
echo "   DIAGNOSTIC MACHINE — P90 Launcher v${P90_VERSION}"
_hdr
echo ""
echo "Date        : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Ordinateur  : $(hostname 2>/dev/null || echo 'inconnu')"
echo "Utilisateur : $(whoami)"
echo "Noyau       : $(uname -sr)"
# Distribution : depuis os-release (fiable), pas depuis df
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    dist="$( . /etc/os-release && echo "${PRETTY_NAME:-$NAME}" )"
    echo "Distribution: ${dist}"
fi
echo "Code        : ${P90_INSTALL_DIR}"
echo "Données     : ${P90_DATA_DIR}"
echo ""

echo "--- Mémoire vive ---"
check_ram
echo ""

echo "--- Processeur ---"
check_cpu
echo ""

echo "--- Stockage (volume des données) ---"
check_disk
echo ""

echo "--- Réseau ---"
check_network
echo ""

echo "--- Adressage local ---"
local_ip="$(p90_local_ip)"
if [[ -n "$local_ip" ]]; then
    echo "  Adresse IP : ${local_ip}"
    echo "  Réseau /24 : ${local_ip%.*}.0/24"
else
    echo "  Aucune adresse détectée"
fi
echo ""

echo "--- Services utiles ---"
for dep in docker git curl python3 yad ollama hermes; do
    if command -v "$dep" >/dev/null 2>&1; then
        printf '  %-8s : présent (%s)\n' "$dep" "$(command -v "$dep")"
    else
        printf '  %-8s : absent\n' "$dep"
    fi
done
echo ""

echo "--- Modules P90 ---"
for f in "${P90_INSTALL_DIR}"/modules/*.sh; do
    [[ -f "$f" ]] || continue
    id="$(basename "$f" .sh)"
    sf="${P90_DATA_DIR}/modules/${id}.state"
    if [[ -f "$sf" ]]; then
        printf '  %-16s : %s\n' "$id" "$(head -1 "$sf")"
    else
        printf '  %-16s : absent\n' "$id"
    fi
done
echo ""

_hdr
echo "  Export de ce rapport :"
echo "    launcher/diagnose.sh > /tmp/p90-rapport.txt"
echo "    ou : p90 doctor --file /tmp/p90-rapport.txt"
_hdr
