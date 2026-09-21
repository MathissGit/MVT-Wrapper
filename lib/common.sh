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

def pick(d, keys):
    if isinstance(d, dict):
        for k in keys:
            if k in d and d[k] not in (None, ""):
                return d[k]
        for v in d.values():
            r = pick(v, keys)
            if r not in (None, ""):
                return r
    elif isinstance(d, list):
        for v in d:
            r = pick(v, keys)
            if r not in (None, ""):
                return r
    return None

PRIO = ["name", "title", "entry", "value", "package", "uid",
        "artistName", "bundleShortVersionString", "bundleVersion",
        "installer", "system", "third_party", "disabled", "sourceURL",
        "url", "path", "key", "label", "serial", "imei", "model", "version"]

def evfmt(ev):
    if not isinstance(ev, dict):
        return ""
    seen = set()
    parts = []
    def add(k, v):
        if k in seen or k in ("message", "matched_indicator"):
            return
        seen.add(k)
        if isinstance(v, dict):
            sub = evfmt(v)
            if sub:
                parts.append(f"{k}: {{{sub}}}")
            return
        if isinstance(v, list):
            if v:
                joined = ", ".join(str(x) for x in v[:5])
                if len(v) > 5:
                    joined += ", ..."
                if len(joined) < 160:
                    parts.append(f"{k}: [{joined}]")
            return
        if isinstance(v, bool):
            s = "oui" if v else "non"
        elif v in (None, ""):
            return
        else:
            s = str(v)
        if len(s) > 140:
            s = s[:137] + "..."
        parts.append(f"{k}: {s}")
    for k in PRIO:
        if k in ev:
            add(k, ev[k])
    for k in ev:
        if k not in PRIO:
            add(k, ev[k])
    return " ; ".join(parts[:10])

LEVELS = {"CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"}
MAX = 100

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
for n, rec in enumerate(data[:MAX], 1):
    if not isinstance(rec, dict):
        continue
    sev = str(pick(rec, ("level", "severity")) or "n/a").upper()
    if sev not in LEVELS:
        sev = "n/a"
    msg = str(pick(rec, ("message", "description", "artifact")) or "n/a")
    ioc_line = ""
    ioc = rec.get("matched_indicator")
    if isinstance(ioc, dict):
        v = ioc.get("value") or "n/a"
        t = ioc.get("type") or ""
        c = ioc.get("name") or ioc.get("stix2_file_name") or ""
        ioc_line = f"        IoC : {v}"
        if t:
            ioc_line += f"  (type: {t})"
        if c:
            ioc_line += f"  [collection: {c}]"
    elif isinstance(ioc, str) and ioc:
        ioc_line = f"        IoC : {ioc}"
    else:
        v = pick(rec, ("value", "indicator", "matched_indicator_value"))
        if v not in (None, ""):
            ioc_line = f"        IoC : {str(v)[:160]}"
    ctx = evfmt(rec.get("event"))
    print(f"    {n}) [{sev}] {msg[:220]}")
    if ioc_line:
        print(ioc_line)
    if ctx:
        print(f"        Détails : {ctx}")
if len(data) > MAX:
    print(f"    (... {len(data) - MAX} autre(s) enregistrement(s) - détail complet dans {path})")
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
  [aqf_get_prop]="Propriétés système Android (build/getprop) ; IoCs sur versions/patch/marque."
  [aqf_packages]="Applications installées Android ; signale les apps non-système (adb/APK)."
  [aqf_settings]="Réglages Android (settings) ; IoCs sur valeurs anormales."
  [aqf_files]="Arborescence des fichiers Android ; IoCs sur chemins/noms suspects."
  [aqf_log_timestamps]="Horodatages des journaux de l'appareil."
  [dbinfo]="Métadonnées de l'acquisition AndroidQF (base, version, taille)."
  [dumpsys_accessibility]="Services d'accessibilité actifs (marqués spyware via Accessibility)."
  [dumpsys_get_prop]="Propriétés build/getprop via dumpsys ; IoCs sur versions/patch."
  [dumpsys_battery_daily]="Historique batterie journalier ; IoCs sur pics anormaux."
  [dumpsys_battery_history]="Historique détaillé de la charge batterie."
  [dumpsys_packages]="Détails des packages installés ; IoCs sur signataires/autorisations."
  [dumpsys_activities]="État de l'activité système / tâches récentes."
  [dumpsys_appops]="Journal des autorisations (appops) accordées par application."
  [dumpsys_receivers]="Récepteurs broadcast enregistrés par les apps."
  [settings]="Réglages Android globaux/sécurisés (settings get)."
  [mounts]="Points de montage du système de fichiers."
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
import base64, json, os, re, sys
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
        n = int(str(val).split()[0])
        if n > 1_000_000_000_000:
            return f"{n / 1_000_000_000_000:.0f} To"
        if n > 1_000_000_000:
            return f"{n / 1_000_000_000:.0f} Go"
        if n > 1_000_000:
            return f"{n / 1_000_000:.0f} Mo"
        return str(n)
    except (ValueError, TypeError, IndexError):
        return str(val)[:40]

