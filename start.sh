#!/usr/bin/env bash
# ============================================================
#  WRAPPER MVT — point d'entrée unique
#   . menu interactif (par défaut) :
#      - lancer une analyse (iOS / Android)
#      - gérer les IoCs (fichier, URL, dépôt git, mise à jour)
#      - vérifier / installer les dépendances
#   . sous-commandes pour un usage direct :
#      start.sh analyse | iocs | update-iocs | add | add-repo
#      list-iocs | env-iocs | install | help
# ============================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib/common.sh"

mkdir -p "$EVIDENCE_DIR" "$REPORTS_DIR" "$IOCS_CUSTOM_DIR" "$IOCS_MANAGED_DIR" "$TOOLS_DIR"

usage() {
  cat <<'EOF'
Usage : ./start.sh [commande] [options]

  (sans commande)        Affiche le menu principal interactif
  menu                   Idem
  analyse                Lance le flux d'analyse (IoCs + analyse)
    --no-ioc-update      Ne pas proposer la mise à jour des IoCs
    --analyst "Nom"      Nom indiqué dans le rapport
  iocs                   Ouvre le menu de gestion des IoCs
  update-iocs            Met à jour les IoCs (repos git + officiels)
  add <fichier|URL>      Ajoute un fichier d'IoC ou une URL distante
  add-repo <URL-git>     Ajoute un dépôt git et le synchronise
  list-iocs              Liste les fichiers IoCs chargés
  env-iocs               Affiche la variable MVT_STIX2
  config                 Ouvre le menu de configuration (VirusTotal, verrou, analyste)
  install                Lance install.sh (dépendances)
  terminal [analyse]     Ouvre dans un terminal dédié (Konsole/WezTerm)
  help                   Cette aide

Navigation des menus : flèches ↑/↓ + Entrée pour valider.
EOF
}

# ============================================================
#  PARTIE 1 — GESTION DES IOCS
# ============================================================

# Mise à jour : synchronise les repos git (iocs/managed/) + IoCs officiels.
cmd_update() {
  local url name dir_i all_before all_after
  local new=() rem=()

  if [ "${#IOC_REPOS[@]}" -eq 0 ]; then
    log_info "Aucun repo git configuré (IOC_REPOS)."
  fi

  all_before="$(find_ioc_files)"

  for url in "${IOC_REPOS[@]}"; do
    name="$(basename "$url" .git)"
    dir_i="$IOCS_MANAGED_DIR/$name"
    if [ -d "$dir_i/.git" ]; then
      log_info "Mise à jour du repo : $name"
      ( cd "$dir_i" && git pull --ff-only ) || log_warn "Échec git pull pour $name"
    else
      log_info "Clonage du repo : $name"
      git clone --depth 1 "$url" "$dir_i" 2>/dev/null || log_warn "Échec git clone pour $url"
    fi
  done

  if [ "${DOWNLOAD_OFFICIAL_IOCS:-yes}" = "yes" ]; then
    if have mvt; then
      log_info "Téléchargement des IoCs officiels (mvt download-iocs)..."
      mvt download-iocs 2>/dev/null || log_warn "mvt download-iocs a échoué (réseau ? IoCs déjà présents ?)"
    else
      log_warn "mvt non installé ; utilisez 'install' dans le menu principal (ou ./install.sh)."
    fi
  fi

  all_after="$(find_ioc_files)"
  mapfile -t new < <(comm -13 <(printf '%s\n' "$all_before") <(printf '%s\n' "$all_after"))
  mapfile -t rem < <(comm -23 <(printf '%s\n' "$all_before") <(printf '%s\n' "$all_after"))

  echo ""
  if [ "${#new[@]}" -gt 0 ]; then
    log_ok "Nouveaux fichiers IoCs importés :"
    printf '   • %s\n' "${new[@]}"
  fi
  if [ "${#rem[@]}" -gt 0 ]; then
    log_warn "Fichiers IoCs disparus (mises à jour / renommés) :"
    printf '   • %s\n' "${rem[@]}"
  fi
  if [ "${#new[@]}" -eq 0 ] && [ "${#rem[@]}" -eq 0 ]; then
    log_ok "Aucun changement par rapport à la dernière synchronisation."
  fi
  write_index
  log_ok "Mise à jour des IoCs terminée."
}

