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
section "12. Étape 2 — Ollama (POC CPU)"
# ---------------------------------------------------------------------------
S2="$ROOT/launcher/02-install-ollama.sh"
if [[ -f "$S2" ]]; then
    t_ok "script 02 présent"
    # Codes de retour documentés
    for c in "0 = PASS" "1 = FAIL" "2 = À CONFIRMER"; do
        grep -qF "$c" "$S2" && t_ok "code retour documenté : $c" || t_fail "code retour non documenté : $c"
    done
    # Empreinte du binaire épinglée (pas de « dernière version » implicite)
    grep -qE '^OLLAMA_SHA256=|P90_OLLAMA_SHA256' "$S2" \
        && t_ok "SHA256 du binaire épinglée" || t_fail "SHA256 non épinglée"
    grep -qE 'P90_OLLAMA_VERSION:-' "$S2" \
        && t_ok "version Ollama demandée explicitement" || t_fail "version non épinglée"
    # Contrôles exigés par le cahier des charges
    grep -q 'sha256sum' "$S2" && t_ok "contrôle d'empreinte avant extraction" || t_fail "pas de contrôle d'empreinte"
    grep -q 'MIN_FREE_MB' "$S2" && t_ok "seuil d'espace libre vérifié" || t_fail "pas de seuil d'espace"
    grep -q 'BACK_TRAN' "$S2" && t_ok "persistance vérifiée par transport USB" || t_fail "persistance non vérifiée"
    grep -q '127\.0\.0\.1' "$S2" && t_ok "écoute limitée à 127.0.0.1" || t_fail "pas de restriction d'écoute"
    grep -q 'systemctl enable' "$S2" && t_ok "démarrage automatique configuré" || t_fail "démarrage auto absent"
    # Idempotence : garde-fous avant réinstallation / re-téléchargement
    grep -q 'déjà présent' "$S2" && t_ok "garde-fou : réutilisation si déjà installé" || t_fail "pas de garde-fou de réinstallation"
    grep -q 'Modèle déjà présent' "$S2" && t_ok "garde-fou : modèle non retéléchargé" || t_fail "modèle retéléchargé à chaque fois"
    # Interdits
    if grep -qE '\b(mkfs|sfdisk|parted|fdisk|wipefs)\b' "$S2"; then
        t_fail "commande de partitionnement/formatage présente"
    else
        t_ok "aucune commande de formatage ou de partitionnement"
    fi
    if grep -qE '\breboot\b|shutdown' "$S2"; then
        t_fail "redémarrage automatique présent (interdit)"
    else
        t_ok "aucun redémarrage automatique"
    fi
    grep -q 'CUDA\|rocm' "$S2" && t_skip "mention GPU présente (vérifier qu'elle n'installe rien)" || t_ok "aucune dépendance GPU"
    # Le verdict doit exiger une génération réelle, pas un simple téléchargement
    grep -q 'api/generate' "$S2" && t_ok "génération réelle testée via /api/generate" || t_fail "aucun test de génération API"
    grep -q 'verdict_reponse' "$S2" && t_ok "verdict sémantique sur la réponse" || t_fail "verdict absent"
else
    t_fail "script 02 absent"
fi

# Déclaration dans la source unique des étapes
if grep -q '2|02-install-ollama.sh' "$ROOT/config/p90.conf"; then
    t_ok "étape 2 déclarée dans config/p90.conf"
else
    t_fail "étape 2 non déclarée dans config/p90.conf"
fi

# CLI et GUI résolvent le MÊME script (pas de duplication de commandes)
if bash -c "source '$ROOT/lib/common.sh'; [[ \"\$(p90_check_script_of 2)\" == '02-install-ollama.sh' ]]"; then
    t_ok "p90 check 2 résout le script de l'étape 2"
else
    t_fail "p90 check 2 ne résout pas le script de l'étape 2"
fi
grep -q 'run_check_step' "$ROOT/launcher/gui.sh" \
    && t_ok "menu YAD délègue au même script" || t_fail "menu YAD ne délègue pas"

# Documentation de l'étape
D2="$ROOT/docs/etapes/02-ollama-poc.md"
if [[ -s "$D2" ]] && (( $(wc -l < "$D2") > 40 )); then
    t_ok "doc étape 2 présente ($(wc -l < "$D2") lignes)"
else
    t_fail "doc étape 2 absente ou trop courte"
