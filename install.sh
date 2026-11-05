#!/usr/bin/env bash
# =============================================================================
# install.sh — Installation / mise à jour du P90 Launcher depuis GitHub
#
# Dépôt officiel : https://github.com/Teacher2X/IPH-P90-CYBER
# Gitea n'est qu'une POC historique : ne plus y pousser.
#
# Usage :
#   bash install.sh              # installe (ou met à jour) dans /opt/p90-launcher
#   P90_INSTALL_DIR=~/p90 bash install.sh   # emplacement personnalisé
#
# Ce script ne fait rien de destructif : les données utilisateur vivent dans
# P90_DATA_DIR (sur la clé USB) et ne sont jamais touchées.
# =============================================================================
set -euo pipefail

P90_REPO_URL="${P90_REPO_URL:-https://github.com/Teacher2X/IPH-P90-CYBER.git}"
P90_BRANCH="${P90_BRANCH:-main}"
P90_INSTALL_DIR="${P90_INSTALL_DIR:-/opt/p90-launcher}"

echo "=== P90 Launcher — installation depuis GitHub ==="
echo "Dépôt    : ${P90_REPO_URL}"
echo "Branche  : ${P90_BRANCH}"
echo "Cible    : ${P90_INSTALL_DIR}"
echo

command -v git >/dev/null 2>&1 || { echo "✖ git est requis." >&2; exit 1; }

if [[ -d "${P90_INSTALL_DIR}/.git" ]]; then
    echo "→ Mise à jour du dépôt existant (aucune donnée utilisateur touchée)."
    git -C "${P90_INSTALL_DIR}" fetch --depth=1 origin "${P90_BRANCH}"
    # On refuse d'écraser un arbre de travail modifié localement.
    if ! git -C "${P90_INSTALL_DIR}" diff --quiet \
       || ! git -C "${P90_INSTALL_DIR}" diff --cached --quiet; then
        echo "✖ Des modifications locales non commitées existent dans ${P90_INSTALL_DIR}." >&2
        echo "  Elles ne seront pas écrasées. Commitez-les ou déplacez-vous," >&2
        echo "  puis relancez : git -C '${P90_INSTALL_DIR}' stash && bash install.sh" >&2
        exit 1
    fi
    git -C "${P90_INSTALL_DIR}" checkout -q FETCH_HEAD
else
    echo "→ Installation initiale."
    if [[ -d "${P90_INSTALL_DIR}" ]] && [[ -n "$(ls -A "${P90_INSTALL_DIR}" 2>/dev/null)" ]]; then
        echo "✖ ${P90_INSTALL_DIR} existe et n'est pas vide : rien n'est écrasé." >&2
        exit 1
    fi
    mkdir -p "$(dirname "${P90_INSTALL_DIR}")"
    git clone --depth=1 --branch "${P90_BRANCH}" \
        "${P90_REPO_URL}" "${P90_INSTALL_DIR}"
fi

chmod +x "${P90_INSTALL_DIR}"/launcher/*.sh \
         "${P90_INSTALL_DIR}"/launcher/p90 \
         "${P90_INSTALL_DIR}"/*.sh 2>/dev/null || true

# Lanceur `p90` sur le PATH utilisateur
BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"
ln -sf "${P90_INSTALL_DIR}/launcher/p90" "${BIN_DIR}/p90"

echo
echo "✔ P90 Launcher installé dans ${P90_INSTALL_DIR}"
echo "  Version : $(tr -d '[:space:]' < "${P90_INSTALL_DIR}/VERSION" 2>/dev/null || echo '?')"
echo "  Lanceur : ${BIN_DIR}/p90"
case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *) echo "  ⚠ ${BIN_DIR} n'est pas dans PATH — ajoutez-le ou appelez ${BIN_DIR}/p90 directement." ;;
esac
echo
echo "  Essayer : p90 check 1     (contrôle de persistance de la clé USB)"
echo "            p90             (menu graphique YAD, si installé)"