# Ajoute un IoC depuis un fichier local ou une URL.
cmd_add() {
  local src="${1:-}" base tmp=""

  if [ -z "$src" ]; then
    log_err "Fournissez un chemin de fichier ou une URL."
    return 1
  fi

  tmp="$(mktemp --suffix=.json)"

  if [[ "$src" =~ ^https?:// ]]; then
    log_info "Téléchargement de $src ..."
    if ! curl -fsSL --max-time 60 -o "$tmp" "$src"; then
      rm -f "$tmp"
      log_err "Échec du téléchargement de l'URL : $src"
      return 1
    fi
  elif [ -f "$src" ]; then
    cp "$src" "$tmp"
  else
    rm -f "$tmp"
    log_err "Fichier introuvable : $src"
    return 1
  fi

  if ! valid_json "$tmp"; then
    rm -f "$tmp"
    log_err "Le fichier n'est pas un JSON/STIX2 valide. Ajout annulé."
    return 1
  fi

  base="$(basename "$src")"; base="${base%%\?*}"
  [[ "$base" == *.stix2 || "$base" == *.json ]] || base="${base}.stix2"
  if [ -e "$IOCS_CUSTOM_DIR/$base" ]; then
    base="${base%.*}_$(date '+%Y%m%d%H%M%S').${base##*.}"
    log_warn "Un fichier du même nom existait déjà ; importé sous $base"
  fi

  mv "$tmp" "$IOCS_CUSTOM_DIR/$base"
  rm -f "$tmp"
  log_ok "IoC ajouté : $IOCS_CUSTOM_DIR/$base"
  write_index
}

# Enregistre un dépôt git dans config.sh et le clone dans iocs/managed/.
cmd_add_repo() {
  local url="${1:-}" name dir_i existed="no" i

  if [ -z "$url" ]; then
    log_err "Fournissez l'URL du dépôt git (ex. https://github.com/user/iocs.git)."
    return 1
  fi
  [[ "$url" =~ ^https?:// ]] || url="https://github.com/$url"

  name="$(basename "$url" .git)"
  dir_i="$IOCS_MANAGED_DIR/$name"

  for i in "${IOC_REPOS[@]}"; do
    [ "$i" = "$url" ] && existed="yes"
  done
  if [ "$existed" = "no" ]; then
    python3 - "$SCRIPT_DIR/config.sh" "$url" <<'PY'
import sys
path, url = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
out = []
for ln in lines:
    out.append(ln)
    if ln.strip().startswith("IOC_REPOS=("):
        out.append('  "%s"%s' % (url, "\n"))
open(path, "w", encoding="utf-8").write("".join(out))
PY
    log_ok "Repo enregistré dans config.sh (IOC_REPOS)."
  else
    log_info "Ce repo est déjà enregistré."
  fi

  if [ -d "$dir_i/.git" ]; then
    log_info "Repo déjà cloné ($dir_i)"
  else
    log_info "Clonage de $url ..."
    git clone --depth 1 "$url" "$dir_i" || log_warn "Échec du clonage. Vérifiez l'URL."
  fi
  write_index
}

# Liste des bundies IoCs chargés.
cmd_list() {
  local custom=() managed=() n
  mapfile -t custom < <(find "$IOCS_CUSTOM_DIR" -type f \( -name '*.stix2' -o -name '*.json' \) 2>/dev/null | LC_ALL=C sort)
  mapfile -t managed < <(find "$IOCS_MANAGED_DIR" -mindepth 2 -type f \( -name '*.stix2' -o -name '*.json' \) ! -path '*/.git/*' 2>/dev/null | LC_ALL=C sort)

  banner "Bundles IoCs disponibles"
  echo "  • iocs/custom/   (${#custom[@]} fichier(s)) - IoCs local)"
  if [ "${#custom[@]}" -gt 0 ]; then printf '      %s\n' "${custom[@]##*/}"; fi
  echo "  • iocs/managed/  (${#managed[@]} fichier(s)) - dépôts git synchronisés)"
  if [ "${#managed[@]}" -gt 0 ]; then
    printf '      %s\n' "${managed[@]}" | sed "s|$IOCS_MANAGED_DIR/||"
  fi
  if have mvt; then
    echo "  • IoCs officiels (téléchargés par 'mvt download-iocs')"
  fi
  echo ""
  [ -f "$IOCS_DIR/index.txt" ] && echo "  Dernière mise à jour : $(head -n 1 "$IOCS_DIR/index.txt")"
  echo ""
  n="$(build_stix2_env | tr ':' '\n' | grep -c . || true)"
  log_info "Fichiers IoCs chargés (MVT_STIX2) : $n"
}

cmd_env() {
  local env="$(build_stix2_env)"
  if [ -n "$env" ]; then
    printf 'export MVT_STIX2=%q\n' "$env"
  else
    echo "# Aucun fichier IoC"
  fi
}

# ============================================================
#  PARTIE 1.5 — CONFIGURATION (menu + sauvegarde dans config.sh)
# ============================================================

# Écrit ou met à jour une variable dans config.sh (remplace la ligne existante
# si présente, sinon l'ajoute en fin de fichier).
config_set_value() {
  local var="$1" val="$2"
  python3 - "${CONFIG_FILE:-$WRAPPER_DIR/config.sh}" "$var" "$val" <<'PY'
import re, sys
path, var, val = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
out, found = [], False
for ln in lines:
    if re.match(r'^\s*' + re.escape(var) + r'\s*=', ln):
        out.append(f'{var}="{val}"\n')
        found = True
    else:
        out.append(ln)
if not found:
    out.append(f'{var}="{val}"\n')
open(path, "w", encoding="utf-8").write("".join(out))
PY
}

# Inverse un flag yes/no dans config.sh ($1 = variable, $2 = actuel) et
# imprime la nouvelle valeur.
toggle_config_flag() {
  local var="$1" cur="$2" new="no"
  [ "$cur" = "yes" ] || new="yes"
  config_set_value "$var" "$new"
  printf '%s' "$new"
}

# Masque une valeur sensible (clés API) : affiche **** + 4 derniers caractères.
mask_secret() {
  local v="$1" n
  [ -n "$v" ] || { printf ' !!! Non définie !!!'; return; }
  n="${#v}"
  if [ "$n" -le 4 ]; then printf '****'; else printf '****%s' "${v: -4}"; fi
}

# Menu de configuration interactif (VirusTotal, verrouillage, analyste).
config_menu() {
  local opt cur new_analyst new_value
  while :; do
    screen_clear
    banner "MVT Config" "=== CONFIGURATION ==="
    opt="$(menu_select_idx \
        "" \
        "VirusTotal : activer / désactiver  [$( [ "${ENABLE_VIRUSTOTAL:-no}" = "yes" ] && echo activé || echo désactivé )]" \
        "VirusTotal : définir la clé API   [$(mask_secret "${MVT_VT_API_KEY:-}")]" \
        "Verrouillage des preuves  [$( [ "${LOCK_EVIDENCE:-yes}" = "yes" ] && echo activé || echo désactivé )]" \
        "Analyste [${ANALYST:-$(whoami)}]" \
        "Structure [${STRUCTURE_NAME:-non renseignée}]" \
        "Retour")"
    echo ""
    
    case "$opt" in
      1) 
         screen_clear
         cur="${ENABLE_VIRUSTOTAL:-no}"
         
         if [ "$cur" = "yes" ]; then
           if ask_yesno "VirusTotal est actuellement ACTIVÉ. Voulez-vous le désactiver ?" "n"; then
             ENABLE_VIRUSTOTAL="no"
             config_set_value "ENABLE_VIRUSTOTAL" "no"
             log_warn "VirusTotal désactivé."
           else
             log_info "Aucun changement, VirusTotal reste activé."
           fi
         else
           if ask_yesno "VirusTotal est actuellement DÉSACTIVÉ. Voulez-vous l'activer ?" "y"; then
             ENABLE_VIRUSTOTAL="yes"
             config_set_value "ENABLE_VIRUSTOTAL" "yes"
             log_ok "VirusTotal activé — la clé API sera utilisée lors des analyses."
           else
             log_info "Aucun changement, VirusTotal reste désactivé."
           fi
         fi
         
         continue_or_back "Configurer VirusTotal" 
         ;;
      2) 
         screen_clear
         log_info "Clé actuelle : $(mask_secret "${MVT_VT_API_KEY:-}")"
         echo ""
         log_info "Saisissez la nouvelle clé API VirusTotal (https://www.virustotal.com/gui/my-apikey)."
         new_value="$(ask_input "Clé API (laisser vide pour effacer) :" "")"
         if [ -n "$new_value" ]; then
           MVT_VT_API_KEY="$new_value"
           config_set_value "MVT_VT_API_KEY" "$new_value"
           log_ok "Clé API VirusTotal enregistrée."
         else
           MVT_VT_API_KEY=""
           config_set_value "MVT_VT_API_KEY" ""
           log_info "Clé API effacée."
         fi
         continue_or_back "Définir la clé API VirusTotal" 
         ;;
      3) 
         screen_clear
         cur="${LOCK_EVIDENCE:-yes}"
         if ask_yesno "Verrouiller les preuves en lecture seule ?" "$cur"; then
           LOCK_EVIDENCE="yes"
           config_set_value "LOCK_EVIDENCE" "yes"
           log_ok "Verrouillage des preuves activé."
         else
           LOCK_EVIDENCE="no"
           config_set_value "LOCK_EVIDENCE" "no"
           log_warn "Verrouillage des preuves désactivé."
         fi
         continue_or_back "Verrouillage des preuves" 
         ;;
      4) 
         screen_clear
         new_analyst="$(ask_input "Nom de l'analyste :" "${ANALYST:-$(whoami)}")"
         if [ -n "$new_analyst" ]; then
           ANALYST="$new_analyst"
           config_set_value "ANALYST" "$new_analyst"
           log_ok "Analyste défini : $new_analyst"
         else
           log_info "Analyste inchangé."
         fi
         continue_or_back "Définir l'analyste" 
         ;;
     5) 
         screen_clear
         new_struct="$(ask_input "Nom de la structure :" "${STRUCTURE_NAME:-}")"
         if [ -n "$new_struct" ]; then
           STRUCTURE_NAME="$new_struct"
           config_set_value "STRUCTURE_NAME" "$new_struct"
           log_ok "Structure enregistrée : $STRUCTURE_NAME"
         else
           STRUCTURE_NAME=""
           config_set_value "STRUCTURE_NAME" ""
           log_warn "Structure effacée (mention « non renseignée » au rapport)."
         fi
         continue_or_back "Définir la structure" 
         ;;
      *) 
         return 0 
         ;;
    esac
  done
}

