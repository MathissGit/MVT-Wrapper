#!/usr/bin/env bash
# ============================================================
#  FONCTIONS PARTAGEES DU WRAPPER MVT
#  (journalisation, prompts, hash, verrouillage, rapports)
# ============================================================

# ------------------------------------------------------------------
# Journalisation colorée
# ------------------------------------------------------------------
if [ -t 1 ]; then
  C_RESET=$'\033[0m';  C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[0;33m'
  C_RED=$'\033[0;31m'; C_CYAN=$'\033[0;36m';  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'; C_REV=$'\033[7m'
else
  C_RESET=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_BOLD=""
  C_DIM=""; C_REV=""
fi
[ -n "${NO_COLOR:-}" ] && { C_RESET=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_BOLD=""; C_DIM=""; C_REV=""; }

NOW() { date '+%Y-%m-%d %H:%M:%S'; }
log_info()  { printf '%s %s[INFO]%s %s\n' "$(NOW)"  "$C_CYAN"   "$C_RESET" "$*"; }
log_ok()    { printf '%s %s[OK]%s %s\n'   "$(NOW)"  "$C_GREEN"  "$C_RESET" "$*"; }
log_warn()  { printf '%s %s[WARN]%s %s\n' "$(NOW)"  "$C_YELLOW" "$C_RESET" "$*"; }
log_err()   { printf '%s %s[ERREUR]%s %s\n' "$(NOW)" "$C_RED"   "$C_RESET" "$*" >&2; }
banner()    { printf '%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
hline()     { printf '%s\n' '--------------------------------------------------------------'; }

# Efface l'écran (tput si dispo). Ignoré si la sortie n'est pas un terminal.
screen_clear() {
  [ -t 1 ] || return 0
  if have tput; then tput clear; else printf '\033[2J\033[H'; fi
}

# Titre ASCII (figlet) coloré, repli sur banner si figlet absent / sortie non-tty.
# $1 = titre ; $2 = sous-titre facultatif.
ascii_banner() {
  local title="${1:-MVT WRAPPER}" sub="${2:-}" w
  if [ -t 1 ] && have figlet; then
    w="$(tput cols 2>/dev/null || printf '90')"
    [ "${w:-0}" -lt 30 ] && w=90
    figlet -w "$w" "$title" | while IFS= read -r l; do
      printf '%s%s%s\n' "$C_CYAN" "$l" "$C_RESET"
    done
  else
    banner "$title"
  fi
  if [ -n "$sub" ]; then
    printf '%s%s%s\n' "$C_BOLD$C_CYAN" "$sub" "$C_RESET"
    hline
  fi
}

die() { log_err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Ajoute ~/.local/bin et les outils téléchargés au PATH (si absents).
ensure_path() {
  local d
  for d in "$HOME/.local/bin" "$ADB_EXTRA_DIR"; do
    if [ -d "$d" ] && [[ ":$PATH:" != *":$d:"* ]]; then
      export PATH="$d:$PATH"
    fi
  done
}
ensure_path

# ------------------------------------------------------------------
# Prompts interactifs
# ------------------------------------------------------------------

# Demande oui/non ; $2 = valeur par défaut ("y" ou "n"). Retour 0 = oui.
ask_yesno() {
  local msg="$1" def="${2:-n}" rep
  while :; do
    printf '%s [%s] ' "$msg" "$([ "$def" = "y" ] && echo "Y/n" || echo "y/N")" >&2
    read -r rep || rep="$def"
    [ -z "$rep" ] && rep="$def"
    case "$rep" in
      y|Y|o|O|oui|Oui) return 0 ;;
      n|N|Non|non)     return 1 ;;
      *) echo "Répondez y (oui) ou n (non)." >&2 ;;
    esac
  done
}

# Demande un texte ; $2 = valeur par défaut (optionnelle). Imprime le résultat.
ask_input() {
  local msg="$1" def="${2:-}" rep
  if [ -n "$def" ]; then
    printf '%s [%s] ' "$msg" "$def" >&2
    read -r rep || return 1
    printf '%s' "${rep:-$def}"
  else
    printf '%s ' "$msg" >&2
    read -r rep || return 1
    printf '%s' "$rep"
  fi
}

# ------------------------------------------------------------------
# Choix du chemin d'acquisition / backup : flèches (candidats auto
# détectés) PUIS gestionnaire de fichiers (zenity/kdialog si présent)
# PUIS saisie (repli). Ne modifie jamais le terminal ; retourne un
# chemin canonique existant.
# ------------------------------------------------------------------
pick_acquisition_path() {
  local candidates=() c pf default_dir
  default_dir="${CASE_DIR:-$PWD}"
  # 1. Candidats auto-détectés dans le périmètre courant (lecture seule)
  if [ -n "$default_dir" ] && [ -d "$default_dir" ]; then
    while IFS= read -r c; do
      [ -n "$c" ] && candidates+=("$c")
    done < <(find "$default_dir" -maxdepth 2 \( -name '*.ab' -o -name '*.zip' -o -name 'Manifest.db' \) 2>/dev/null)
  fi
  # 2. Gestionnaire de fichiers si dispo : résultat placé en tête de liste
  pf=""
  if command -v zenity >/dev/null 2>&1; then
    pf="$(zenity --file-selection --title="Choisir l'acquisition / backup" --filename="${default_dir}/" 2>/dev/null || true)"
  elif command -v kdialog >/dev/null 2>&1; then
    pf="$(kdialog --getexistingdirectory "$default_dir" 2>/dev/null || true)"
  fi
  [ -n "$pf" ] && candidates=( "$pf" "${candidates[@]}" )
  # 3. Menu fléché si candidats, sinon saisie directe (repli)
  if [ "${#candidates[@]}" -gt 0 ]; then
    local chosen
    chosen="$(menu_select "Chemin de l'acquisition / backup :" "${candidates[@]}" "Saisie manuelle" "Ouvrir le gestionnaire de fichiers")"
    case "$chosen" in
      "Saisie manuelle")
        chosen="$(ask_input "Chemin de l'acquisition / backup (dossier, .ab, .zip) :" "")" ;;
      "Ouvrir le gestionnaire de fichiers")
        if command -v zenity >/dev/null 2>&1; then
          chosen="$(zenity --file-selection --title="Choisir l'acquisition / backup" --filename="${default_dir}/" 2>/dev/null || true)"
        elif command -v kdialog >/dev/null 2>&1; then
          chosen="$(kdialog --getexistingdirectory "$default_dir" 2>/dev/null || true)"
        fi
        [ -z "$chosen" ] && chosen="$(ask_input "Chemin de l'acquisition / backup (dossier, .ab, .zip) :" "")" ;;
    esac
    printf '%s' "$chosen"
  else
    ask_input "Chemin de l'acquisition / backup (dossier, .ab, .zip) :" ""
  fi
}

