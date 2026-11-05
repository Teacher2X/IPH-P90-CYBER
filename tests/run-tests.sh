#!/usr/bin/env bash
# =============================================================================
# tests/run-tests.sh — Suite de tests automatisés P90 Launcher
#
# Tests STATIQUES uniquement (pas de Docker, pas de réseau, pas de modèle).
# Une validation statique ne remplace PAS un test sur clé USB réelle.
#
# Usage : bash tests/run-tests.sh
# =============================================================================

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
SKIP=0
declare -a FAILURES=()

c_green=$'\033[0;32m'; c_red=$'\033[0;31m'; c_yellow=$'\033[1;33m'
c_bold=$'\033[1m'; c_reset=$'\033[0m'

t_ok()   { PASS=$((PASS+1)); printf '  %sPASS%s  %s\n' "$c_green" "$c_reset" "$1"; }
t_fail() { FAIL=$((FAIL+1)); FAILURES+=("$1"); printf '  %sFAIL%s  %s\n' "$c_red" "$c_reset" "$1"; }
t_skip() { SKIP=$((SKIP+1)); printf '  %sSKIP%s  %s\n' "$c_yellow" "$c_reset" "$1"; }
section() { printf '\n%s== %s ==%s\n' "$c_bold" "$1" "$c_reset"; }

# ---------------------------------------------------------------------------
section "1. Syntaxe Bash (bash -n)"
# ---------------------------------------------------------------------------
while IFS= read -r f; do
    rel="${f#"$ROOT"/}"
    if bash -n "$f" 2>/dev/null; then
        t_ok "syntaxe OK : $rel"
    else
        t_fail "syntaxe KO : $rel"
        bash -n "$f" 2>&1 | head -3 | sed 's/^/         /'
    fi
done < <(find "$ROOT" -name '*.sh' -o -name 'p90' -type f | grep -v '/tests/' | sort)

# ---------------------------------------------------------------------------
section "2. ShellCheck (si disponible)"
# ---------------------------------------------------------------------------
SC_BIN="$(command -v shellcheck 2>/dev/null || true)"
[[ -z "$SC_BIN" && -x /tmp/shellcheck-v0.10.0/shellcheck ]] && SC_BIN=/tmp/shellcheck-v0.10.0/shellcheck
if [[ -n "$SC_BIN" ]]; then
    t_ok "shellcheck : $($SC_BIN --version 2>/dev/null | tail -1)"
    while IFS= read -r f; do
        rel="${f#"$ROOT"/}"
        # severité error uniquement : le style warning n'est pas bloquant ici
        if "$SC_BIN" -S error -e SC1091 "$f" >/dev/null 2>&1; then
            t_ok "shellcheck (error) : $rel"
        else
            t_fail "shellcheck (error) : $rel"
            "$SC_BIN" -S error -e SC1091 "$f" 2>&1 | head -6 | sed 's/^/         /'
        fi
    done < <(find "$ROOT" -name '*.sh' -o -name 'p90' -type f | grep -v '/tests/' | sort)
else
    t_skip "shellcheck absent de la machine de développement"
fi

# ---------------------------------------------------------------------------
section "3. Arborescence attendue"
# ---------------------------------------------------------------------------
expected=(
    "README.md" "bootstrap.sh" "VERSION"
    "config/p90.conf" "config/modules.json"
    "launcher/p90" "launcher/gui.sh" "launcher/diagnose.sh" "launcher/p90.desktop"
    "lib/common.sh" "lib/checks.sh" "lib/install.sh" "lib/update.sh"
    "modules/A1-ollama.sh" "modules/A2-openwebui.sh" "modules/A3-hermes.sh"
    "modules/A4-whatsapp.sh" "modules/A5-memory-rag.sh"
    "compose/openwebui.yaml" "compose/waha.yaml"
    "docs/enseignant.md" "docs/A1-ollama.md" "docs/A2-openwebui.md"
    "docs/A3-hermes.md" "docs/A4-whatsapp.md" "docs/A5-memory-rag.md"
    ".gitignore"
)
for f in "${expected[@]}"; do
    if [[ -f "$ROOT/$f" ]]; then t_ok "présent : $f"; else t_fail "manquant : $f"; fi
done

# ---------------------------------------------------------------------------
section "4. Interface des modules (install/check|status/launch/repair)"
# ---------------------------------------------------------------------------
for m in A1-ollama A2-openwebui A3-hermes A4-whatsapp A5-memory-rag; do
    f="$ROOT/modules/$m.sh"
    [[ -f "$f" ]] || { t_fail "$m : fichier absent"; continue; }
    # Les fonctions doivent être définies avec l'identifiant sans suffixe module
    base="${m#*-}"; base="${base//-/_}"
    for fn in "install_${base}" "check_${base}" "launch_${base}" "repair_${base}"; do
        if grep -qE "^${fn}\(\)" "$f"; then
            t_ok "$m : ${fn}()"
        else
            t_fail "$m : ${fn}() manquante"
        fi
    done
    # dispatch
    for sub in install check launch repair; do
        grep -qE "^\s*${sub}\|?[a-z|]*\)" "$f" \
            && t_ok "$m : dispatch '$sub'" \
            || t_fail "$m : dispatch '$sub' absent"
    done
