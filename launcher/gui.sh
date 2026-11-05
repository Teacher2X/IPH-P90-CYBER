#!/usr/bin/env bash
# =============================================================================
# launcher/gui.sh — Interface graphique P90 Launcher (YAD)
#
# Principe : une fenêtre liste les cinq modules. L'utilisateur sélectionne une
# ligne, puis choisit une action. Chaque action s'applique au module SÉLECTIONNÉ.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
export P90_INSTALL_DIR="$INSTALL_DIR"

source "${INSTALL_DIR}/lib/common.sh"
source "${INSTALL_DIR}/lib/install.sh"

p90_ensure_data_dir
mkdir -p "${P90_DATA_DIR}/modules"

TITLE="P90 Launcher v${P90_VERSION}"

if ! command -v yad >/dev/null 2>&1; then
    p90_err "YAD n'est pas installé : interface graphique indisponible."
    p90_info "Installez-le : sudo apt install yad"
    p90_info "En attendant, utilisez : p90 status | p90 doctor | p90 install <module>"
    exit 1
fi

# --- Liste ordonnée des modules (source unique de vérité : les fichiers) ---
MOD_IDS=()
for f in "${INSTALL_DIR}"/modules/*.sh; do
    [[ -f "$f" ]] || continue
    MOD_IDS+=("$(basename "$f" .sh)")
done

# --- libellé lisible d'un état ---
state_label() {
    local id="$1" f="${P90_DATA_DIR}/modules/${1}.state"
    if [[ ! -f "$f" ]]; then echo "absent"; return; fi
    local s; s="$(head -1 "$f")"
    case "$s" in
        ready*)      echo "prêt" ;;
        installed*)  echo "installé" ;;
        broken*)     echo "défaillant" ;;
        stopped*)    echo "arrêté" ;;
        *)           echo "inconnu" ;;
    esac
}

# --- description pédagogique depuis config/modules.json (sans jq) ---
desc_of() {
    local id="$1" j="${INSTALL_DIR}/config/modules.json"
    [[ -f "$j" ]] || { echo ""; return; }
    python3 - "$j" "$id" <<'PY' 2>/dev/null || echo ""
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
mid = sys.argv[2]
mods = data.get("modules", [])
if isinstance(mods, dict):
    m = mods.get(mid) or {}
    if isinstance(m, dict):
        print(m.get("desc") or m.get("description") or "")
        sys.exit(0)
    sys.exit(1)
for m in mods:
    if isinstance(m, dict) and m.get("id") == mid:
        print(m.get("desc") or m.get("description") or "")
        sys.exit(0)
PY
}

# --- Construire les lignes du tableau YAD ---
# Colonnes : Module | État | Description
rows=""
for id in "${MOD_IDS[@]}"; do
    st="$(state_label "$id")"
    ds="$(desc_of "$id")"
    # YAD --list : séparateur | ; jamais de | dans les champs
    ds="${ds//|/-}"
    rows+="${id}|${st}|${ds}"$'\n'
done

# --- Contrôles d'installation (point 1, etc.) ------------------------------
# Le menu graphique n'invente aucun diagnostic : il exécute le MÊME script que
# `p90 check <n>` et affiche sa sortie brute, code de retour compris.
run_check_step() {
    local num="$1"
    local script_name
    if ! script_name="$(p90_check_script_of "$num")"; then
        yad --text="Étape inconnue : ${num}" --button="Fermer:0" --width=360 2>/dev/null
        return 1
    fi
    local script="${INSTALL_DIR}/launcher/${script_name}"
    if [[ ! -f "$script" ]]; then
        yad --text="Script introuvable :\n${script}" --button="Fermer:0" --width=460 2>/dev/null
        return 1
    fi

    local out rc
    out="$(bash "$script" 2>&1)"; rc=$?

    local verdict icon
    case $rc in
        0) verdict="PASS"      ; icon="dialog-information" ;;
        2) verdict="À CONFIRMER" ; icon="dialog-warning" ;;
        *) verdict="FAIL"      ; icon="dialog-error" ;;
    esac

    local esc
    esc="$(printf '%s' "$out" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
    yad --text="<b>${verdict}</b>  —  ${script_name}\n\n<tt>${esc}</tt>" \
        --title="Contrôle ${num} — code de retour ${rc}" \
        --width=720 --height=520 --center --scroll \
        --button="Fermer:0" 2>/dev/null
    return $rc
}

# --- Fenêtre des contrôles d'installation : une ligne par étape ---
menu_checks() {
    while true; do
        local rows_c="" num _scr lbl st
        while IFS='|' read -r num _scr lbl; do
            [[ -n "$num" ]] || continue
            rows_c+="${num}|${lbl}"$'\n'
        done < <(p90_check_steps)

        if [[ -z "$rows_c" ]]; then
            yad --text="Aucun contrôle d'installation déclaré." --button="Fermer:0" --width=400 2>/dev/null
            return 0
        fi

        local pick rc_c
        local summary; summary="$(p90_ollama_summary 2>/dev/null)"
        pick=$(printf '%s' "$rows_c" | yad --list \
            --title="Contrôles d'installation" \
            --text="<b>Sélectionnez un contrôle à exécuter.</b>\n<tt>${summary}</tt>" \
            --column="N°" --column="Contrôle" \
            --width=620 --height=280 --center \
            --print-column=1 --separator="|" \
            --button="Retour:0" --button="Exécuter:20" \
            2>/dev/null)
        rc_c=$?

        (( rc_c == 0 || rc_c == 1 || rc_c == 252 )) && return 0

        if (( rc_c == 20 )); then
            local sel="${pick%%|*}"
            if [[ -z "$sel" ]]; then
                yad --text="Sélectionnez d'abord un contrôle dans la liste." \
                    --button="Fermer:0" --width=420 2>/dev/null
                continue
            fi
            run_check_step "$sel" || true
        fi
    done
}

# --- Boucle principale : on revient au menu après chaque action ---
while true; do
    selection=$(
        printf '%s' "$rows" | yad --list \
            --title="$TITLE" \
            --text="<b>Sélectionnez un module, puis une action.</b>" \
            --column="Module" --column="État" --column="Description" \
            --width=760 --height=380 --center \
            --print-column=1 \
            --separator="|" \
            --button="Fermer:0" \
            --button="Contrôles:16" \
            --button="Documentation:10" \
            --button="Diagnostic:11" \
            --button="Réparer:12" \
            --button="Vérifier:13" \
            --button="Lancer:14" \
            --button="Installer:15" \
            2>/dev/null
    )
    rc=$?

    # Fenêtre fermée (croix ou bouton Fermer)
    (( rc == 0 || rc == 1 || rc == 252 )) && [[ -z "$selection" ]] && exit 0

    # Les contrôles d'installation ne portent sur aucun module : traités avant.
    if (( rc == 16 )); then
        menu_checks
        rows=""
        for id in "${MOD_IDS[@]}"; do
            rows+="${id}|$(state_label "$id")|$(desc_of "$id" | tr '|' '-')"$'\n'
        done
        continue
    fi

    # Extraire le module sélectionné
    mod_id="${selection%%|*}"
    [[ -n "$mod_id" ]] || exit 0

    case $rc in
        15)  # Installer
            if command -v xfce4-terminal >/dev/null 2>&1; then
                xfce4-terminal -x bash -lc \
                    "bash '${INSTALL_DIR}/launcher/p90' install '${mod_id}'; echo; read -rp 'Appuyez sur Entrée pour fermer…'"
            else
                x-terminal-emulator -e "bash '${INSTALL_DIR}/launcher/p90' install '${mod_id}'" 2>/dev/null \
                    || p90_err "Aucun terminal graphique disponible."
            fi
            ;;
        14)  # Lancer
            if command -v xfce4-terminal >/dev/null 2>&1; then
                xfce4-terminal -x bash -lc \
                    "bash '${INSTALL_DIR}/launcher/p90' run '${mod_id}'; echo; read -rp 'Appuyez sur Entrée pour fermer…'"
            else
                x-terminal-emulator -e "bash '${INSTALL_DIR}/launcher/p90' run '${mod_id}'" 2>/dev/null \
                    || p90_err "Aucun terminal graphique disponible."
            fi
            ;;
        13)  # Vérifier
            out="$(bash "${INSTALL_DIR}/modules/${mod_id}.sh" check 2>&1)"
            yad --text="<b>Vérification de ${mod_id}</b>\n\n<tt>$(printf '%s' "$out" | sed 's/&/\&amp;/g; s/</\&lt;/g')</tt>" \
                --title="Vérification" --width=640 --height=400 --center \
                --button="Fermer:0" 2>/dev/null
            ;;
        12)  # Réparer
            if command -v xfce4-terminal >/dev/null 2>&1; then
                xfce4-terminal -x bash -lc \
                    "bash '${INSTALL_DIR}/launcher/p90' repair '${mod_id}'; echo; read -rp 'Appuyez sur Entrée pour fermer…'"
            else
                p90_err "Terminal graphique requis pour la réparation."
            fi
            ;;
        11)  # Diagnostic complet
            out="$(bash "${INSTALL_DIR}/launcher/p90" doctor 2>&1)"
            yad --text="<tt>$(printf '%s' "$out" | sed 's/&/\&amp;/g; s/</\&lt;/g')</tt>" \
                --title="Diagnostic P90" --width=760 --height=560 --center \
                --scroll --button="Fermer:0" 2>/dev/null
            ;;
        10)  # Documentation
            doc=""
            [[ -f "${INSTALL_DIR}/docs/${mod_id}.md" ]] && doc="${INSTALL_DIR}/docs/${mod_id}.md"
            [[ -z "$doc" && -f "${INSTALL_DIR}/docs/enseignant.md" ]] && doc="${INSTALL_DIR}/docs/enseignant.md"
            if [[ -n "$doc" ]]; then
                if command -v xdg-open >/dev/null 2>&1; then
                    xdg-open "$doc" >/dev/null 2>&1 &
                else
                    yad --text="$(sed 's/&/\&amp;/g; s/</\&lt;/g' "$doc")" \
                        --title="Documentation" --width=760 --height=560 --scroll \
                        --button="Fermer:0" 2>/dev/null
                fi
            else
                yad --text="Aucune documentation pour ${mod_id}." \
                    --button="Fermer:0" --width=400 2>/dev/null
            fi
            ;;
    esac

    # Rafraîchir les états après action
    rows=""
    for id in "${MOD_IDS[@]}"; do
        rows+="${id}|$(state_label "$id")|$(desc_of "$id" | tr '|' '-')"$'\n'
    done
done