# Menu horizontal : $1 = question, $2+ = options. Imprime l'option choisie.
# Usage: choix=$(menu_select "Question ?" "Opt1" "Opt2" ...)
# Navigation au clavier : ↑/↓ + Entrée (choix immédiat), q/Esc sans effet.
# Repli en saisie numérique si stdin n'est pas un TTY (scripts, pipes), pour
# rester compatible avec les usages non-interactifs.
menu_select() {
  local prompt="$1"; shift
  local opts=("$@")
  if [ -t 0 ]; then
    arrow_select "$prompt" 0 "${opts[@]}"
  else
    numeric_select "$prompt" 0 "${opts[@]}"
  fi
}

# Idem menu_select mais imprime l'INDEX choisi (1-based) au lieu du libellé.
menu_select_idx() {
  local prompt="$1"; shift
  local opts=("$@")
  if [ -t 0 ]; then
    arrow_select "$prompt" 1 "${opts[@]}"
  else
    numeric_select "$prompt" 1 "${opts[@]}"
  fi
}

# Sélection par flèches : surlignage de l'option survolée (vidéo inversée).
# $3.. = options ; $2 = 0 => sort le libellé, 1 => sort l'index.
# Entrée valide immédiatement (pas de confirmation). q/Échap pendant la
# navigation ne font rien ; seul EOF (Ctrl-D) fait return 1.
arrow_select() {
  local prompt="$1" want_idx="$2"; shift 2
  local opts=("$@") total="${#opts[@]}" sel=0 key seq i

  local c_rev="${C_REV:-\033[7m}"
  local c_reset="${C_RESET:-\033[0m}"
  local c_dim="${C_DIM:-\033[2m}"

  printf '\n%s\n' "$prompt" >&2

  render() {
    local i
    for ((i=0;i<total;i++)); do
      printf '\r\033[K  ' >&2
      if [ "$i" -eq "$sel" ]; then
        printf '%s %s %s' "$c_rev" "${opts[$i]}" "$c_reset" >&2
      else
        printf '  %s' "${opts[$i]}" >&2
      fi
      [ "$i" -lt $((total-1)) ] && printf '\n' >&2
    done
    printf '\n\033[K%s↑/↓ naviguer · Entrée pour valider%s\033[J' \
      "$c_dim" "$c_reset" >&2
  }
  
  render

  while :; do
    IFS= read -rsn1 key || return 1
    case "$key" in
      $'\e')
        IFS= read -rsn2 -t 0.1 seq || true
        case "$seq" in
          '[A') sel=$(( (sel-1+total)%total )) ;;
          '[B') sel=$(( (sel+1)%total )) ;;
          *) continue ;;
        esac ;;
      $'\r'|$'\n'|"")
        printf '\n\033[K' >&2
        if [ "$want_idx" = "1" ]; then 
          printf '%d' $((sel+1))
        else 
          printf '%s' "${opts[$sel]}"
        fi
        return 0 ;;
      *) continue ;;
    esac
    printf '\033[%dA' "$total" >&2
    render
  done
}

# Après l'affichage du contenu d'une option : « ✔ <label> - Entrée pour
# continuer. Entrée -> 0 (continuer) ; q -> screen_clear
# + 1 (revenir au menu). Repli non-interactif : consomme une ligne, continue.
continue_or_back() {
  local label="$1" k
  local c_green="${C_GREEN:-\033[32m}"
  local c_reset="${C_RESET:-\033[0m}"
  
  printf '\n\033[K%s✔ %s%s - Entrée pour continuer' \
    "$c_green" "$label" "$c_reset" >&2
    
  if [ ! -t 0 ]; then
    while IFS= read -r _; do break; done
    printf '\n' >&2
    return 0
  fi
  
  IFS= read -rsn1 k || { screen_clear; return 1; }
  case "$k" in
    q|Q) screen_clear; return 1 ;;
    *)   printf '\n' >&2; return 0 ;;
  esac
}