# ============================================================
#  PARTIE 2 — ANALYSE D'UN MOBILE
# ============================================================

write_index() {
  mkdir -p "$IOCS_DIR"
  {
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo ""
    echo "### Bundles IoCs ($(find_ioc_files | wc -l | tr -d ' ') fichiers) ###"
    find_ioc_files | while IFS= read -r _f; do printf '  %s\n' "$(to_relative "$_f")"; done
  } > "$IOCS_DIR/index.txt"
}

# Menu interactif des IoCs (réutilisé par le menu principal et l'analyse).
iocs_menu() {
  local opt p u g
  while :; do
    screen_clear
    ascii_banner "MVT IoCs" "=== GESTION DES IOCS ==="
    opt="$(menu_select_idx \
        "" \
        "Mettre à jour (repos git + IoCs officiels)" \
        "Ajouter un fichier local (.stix2/.json)" \
        "Ajouter une URL distante" \
        "Ajouter un dépôt git" \
        "Lister les fichiers IoCs chargés" \
        "Retour")"
    echo ""
    case "$opt" in
      1) screen_clear; cmd_update; continue_or_back "Mettre à jour les IoCs" ;;
      2) screen_clear
         p="$(ask_input "Chemin du fichier .stix2/.json (ou deplacer le fichier dans le dossier iocs/custom/ de ce projet) : " "")"
         [ -n "$p" ] && cmd_add "$p" || echo "  (Annulé)"
         continue_or_back "Ajouter un fichier local" ;;
      3) screen_clear
         u="$(ask_input "Fournissez l'URL du fichier d'IoCs (https://...) : " "")"
         [ -n "$u" ] && cmd_add "$u" || echo "  (Annulé)"
         continue_or_back "Ajouter une URL distante" ;;
      4) screen_clear
         g="$(ask_input "Fournissez l'URL du dépôt git (https://...) : " "")"
         [ -n "$g" ] && cmd_add_repo "$g" || echo "  (Annulé)"
         continue_or_back "Ajouter un dépôt git" ;;
      5) screen_clear; cmd_list; continue_or_back "Lister les fichiers IoCs chargés" ;;
      *) log_ok "Retour au menu principal."; return 0 ;;
    esac
  done
}

# ============================================================
#  PARTIE 2 — ANALYSE D'UN MOBILE
# ============================================================