done

# ---------------------------------------------------------------------------
section "5. Documentation liée aux modules"
# ---------------------------------------------------------------------------
for m in A1-ollama A2-openwebui A3-hermes A4-whatsapp A5-memory-rag; do
    d="$ROOT/docs/${m}.md"
    if [[ -s "$d" ]]; then
        n=$(wc -l < "$d")
        (( n > 20 )) && t_ok "doc $m : ${n} lignes" || t_fail "doc $m : trop courte (${n} lignes)"
    else
        t_fail "doc $m absente"
    fi
done

# ---------------------------------------------------------------------------
section "6. Pas de secrets dans le dépôt"
# ---------------------------------------------------------------------------
# Motifs de secrets réels (pas les exemples de doc)
secret_patterns=(
    'ghp_[A-Za-z0-9]{20,}'
    'github_pat_[A-Za-z0-9_]{20,}'
    'sk-[A-Za-z0-9]{20,}'
    'AKIA[0-9A-Z]{16}'
    'BEGIN (RSA|OPENSSH|EC) PRIVATE KEY'
)
leak=0
for pat in "${secret_patterns[@]}"; do
    hits=$(grep -rIlE "$pat" "$ROOT" \
            --exclude-dir=.git --exclude-dir=tests 2>/dev/null || true)
    if [[ -n "$hits" ]]; then
        t_fail "secret potentiel (motif ${pat:0:18}…) dans : $hits"
        leak=1
    fi
done
(( leak == 0 )) && t_ok "aucun motif de secret détecté"

# Fichiers sensibles interdits
for bad in ".env" "id_rsa" "id_ed25519" "credentials.json"; do
    if find "$ROOT" -name "$bad" -not -path '*/.git/*' | grep -q .; then
        t_fail "fichier sensible présent : $bad"
    fi
done
t_ok "aucun fichier sensible connu"

# ---------------------------------------------------------------------------
section "7. Aucune donnée utilisateur versionnable"
# ---------------------------------------------------------------------------
if [[ -f "$ROOT/.gitignore" ]]; then
    for patt in '.p90-data' 'state' 'models' 'waha-session'; do
        grep -qF -- "$patt" "$ROOT/.gitignore" \
            && t_ok ".gitignore couvre : $patt" \
            || t_fail ".gitignore ne couvre pas : $patt"
    done
else
    t_fail ".gitignore absent"
fi

# ---------------------------------------------------------------------------
section "8. Configuration"
# ---------------------------------------------------------------------------
if bash -c "source '$ROOT/lib/common.sh' 2>/dev/null"; then
    t_ok "lib/common.sh se charge sans erreur"
else
    t_fail "lib/common.sh ne se charge pas"
fi

if python3 -c "import json,sys; json.load(open('$ROOT/config/modules.json'))" 2>/dev/null; then
    t_ok "config/modules.json est un JSON valide"
    # Cohérence : les 5 modules déclarés existent bien comme fichiers
    for mid in A1-ollama A2-openwebui A3-hermes A4-whatsapp A5-memory-rag; do
        if python3 - "$ROOT/config/modules.json" "$mid" <<'PY' >/dev/null 2>&1
import json,sys
d=json.load(open(sys.argv[1])); mods=d.get("modules")
assert mods, "clé 'modules' absente"
ids = list(mods.keys()) if isinstance(mods,dict) else [m.get("id") for m in mods]
sys.exit(0 if sys.argv[2] in ids else 1)
PY
        then t_ok "modules.json déclare $mid"; else t_fail "modules.json ne déclare pas $mid"; fi
    done
else
    t_fail "config/modules.json invalide"
fi

# config/p90.conf doit être du Bash valide (aucune section [ini])
if bash -n "$ROOT/config/p90.conf" 2>/dev/null; then
    t_ok "config/p90.conf est du Bash valide"
else
    t_fail "config/p90.conf contient une syntaxe non Bash (sections ini ?)"
fi

# Ports cohérents entre p90.conf et les fichiers Compose
conf_waha=$(grep -oP '^P90_WAHA_PORT=\K[0-9]+' "$ROOT/config/p90.conf" 2>/dev/null || echo "")
if [[ -n "$conf_waha" ]] && grep -q "127.0.0.1:${conf_waha}" "$ROOT/compose/waha.yaml" 2>/dev/null; then
    t_ok "port WAHA cohérent entre p90.conf (${conf_waha}) et waha.yaml"