# Sélection numérique
numeric_select() {
  local prompt="$1" want_idx="$2"; shift 2
  local opts=("$@") i n chosen
  printf '\n%s\n' "$prompt" >&2
  
  for i in "${!opts[@]}"; do
    printf '   %d) %s\n' "$((i+1))" "${opts[$i]}" >&2
  done
  
  while :; do
    printf 'Choix [1-%d] : ' "${#opts[@]}" >&2
    read -r n || return 1
    
    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#opts[@]}" ]; then
      if [ "$want_idx" = "1" ]; then 
        printf '%d' "$n"
      else 
        chosen="${opts[$((n-1))]}"
        printf '%s' "$chosen"
      fi
      return 0
    fi
    echo "Choix invalide." >&2
  done
}

# ------------------------------------------------------------------
# Identifiants
# ------------------------------------------------------------------
get_case_id() { date '+CASE-%Y%m%d-%H%M%S'; }

# Identifiant avec IMEI (ex. CASE-20260911-353456789012345)
get_case_id_with_imei() {
  local imei="${1:-unknown}"
  date '+CASE-%Y%m%d-'"$imei"
}

# Convertit un chemin absolu en chemin relatif par rapport à WRAPPER_DIR.
# Utilisé pour les fichiers de preuve (rapport, chaîne de traçabilité) afin
# de ne pas relier la preuve à la machine de l'analyste.
to_relative() {
  local abs="$1" base="${WRAPPER_DIR:-}"
  [ -z "$base" ] && { printf '%s' "$abs"; return; }
  case "$abs" in
    "$base"/*) printf '%s' "${abs#"$base"/}" ;;
    *)         printf '%s' "$abs" ;;
  esac
}

# Journalisation (chaîne de traçabilité / audit) : écrit une ligne
# horodatée dans les fichiers définis par CUSTODY_FILE et AUDIT_FILE.
custody_log() {
  [ -n "${CUSTODY_FILE:-}" ] && printf '%s | %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$CUSTODY_FILE"
}
audit_log() {
  [ -n "${AUDIT_FILE:-}" ] && printf '%s | %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$AUDIT_FILE"
}

# ------------------------------------------------------------------
# Intégrité des preuves (non-altération, aspect juridique)
# ------------------------------------------------------------------

# Manifeste sha256 de tous les fichiers d'un dossier (chemins relatifs).
# $1 = dossier ; $2 = fichier de sortie (SHA256SUMS).
hash_tree() {
  local dir="$1" out="$2" start pwd_save
  local f rel
  mapfile -t files < <(find "$dir" -type f ! -name 'SHA256SUMS.txt' ! -name 'SHA256SUMS-acquisition.txt' 2>/dev/null | LC_ALL=C sort)
  pwd_save="$(pwd)"
  : > "$out"
  cd "$dir" || return 1
  for f in "${files[@]}"; do
    rel="${f#"$dir"/}"
    sha256sum "$rel" >> "$out" 2>/dev/null || sha256sum "$f" >> "$out" 2>/dev/null
  done
  cd "$pwd_save" || true
}

# Vérifie un manifeste SHA256SUMS. Retour 0 si OK.
verify_hashes() {
  local dir="$1"
  ( cd "$dir" && sha256sum -c SHA256SUMS.txt ) >/dev/null 2>&1
}

# Passe un dossier en lecture seule (chmod a-w, et chattr +i si root).
lock_dir() {
  local dir="$1"
  if [ "${LOCK_EVIDENCE:-yes}" = "yes" ]; then
    chmod -R a-w "$dir" 2>/dev/null
    if [ "$(id -u)" = 0 ]; then
      chattr -R +i "$dir" 2>/dev/null
      log_ok "Preuves verrouillées en lecture seule (chattr +i): $dir"
    else
      log_ok "Preuves verrouillées en lecture seule (chmod a-w): $dir"
    fi
  else
    log_warn "Verrouillage des preuves désactivé - dossier modifiable."
  fi
}

# ------------------------------------------------------------------
# CONSENTEMENT + PÉRIMÈTRE (loi Godfrain - art. 323-1 s. C. pén.)
# On n'analyse QUE les appareils et comptes de la personne accompagnée,
# JAMAIS ceux d'un tiers (en particulier d'un agresseur présumé -
# ce serait un délit Godfrain, pas une preuve). Exigé AVANT chaque
# acquisition iOS et Android : si refus, on s'arrête là, aucune donnée.
# ------------------------------------------------------------------
# CONSENTEMENT + PÉRIMÈTRE (loi Godfrain - art. 323-1 à 323-7 C. pén.)
# Garde-fou légal : n'analyser QUE les appareils et comptes de la personne
#   $1 = plateforme (iOS / Android)
#   $2 = nom du dossier d'acquisition
# ------------------------------------------------------------------

# ------------------------------------------------------------------
# Consentement et périmètre (loi Godfrain - art. 323-1 à 323-7 C. pén.)
# Garde-fou légal : n'analyser QUE les appareils et comptes de la personne
# accompagnée, JAMAIS ceux d'un tiers (ni d'un agresseur présumé). 
# Refus de confirmation => acquisition abandonnée, aucun octet collecté.
#   $1 = plateforme (iOS / Android)
# ------------------------------------------------------------------
confirm_consent_and_scope() {
  local platform="$1"
  screen_clear
  banner "====== CADRE LEGAL ======"
  log_warn "Rappel : l'accès frauduleux à un système de traitement automatisé de données (art. 323-1 s. C. pén.) est pénalement répréhensible."
  log_warn "Cet outil n'analyse QUE les appareils et comptes DE LA PERSONNE ACCOMPAGNÉE, avec son consentement, dans le seul cadre de l'aide."
  echo ""
  if ask_yesno "Confirmez-vous que CET appareil (et ses éventuels comptes), vous appartient ou appartiennent à la personne accompagnée, dans le strict cadre de son accompagnement ?" "yes"; then
    custody_log "Consentement confirmé ($platform)."
    log_ok "Périmètre validé - $platform : appareil de la personne accompagnée."
  else
    custody_log "REFUS de consentement ($platform)"
    die "Acquisition refusée : Vous devez consentir au cadre légal et confirmer que l'appareil analyser vous appartient."
  fi
}


# Quarantaine d'une acquisition partielle/échouée : le dossier (et son contenu
# non scellé) est sorti du chemin d'affaire actif pour ne JAMAIS être réutilisé
# par une reprise (intégrité de la chaîne de preuve garantie côté analyse).
#   $1 = dossier d'acquisition partiel   $2 = plateforme (iOS / Android)
quarantine_failed_acquisition() {
  local dir platform quarantine
  dir="$1"
  platform="$2"
  log_warn "Acquisition $platform ABANDONNÉE - capture partielle inexploitable."
  custody_log "Acquisition $platform interrompue - capture partielle NON scellée."
  if [ -d "$dir" ] && [ -n "$(find "$dir" -mindepth 1 2>/dev/null | head -n 1)" ]; then
    chmod -R u+w "$dir" 2>/dev/null
    quarantine="$dir-QUARANTAINE_non-scellée"
    if mv "$dir" "$quarantine" 2>/dev/null; then
      log_warn "Capture partielle isolée : $(basename "$quarantine") - son SHA256 n'engage pas une preuve scellée."
      custody_log "Capture partielle isolée dans $quarantine (non scellée, non reprise)."
    fi
  fi
}

# ------------------------------------------------------------------
# Validation d'un fichier STIX2/JSON (doit être du JSON valide)
# ------------------------------------------------------------------
valid_json() {
  python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$1" 2>/dev/null
}

# ------------------------------------------------------------------
# IoCs : liste des fichiers STIX2 disponibles et construction de MVT_STIX2
# ------------------------------------------------------------------
find_ioc_files() {
  find "$IOCS_CUSTOM_DIR" "$IOCS_MANAGED_DIR" \
      \( -path '*/.git' -o -path '*/.state' \) -prune -o \
      -type f \( -name '*.stix2' -o -name '*.json' \) -print 2>/dev/null \
    | LC_ALL=C sort -u
}