def b64name(v):
    try:
        s = base64.b64decode(v).decode("utf-8", "ignore")
        return s if s.isprintable() else None
    except Exception:
        return None

APPLE_MODELS = {
    "iPhone1,1": "iPhone (1re)", "iPhone1,2": "iPhone 3G", "iPhone2,1": "iPhone 3GS",
    "iPhone3,1": "iPhone 4", "iPhone3,3": "iPhone 4 (CDMA)",
    "iPhone4,1": "iPhone 4s", "iPhone5,1": "iPhone 5", "iPhone5,2": "iPhone 5",
    "iPhone5,3": "iPhone 5c", "iPhone5,4": "iPhone 5c",
    "iPhone6,1": "iPhone 5s", "iPhone6,2": "iPhone 5s",
    "iPhone7,1": "iPhone 6 Plus", "iPhone7,2": "iPhone 6",
    "iPhone8,1": "iPhone 6s", "iPhone8,2": "iPhone 6s Plus", "iPhone8,4": "iPhone SE (1re gen.)",
    "iPhone9,1": "iPhone 7", "iPhone9,2": "iPhone 7 Plus",
    "iPhone9,3": "iPhone 7", "iPhone9,4": "iPhone 7 Plus",
    "iPhone10,1": "iPhone 8", "iPhone10,2": "iPhone 8 Plus", "iPhone10,3": "iPhone X",
    "iPhone10,4": "iPhone 8", "iPhone10,5": "iPhone 8 Plus", "iPhone10,6": "iPhone X",
    "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max",
    "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
    "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
    "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
    "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
    "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
    "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
    "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
    "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
    "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
    "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
    "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
    "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,5": "iPhone 16e",
    "iPad1,1": "iPad", "iPad2,5": "iPad mini", "iPad2,7": "iPad mini",
    "iPad4,1": "iPad Air", "iPad4,4": "iPad mini 2", "iPad4,7": "iPad mini 3",
    "iPad5,1": "iPad mini 4", "iPad5,2": "iPad mini 4",
    "iPad5,3": "iPad Air 2", "iPad5,4": "iPad Air 2",
    "iPad6,7": "iPad Pro (12,9\")", "iPad6,8": "iPad Pro (12,9\")",
    "iPad6,11": "iPad (5e gen.)", "iPad6,12": "iPad (5e gen.)",
    "iPad7,1": "iPad Pro (12,9\")", "iPad7,2": "iPad Pro (12,9\")",
    "iPad7,5": "iPad (6e gen.)", "iPad7,6": "iPad (6e gen.)",
    "iPad11,1": "iPad mini (5e gen.)", "iPad11,2": "iPad mini (5e gen.)",
    "iPad11,6": "iPad (8e gen.)", "iPad11,7": "iPad (8e gen.)",
    "iPad13,1": "iPad Air (4e gen.)", "iPad13,2": "iPad Air (4e gen.)",
    "iPad13,16": "iPad Air (5e gen.)", "iPad13,17": "iPad Air (5e gen.)",
    "iPad14,1": "iPad mini (6e gen.)", "iPad14,2": "iPad mini (6e gen.)",
    "iPod5,1": "iPod touch (5e gen.)", "iPod7,1": "iPod touch (6e gen.)",
    "iPod9,1": "iPod touch (7e gen.)",
}
SAMSUNG_MODELS = {
    "SM-J710F": "Galaxy J7 (2016)", "SM-J710FN": "Galaxy J7 (2016)", "SM-J710MN": "Galaxy J7 (2016)",
    "SM-J730F": "Galaxy J7 (2017)", "SM-J530F": "Galaxy J5 (2017)", "SM-J600F": "Galaxy J6",
    "SM-A515F": "Galaxy A51", "SM-A525F": "Galaxy A52", "SM-A325F": "Galaxy A32",
    "SM-A217F": "Galaxy A21s", "SM-A217M": "Galaxy A21s",
    "SM-G950F": "Galaxy S8", "SM-G955F": "Galaxy S8+",
    "SM-G960F": "Galaxy S9", "SM-G965F": "Galaxy S9+",
    "SM-G970F": "Galaxy S10e", "SM-G973F": "Galaxy S10", "SM-G975F": "Galaxy S10+",
    "SM-G975U": "Galaxy S10+", "SM-G970U": "Galaxy S10e",
    "SM-G991B": "Galaxy S21", "SM-G996B": "Galaxy S21+", "SM-G998B": "Galaxy S21 Ultra",
    "SM-S901B": "Galaxy S22", "SM-S906B": "Galaxy S22+", "SM-S908B": "Galaxy S22 Ultra",
    "SM-S911B": "Galaxy S23", "SM-S916B": "Galaxy S23 Ultra",
    "SM-N975F": "Galaxy Note 10+", "SM-N970F": "Galaxy Note 10",
    "SM-T510": "Galaxy Tab A (10.1)", "SM-T515": "Galaxy Tab A (10.1)",
}

