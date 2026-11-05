#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — Installation initiale de P90 Launcher
#
# Usage :
#   curl -fsSL https://raw.githubusercontent.com/Teacher2X/IPH-P90-CYBER/main/bootstrap.sh | bash
#   ou, si le dépôt est déjà récupéré :
#   bash bootstrap.sh
#
# La source de vérité est le dépôt GitHub officiel Teacher2X/IPH-P90-CYBER.
# Gitea n'est plus qu'une POC historique : ne pas y pousser.
# =============================================================================

set -euo pipefail

P90_INSTALL_DIR="${P90_INSTALL_DIR:-/opt/p90-launcher}"
P90_BOOTSTRAP_VERSION="0.1.0"

# URL du dépôt : surchargeable, sinon valeur du dépôt local si présent
if [[ -z "${P90_REPO_URL:-}" ]]; then
    if [[ -d "$(dirname "${BASH_SOURCE[0]}")/.git" ]]; then
        P90_REPO_URL="$(git -C "$(dirname "${BASH_SOURCE[0]}")" remote get-url origin 2>/dev/null || echo "")"
    fi
fi
P90_REPO_URL="${P90_REPO_URL:-https://github.com/Teacher2X/IPH-P90-CYBER.git}"

echo "============================================================"
echo "   Installation P90 Launcher v${P90_BOOTSTRAP_VERSION}"
echo "============================================================"
echo ""

# --- 1. Vérifications préalables ---
prechecks() {
    local ok=0

    if [[ ! -r /proc/version ]] || ! grep -qi 'linux' /proc/version 2>/dev/null; then
        echo "❌ Système non Linux détecté. P90 Launcher nécessite Linux."
        return 1
    fi
    echo "✅ Linux détecté"

    local arch; arch="$(uname -m)"
    case "$arch" in
        x86_64|aarch64|arm64) echo "✅ Architecture ${arch} compatible" ;;
        *) echo "⚠️  Architecture ${arch} : non testée." ;;
    esac

    # Bash ≥ 4
    local maj="${BASH_VERSINFO[0]:-0}"
    if (( maj >= 4 )); then
        echo "✅ Bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
    else
        echo "❌ Bash ≥ 4 requis (trouvé ${BASH_VERSION:-inconnu})"
        ok=1
    fi

    if command -v curl >/dev/null 2>&1; then
        echo "✅ curl disponible"
    else
        echo "❌ curl requis mais absent"
        ok=1
    fi

    if command -v git >/dev/null 2>&1; then
        echo "✅ git disponible"
    else
        echo "⚠️  git non détecté — nécessaire pour les mises à jour depuis GitHub"
    fi

    if [[ -r /proc/meminfo ]]; then
        local total_kb
        total_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo)"
        if [[ "$total_kb" =~ ^[0-9]+$ ]]; then
            echo "✅ RAM totale : $((total_kb / 1024)) Mo"
        fi
    fi

    return $ok
}

# --- 2. Récupération du code (GitHub) ---
fetch_code() {
    echo ""
    echo "--- Récupération du code ---"

    if [[ -d "${P90_INSTALL_DIR}/.git" ]]; then
        echo "Dépôt déjà présent : mise à jour (git pull)."
        git -C "$P90_INSTALL_DIR" pull --ff-only || {
            echo "⚠️  git pull impossible — l'installation existante est conservée."
            return 1
        }
    elif [[ -d "${P90_INSTALL_DIR}" ]] && [[ -n "$(ls -A "$P90_INSTALL_DIR" 2>/dev/null)" ]]; then
        echo "⚠️  ${P90_INSTALL_DIR} existe déjà et n'est pas un dépôt Git."
        echo "    Aucune modification effectuée pour ne rien écraser."
        return 1
    else
        if [[ -z "$P90_REPO_URL" ]]; then
            echo "❌ Aucune source de code définie."
            echo "   Relancez avec : P90_REPO_URL=https://github.com/Teacher2X/IPH-P90-CYBER.git bash bootstrap.sh"
            return 1
        fi
        mkdir -p "$(dirname "$P90_INSTALL_DIR")"
        git clone --depth=1 "$P90_REPO_URL" "$P90_INSTALL_DIR" || {
            echo "❌ Clone impossible depuis ${P90_REPO_URL}"
            echo "   Vérifiez le réseau et les droits d'accès au dépôt privé."
            return 1
        }
        echo "Code récupéré dans ${P90_INSTALL_DIR}"
    fi

    if [[ -f "${P90_INSTALL_DIR}/VERSION" ]]; then
        echo "Version : $(tr -d '[:space:]' < "${P90_INSTALL_DIR}/VERSION")"
    fi
    return 0
}