# Retourne la liste des fichiers IoCs séparés par ':' (format MVT_STIX2).
build_stix2_env() {
  local f out=""
  while IFS= read -r f; do
    out="${out}${out:+:}${f}"
  done < <(find_ioc_files)
  printf '%s' "$out"
}

# ------------------------------------------------------------------
# Résumé JSON des détections (_detected.json) via python3
# ------------------------------------------------------------------
json_summary() {
  python3 - "$1" <<'PY'
import json, sys

def deep_get(d, key):
    if isinstance(d, dict):
        if key in d and d[key] not in (None, ""):
            return d[key]
        for v in d.values():
            r = deep_get(v, key)
            if r not in (None, ""):
                return r
    elif isinstance(d, list):
        for v in d:
            r = deep_get(v, key)
            if r not in (None, ""):
                return r
    return None

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
except Exception as exc:
    print(f"    [fichier JSON illisible : {exc}]")
    sys.exit(0)
if not isinstance(data, list) or not data:
    print("    (aucun enregistrement)")
    sys.exit(0)
print(f"    {len(data)} enregistrement(s) correspondant à un IoC :")
for rec in data[:50]:
    ioc = deep_get(rec, "value") or deep_get(rec, "indicator") or deep_get(rec, "matched_indicator_value") or "n/a"
    typ = deep_get(rec, "indicator_type") or "n/a"
    sev = deep_get(rec, "severity") or "n/a"
    art = deep_get(rec, "artifact") or deep_get(rec, "description") or "n/a"
    if isinstance(art, dict):
        art = json.dumps(art)[:160]
    print(f"    - IoC: {ioc}   [{typ}]   sévérité: {sev}")
    print(f"      artefact: {str(art)[:170]}")
if len(data) > 50:
    print(f"    (… {len(data)-50} autre(s) enregistrement(s) - détail dans {path})")
PY
}