choose_label() {  # $1..n : labels ; imprime l'index choisi (1-based)
  local i label choice
  choice="$(menu_select "Quel appareil analyser ?" "$@")"
  for ((i=1;i<=$#;i++)); do
    label="${!i}"
    [ "$label" = "$choice" ] && { echo "$i"; return 0; }
  done
  echo 1
}

detect_ios() {
  local udid name model ver imei serial tsd
  local _u=()
  mapfile -t _u < <(idevice_id -l 2>/dev/null)
  IOS_DEVICES=(); IOS_IMEIS=(); IOS_SERIALS=(); IOS_CAPACITY=()
  for udid in "${_u[@]}"; do
    [ -n "$udid" ] || continue
    name=$(ideviceinfo -u "$udid" -k DeviceName 2>/dev/null | tr -d '\r')
    model=$(ideviceinfo -u "$udid" -k ProductType 2>/dev/null | tr -d '\r')
    ver=$(ideviceinfo -u "$udid" -k ProductVersion 2>/dev/null | tr -d '\r')
    imei=$(ideviceinfo -u "$udid" -k InternationalMobileEquipmentIdentity 2>/dev/null | tr -d '\r')
    serial=$(ideviceinfo -u "$udid" -k SerialNumber 2>/dev/null | tr -d '\r')
    tsd=$(ideviceinfo -u "$udid" -k TotalDataCapacity 2>/dev/null | tr -d '\r')
    IOS_DEVICES+=("${udid}|${name:-inconnu}|${model:-inconnu}|${ver:-inconnu}")
    IOS_IMEIS+=("${imei:-}")
    IOS_SERIALS+=("${serial:-}")
    IOS_CAPACITY+=("${tsd:-}")
  done
}

# Nécessite ideviceinfo (libimobiledevice). Extraction IMEI/série/capacité (octets).
ios_device_details() {
  local udid="$1" k v out=""
  for k in InternationalMobileEquipmentIdentity SerialNumber TotalDataCapacity; do
    v="$(ideviceinfo -u "$udid" -k "$k" 2>/dev/null | tr -d '\r')"
    [ -n "$v" ] && out="${out:+$out|}$k=$v"
  done
  printf '%s' "$out"
}

detect_android() {
  local s m d v
  local _s=()
  mapfile -t _s < <(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}')
  ANDROID_SERIALS=(); ANDROID_DEVICES=()
  if [ "${#_s[@]}" -eq 0 ]; then
    local _raw; _raw="$(adb devices 2>/dev/null | awk 'NR>1 && $1{print $1" "$2}')"
    [ -n "$_raw" ] && log_warn "Appareil non autorisé / non connecté : $_raw"
  fi
  for s in "${_s[@]}"; do
    m=$(adb -s "$s" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    d=$(adb -s "$s" shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r')
    v=$(adb -s "$s" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
    ANDROID_SERIALS+=("$s")
    ANDROID_IMEIS+=("$(_android_imei "$s")")
    ANDROID_CAPACITY+=("$(_android_capacity "$s")")
    ANDROID_DEVICES+=("${s}|${d:-?}|${m:-?}|Android ${v:-?}")
  done
}

# IMEI Android : ro.ril.oem.imei1/2 puis ro.ril.oem.imei (vide si non exposé).
_android_imei() {
  local s="$1" i
  for i in ro.ril.oem.imei1 ro.ril.oem.imei2 ro.ril.oem.imei ro.serialno; do
    local v
    v="$(adb -s "$s" shell getprop "$i" 2>/dev/null | tr -d '\r')"
    [ -n "$v" ] && { printf '%s' "$v"; return; }
  done
}

# Capacité de stockage Android (octets) à partir de /proc/partitions (disque mmcblk).
_android_capacity() {
  local s="$1" b name total=0
  while IFS= read -r b; do name=${b##* } total=$((total + ${name:-0})); done \
    < <(adb -s "$s" shell cat /proc/partitions 2>/dev/null | sed 's/  */ /g' | cut -d' ' -f3 | tail -n +1)
  [ "$total" -gt 0 ] && printf '%s' "$((total * 1024))" || printf '%.0f' "$(adb -s "$s" shell df -k /data 2>/dev/null | awk 'NR==2{print $2 * 1024}')"
}

# Attend que le téléphone soit branché et détecté avant l'acquisition.
# $1 = "ios" | "android". Boucle : Entrée relance la détection, q annule.
wait_for_device() {
  local plat="$1" found=0 k
  echo ""
  banner "Préparation de l'analyse"
  if [ "$plat" = "ios" ]; then
    echo "  1. Branchez votre iPhone avec le câble USB."
    echo "  2. Déverrouillez l'écran."
    echo "  3. Acceptez « Faire confiance à cet ordinateur » et le jumelage (PIN si demandé)."
  else
    echo "  1. Branchez votre téléphone Android avec le câble USB."
    echo "  2. Activez le débogage USB (Réglages > Options développeur)."
    echo "  3. Sur le téléphone, acceptez « Autoriser le débogage USB »."
  fi
  echo ""
  while [ "$found" -eq 0 ]; do
    if [ -t 0 ]; then
      printf '> Appuyez sur Entrée pour (re)détecter : ' >&2
      IFS= read -rsn1 k || return 1
      case "$k" in q|Q) log_ok "Appareil non détecté — analyse annulée."; return 1 ;; esac
    else
      read -r || return 1   # repli non-interactif
    fi
    if [ "$plat" = "ios" ]; then detect_ios; else detect_android; fi
    if [ "$plat" = "ios" ]; then [ "${#IOS_DEVICES[@]}" -ge 1 ] && found=1; else [ "${#ANDROID_SERIALS[@]}" -ge 1 ] && found=1; fi
    [ "$found" -eq 0 ] && log_warn "Toujours pas détecté — rebranchez / autorisez, puis Entrée."
  done
  return 0
}

resolve_backup_dir() {  # dossier contenant Manifest.db (ou lui-même)
  local p="$1" m
  if [ -d "$p" ]; then
    if [ -e "$p/Manifest.db" ]; then printf '%s' "$p"
    else
      m="$(find "$p" -maxdepth 2 -name Manifest.db 2>/dev/null | head -n 1)"
      [ -n "$m" ] && printf '%s' "${m%/Manifest.db}" || printf '%s' "$p"
    fi
  else
    printf '%s' "$p"
  fi
}

hash_external() {  # hash d'une source externe SANS la modifier
  local src="$1" out="$2"
  if [ -f "$src" ]; then
    ( cd "$(dirname "$src")" && sha256sum "$(basename "$src")" ) > "$out"
  elif [ -d "$src" ]; then
    ( cd "$src" && find . -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 sha256sum 2>/dev/null ) > "$out"
  fi
}

run_mvt() {
  local cmd=("$@")
  audit_log "CMD: ${cmd[*]}"
  log_info "Lancement : ${cmd[*]}"
  "${cmd[@]}"
}

# ============================================================
#  FLUX D'ANALYSE COMPLET
# ============================================================
cmd_analyse() {
  local MODE_NO_IOC_UPDATE=no
  local opt platform action add_choice p u g ud n mo v s d m
  local idx case_dir results backup_dir acq path enc raw
  local defU nbf
  local FAST local_labels fn_device ANALYSIS_INPUT ANALYSIS_TYPE
  local mvt_cmd DEVICE_INFO RESULTSIF nb

  while [ $# -gt 0 ]; do
    case "$1" in
      --no-ioc-update) MODE_NO_IOC_UPDATE=yes ;;
      --analyst)       ANALYST="${2:-}"; shift ;;
      -h|--help) cat <<'EOF'
Usage : ./start.sh analyse [--no-ioc-update] [--analyst "Nom de l'analyste"]
EOF
        return 0 ;;
      *) log_err "Option inconnue : $1" ; return 1 ;;
    esac
    shift
  done

  screen_clear
  ascii_banner "MVT WRAPPER" "=== ANALYSE MOBILE ==="
  log_info "Analyste : ${ANALYST:-$(whoami)}"

  # --- Préparation des IoCs (mise à jour + gestion éventuelle) ---
  if [ "$MODE_NO_IOC_UPDATE" != "yes" ]; then
    defU="n"; [ "${UPDATE_IOCS_BEFORE_ANALYSIS:-yes}" = "yes" ] && defU="y"
    if ask_yesno "Mettre à jour les IoCs avant l'analyse ?" "$defU"; then
      cmd_update
    fi
  fi
  if ask_yesno "Gérer / ajouter des IoCs maintenant ?" "n"; then
    iocs_menu
  fi

  MVT_STIX2="$(build_stix2_env)"
  export MVT_STIX2
  nbf="$(printf '%s' "$MVT_STIX2" | tr ':' '\n' | grep -c . || true)"
  if [ "$nbf" -gt 0 ]; then
    log_ok "IoCs chargés (${nbf} fichier(s)) :"
  else
    log_warn "Aucun IoC perso dans iocs/custom|managed — MVT utilisera ses IoCs officiels (si téléchargés)."
  fi

  # --- Prérequis ---
  if ! have mvt; then
    log_err "MVT non installé."
    if ask_yesno "Lancer install.sh maintenant ?" "n"; then "$SCRIPT_DIR/install.sh"; fi
    have mvt || { log_err "MVT toujours absent — analyse annulée."; return 1; }
  fi
  have mvt-ios    || log_warn "mvt-ios introuvable (relancez install.sh)"
  have mvt-android || log_warn "mvt-android introuvable (relancez install.sh)"

  # --- Menu principal d'action ---
  action="$(menu_select "Que souhaitez-vous faire ?" \
      "Nouvelle aquisition" \
      "Analyser un backup existant" \
      "Retour")"
  [ "${action#Retour}" != "$action" ] && { log_ok "Retour."; return 0; }
  MODE_ACQUISITION="no"; [ "${action#Nouvelle}" != "$action" ] && MODE_ACQUISITION="yes"

  platform="$(menu_select "Plateforme ?" "iOS" "Android")"

  # --- Dossier d'affaire ---
  CASE_ID="$(get_case_id)"
  case_dir="$EVIDENCE_DIR/$CASE_ID"
  results="$REPORTS_DIR/$CASE_ID"
  mkdir -p "$case_dir" "$results"
  CUSTODY_FILE="$case_dir/chain_of_custody.txt"
  AUDIT_FILE="$case_dir/audit.log"
  : > "$AUDIT_FILE"
  custody_log "Début de l'affaire $CASE_ID — plateforme $platform — analyste ${ANALYST:-$(whoami)}"
  custody_log "Dossier de preuve : $case_dir"
  custody_log "Dossier des résultats : $results"
  log_info "Dossier d'affaire (preuve) : $case_dir"
  log_info "Dossier des résultats    : $results"

  if [ "$MODE_ACQUISITION" = "yes" ]; then
    # ================= Analyse =================
    if [ "$platform" = "iOS" ]; then
      have idevice_id || die "libimobiledevice manquant. Lancez : ./install.sh"
      wait_for_device ios || { rm -rf "$case_dir" "$results"; return 1; }
      local_labels=(); for line in "${IOS_DEVICES[@]}"; do
        IFS='|' read -r ud n mo v <<< "$line"
        local_labels+=("$n — $mo (iOS $v) — $ud")
      done
      idx="$(choose_label "${local_labels[@]}")"
      IFS='|' read -r IOS_UDID IOS_NAME IOS_MODEL IOS_VER <<< "${IOS_DEVICES[$((idx-1))]}"
      log_info "Appareil sélectionné : $IOS_NAME ($IOS_MODEL), iOS $IOS_VER"
      custody_log "Appareil sélectionné : $IOS_NAME ($IOS_MODEL) iOS $IOS_VER — UDID $IOS_UDID"

      # --- Dossier d'affaire : CASE-<date>-<IMEI> si IMEI disponible (sinon date seule) ---
      IOS_IMEI="${IOS_IMEIS[$((idx-1))]:-}"
      if [ -n "$IOS_IMEI" ]; then
        local _new case_new
        _new="$(get_case_id_with_imei "$IOS_IMEI")"
        if [ "$_new" != "$CASE_ID" ]; then
          case_new="$EVIDENCE_DIR/$_new"
          mv "$case_dir" "$case_new" 2>/dev/null || case_new="$case_dir"
          custody_log "Renommage du dossier d'affaire -> $case_new (IMEI $IOS_IMEI)"
          case_dir="$case_new"
          CASE_ID="$_new"
          results="$REPORTS_DIR/$CASE_ID"
          mkdir -p "$results"
          CUSTODY_FILE="$case_dir/chain_of_custody.txt"
          AUDIT_FILE="$case_dir/audit.log"
        fi
      else
        IOS_IMEI="non disponible"
      fi

      enc=""; enc="$(idevicebackup2 -i encryption status 2>/dev/null ||
                            idevicebackup2 encryption status 2>/dev/null || true)"
      if echo "$enc" | grep -qi enabled; then
        IOS_ENCRYPTED=yes
        log_ok "Backup de l'appareil chiffrée (recommandé pour la forensique)."
      elif echo "$enc" | grep -qi disabled; then
        IOS_ENCRYPTED=no
        log_warn "Chiffrement du backup DÉSACTIVÉ. Sans chiffrement des sources clés seront absentes (calls, safari_history, analytics, ...)."
        if ask_yesno "Activer le chiffrement maintenant ? (PIN requis sur l'appareil)" "y"; then
          idevicebackup2 -i encryption on 2>&1 || idevicebackup2 encryption on 2>&1 || true
          IOS_ENCRYPTED=yes
        fi
      else
        IOS_ENCRYPTED=unknown
        log_warn "Impossible de déterminer l'état du chiffrement ; confirmez sur l'appareil."
      fi

      IOS_PASSWORD=""
      if [ "$IOS_ENCRYPTED" = "yes" ] || ask_yesno "La backup est-elle protégée par mot de passe (chiffrée) ?" "n"; then
        IOS_PASSWORD="$(ask_input "Mot de passe de la backup iOS :" "")"
        [ -n "$IOS_PASSWORD" ] || log_warn "Aucun mot de passe saisi — déchiffrement ignoré le cas échéant."
      fi

      confirm_consent_and_scope "iOS" "$case_dir" || { custody_log "Acquisition iOS refusée (consentement/périmètre non confirmé)."; continue_or_back "Acquisition iOS" ; }

      screen_clear
      banner "Lancement de la sauvegarde (gardez l'appareil DÉVERROUILLÉ et branché)..."
      idevicebackup2 backup --full "$case_dir" \
        || { quarantine_failed_acquisition "$case_dir" "iOS"; die "Échec de la sauvegarde iTunes (idevicebackup2) — capture partielle isolée en quarantaine."; }
      custody_log "Sauvegarde iTunes effectuée -> $case_dir"
      backup_dir="$(find "$case_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
      [ -n "$backup_dir" ] || die "Sauvegarde créée mais dossier introuvable dans $case_dir"
      log_ok "Sauvegarde brute : $backup_dir"

      hash_tree "$case_dir" "$case_dir/SHA256SUMS-acquisition.txt"
      custody_log "Manifeste d'intégrité de l'acquisition brute -> SHA256SUMS-acquisition.txt"
      chmod -R a-w "$backup_dir" 2>/dev/null
      custody_log "Acquisition brute passée en lecture seule (chmod a-w)"

      ANALYSIS_INPUT="$backup_dir"; ANALYSIS_TYPE="backup"
      if [ -n "$IOS_PASSWORD" ]; then
        log_info "Déchiffrement de la backup..."
        MVT_IOS_BACKUP_PASSWORD="$IOS_PASSWORD" \
          mvt-ios decrypt-backup -d "$case_dir/decrypted" "$backup_dir" \
          || log_warn "Échec du déchiffrement — l'analyse portera sur la backup brute."
        if [ -d "$case_dir/decrypted" ]; then
          ANALYSIS_INPUT="$(resolve_backup_dir "$case_dir/decrypted")"
          custody_log "Backup déchiffrée -> $ANALYSIS_INPUT (copie de travail)"
        fi
      fi
      fn_device="$ANALYSIS_INPUT"

    else
      # --------- Android (AndroidQF) ---------
      have adb || die "adb manquant. Lancez : ./install.sh"
      [ -x "$ANDROIDQF_BIN" ] || die "AndroidQF manquant (tools/androidqf). Lancez : ./install.sh"
      wait_for_device android || { rm -rf "$case_dir" "$results"; return 1; }
      local_labels=(); for line in "${ANDROID_DEVICES[@]}"; do
        IFS='|' read -r s d m v <<< "$line"
        local_labels+=("$d $m — $v — $s")
      done
      idx="$(choose_label "${local_labels[@]}")"
      ANDROID_SERIAL="${ANDROID_SERIALS[$((idx-1))]}"
      IFS='|' read -r ANDROID_SERIAL ANDROID_MAKER ANDROID_MODEL ANDROID_REL <<< "${ANDROID_DEVICES[$((idx-1))]}"
      log_info "Appareil sélectionné : $ANDROID_MAKER $ANDROID_MODEL, $ANDROID_REL — serial $ANDROID_SERIAL"
      custody_log "Appareil sélectionné : $ANDROID_MAKER $ANDROID_MODEL $ANDROID_REL — serial $ANDROID_SERIAL"

      # --- Dossier d'affaire : CASE-<date>-<IMEI> si IMEI lisible (sinon date seule) ---
      # Parité iOS (preuve légale : identifiant matériel pérenne dans le nom du dossier).
      ANDROID_IMEI="${ANDROID_IMEIS[$((idx-1))]:-}"
      if [ -n "$ANDROID_IMEI" ]; then
        local _android_case_new
        _android_case_new="$(get_case_id_with_imei "$ANDROID_IMEI")"
        custody_log "IMEI Android détecté : $ANDROID_IMEI"
        log_ok "IMEI Android détecté : $ANDROID_IMEI"
        if [ "$_android_case_new" != "$CASE_ID" ]; then
          local _case_dir_new
          _case_dir_new="$EVIDENCE_DIR/$_android_case_new"
          mv "$case_dir" "$_case_dir_new" 2>/dev/null || _case_dir_new="$case_dir"
          custody_log "Renommage du dossier d'affaire : $CASE_ID -> $_android_case_new (IMEI $ANDROID_IMEI)"
          case_dir="$_case_dir_new"
          CASE_ID="$_android_case_new"
          results="$REPORTS_DIR/$CASE_ID"
          mkdir -p "$results"
          CUSTODY_FILE="$case_dir/chain_of_custody.txt"
          AUDIT_FILE="$case_dir/audit.log"
        fi
      else
        ANDROID_IMEI="non disponible — dossier daté uniquement"
      fi
      log_info "Dossier d'affaire (preuve) : $case_dir"
      custody_log "Dossier de preuve : $case_dir"
      log_info "Dossier d'affaire (preuve) : $case_dir"
      custody_log "Dossier de preuve : $case_dir"

      # AndroidQF (v1.x) gère lui-même ses questions interactives : Backup
      # (SMS/Tout/Aucun), téléchargement des apps, Intrusion Logs. On ne passe
      # que -serial/-output : les flags d'automatisation (-backup, -download,
      # -non-interactive, ...) n'existent pas dans la release 1.8.3.
      # Le `cd` dans $case_dir fait écrire backup.ab sur le même filesystem
      # que -output (sinon rename => "invalid cross-device link").
      screen_clear
      banner "Démarrage d'AndroidQF (autorisez la connexion USB sur le téléphone puis répondez à ses questions : Backup, Apps, Intrusion Logs)..."
      confirm_consent_and_scope "Android" "$case_dir" \
        || { custody_log "Refus de consentement Android — acquisition annulée (loi Godfrain, aucun octet collecté)."; continue_or_back "Acquisition Android"; }
      ( cd "$case_dir" \
          && "$ANDROIDQF_BIN" -serial "$ANDROID_SERIAL" -output "$case_dir" \
              2> >(tee -a "$AUDIT_FILE" >&2) ) \
        || { quarantine_failed_acquisition "$case_dir" "Android"; die "Échec de l'analyse AndroidQF (voir audit.log) — capture partielle isolée en quarantaine."; }
      # AndroidQF rend son dossier de sortie lecture seule ; on rétablit l'écriture
      # sur nos propres journaux pour poursuivre la traçabilité (scellage en fin CAS).
      chmod u+w "$CUSTODY_FILE" "$AUDIT_FILE" 2>/dev/null || true
      custody_log "Analyse AndroidQF terminée -> $case_dir"
      # v1.8.3 écrit l'acquisition directement dans -output (backup.ab + modules).
      ANALYSIS_INPUT="$case_dir"
      ANALYSIS_TYPE="androidqf"
      hash_tree "$case_dir" "$case_dir/SHA256SUMS-acquisition.txt"
      custody_log "Manifeste d'intégrité de l'acquisition brute -> SHA256SUMS-acquisition.txt"
    fn_device="$case_dir"
    # --- Choix fléché post-acquisition AndroidQF : jamais d'analyse auto ---
    FAST="preserve"
    local _asi_label
    _asi_android="$(menu_select "Que faire après l'acquisition AndroidQF ?" \
      "Préservation + orientation (défaut — aucune analyse)" \
      "Analyse complète (MVT AndroidQF, IoCs, tous modules)")"
    case "$_asi_android" in
      *Préservation*) FAST="preserve"; _asi_label="préservation + orientation (aucune analyse)" ;;
      *complète*)    FAST="n";         _asi_label="complète (IoCs actifs)" ;;
    esac
    custody_log "Choix post-acquisition Android : $_asi_label (loi Godfrain — analyse uniquement si éligible)."
  fi

  else
    # ============ ANALYSE D'UNE ACQUISITION EXISTANTE ============
    path="$(pick_acquisition_path)"
    [ -n "$path" ] && [ -e "$path" ] || { die "Chemin introuvable : $path"; }
    path="$(readlink -f "$path")"
    ANALYSIS_INPUT="$path"

    hash_external "$path" "$case_dir/SHA256SUMS-acquisition.txt"
    [ -s "$case_dir/SHA256SUMS-acquisition.txt" ] \
      && custody_log "Manifeste d'intégrité de la source analysée -> SHA256SUMS-acquisition.txt (source non modifiée)"

    if [ "$platform" = "iOS" ]; then
      if [ -d "$path" ] && [ -e "$(resolve_backup_dir "$path")/Manifest.db" ]; then
        ANALYSIS_INPUT="$(resolve_backup_dir "$path")"; ANALYSIS_TYPE="backup"
      elif [ -d "$path" ] && { [ -e "$path/root" ] || [ -e "$path/ios_filesystem" ] || ls "$path"/*.ipsw >/dev/null 2>&1; }; then
        ANALYSIS_TYPE="fs"
      elif [ -f "$path" ] && [[ "$path" == *.zip || "$path" == *sysdiagnose* ]]; then
        ANALYSIS_TYPE="sysdiagnose"
      else
        ANALYSIS_TYPE="$(menu_select "Type d'analyse iOS ?" "Backup" "Dump du système de fichiers" "Sysdiagnose (archive)")"
        case "$ANALYSIS_TYPE" in Backup*) ANALYSIS_TYPE="backup";; Dump*) ANALYSIS_TYPE="fs";; *) ANALYSIS_TYPE="sysdiagnose";; esac
      fi
    else
      if [ -d "$path" ] && { [ -e "$path/acquisition.json" ] || [ -e "$path/command.log" ]; }; then
        ANALYSIS_TYPE="androidqf"
      elif [ -f "$path" ] && [[ "$path" == *.ab ]]; then
        ANALYSIS_TYPE="ab"
        if ask_yesno "Backup .ab chiffrée ?" "n"; then
          export MVT_ANDROID_BACKUP_PASSWORD="$(ask_input "Mot de passe de la backup Android :" "")"
        fi
      else
        ANALYSIS_TYPE="$(menu_select "Type d'analyse Android ?" "Acquisition AndroidQF (dossier)" "Backup (.ab / dossier)")"
        [ "${ANALYSIS_TYPE#Acquisition}" != "$ANALYSIS_TYPE" ] && ANALYSIS_TYPE="androidqf" || ANALYSIS_TYPE="ab"
      fi
    fi
    fn_device="$ANALYSIS_INPUT"
  fi

  # --- Options d'analyse ---
  FAST="n"
  local _ios_after _asi_label
  _ios_after="$(menu_select "Que faire après l'acquisition iOS ?" \
    "Préservation + orientation (défaut — aucune analyse)" \
    "Analyse rapide (MVT --fast)" \
    "Analyse complète (MVT, IoCs, tous modules)")"
  case "$_ios_after" in
    *Préservation*)
      FAST="preserve"
      _asi_label="préservation + orientation (analyse non lancée)"
      ;;
    *rapide*)  FAST="y";  _asi_label="rapide (--fast)" ;;
    *complète*) FAST="n"; _asi_label="complète (IoCs actifs)" ;;
  esac
  custody_log "Choix post-acquisition iOS : $_asi_label (loi Godfrain — analyse uniquement si éligible)."

  # --- Construction de la commande MVT ---
  if [ "$platform" = "iOS" ]; then
    case "$ANALYSIS_TYPE" in
      backup)      mvt_cmd=(mvt-ios check-backup) ;;
      fs)          mvt_cmd=(mvt-ios check-fs) ;;
      sysdiagnose) mvt_cmd=(mvt-ios check-sysdiagnose) ;;
      *)           log_warn "Type inconnu -> check-backup"; mvt_cmd=(mvt-ios check-backup) ;;
    esac
  else
    case "$ANALYSIS_TYPE" in
      androidqf) mvt_cmd=(mvt-android check-androidqf) ;;
      ab)        mvt_cmd=(mvt-android check-backup) ;;
      *)         mvt_cmd=(mvt-android check-androidqf) ;;
    esac
    if [ "${mvt_cmd[0]}" = "mvt-android" ] && [ "$ANALYSIS_TYPE" = "androidqf" ] \
       && [ "${ENABLE_VIRUSTOTAL:-no}" = "yes" ] && [ -n "${MVT_VT_API_KEY:-}" ]; then
      # Choix interactif à chaque analyse : la comparaison avec la base VirusTotal est longue
      if ask_yesno "Vérifier les APK non-système sur VirusTotal pour CETTE analyse ? (comparaison longue avec la base VT)" "n"; then
        export MVT_VT_API_KEY
        mvt_cmd+=(--virustotal)
        log_info "VirusTotal activé pour cette analyse (hash d'APK non-système)."
      else
        log_warn "VirusTotal ignoré pour cette analyse (comparaison VT longue non souhaitée)."
      fi
    fi
  fi
  # --fast n'est supporté que par mvt-ios check-backup/check-fs ;
  # mvt-android (check-androidqf/check-backup) et check-sysdiagnose le refusent
  [ "$FAST" = "y" ] && [ "$platform" = "iOS" ] && [ "$ANALYSIS_TYPE" != "sysdiagnose" ] && mvt_cmd+=(--fast)
  mvt_cmd+=(--output "$results")
  mvt_cmd+=("$ANALYSIS_INPUT")

  if [ "$FAST" = "preserve" ]; then
    custody_log "iOS — préservation : analyse NON lancée (préservation avant remédiation ; aucune remédiation à ce stade)."
    orientation_accompagnement iOS 2>/dev/null || true
  else
    run_mvt "${mvt_cmd[@]}" || log_err "Analyse MVT en échec (voir erreurs ci-dessus)."
    custody_log "Analyse MVT exécutée : ${mvt_cmd[*]}"
  fi

  # --- Rapport + finalisation des preuves ---
  DEVICE_INFO="$(device_info_from "$results" 2>/dev/null)"
  [ -z "$DEVICE_INFO" ] && DEVICE_INFO="$(device_info_from "$fn_device" 2>/dev/null)"
  DEVICE_INFO="${DEVICE_INFO:-modèle non détecté automatiquement}"
  log_info "Device : $DEVICE_INFO"

  make_report "$CASE_ID" "$results" "$platform" \
      "$(printf '%s' "$MVT_STIX2" | tr ':' '\n' | sed 's#^.*/##' | paste -sd ', ')" \
      "$case_dir" "$DEVICE_INFO" "$ANALYSIS_TYPE"

  # Source unique des résultats : reports/CASE-.../ (aucun doublon copié dans les preuves).
  # Le rapport et les JSON bruts ne sont plus dupliqués : l'analyse est déjà tracée et scellée
  # (SHA256SUMS + chain_of_custody + audit.log gérés dans reports/ et evidence/).
  log_info "Résultats d'analyse (source unique) : $results"

  # ---- Scellement du dossier de preuve ----
  # TOUT le contenu du dossier (dont chain_of_custody.txt) doit être écrit
  # AVANT la création du manifeste : plus rien ne doit y être ajouté ensuite.
  nb="$(find "$case_dir" -type f ! -name 'SHA256SUMS.txt' ! -name 'SHA256SUMS-acquisition.txt' 2>/dev/null | wc -l | tr -d ' ')"
  custody_log "Génération du manifeste SHA256 final (SHA256SUMS.txt) — $nb fichier(s)..."
  hash_tree "$case_dir" "$case_dir/SHA256SUMS.txt"
  if ( cd "$case_dir" && sha256sum -c SHA256SUMS.txt ) >/dev/null 2>&1; then
    log_ok "Intégrité des preuves vérifiée ($nb fichiers) : OK"
  else
    log_warn "Intégrité des preuves À CONTRÔLER (anomalie)."
  fi
  lock_dir "$case_dir"

  banner ''
  banner '=========================================='
  banner '  ANALYSE TERMINÉE'
  banner '=========================================='
  echo "  Preuves   : $case_dir   (lecture seule)"
  echo "  Rapport   : $results/rapport.txt"
  echo "  Traçabilité : $case_dir/chain_of_custody.txt"
  echo ""
  log_info "Détails dans les fichiers *_detected.json du rapport."
  echo ""
  return 0
}