def human_model(code, brand):
    if not code:
        return None
    c = str(code).split("/")[0].strip()
    if c in APPLE_MODELS:
        return APPLE_MODELS[c] if c.lower().startswith("iphone") else APPLE_MODELS[c]
    if c in SAMSUNG_MODELS:
        return SAMSUNG_MODELS[c]
    if c.upper().startswith("SM-"):
        return "Galaxy " + c[3:]
    return None

# ordre d'affichage dans le rapport
ORDER = ["Nom de l'appareil", "Marque", "Modele", "Systeme d exploitation",
         "Build", "Dernier patch de securite", "Numero de telephone", "IMEI",
         "Numero de serie", "ICCID", "MEID", "Target identifier",
         "Derniere sauvegarde", "Applications installees", "Capacite stockage"]

result = {k: (overrides.get({
    "Nom de l'appareil": "DeviceName", "Marque": "Brand", "Modele": "Model",
    "Systeme d exploitation": "OS", "Build": "Build", "IMEI": "IMEI",
    "Numero de serie": "Serial", "Capacite stockage": "Storage",
    "Numero de telephone": "Phone",
}.get(k, "")) or None) for k in ORDER}

model_code = overrides.get("ModelCode") or None
platform = overrides.get("Platform")

# --- Sources iOS (clés PascalCase) ---
for name in ("backup_info.json", "sysdiagnose_info.json"):
    p = os.path.join(root, name)
    if not os.path.isfile(p):
        continue
    try:
        d = json.load(open(p, encoding="utf-8"))
    except Exception:
        continue
    platform = "iOS"
    model_code = model_code or dig(d, ("Product Type", "product_type", "ProductType", "model"))
    ver = dig(d, ("Product Version", "product_version", "ProductVersion", "ios_version"))
    build = dig(d, ("Build Version", "build_version", "BuildVersion"))
    if ver:
        result["Systeme d exploitation"] = result["Systeme d exploitation"] or ("iOS " + str(ver))
    result["Build"] = result["Build"] or build
    result["Nom de l'appareil"] = result["Nom de l'appareil"] or \
        b64name(dig(d, ("Display Name",)) or "") or dig(d, ("Device Name", "device_name", "name", "Devicename"))
    result["Numero de telephone"] = result["Numero de telephone"] or \
        dig(d, ("Phone Number", "phone_number", "PhoneNumber"))
    result["IMEI"] = result["IMEI"] or dig(d, ("IMEI", "imei"))
    result["Numero de serie"] = result["Numero de serie"] or \
        dig(d, ("Serial Number", "serial_number", "SerialNumber", "Serial"))
    result["ICCID"] = result["ICCID"] or dig(d, ("ICCID", "iccid"))
    result["MEID"] = result["MEID"] or dig(d, ("MEID", "meid"))
    result["Target identifier"] = result["Target identifier"] or \
        dig(d, ("Target Identifier", "target_identifier", "Unique Identifier", "unique_identifier"))
    result["Derniere sauvegarde"] = result["Derniere sauvegarde"] or \
        dig(d, ("Last Backup Date", "last_backup_date", "LastBackupDate"))
    apps = dig(d, ("Installed Applications", "installed_applications"))
    if isinstance(apps, list) and apps:
        result["Applications installees"] = result["Applications installees"] or f"{len(apps)} application(s)"
    result["Marque"] = result["Marque"] or "Apple"
    break