# ------------------------------------------------------------------
# Descriptions des modules MVT (basées sur record_extracted.txt)
# ------------------------------------------------------------------
declare -A MODULE_DESC=(
  [analytics]="Infos analytics (échecs réseau, certificat/TLS, pinning)."
  [backup_info]="Infos device : nom, numéro, IMEI, product type, version iOS."
  [applications]="Applications installées ; signale les apps hors App Store."
  [cache_files]="Caches HTTP (Cache.db) : requêtes réseau des apps/services."
  [calendar]="Agenda ; IoCs vérifiés sur l'email de l'invitant."
  [calls]="Journal d'appels (iOS natif et Whatsapp/Skype)."
  [chrome_favicon]="Favicons Chrome ; IoCs sur les URLs des favicons/visites."
  [chrome_history]="Historique de navigation Chrome."
  [configuration_profiles]="Profils de configuration iOS (détection de profils malveillants)."
  [contacts]="Carnet d'adresses."
  [firefox_favicon]="Favicons Firefox."
  [firefox_history]="Historique de navigation Firefox."
  [global_preferences]="Préférences système (ex. Lockdown Mode)."
  [id_status_cache]="Cache des identités Apple (Facetime/iMessage)."
  [shortcuts]="Raccourcis iOS ; quelques spyware l'utilisent pour persister."
  [interaction_c]="Interactions utilisateur avec les apps."
  [locationd_clients]="Apps ayant demandé accès à la localisation."
  [manifest]="Index des fichiers présents dans le backup ; IoCs sur les chemins."
  [os_analytics_ad_daily]="Consommation réseau par processus."
  [datausage]="Usage réseau des processus (DataUsage.sqlite)."
  [netusage]="Usage réseau des processus (netusage.sqlite)."
  [profile_events]="Chronologie des opérations sur les profils de configuration."
  [safari_browser_state]="Onglets ouverts dans Safari (ex. URLs malveillantes)."
  [safari_favicon]="Favicons Safari."
  [safari_history]="Historique de navigation Safari."
  [shutdown_log]="Processus n'ayant pas quitté après SIGTERM à l'extinction."
  [sms]="SMS/iMessage ; IoCs sur les liens HTTP extraits."
  [sms_attachments]="Pièces jointes SMS/iMessage (schémas d'exploitation possibles)."
  [tcc]="Permissions accordées aux apps (micro, caméra, localisation, ...)."
  [version_history]="Historique des mises à jour iOS."
  [webkit_indexeddb]="Bases IndexedDB créées par les apps."
  [webkit_local_storage]="Stockage LocalStorage des apps."
  [webkit_resource_load_statistics]="Domaines contactés par les apps (avec timestamps)."
  [webkit_safari_view_service]="Fichiers cachés par SafariViewService."
  [webkit_session_resource_log]="Ressources chargées par les sites visités."
  [whatsapp]="Messages WhatsApp (ChatStorage.sqlite) ; IoCs sur les liens extraits."
  [whatsapp_contacts]="Contacts WhatsApp (ContactsV2.sqlite)."
  [sysdiagnose_info]="Infos device depuis le sysdiagnose (UDID, IMEI, serial, compte Apple)."
  [urls]="URLs extraites des SMS/iMessage/WhatsApp (déjà résolues si raccourcies)."
)

module_desc() {
  local m="$1"
  m="${m%.json}"; m="${m%_detected}"; m="${m//-/_}"
  printf '%s' "${MODULE_DESC[$m]:-}"
}

# ------------------------------------------------------------------
# Infos device (modèle, version, ...) depuis les fichiers d'une analyse
# ------------------------------------------------------------------
device_info_from() {
  local dir="$1"
  python3 - "$dir" <<'PY'
import json, os, re, sys
root = sys.argv[1]
def dig(d, keys):
    if isinstance(d, dict):
        for k in keys:
            if k in d and d[k] not in (None, ""):
                return d[k]
        for v in d.values():
            r = dig(v, keys)
            if r not in (None, ""):
                return r
    elif isinstance(d, list):
        for v in d:
            r = dig(v, keys)
            if r not in (None, ""):
                return r
    return None
parts = []
for name in ("backup_info.json", "sysdiagnose_info.json"):
    p = os.path.join(root, name)
    if os.path.isfile(p):
        try:
            d = json.load(open(p, encoding="utf-8"))
            model  = dig(d, ("product_type", "product", "devicemodel", "model"))
            ver    = dig(d, ("product_version", "ios_version", "version"))
            dname  = dig(d, ("device_name", "name"))
            imei   = dig(d, ("imei",))
            serial = dig(d, ("serial_number", "serialNumber", "SerialNumber"))
            if dname: parts.append(f"Nom: {dname}")
            if model: parts.append(f"Modèle: {model}")
            if ver:   parts.append(f"OS: {ver}")
            if imei:  parts.append(f"IMEI: {imei}")
            if serial: parts.append(f"Serial: {serial}")
        except Exception:
            pass
        if parts:
            break
if not parts:
    p = os.path.join(root, "acquisition.json")
    if os.path.isfile(p):
        try:
            d = json.load(open(p, encoding="utf-8"))
            model  = dig(d, ("product_model", "model", "device_model"))
            ver    = dig(d, ("device_version", "android_version", "version", "os_version"))
            manuf  = dig(d, ("product_manufacturer", "manufacturer", "brand"))
            imei   = dig(d, ("imei", "imei1", "Imei"))
            serial = dig(d, ("serial_number", "serial", "Serial"))
            if not serial:
                adb = dig(d, ("collector", "Adb"))
                if isinstance(adb, dict):
                    serial = adb.get("Serial")
            if model:  parts.append(f"Modèle: {model}")
            if ver:    parts.append(f"OS: {ver}")
            if manuf:  parts.append(f"Constructeur: {manuf}")
            if imei:   parts.append(f"IMEI: {imei}")
            if serial: parts.append(f"Serial: {serial}")
        except Exception:
            pass
if not parts:
    p = os.path.join(root, "getprop.txt")
    if os.path.isfile(p):
        try:
            txt = open(p, encoding="utf-8", errors="ignore").read()
            for key, label in (("ro.product.model","Modèle"),
                               ("ro.build.version.release","OS"),
                               ("ro.product.manufacturer","Constructeur"),
                               ("ro.ril.oem.imei","IMEI"),
                               ("ro.serialno","Serial")):
                m = re.search(r'\[(' + re.escape(key) + r')\]:\s*\[([^\]]*)\]', txt)
                if m and m.group(2):
                    parts.append(f"{label}: {m.group(2)}")
        except Exception:
            pass
  print(" ; ".join(parts))
PY
}