fi
grep -q '02-ollama-poc.md' "$ROOT/README.md" && t_ok "README pointe la fiche étape 2" || t_fail "README ne pointe pas la fiche"

# ---------------------------------------------------------------------------
section "13. Étape 3 — partage réseau d'Ollama"
# ---------------------------------------------------------------------------
S3="$ROOT/launcher/03-share-ollama.sh"
[[ -f "$S3" ]] && t_ok "script 03 présent" || t_fail "script 03 absent"
for code in '0 = PASS' '1 = FAIL' '2 = À CONFIRMER'; do
    grep -q "$code" "$S3" && t_ok "code retour documenté : $code" || t_fail "code retour non documenté : $code"
done

# OLLAMA_HOST doit passer sur 0.0.0.0, mais JAMAIS dans l'unité d'installation (étape 2)
grep -q 'OLLAMA_HOST=0.0.0.0' "$S3" && t_ok "partage : écoute sur 0.0.0.0" || t_fail "OLLAMA_HOST non élargi"
grep -q 'OLLAMA_HOST=127.0.0.1' "$ROOT/launcher/02-install-ollama.sh" \
    && t_ok "étape 2 conserve une écoute locale" || t_fail "étape 2 n'est plus locale"

# Filtrage réellement présent ET restriction effective
grep -q 'table inet' "$S3" && t_ok "règle nftables générée" || t_fail "aucune règle nftables"
grep -q 'tcp dport ${PORT} drop' "$S3" && t_ok "règle de rejet présente" || t_fail "aucune règle de rejet"
grep -q 'ip saddr @allowed_ipv4 accept' "$S3" && t_ok "accept limité au jeu d'adresses" || t_fail "accept non restreint"

# Garde-fous de restriction
grep -q 'préfixe >= /16' "$S3" && t_ok "garde-fou : plage trop large refusée" || t_fail "pas de garde-fou sur /0"
grep -q 'is_ipv4' "$S3" && t_ok "validation IPv4/CIDR présente" || t_fail "pas de validation d'adresse"

# Le modèle ne doit PAS être retéléchargé par cette étape
grep -qE '(\$BIN|ollama) pull' "$S3" \
    && t_fail "l'étape 3 lance un pull (interdit : aucun téléchargement)" \
    || t_ok "aucun téléchargement de modèle dans l'étape 3"

# Preuve distante obligatoire pour un PASS ; pas de PASS déguisé
grep -q 'remote-test' "$S3" && t_ok "test distant supporté" || t_fail "aucun test distant"
grep -q 'génération distante NON testée' "$S3" \
    && t_ok "absence de preuve distante signalée" || t_fail "absence de preuve non signalée"

# Aucun joker CORS, aucun redémarrage, aucune écriture sur disque interne
grep -q 'OLLAMA_ORIGINS=http://127.0.0.1,http://localhost,http://' "$S3" \
    && t_ok "ORIGINS explicites (sans joker)" || t_skip "forme des ORIGINS à revoir"
grep -qE '(^|[^a-z])reboot|shutdown' "$S3" && t_fail "redémarrage machine demandé" || t_ok "aucun redémarrage machine"
grep -qE 'mkfs|fdisk|parted|dd ' "$S3" && t_fail "commande de partitionnement détectée" || t_ok "aucun partitionnement"

# Déclaration dans la source unique + résolution CLI/YAD
grep -q '3|03-share-ollama.sh' "$ROOT/config/p90.conf" && t_ok "étape 3 déclarée dans config/p90.conf" || t_fail "étape 3 non déclarée"
if bash -c "source '$ROOT/lib/common.sh'; [[ \"\$(p90_check_script_of 3)\" == '03-share-ollama.sh' ]]"; then
    t_ok "p90 check 3 résout le script de l'étape 3"
else
    t_fail "p90 check 3 ne résout pas le script de l'étape 3"
fi

D3="$ROOT/docs/etapes/03-partage-reseau.md"
if [[ -s "$D3" ]] && (( $(wc -l < "$D3") > 40 )); then
    t_ok "doc étape 3 présente ($(wc -l < "$D3") lignes)"
else
    t_fail "doc étape 3 absente ou trop courte"
fi
grep -q '03-partage-reseau.md' "$ROOT/README.md" && t_ok "README pointe la fiche étape 3" || t_fail "README ne pointe pas la fiche 3"


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