# --- Source Android : acquisition.json ---
if platform != "iOS":
    p = os.path.join(root, "acquisition.json")
    if os.path.isfile(p):
        try:
            d = json.load(open(p, encoding="utf-8"))
        except Exception:
            d = {}
        platform = "Android"
        model_code = model_code or dig(d, ("product_model", "model", "device_model"))
        ver = dig(d, ("device_version", "android_version", "version", "os_version"))
        if ver:
            result["Systeme d exploitation"] = result["Systeme d exploitation"] or ("Android " + str(ver))
        result["Marque"] = result["Marque"] or \
            dig(d, ("product_manufacturer", "manufacturer", "brand"))
        result["IMEI"] = result["IMEI"] or dig(d, ("imei", "imei1", "Imei"))
        serial = result["Numero de serie"] or dig(d, ("serial_number", "serial", "Serial"))
        if not serial:
            adb = dig(d, ("collector", "Adb"))
            if isinstance(adb, dict):
                serial = adb.get("Serial")
        result["Numero de serie"] = result["Numero de serie"] or serial

# --- Source Android : getprop.txt ---
p = os.path.join(root, "getprop.txt")
if os.path.isfile(p):
    try:
        txt = open(p, encoding="utf-8", errors="ignore").read()
        gmap = {
            "ro.product.model": "Modele",
            "ro.product.manufacturer": "Marque",
            "ro.build.version.short": "Build",
            "ro.build.version.incremental": "Build",
            "ro.build.display.id": "Build",
            "ro.build.version.security_patch": "Dernier patch de securite",
            "ro.ril.oem.imei": "IMEI",
            "ro.serialno": "Numero de serie",
        }
        release = None
        mrel = re.search(r'\[ro\.build\.version\.release\]:\s*\[([^\]]*)\]', txt)
        if mrel:
            release = mrel.group(1)
        if release:
            result["Systeme d exploitation"] = result["Systeme d exploitation"] or ("Android " + release)
        for key, field in gmap.items():
            if result[field]:
                continue
            m = re.search(r'\[' + re.escape(key) + r'\]:\s*\[([^\]]*)\]', txt)
            if m and m.group(1):
                result[field] = m.group(1)
        if not result["Capacite stockage"]:
            for key in ("ro.product.disk.size", "ro.emmc.size"):
                m = re.search(r'\[' + re.escape(key) + r'\]:\s*\[([^\]]*)\]', txt)
                if m and m.group(1):
                    result["Capacite stockage"] = fmt_storage(m.group(1))
                    break
    except Exception:
        pass

# --- Compteur d'applications Android ---
if not result["Applications installees"]:
    for name in ("aqf_packages.json", "dumpsys_packages.json"):
        ap = os.path.join(root, name)
        if os.path.isfile(ap):
            try:
                alist = json.load(open(ap, encoding="utf-8"))
                if isinstance(alist, list):
                    n = len([x for x in alist if isinstance(x, dict) and x.get("name")])
                    if n:
                        result["Applications installees"] = f"{n} application(s)"
                        break
            except Exception:
                pass

# --- Modele humain + codé ---
if not result["Modele"] and model_code:
    human = human_model(model_code, result["Marque"])
    result["Modele"] = f"{human} ({model_code})" if human else str(model_code)
elif result["Modele"]:
    human = human_model(result["Modele"], result["Marque"])
    if human and human != str(result["Modele"]):
        result["Modele"] = f"{human} ({result['Modele']})"

for field in ORDER:
    val = result[field]
    if val not in (None, "", "non disponible"):
        print(f"{field}: {str(val)[:170]}")
PY
}

# ------------------------------------------------------------------
# Rapport d'analyse texte (rapport.txt) + retour console
# ------------------------------------------------------------------
collect_detected() {
  find "$1" -maxdepth 1 -type f -name '*_detected.json' 2>/dev/null | LC_ALL=C sort
}

# Statistiques agrégées sur tous les *_detected.json du dossier.
# Sortie TSV : total|<n> | level|<SEV>|<n> | module|<mod>|<nb>|<niveau max>
detection_stats() {
  python3 - "$1" <<'PY'
import json, os, sys
from collections import defaultdict
root = sys.argv[1]
order = {"CRITICAL": 4, "HIGH": 3, "MEDIUM": 2, "LOW": 1, "INFO": 0}
try:
    files = sorted(f for f in os.listdir(root)
                   if f.endswith("_detected.json") and os.path.isfile(os.path.join(root, f)))
except OSError:
    sys.exit(0)
tot, bylev, bymod = 0, defaultdict(int), {}
for fn in files:
    try:
        data = json.load(open(os.path.join(root, fn), encoding="utf-8"))
    except Exception:
        continue
    if not isinstance(data, list):
        continue
    mod = fn.replace("_detected.json", "")
    for rec in data:
        if not isinstance(rec, dict):
            continue
        lev = str((rec.get("level") or rec.get("severity") or "")).upper()
        if lev not in order:
            lev = "INFO"
        tot += 1
        bylev[lev] += 1
        if mod not in bymod:
            bymod[mod] = [0, ""]
        bymod[mod][0] += 1
        if not bymod[mod][1] or order[lev] > order[bymod[mod][1]]:
            bymod[mod][1] = lev
print(f"total|{tot}")
for k in ("CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"):
    print(f"level|{k}|{bylev.get(k, 0)}")
for mod, (c, mx) in sorted(bymod.items()):
    print(f"module|{mod}|{c}|{mx}")
PY
}