# ------------------------------------------------------------------
# Infos device structurées pour le rapport juridique
# Retourne des lignes clé:valeur pour le rapport.
# $1 = dossier d'analyse (results ou case_dir)
# $2.. = paires clé=valeur surchargées (ex: IMEI=xxx Serial=yyy)
# ------------------------------------------------------------------
extract_device_details() {
  local dir="$1"; shift
  local extra_args=("$@")
  python3 - "$dir" "${extra_args[@]}" <<'PY'
import json, os, re, sys
root = sys.argv[1]
overrides = {}
for a in sys.argv[2:]:
    if "=" in a:
        k, v = a.split("=", 1)
        overrides[k] = v
def dig(d, keys):
    if isinstance(d, dict):
        for k in keys:
            if k in d and d[k] not in (None, ""):
                return d[k]
        for v in d.values():
            r = dig(v, keys)
            if r not in (None, ""):
                return r
    elif isinstance(d, list):
        for v in d:
            r = dig(v, keys)
            if r not in (None, ""):
                return r
    return None

def fmt_storage(val):
    if val is None:
        return None
    try:
        n = int(val)
        if n > 1_000_000_000_000:
            return f"{n / 1_000_000_000_000:.0f} To"
        elif n > 1_000_000_000:
            return f"{n / 1_000_000_000:.0f} Go"
        elif n > 1_000_000:
            return f"{n / 1_000_000:.0f} Mo"
        return str(n)
    except (ValueError, TypeError):
        return str(val)

result = {
    "IMEI":               overrides.get("IMEI"),
    "Numero de serie":    overrides.get("Serial"),
    "Marque":             overrides.get("Brand"),
    "Modele":             overrides.get("Model"),
    "Capacite stockage":  overrides.get("Storage"),
    "Systeme d exploitation": overrides.get("OS"),
}

# Try to fill from files if not overridden
if not result["IMEI"] or not result["Numero de serie"] or not result["Modele"]:
    for name in ("backup_info.json", "sysdiagnose_info.json"):
        p = os.path.join(root, name)
        if os.path.isfile(p):
            try:
                d = json.load(open(p, encoding="utf-8"))
                if not result["Modele"]:
                    v = dig(d, ("product_type", "product", "devicemodel", "model"))
                    if v: result["Modele"] = v
                if not result["Systeme d exploitation"]:
                    v = dig(d, ("product_version", "ios_version", "version"))
                    if v: result["Systeme d exploitation"] = v
                if not result["IMEI"]:
                    v = dig(d, ("imei",))
                    if v: result["IMEI"] = v
                if not result["Numero de serie"]:
                    v = dig(d, ("serial_number", "serialNumber", "SerialNumber"))
                    if v: result["Numero de serie"] = v
                if not result["Marque"]:
                    result["Marque"] = "Apple"
            except Exception:
                pass
            if any(result[k] for k in result):
                break
    if not any(result[k] for k in ("Modele", "IMEI", "Numero de serie")):
        p = os.path.join(root, "acquisition.json")
        if os.path.isfile(p):
            try:
                d = json.load(open(p, encoding="utf-8"))
                if not result["Modele"]:
                    v = dig(d, ("product_model", "model", "device_model"))
                    if v: result["Modele"] = v
                if not result["Systeme d exploitation"]:
                    v = dig(d, ("device_version", "android_version", "version", "os_version"))
                    if v: result["Systeme d exploitation"] = v
                if not result["Marque"]:
                    v = dig(d, ("product_manufacturer", "manufacturer", "brand"))
                    if v: result["Marque"] = v
                if not result["IMEI"]:
                    v = dig(d, ("imei", "imei1", "Imei"))
                    if v: result["IMEI"] = v
                if not result["Numero de serie"]:
                    v = dig(d, ("serial_number", "serial", "Serial"))
                    if not v:
                        adb = dig(d, ("collector", "Adb"))
                        if isinstance(adb, dict):
                            v = adb.get("Serial")
                    if v: result["Numero de serie"] = v
            except Exception:
                pass
    if not any(result[k] for k in ("Modele", "IMEI", "Numero de serie")):
        p = os.path.join(root, "getprop.txt")
        if os.path.isfile(p):
            try:
                txt = open(p, encoding="utf-8", errors="ignore").read()
                mapping = {
                    "ro.product.model": "Modele",
                    "ro.build.version.release": "Systeme d exploitation",
                    "ro.product.manufacturer": "Marque",
                    "ro.ril.oem.imei": "IMEI",
                    "ro.serialno": "Numero de serie",
                }
                for key, field in mapping.items():
                    if not result[field]:
                        m = re.search(r'\[' + re.escape(key) + r'\]:\s*\[([^\]]*)\]', txt)
                        if m and m.group(1):
                            result[field] = m.group(1)
            except Exception:
                pass

# Storage from getprop if not overridden
if not result["Capacite stockage"]:
    p = os.path.join(root, "getprop.txt")
    if os.path.isfile(p):
        try:
            txt = open(p, encoding="utf-8", errors="ignore").read()
            for key in ("ro.product.disk.size", "ro.emmc.size"):
                m = re.search(r'\[' + re.escape(key) + r'\]:\s*\[([^\]]*)\]', txt)
                if m and m.group(1):
                    result["Capacite stockage"] = fmt_storage(m.group(1))
                    break
        except Exception:
            pass

for field in ("IMEI", "Numero de serie", "Marque", "Modele", "Capacite stockage", "Systeme d exploitation"):
    val = result.get(field) or "non disponible"
    print(f"{field}: {val}")
PY
}