# ============================================================
#  MENU PRINCIPAL
# ============================================================
main_menu() {
  local opt
  while :; do
    screen_clear
    ascii_banner "MVT WRAPPER" "=== MENU PRINCIPAL ==="
    opt="$(menu_select "Que souhaitez-vous faire ?" \
        "Lancer une analyse" \
        "Gérer les IoCs" \
        "Configuration" \
        "Vérifier les dépendances" \
        "Quitter")"
    echo ""
    case "${opt,,}" in
      *analyse*) screen_clear; cmd_analyse;       continue_or_back "Lancer une analyse" ;;
      *iocs*)    screen_clear; iocs_menu;         continue_or_back "Gérer les IoCs" ;;
      *config*)  screen_clear; config_menu;       continue_or_back "Configuration" ;;
      *dépend*)  screen_clear; install_shortcut;  continue_or_back "Vérifier les dépendances" ;;
      *) echo ""; log_ok "Au revoir."; return 0 ;;
    esac
  done
}

install_shortcut() {
  if [ -x "$SCRIPT_DIR/install.sh" ]; then
    if ask_yesno "Lancer install.sh (installe MVT, AndroidQF et les dépendances) ?" "y"; then
      "$SCRIPT_DIR/install.sh"
    fi
  else
    log_err "install.sh introuvable dans $SCRIPT_DIR."
  fi
}