# Bloc de synthèse (ligne de verdict) inséré en tête du rapport.
# $1 = dossier d'analyse
detection_synthesis() {
  local results="$1"
  local tot=0 c_crit=0 c_high=0 c_med=0 c_low=0 c_info=0 mods=0
  local t a b verdict
  while IFS='|' read -r t a b; do
    case "$t" in
      total) tot="$a" ;;
      level) case "$a" in
               CRITICAL) c_crit="$b" ;;
               HIGH)     c_high="$b" ;;
               MEDIUM)   c_med="$b" ;;
               LOW)      c_low="$b" ;;
               INFO)     c_info="$b" ;;
             esac ;;
      module) mods=$((mods + 1)) ;;
    esac
  done < <(detection_stats "$results")

  if [ "$tot" -le 0 ]; then
    verdict="AUCUNE détection d'IoC - preuve a priori saine (à confirmer)."
  elif [ "$c_crit" -gt 0 ]; then
    verdict="CRITIQUE - indicateurs de niveau maximal détectés : compromission hautement probable, investigation immédiate requise."
  elif [ "$c_high" -gt 0 ]; then
    verdict="ELEVE - indicateurs de niveau élevé détectés : investigation prioritaire recommandée."
  elif [ "$c_med" -gt 0 ]; then
    verdict="MOYEN - indicateurs de niveau moyen détectés : à investiguer et corroborer."
  else
    verdict="FAIBLE/INFO - seuls des indicateurs de niveau faible ou informatifs ont été relevés (à surveiller)."
  fi

  echo '--------------------------------------------------------------'
  echo "  SYNTHESE DE L'ANALYSE"
  echo '--------------------------------------------------------------'
  echo "  Detections            : $tot"
  echo "  Repartition severite  : CRITICAL: $c_crit | HIGH: $c_high | MEDIUM: $c_med | LOW: $c_low | INFO: $c_info"
  echo "  Modules concernes     : $mods"
  echo "  Verdict               : $verdict"
  echo ""
}

# Liste propre des IoCs utilisés (basename, dédupliqués) depuis info.json.
iocs_csv_from_results() {
  local results="$1"
  [ -f "$results/info.json" ] || { printf '%s' "${2:-}"; return 0; }
  python3 - "$results/info.json" <<'PY'
import json, os, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    files = [os.path.basename(x) for x in (d.get("ioc_files") or [])]
    files = sorted(set(files))
    print(", ".join(files))
except Exception:
    pass
PY
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
    echo "Structure        : ${STRUCTURE_NAME:-non renseignée}"
    echo "Consentement     : consentement écrit recueilli"
    echo "Versions outil   : wrapper ${VERSION:-n/a} / MVT $(mvt_version_local 2>/dev/null || echo n/a)"
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
  local _dev_lines=""
  _dev_lines="$(extract_device_details "$results" 2>/dev/null)"
  if [ -z "$_dev_lines" ] && [ -n "$evidence_dir" ] && [ -d "$evidence_dir" ]; then
    _dev_lines="$(extract_device_details "$evidence_dir" 2>/dev/null)"
  fi
  if [ -n "$_dev_lines" ]; then
    printf '  %s\n' "$_dev_lines"
  else
    echo "  Informations sur l'appareil non disponibles."
  fi
  echo ''
  if [ -n "$iocs_csv" ]; then
    echo "IoCs utilisés    : $iocs_csv"
  elif [ -n "$results" ] && [ -f "$results/info.json" ]; then
    echo "IoCs utilisés    : $(iocs_csv_from_results "$results")"
  else
    echo "IoCs utilisés    : (aucun; IoCs officiels MVT éventuels)"
  fi
  echo ''
  echo '--------------------------------------------------------------'
  echo '  MENACES / INDICATEURS DE COMPROMISSION DETECTES'
  echo '--------------------------------------------------------------'
  detection_synthesis "$results"
  echo ''
  detection_stats "$results"
  echo ''
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
    echo '  MODULES EXECUTES'
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
  custody_log "Accompagnement proposé ($platform) : 3919, 116 006, Centre Hubertine Auclert, CNIL, Cybermalveillance, Echap, commissaire de justice."
  return 0
}