# --- 3. Accès à la commande p90 ---
make_p90_accessible() {
    echo ""
    echo "--- Accès à la commande 'p90' ---"

    local launcher_dir="${P90_INSTALL_DIR}/launcher"
    local rc_file="${HOME}/.bashrc"

    if [[ -f "$rc_file" ]] && grep -qF "${launcher_dir}" "$rc_file" 2>/dev/null; then
        echo "🟡 PATH déjà configuré dans ${rc_file}"
    else
        {
            echo ""
            echo "# P90 Launcher — accès à la commande p90"
            echo "export PATH=\"\$PATH:${launcher_dir}\""
        } >> "$rc_file"
        echo "✅ ${rc_file} mis à jour"
    fi

    chmod +x "${launcher_dir}/p90" 2>/dev/null || true
    echo "ℹ️  Redémarrez le terminal (ou : source ${rc_file}) pour activer 'p90'."
}

# --- 4. Initialisation des données ---
init_data() {
    echo ""
    echo "--- Initialisation des données ---"

    # shellcheck disable=SC1091
    source "${P90_INSTALL_DIR}/lib/common.sh"
    # shellcheck disable=SC1091
    source "${P90_INSTALL_DIR}/lib/install.sh"
    install_data_dirs
    echo "✅ Données initialisées dans ${P90_DATA_DIR}"
}

# --- 5. Raccourci de bureau ---
install_desktop_entry() {
    echo ""
    echo "--- Raccourci de bureau ---"

    local src="${P90_INSTALL_DIR}/launcher/p90.desktop"
    if [[ ! -f "$src" ]]; then
        echo "🟡 Fichier .desktop absent : raccourci non créé."
        return 0
    fi

    local desktop_dir
    desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || echo "${HOME}/Desktop")"
    if [[ ! -d "$desktop_dir" ]]; then
        echo "🟡 Bureau non détecté. Copie manuelle possible :"
        echo "   cp ${src} ~/Desktop/"
        return 0
    fi

    local dest="${desktop_dir}/p90-launcher.desktop"
    sed "s|^Exec=.*|Exec=${P90_INSTALL_DIR}/launcher/p90|" "$src" > "$dest"
    chmod +x "$dest"
    echo "✅ Raccourci : ${dest}"
}

# --- Exécution ---
main() {
    echo ""
    if ! prechecks; then
        echo ""
        echo "⚠️  Des prérequis manquent."
        if [[ -t 0 ]]; then
            read -r -p "Continuer malgré tout ? (o/N) " rep
            case "${rep,,}" in o|oui|y|yes) ;; *) echo "Installation annulée."; exit 1 ;; esac
        else
            echo "Mode non interactif : installation interrompue."
            exit 1
        fi
    fi

    fetch_code || {
        echo ""
        echo "❌ Récupération du code impossible. Aucune modification des données."
        exit 1
    }
    make_p90_accessible
    init_data
    install_desktop_entry

    echo ""
    echo "============================================================"
    echo "   P90 Launcher v${P90_BOOTSTRAP_VERSION} installé"
    echo "============================================================"
    echo ""
    echo "Prochaines étapes :"
    echo "  1. Redémarrez le terminal (pour activer 'p90')"
    echo "  2. Lancez : p90"
    echo "  3. Documentation : ${P90_INSTALL_DIR}/docs/enseignant.md"
    echo ""
}

main "$@"