else
    t_fail "port WAHA incohérent entre p90.conf et waha.yaml"
fi
conf_owui=$(grep -oP '^P90_OPENWEBUI_PORT=\K[0-9]+' "$ROOT/config/p90.conf" 2>/dev/null || echo "")
if [[ -n "$conf_owui" ]] && grep -q ":${conf_owui}:8080" "$ROOT/compose/openwebui.yaml" 2>/dev/null; then
    t_ok "port OpenWebUI cohérent entre p90.conf (${conf_owui}) et openwebui.yaml"
else
    t_fail "port OpenWebUI incohérent entre p90.conf et openwebui.yaml"
fi

# Ports : vérifier la contrainte de sécurité essentielle
if grep -q '11434:11434' "$ROOT/compose/openwebui.yaml" 2>/dev/null; then
    t_fail "openwebui.yaml publie Ollama sur 11434 (interdit)"
else
    t_ok "Ollama n'est pas publié sur le LAN dans openwebui.yaml"
fi
if grep -qE 'WEBUI_AUTH=true' "$ROOT/compose/openwebui.yaml" 2>/dev/null; then
    t_ok "WEBUI_AUTH=true présent"
else
    t_fail "WEBUI_AUTH=true absent"
fi
if grep -qE '127\.0\.0\.1:3001' "$ROOT/compose/waha.yaml" 2>/dev/null; then
    t_ok "WAHA écoute en local seulement (127.0.0.1)"
else
    t_fail "WAHA n'est pas restreint à 127.0.0.1"
fi

# ---------------------------------------------------------------------------
section "9. Persistance des données (chemins hors code)"
# ---------------------------------------------------------------------------
if grep -q 'P90_DATA_DIR' "$ROOT/lib/common.sh"; then
    t_ok "P90_DATA_DIR défini dans common.sh"
else
    t_fail "P90_DATA_DIR absent"
fi
# Les volumes Compose doivent pointer hors du dépôt
for yml in openwebui waha; do
    if grep -q 'P90_DATA_DIR' "$ROOT/compose/$yml.yaml" 2>/dev/null; then
        t_ok "$yml.yaml : volumes sur P90_DATA_DIR"
    else
        t_fail "$yml.yaml : volumes non persistants"
    fi
done

# ---------------------------------------------------------------------------
section "10. Ré-exécution / idempotence (garde-fous présents)"
# ---------------------------------------------------------------------------
if grep -qE 'déjà installé|deja installe' "$ROOT/lib/install.sh" 2>/dev/null; then
    t_ok "install.sh vérifie l'état avant réinstallation"
else
    t_fail "install.sh sans garde-fou de réinstallation"
fi
grep -qE 'mkdir -p' "$ROOT/modules/A5-memory-rag.sh" \
    && t_ok "A5 : création de répertoires idempotente (mkdir -p)" \
    || t_fail "A5 : mkdir non idempotent"

# ---------------------------------------------------------------------------
section "11. Contraintes de sécurité du cahier des charges"
# ---------------------------------------------------------------------------
grep -q '0\.0\.0\.0:3000' "$ROOT/compose/openwebui.yaml" \
    && t_ok "OpenWebUI écoute sur 0.0.0.0:3000 (accès LAN pédagogique)" \
    || t_fail "OpenWebUI n'écoute pas sur 0.0.0.0:3000"

grep -qi 'pas de synchronisation automatique\|manuel' "$ROOT/docs/enseignant.md" \
    && t_ok "export GitHub documenté comme manuel" \
    || t_fail "procédure d'export GitHub absente"

if grep -q 'repartitionner\|disque interne' "$ROOT/README.md"; then
    t_ok "README rappelle l'interdiction de repartitionner"
else
    t_skip "README : rappel de non-repartitionnement non trouvé (vérifier manuellement)"
fi

# ---------------------------------------------------------------------------
# Résumé
# ---------------------------------------------------------------------------
printf '\n%s================ RÉSULTAT ================%s\n' "$c_bold" "$c_reset"
printf 'PASS : %d   FAIL : %d   SKIP : %d\n' "$PASS" "$FAIL" "$SKIP"
if (( FAIL > 0 )); then
    printf '\n%sÉchecs :%s\n' "$c_red" "$c_reset"
    for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
    printf '\n%sRappel : validation statique ≠ validation fonctionnelle sur clé USB.%s\n' \
        "$c_yellow" "$c_reset"
    exit 1
fi
printf '\n%sTous les contrôles statiques passent.%s\n' "$c_green" "$c_reset"
printf '%sRappel : validation statique ≠ validation fonctionnelle sur clé USB.%s\n' \
    "$c_yellow" "$c_reset"
exit 0
