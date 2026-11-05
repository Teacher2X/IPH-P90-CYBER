#!/usr/bin/env bash
# =============================================================================
# menu.sh — Point d'entrée du menu P90
#
# Sans argument : menu graphique YAD si disponible, sinon menu terminal.
# Le menu ne contient AUCUNE logique de diagnostic : il délègue à p90 check <n>
# pour que CLI et GUI produisent exactement le même verdict.
# =============================================================================
set -uo pipefail

P90_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export P90_ROOT

P90_CLI="${P90_ROOT}/launcher/p90"
[[ -x "$P90_CLI" ]] || chmod +x "$P90_CLI" 2>/dev/null || true

usage() {
    cat <<'EOF'
P90 — menu

  ./menu.sh              Menu graphique (YAD) s'il est disponible, sinon terminal
  ./menu.sh --gui        Force le menu graphique
  ./menu.sh --cli        Force le menu terminal
  ./menu.sh --check N    Exécute directement le contrôle N (équivaut à p90 check N)

EOF
}

mode="auto"
check_step=""
while (( $# )); do
    case "$1" in
        --gui)   mode="gui" ;;
        --cli)   mode="cli" ;;
        --check) shift; check_step="${1:-}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Option inconnue : $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ -n "$check_step" ]]; then
    exec bash "$P90_CLI" check "$check_step"
fi

case "$mode" in
    gui)
        command -v yad >/dev/null 2>&1 || { echo "✖ yad n'est pas installé." >&2; exit 1; }
        exec bash "${P90_ROOT}/launcher/gui.sh" ;;
    cli)
        exec bash "$P90_CLI" ;;
    auto)
        if command -v yad >/dev/null 2>&1; then
            exec bash "${P90_ROOT}/launcher/gui.sh"
        fi
        echo "ℹ yad absent — bascule sur le menu terminal." >&2
        exec bash "$P90_CLI" ;;
esac