# ------------------------------------------------------------------
# Rapport d'analyse texte (rapport.txt) + retour console
# ------------------------------------------------------------------
collect_detected() {
  find "$1" -maxdepth 1 -type f -name '*_detected.json' 2>/dev/null | LC_ALL=C sort
}

make_report() {
  local case_id="$1" results="$2" platform="$3" iocs_csv="${4:-}" evidence_dir="${5:-}" device="${6:-}" analysis_type="${7:-}"
  local report="$results/rapport.txt"
  local mod desc f nbf
  local det=() files=()
  local evidence_rel=""
  mapfile -t det < <(collect_detected "$results")

  [ -n "$evidence_dir" ] && evidence_rel="$(to_relative "$evidence_dir")"

  banner "Génération du rapport..."
  {
    echo '══════════════════════════════════════════════════════════'
    echo "  RAPPORT D'ANALYSE - MVT WRAPPER"
    echo '══════════════════════════════════════════════════════════'
    echo "Affaire          : $case_id"
    echo "Date d'analyse   : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Analyste         : ${ANALYST:-$(whoami)}"
    echo "Plateforme       : $platform"
    echo "Type d'analyse   : ${analysis_type:-n/a}"
    echo ""
    echo '--------------------------------------------------------------'
    echo '  STATUT DU RAPPORT'
    echo '--------------------------------------------------------------'
    echo "  Ce rapport est un élément technique d'aide à l'orientation et non"
    echo "  une expertise judiciaire au sens du Code de procedure penale."
    echo "  Il ne se substitue ni à une plainte, ni à une expertise ordonnée par"
    echo "  la juridiction ou sur requisition (art. 60, 77-1-1 et 156 C. pr. pen)."
    echo "  Il ne prejuge pas de la decision de justice."
    echo "  Methode et limites : analyses portant exclusivement sur les appareils"
    echo "  et comptes de la personne accompagnée avec son consentement ecrit."
    echo "  Les IoCs publics sont des indicateurs et non une preuve :"
    echo "  une detection doit être corroborer et peut présenter des faux positifs/negatifs;"
    echo ""
    echo '--------------------------------------------------------------'
    echo '  IDENTIFICATION DU DISPOSITIF'
    echo '--------------------------------------------------------------'
    if [ -n "$device" ] && [ "$device" != "modèle non détecté automatiquement" ]; then
      local _imei="" _serial="" _brand="" _model="" _storage="" _os=""
      while IFS= read -r _line; do
        case "$_line" in
          IMEI:*)                    _imei="${_line#IMEI: }" ;;
          "Numero de serie:"*)       _serial="${_line#Numero de serie: }" ;;
          Marque:*)                  _brand="${_line#Marque: }" ;;
          Modele:*)                  _model="${_line#Modele: }" ;;
          "Capacite stockage:"*)     _storage="${_line#Capacite stockage: }" ;;
          "Systeme d exploitation:"*) _os="${_line#Systeme d exploitation: }" ;;
        esac
      done <<< "$device"
      printf '  %-25s : %s\n' "IMEI" "${_imei:-non disponible}"
      printf '  %-25s : %s\n' "Numero de serie" "${_serial:-non disponible}"
      printf '  %-25s : %s\n' "Marque" "${_brand:-non disponible}"
      printf '  %-25s : %s\n' "Modele" "${_model:-non disponible}"
      printf '  %-25s : %s\n' "Capacite stockage" "${_storage:-non disponible}"
      printf '  %-25s : %s\n' "Systeme d exploitation" "${_os:-non disponible}"
    else
      echo "  Informations sur l'appareil non disponibles."
    fi
    echo ''
    if [ -n "$iocs_csv" ]; then
      echo "IoCs utilisés    : $iocs_csv"
    else
      echo "IoCs utilisés    : (aucun; IoCs officiels MVT éventuels)"
    fi
    echo ''
    echo '--------------------------------------------------------------'
    echo '  MENACES / INDICATEURS DE COMPROMISSION DETECTES'
    echo '--------------------------------------------------------------'
    if [ "${#det[@]}" -eq 0 ]; then
      echo "  [INFO] Aucune menace correspondant aux IoCs n'a été détectée."
    else
      echo "  ${#det[@]} fichier(s) de détection :"
      echo ''
      for f in "${det[@]}"; do
        mod="$(basename "$f")"; mod="${mod%_detected.json}"
        desc="$(module_desc "$mod")"
        printf '[%s]\n' "$mod"
        [ -n "$desc" ] && printf '  * %s\n' "$desc"
        json_summary "$f"
        echo ''
      done
    fi
    echo ''
    echo '--------------------------------------------------------------'
    echo '  MODULES EXECUTES (fichiers produits)'
    echo '--------------------------------------------------------------'
    mapfile -t files < <(find "$results" -maxdepth 1 -type f \( -name '*.json' -o -name '*.csv' \) ! -name '*_detected.json' 2>/dev/null | LC_ALL=C sort | sed "s|$results/||")
    if [ "${#files[@]}" -gt 0 ]; then
      printf '  %s\n' "${files[@]}"
    else
      echo '  (aucun fichier JSON produit)'
    fi
    echo ''
    echo '--------------------------------------------------------------'
    echo '  PREUVES ET CHAINE DE TRAÇABILITE'
    echo '--------------------------------------------------------------'
    if [ -n "$evidence_dir" ] && [ -d "$evidence_dir" ]; then
      echo "  Dossier de preuve : $evidence_rel"
      [ -f "$evidence_dir/SHA256SUMS-acquisition.txt" ] && echo "  Manifeste acquisition : $evidence_rel/SHA256SUMS-acquisition.txt"
      if [ -f "$evidence_dir/SHA256SUMS.txt" ]; then
        if ( cd "$evidence_dir" && sha256sum -c SHA256SUMS.txt >/dev/null 2>&1 ); then
          echo '  Intégrité (SHA256) : verifiée - OK'
        else
          echo '  Intégrité (SHA256) : À CONTRÔLER (anomalie detectée !)'
        fi
      fi
      [ -f "$evidence_dir/chain_of_custody.txt" ] && echo "  Journal de traçabilité : $evidence_rel/chain_of_custody.txt"
    else
      echo '  n/a'
    fi
    echo ''
    echo "Note : une détection d'IoC ne signifie pas automatiquement que le"
    echo 'dispositif est compromis ; les IoCs publics seuls ne suffisent pas à'
    echo 'conclure. Chaque détection doit être investiguée par un analyste.'
    echo "Preservation avant remediation : aucune action de remediation (dont"
    echo "la desinstallation d'un logiciel espion) n'engage la securite d'etre"
    echo "techniquement realisee sur ce terminal a ce stade."
    echo 'Orientation : 3919 (violences au sein du couple), 116 006 (France'
    echo 'Victimes), Cybermalveillance.gouv.fr, CNIL (le-chatelier.cyberstalking),'
    echo 'et un constat par commissaire de justice peut etre envisage.'
    echo '══════════════════════════════════════════════════════════'
  } > "$report"
  log_ok "Rapport généré : $report"

  if [ "${#det[@]}" -eq 0 ]; then
    log_ok "Résultat de l'analyse : aucune détection d'IoC."
  else
    log_warn "Résultat de l'analyse : ${#det[@]} fichier(s) de détection d'IoC - voir le rapport."
  fi
  hline
  if [ "${#det[@]}" -gt 0 ]; then
    for f in "${det[@]}"; do
      printf '  * %s\n' "$f"
    done
  fi
  hline
}
# ------------------------------------------------------------------
# Triage passif non-invasif (phase 1 de la méthodologie - TinyCheck)
# Observation du trafic réseau via un point d'accès instrumenté, SANS
# intervention sur le terminal et SANS notification à l'agresseur.
# Uniquement les flux liés aux appareils et comptes de la personne
# accompagnée (loi Godfrain, consentement confirmé avant appel).
# TinyCheck reste OPTIONNEL : sans binaire, on documente la limite et
# on propose l'orientation, sans jamais échouer l'analyse (non-invasive).
triage_passif_tinycheck() {
  local platform="$1"
  custody_log "Triage passif ($platform) : TinyCheck non-invasif sur les flux de la personne accompagnée."
  if [ -n "${TINYCHECK_BIN:-}" ] && [ -x "${TINYCHECK_BIN:?}" ]; then
    log_ok "TinyCheck présent ($TINYCHECK_BIN) - triage passif sur point d'accès instrumenté."
    custody_log "Triage passif TinyCheck ($platform) : point d'accès instrumenté, aucun octet du terminal touché."
  else
    log_warn "TinyCheck non installé - triage passif à concevoir avec cet outil (méthodologie phase 1)."
    custody_log "Triage passif ($platform) : TinyCheck absent - limitation documentée, aucune donnée invasive."
  fi
  return 0
}