# Ouvre l'analyse dans un terminal dédié (Konsole/WezTerm selon DEDICATED_TERMINAL).
dedicated_terminal() {
  local sub="${1:-analyse}"
  local term="${DEDICATED_TERMINAL:-auto}" run fp
  [ "$term" = "auto" ] && { have konsole && term=konsole; }
  [ "$term" = "auto" ] && { have wezterm && term=wezterm; }
  [ "$term" = "auto" ] && { have x-terminal-emulator && term=x-terminal-emulator; }
  fp="$SCRIPT_DIR/start.sh $sub"
  case "$term" in
    konsole) konsole --noclose -e bash -c "$fp; printf '\nAppuyez sur Entrée pour fermer...'; read" ;;
    wezterm) wezterm start -- bash -c "$fp; printf '\\nAppuyez sur Entrée pour fermer...'; read" ;;
    x-terminal-emulator) x-terminal-emulator -e bash -c "$fp" ;;
    *)
      if have konsole || have wezterm; then
        log_err "Aucun terminal compatible détecté (DEDICATED_TERMINAL=$term)."
      else
        log_err "DEDICATED_TERMINAL=$term : installez Konsole ou WezTerm, ou passez à 'auto'."
      fi
      return 1 ;;
  esac
}

# Purge des preuves : retire le scellement (tell +i / déchiffre AES) puis supprime.
# Avec argument : son regex CASE-XXX ; sinon : menu de sélection.
#   ./start.sh purge            -> menu de sélection des affaires
#   ./start.sh purge 20260911   -> purge l'affaire CASE-2026...-160330 (si elle existe)
cmd_purge() {
  local target="${1:-}" dir hdr enc
  local -a dirs=() choices=()
  for dir in "$EVIDENCE_DIR"/CASE-*; do
    [ -d "$dir" ] && dirs+=("$dir")
  done

  local d
  if [ -n "$target" ]; then
    local found=""
    for d in "${dirs[@]:-}"; do
      case "$(basename "$d")" in
        "$target"|*"$target"*) found="$d" ; break ;;
      esac
    done
    [ -z "$found" ] && { log_err "Aucune affaire ne correspond à '$target'."; return 1; }
    { unseal_and_delete "$found" && rm -rf -- "$found"; } || return 1
    return 0
  fi

  if [ "${#dirs[@]}" -eq 0 ]; then
    log_warn "Aucune affaire à purger dans $EVIDENCE_DIR."
    return 0
  fi
  screen_clear
  banner 'PURGE DES PREUVES'
  echo "Affaires trouvées :"
  declare -i i=0
  for d in "${dirs[@]:-}"; do
    i+=1
    local sealed="(claire)"
    [ -f "$d.aes" ] && sealed="(chiffré .aes)"
    if lsattr -d "$d" 2>/dev/null | grep -q '\bi\b'; then sealed="(verrouillé +i)"; fi
    printf '  %2d) %s  %s\n' "$i" "$(basename "$d")" "$sealed"
  done
  local sel
  sel="$(ask_input "Numéro de l'affaire à purger (defaut: aucune) : " "")"
  if [ -n "$sel" ] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#dirs[@]}" ]; then
    d="${dirs[$((sel-1))]}"
    log_warn "PURGE destrcutive : suppression définitive de $(basename "$d")"
    if ask_yesno "Confirmer la suppression définitive des preuves ?" "n"; then
      { unseal_and_delete "$d" && rm -rf -- "$d"; } && log_ok "Preuves purgées : $d" || log_err "Purge refusée."
    else
      log_warn "Purge annulée."
    fi
  fi
  return 0
}

# ============================================================
#  LANCEMENT
# ============================================================
SUB="${1:-}"
[ $# -gt 0 ] && shift
rc=0
case "$SUB" in
  ""|menu)            main_menu ;;
  analyse|analyze)    cmd_analyse "$@" || rc=1 ;;
  iocs)               iocs_menu ;;
  update-iocs|update) cmd_update ;;
  add)                cmd_add "${1:-}" || rc=1 ;;
  add-repo)           cmd_add_repo "${1:-}" || rc=1 ;;
  list-iocs|list)     cmd_list ;;
  env-iocs|env)       cmd_env ;;
  config)             config_menu ;;
  install)            install_shortcut ;;
  terminal|--dedicated) dedicated_terminal "${1:-analyse}" ;;
  purge)                cmd_purge "$@" || rc=1 ;;
  -h|--help|help)     usage ;;
  *) log_err "Sous-commande inconnue : $SUB" ; usage ; exit 1 ;;
esac
exit $rc