# ------------------------------------------------------------------
# Volet orientation et accompagnement (checklist consentement RGPD)
# Après l'acquisition : numéros visibles, orientation judiciaire (consentement
# écrit requis préalablement), réorientation loi Godfrain rappelée. Journalisé.
orientation_accompagnement() {
  local platform="$1"
  log_info "Orientation et accompagnement proposés ($platform)."
  echo ''
  echo '--------------------------------------------------------------'
  echo '  ORIENTATION ET ACCOMPAGNEMENT '
  echo '--------------------------------------------------------------'
  echo '  3919        : violences au sein du couple (info, écoute, orientation)'
  echo '  116 006     : France Victimes - aide aux victimes (7j/7)'
  echo '  Hubertine Auclert : centre Hubertine Auclert (Île-de-France)'
  echo '  CNIL        : le-chatelier.cyberstalking (CNIL)'
  echo '  Cybermalveillance : Cybermalveillance.gouv.fr'
  echo '  Asso Echap  : github.com/AssoEchap/stalkerware-indicators'
  echo '  Commissaire de justice : constat opposable (préservation)'
  echo '  Plainte     : dépôt de plainte / main courante en brigade (3919)'
  echo ''
  echo '  Préservation avant remédiation : la désinstallation notifie'
  echo "  l'agresseur et détruit la preuve - aucune remédiation n'est"
  echo '  engagée avant scellage et plainte.'
  echo '--------------------------------------------------------------'
  custody_log "Accompagnement proposé ($platform) : 3919, 116 006, Hubertine, CNIL, Cybermalveillance, Echap, commissaire de justice."
  return 0
}
