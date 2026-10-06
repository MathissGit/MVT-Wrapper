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

# Version locale de MVT
mvt_version_local() {
  local v=""
  if have mvt; then
    v="$(mvt version 2>/dev/null | grep -i '^mvt' | awk '{print $2}' | head -n 1)"
  fi
  if [ -n "$v" ]; then
    printf '%s' "$v"
  else
    return 1
  fi
}

# ------------------------------------------------------------------
# Versions de l'outil et de ses composants (traçabilité + rapport).
#   $1 = composant (wrapper|mvt|mvt-ios|mvt-android|androidqf|adb|idevicebackup2)
#   Sortie : numéro de version, ou "n/a".
# ------------------------------------------------------------------
tool_version_of() {
  local name="$1" v=""
  case "$name" in
    wrapper)        v="${VERSION:-n/a}" ;;
    mvt)            v="$(mvt_version_local 2>/dev/null || true)" ;;
    mvt-ios)        have mvt-ios && v="$("$(command -v mvt-ios)" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)" ;;
    mvt-android)    have mvt-android && v="$("$(command -v mvt-android)" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)" ;;
    androidqf)      [ -x "${ANDROIDQF_BIN:-}" ] && v="$("$ANDROIDQF_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)" ;;
    adb)            have adb && v="$("$(command -v adb)" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)" ;;
    idevicebackup2) have idevicebackup2 && v="$("$(command -v idevicebackup2)" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)" ;;
    *)              v="n/a" ;;
  esac
  printf '%s' "${v:-n/a}"
}

# Ligne récapitulative des versions wrapper + composants (une seule string).
tool_versions() {
  local parts=() c
  for c in wrapper mvt mvt-ios mvt-android androidqf adb idevicebackup2; do
    parts+=("$c $(tool_version_of "$c")")
  done
  printf '%s' "${parts[*]}"
}

# ------------------------------------------------------------------
# Signature de la base d'indicateurs utilisée : nombre + fichiers,
# commits des dépôts managed, dernière mise à jour.
# ------------------------------------------------------------------
ioc_base_signature() {
  local f total=0 list=() names="" d latest="" repo h cd
  while IFS= read -r f; do
    total=$((total + 1))
    d="$(stat -c '%y' "$f" 2>/dev/null | cut -d. -f1)"
    if [ -n "$d" ] && [ "$d" \> "${latest:-}" ]; then latest="$d"; fi
    list+=("$(basename "$f")")
  done < <(find_ioc_files)
  if [ "$total" -eq 0 ]; then
    printf 'aucun fichier personnalisé (IoCs officiels MVT utilisés le cas échéant)'
    return 0
  fi
  for f in "${list[@]:0:8}"; do names="${names}${names:+, }$f"; done
  [ "${#list[@]}" -gt 8 ] && names="$names, ..."
  printf '%d fichier(s) : %s — dernière mise à jour %s' "$total" "$names" "${latest:-n/a}"
  for repo in "$IOCS_MANAGED_DIR"/*/; do
    [ -d "$repo/.git" ] || continue
    h="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo n/a)"
    cd="$(git -C "$repo" log -1 --format=%cs 2>/dev/null || true)"
    printf ' ; %s@%s (%s)' "$(basename "$repo")" "$h" "$cd"
  done
  return 0
}

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
# Fenêtre de sélection de DOSSIER (zenity / kdialog), avec repli en
# saisie manuelle. Même approche que pick_acquisition_path, mais
# --directory : on ne peut choisir qu'un dossier, pas un fichier.
# Le dossier de départ est proposé ; rien n'est créé ni modifié ici.
# ------------------------------------------------------------------
pick_directory_gui() {
  local title="$1" start="${2:-$PWD}" got=""
  [ -d "$start" ] || start="$PWD"
  if command -v zenity >/dev/null 2>&1; then
    got="$(zenity --file-selection --directory --confirm-overwrite \
            --title="$title" --filename="$start/" 2>/dev/null || true)"
  elif command -v kdialog >/dev/null 2>&1; then
    got="$(kdialog --getexistingdirectory "$start" 2>/dev/null || true)"
  fi
  printf '%s' "$got"
}

# Un chemin donné peut-il être un volume "amovible" (/media, /run/media,
# /mnt) ? Sert à proposer ces emplacements comme candidats usuels.
seal_is_removable_spot() {
  case "$1" in
    /media|/media/*|/run/media|/run/media/*|/mnt|/mnt/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Volumes réellement montés et inscriptibles : les emplacements classiques
# d'un disque externe, pour l'utilisateur réel (le wrapper tourne souvent
# en sudo, donc $USER vaut root alors que les disques appartiennent à
# l'analyste). Ne liste QUE des points de montage avérés, sinon on
# remonterait tous les ~/Documents, ~/Images... comme de fausses pistes.
seal_mounted_candidates() {
  local u base d
  u="${SUDO_USER:-$USER}"
  for base in "/media/$u" "/run/media/$u"; do
    [ -d "$base" ] || continue
    for d in "$base"/*; do
      [ -d "$d" ] || continue
      mountpoint -q "$d" 2>/dev/null || continue
      [ -w "$d" ] || continue
      printf '%s\n' "$d"
    done
  done
}

# Choix d'un dossier. La FENÊTRE GUI n'est ouverte qu'à la demande
# ("Ouvrir le gestionnaire de fichiers") : ouvrir une fenêtre qui popup
# en plein écran à l'entrée dans une option de menu est agressif, et
# l'utilisateur ne peut alors plus corriger sa saisie au clavier.
# $1 = titre  $2 = dossier de départ  $3.. = candidats supplémentaires
# Imprime le chemin choisi ; vide si annulé.
pick_directory() {
  local title="$1" start="${2:-$PWD}" chosen="" c u dup n
  shift 2 2>/dev/null || shift $#
  local -a extra=("$@") uniq=() opts=()

  # Candidats sans doublon : dossier de départ, extras, volumes montés.
  for c in "$start" ${extra[@]+"${extra[@]}"}; do
    [ -n "$c" ] || continue
    dup=0
    for u in ${uniq[@]+"${uniq[@]}"}; do [ "$u" = "$c" ] && { dup=1; break; }; done
    [ "$dup" -eq 0 ] && uniq+=("$c")
  done
  if [ -t 0 ]; then
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      dup=0
      for u in ${uniq[@]+"${uniq[@]}"}; do [ "$u" = "$c" ] && { dup=1; break; }; done
      [ "$dup" -eq 0 ] && uniq+=("$c")
    done < <(seal_mounted_candidates)
  fi

  # Menu fléché si le terminal le permet, sinon saisie directe.
  if [ -t 0 ] && [ "${#uniq[@]}" -gt 1 ]; then
    for c in "${uniq[@]}"; do
      if [ -d "$c" ]; then
        opts+=("$c  [$(seal_human_bytes "$(seal_avail_bytes "$c")") libres]")
      else
        opts+=("$c  (à créer)")
      fi
    done
    opts+=("Ouvrir le gestionnaire de fichiers…")
    opts+=("Saisie manuelle du chemin")
    opts+=("Revenir au défaut (à côté du dossier de preuve)")

    # menu_select_idx renvoie un index 1-based ; on raisonne donc en 1-based.
    local n_cand="${#uniq[@]}" pick_gui pick_manu pick_def i
    pick_gui=$(( n_cand + 1 ))
    pick_manu=$(( n_cand + 2 ))
    pick_def=$(( n_cand + 3 ))

    chosen="$(menu_select_idx "$title" "${opts[@]}")"
    case "$chosen" in
      "$pick_gui")
        chosen="$(pick_directory_gui "$title" "$start")"
        if [ -z "$chosen" ]; then
          log_info "Fenêtre de sélection fermée - rien n'est changé."
          printf '%s' ""
          return 0
        fi
        ;;
      "$pick_manu")
        chosen="$(ask_input "$title (chemin du dossier) :" "$start")"
        ;;
      "$pick_def")
        printf '%s' "-"
        return 0
        ;;
      *)
        # Libellé choisi : le chemin réel est le candidat correspondant
        # (le libellé affiché est suffixé par l'espace libre).
        i=$(( chosen - 1 ))
        if [ "$i" -ge 0 ] && [ "$i" -lt "$n_cand" ]; then
          chosen="${uniq[$i]}"
        else
          chosen=""
        fi
        ;;
    esac
  else
    # Repli non interactif : on propose les candidats puis la saisie.
    if [ "${#uniq[@]}" -gt 1 ]; then
      local line="" n
      for c in "${uniq[@]}"; do
        if [ -d "$c" ]; then
          line="$line$c  [$(seal_human_bytes "$(seal_avail_bytes "$c")") libres]
"
        else
          line="$line$c  (à créer)
"
        fi
      done
      printf '%s' "$line" >&2
    fi
    chosen="$(ask_input "$title (chemin du dossier) :" "$start")"
  fi
  printf '%s' "$chosen"
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
  local opts=("$@")
  local total="${#opts[@]}" sel=0 key seq i

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

# Valeur booléenne d'une clé dans un plist (binaire ou XML) via python3/plistlib.
# Sortie : yes | no | unknown.
plist_key_bool() {
  local file="$1" key="$2"
  python3 - "$file" "$key" <<'PY'
import plistlib, sys
try:
    with open(sys.argv[1], "rb") as fh:
        d = plistlib.load(fh)
    v = d.get(sys.argv[2])
    if v is True:
        print("yes")
    elif v is False:
        print("no")
    else:
        print("unknown")
except Exception:
    print("unknown")
PY
}

# Journalisation (chaîne de traçabilité / audit) : écrit une ligne
# horodatée dans les fichiers définis par CUSTODY_FILE et AUDIT_FILE.
custody_log() {
  [ -n "${CUSTODY_FILE:-}" ] && printf '%s | %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$CUSTODY_FILE"
}
audit_log() {
  [ -n "${AUDIT_FILE:-}" ] && printf '%s | %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$AUDIT_FILE"
}

# Indicateur d'activité : spinner + chrono (secondes) pendant une commande
# longue sans retour visuel (backup iTunes, déchiffrement, modules MVT…).
# Le flux de la commande est redirigé vers $2 (fichier log) pour ne pas
# mélanger spinner et sortie ; à la fin, l'appelant peut afficher le tail.
#   $1 = libellé   $2 = log ('' = /dev/null)   ... = commande
# Retourne le code de sortie de la commande.
run_with_progress() {
  local label="$1" log="$2" pid rc t0 i chars
  shift 2
  if [ "${CI:-}" = "true" ] || [ ! -t 1 ] || [ -z "${TERM:-}" ]; then
    if [ -n "$log" ]; then
      "$@" >"$log" 2>&1
    else
      "$@" >/dev/null 2>&1
    fi
    return $?
  fi
  if [ -n "$log" ]; then
    "$@" >"$log" 2>&1 &
  else
    "$@" >/dev/null 2>&1 &
  fi
  pid=$!
  chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  t0=$(date +%s)
  i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  %s %s  %ds   ' "${chars:$((i%10)):1}" "$label" "$(( $(date +%s) - t0 ))"
    sleep 0.25
    i=$((i+1))
  done
  wait "$pid"
  rc=$?
  printf '\r%80s\r' ''
  return "$rc"
}

# ------------------------------------------------------------------
# Intégrité des preuves (non-altération et juridique)
# ------------------------------------------------------------------

# Manifeste sha256 de tous les fichiers d'un dossier (chemins relatifs)
hash_tree() {
  local dir="$1" out="$2" pwd_save
  pwd_save="$(pwd)"
  cd "$dir" || return 1
  printf 'Manifeste SHA256 généré le %s par %s' \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "${ANALYST:-$(whoami)}" > "$out"
  find . -type f \
        ! -name 'SHA256SUMS.txt' ! -name 'SHA256SUMS-acquisition.txt' \
        ! -name 'rapport.txt' ! -name 'rapport.pdf' -print0 2>/dev/null \
    | LC_ALL=C sort -z \
    | xargs -0 -r -P "$(nproc 2>/dev/null || echo 4)" sha256sum \
    | sed -E 's#^([0-9a-f]{64}  )\./#\1#' \
    | LC_ALL=C sort -k2 >> "$out"
  cd "$pwd_save" || true
}

# Vérification d'un manifeste SHA256 en parallèle
verify_manifest() {
  local dir="$1" manifest="${2:-SHA256SUMS.txt}" cores tmp rc pwd_save
  cores="$(nproc 2>/dev/null || echo 4)"
  tmp="$(mktemp -d)"
  pwd_save="$(pwd)"
  cd "$dir" || { rm -rf "$tmp"; return 1; }
  grep -v '^#' "$manifest" 2>/dev/null \
    | awk -v n="$cores" -v t="$tmp" '{ f = sprintf("%s/chunk.%02d", t, NR % n); print > f }'
  mapfile -t chunks < <(find "$tmp" -type f)
  # shellcheck disable=SC2016
  printf '%s\0' "${chunks[@]}" | xargs -0 -r -P "$cores" -n1 sh -c 'sha256sum -c "$1" >/dev/null 2>&1' sh
  rc=$?
  rm -rf "$tmp"
  cd "$pwd_save" || true
  [ "$rc" -eq 0 ]
}

# Passage en lecture seule (chmod a-w, et chattr +i si root) -- ancienne méthode.
# Depuis 1.4 : SEAL_METHOD pilote le scellement ; "encrypt" (défaut) ne verrouille
# plus rien (dossier supprimable). "lock" conserve l'ancien comportement.
lock_dir() {
  local dir="$1"
  case "${SEAL_METHOD:-encrypt}" in
    encrypt)
      seal_encrypted "$dir"
      ;;
    lock)
      if [ "${LOCK_EVIDENCE:-yes}" = "no" ]; then
        log_warn "Verrouillage des preuves désactivé - dossier modifiable."
        return 0
      fi
      chmod -R a-w "$dir" 2>/dev/null
      if [ "$(id -u)" = 0 ]; then
        chattr -R +i "$dir" 2>/dev/null
        log_ok "Preuves verrouillées en lecture seule (chattr +i): $dir"
      else
        log_ok "Preuves verrouillées en lecture seule (chmod a-w): $dir"
      fi
      ;;
    no|off)
      log_warn "Scellement des preuves désactivé - dossier modifiable."
      ;;
    *)
      log_warn "SEAL_METHOD inconnue ('$SEAL_METHOD') - aucun scellement."
      ;;
  esac
}

# ---- Scellement par CHIFFREMENT (AES-256, mot de passe) + suppression du clair ----
# Preuves inaltérables (chiffrées) MAIS dossier restant supprimable : c'est le
# comportement demandé ("sceller sans bloquer la suppression").

# Taille totale (octets) du dossier à sceller.
seal_needed_bytes() {
  du -sb "$1" 2>/dev/null | awk '{print $1}'
}

# Espace libre (octets) sur le FS qui PORTERA l'archive chiffrée.
seal_avail_bytes() {
  local target="$1"
  while [ -n "$target" ] && [ ! -d "$target" ]; do target="$(dirname "$target")"; done
  df -B1 --output=avail "${target:-/}" 2>/dev/null | tail -1 | tr -dc '0-9'
}

# Le plus gros fichier (octets) : plancher d'espace du mode flux.
seal_biggest_file_bytes() {
  find "$1" -type f -printf '%s\n' 2>/dev/null | sort -rn | head -1
}

# Formate un nombre d'octets pour l'affichage (ex. 33G). Repli sur l'octet.
seal_human_bytes() {
  local b="${1:-0}"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$b" 2>/dev/null && return 0
  fi
  printf '%s octets' "$b"
}

# Etiquette lisible d'un volume : "ext4, 9.1GB libres". Sert à rappeler sur
# QUEL disque l'archive va réellement atterrir.
seal_volume_label() {
  local p="$1" fs avail
  while [ -n "$p" ] && [ ! -d "$p" ]; do p="$(dirname "$p")"; done
  fs="$(df -PT "$p" 2>/dev/null | awk 'NR==2 {print $2}')"
  avail="$(seal_avail_bytes "$p")"
  printf '%s, %s libres' "${fs:-?}" "$(seal_human_bytes "${avail:-0}")"
}

# ------------------------------------------------------------------
# Validation d'une destination de scellement. N'écrit RIEN : renvoie
# seulement un verdict, l'appelant décide (c'est lui qui affiche et
# qui demande confirmation avant toute création).
#   0 = chemin utilisable (dossier existant, inscriptible)
#   1 = chemin absent (peut être créé)
#   2 = chemin inutilisable (fichier, non-inscriptible, disque non monté)
# Le motif est renvoyé sur stdout.
# ------------------------------------------------------------------

# Expansion du ~ de début, SANS eval (une saisie utilisateur ne doit
# jamais être réinterprétée comme du shell). Sans cela, `mkdir -p "~/X"`
# créait un dossier littéralement nommé "~".
seal_expand_tilde() {
  local p="$1"
  case "$p" in
    "~")    printf '%s' "$HOME" ;;
    "~/"*)  printf '%s/%s' "${HOME%/}" "${p#\~/}" ;;
    *)      printf '%s' "$p" ;;
  esac
}

# Le chemin est-il sous un point de montage "amovible" (/media, /run/media,
# /mnt) dont le volume attendu n'est PAS monté ? Dans ce cas un `mkdir -p`
# créerait le dossier sur le disque INTERNE : l'archive atterrirait au
# mauvais endroit, en silence. C'est le piège classique du disque
# débranché au moment du scellement.
seal_unmounted_risk() {
  local p="$1" q mount prev
  # Un chemin relatif (ou contenant ".") ne peut jamais être sous /media :
  # on le ramène d'abord en absolu, sinon dirname(".") boucle indéfiniment.
  case "$p" in
    /*) ;;
    *)  p="$PWD/$p" ;;
  esac
  while [ "$p" != "/" ] && [ -n "$p" ]; do
    case "$p" in
      /media/*|/run/media/*|/mnt/*)
        # Cherche le point de montage le plus proche en remontant.
        q="$p"; mount=""
        while [ "$q" != "/" ] && [ -n "$q" ]; do
          if mountpoint -q "$q" 2>/dev/null; then mount="$q"; break; fi
          prev="$q"; q="$(dirname "$q")"
          [ "$q" = "$prev" ] && break
        done
        # /media/<user> est un simple dossier sur la racine : ce ne sont
        # que ses sous-dossiers (les disques montés) qui sont des points
        # de montage. Sans volume monté plus bas, le chemin est fantôme.
        [ -z "$mount" ] && return 0
        return 1
        ;;
    esac
    prev="$p"; p="$(dirname "$p")"
    [ "$p" = "$prev" ] && break
  done
  return 1
}

seal_validate_dest() {
  local raw="$1" path probe parent
  path="$(seal_expand_tilde "$raw")"

  if [ -z "$path" ]; then
    printf 'chemin vide'; return 2
  fi

  # Un chemin relatif est ambigu : il dépendrait du répertoire courant au
  # moment du scellement, qui n'est pas forcément le même. On exige un
  # chemin absolu plutôt que de créer un dossier au hasard.
  case "$path" in
    /*) ;;
    *)  printf '%s n'"'"'est pas un chemin absolu (ex. /media/ryuu/SAUVEGARDES)' "$path"
        return 2 ;;
  esac

  if [ -e "$path" ]; then
    if [ ! -d "$path" ]; then
      printf '%s existe mais n'"'"'est pas un dossier' "$path"; return 2
    fi
    if [ ! -w "$path" ]; then
      printf '%s n'"'"'est pas accessible en écriture' "$path"; return 2
    fi
    # [ -w ] peut mentir sur un volume monté en lecture seule : on teste
    # pour de vrai en créant puis supprimant un fichier.
    probe="$path/.mvt_seal_test_$$"
    if ! ( : > "$probe" ) 2>/dev/null; then
      printf '%s refuse l'"'"'écriture (volume monté en lecture seule ?)' "$path"; return 2
    fi
    rm -f "$probe" 2>/dev/null
    printf '%s' "$path"; return 0
  fi

  # Absent : vérifie d'abord qu'on ne va pas créer un dossier fantôme sur
  # le disque interne parce qu'un disque externe serait débranché.
  if seal_unmounted_risk "$path"; then
    printf '%s est sous un point de montage non monté : le dossier serait créé sur le disque interne. Montez le disque puis réessayez.' "$path"
    return 2
  fi

  # Le parent doit exister et être inscriptible, sinon mkdir échouera.
  parent="$(dirname "$path")"
  if [ ! -d "$parent" ]; then
    printf 'le dossier parent %s n'"'"'existe pas' "$parent"; return 2
  fi
  if [ ! -w "$parent" ]; then
    printf 'le dossier parent %s n'"'"'est pas accessible en écriture' "$parent"; return 2
  fi
  printf '%s' "$path"; return 1
}

# Destination de l'archive chiffrée. SEAL_DEST (config) prime ; sinon à côté
# du dossier de preuve. modes: dir | archive | stream
seal_dest_path() {
  local dir="$1" mode="$2" base="${SEAL_DEST:-}"
  [ -n "$base" ] || base="$(dirname "$dir")"
  case "$mode" in
    archive) printf '%s/%s.aes256.tar.gz' "$base" "$(basename "$dir")" ;;
    stream)  printf '%s/%s.aes256.d'      "$base" "$(basename "$dir")" ;;
    *)       printf '%s' "$base" ;;
  esac
}

# Trace un échec de scellement : l'anomalie doit être visible dans la chaîne
# de traçabilité, pas seulement sur stderr (l'écran est perdu, le journal reste).
seal_incident() {
  log_err "$*"
  custody_log "INCIDENT : $*"
  audit_log "SCELLEMENT : $*"
}

# Saisie du mot de passe (2 fois). Refuse le non-TTY explicitement au lieu de
# d'échouer en silence sur un read qui renvoie EOF.
seal_read_password() {
  local pw1 pw2
  if [ ! -t 0 ]; then
    log_err "Scellement impossible : aucun terminal (stdin non interactif) pour saisir le mot de passe."
    return 1
  fi
  printf 'Mot de passe de scellement AES-256 (≥ 8 caractères) : ' >&2
  IFS= read -r -s pw1 || { echo >&2; log_err "Saisie du mot de passe interrompue - scellement annulé."; return 1; }
  echo >&2
  printf 'Confirmez le mot de passe : ' >&2
  IFS= read -r -s pw2 || { echo >&2; log_err "Saisie de la confirmation interrompue - scellement annulé."; return 1; }
  echo >&2
  if [ -z "$pw1" ]; then
    log_err "Mot de passe vide - scellement annulé."
    return 1
  fi
  if [ "$pw1" != "$pw2" ]; then
    log_err "Les deux mots de passe diffèrent - scellement annulé."
    return 1
  fi
  if [ "${#pw1}" -lt 8 ]; then
    log_err "Mot de passe trop court (${#pw1} caractères, 8 minimum) - scellement annulé."
    return 1
  fi
  printf '%s' "$pw1"
}

seal_encrypted() {
  local dir="$1" enc streamdir pw nb need avail biggest mode seal_log destdir vwhy
local vrc=0
  [ -d "$dir" ] || return 0
  nb="$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')"
  need="$(seal_needed_bytes "$dir")"; need="${need:-0}"
  biggest="$(seal_biggest_file_bytes "$dir")"; biggest="${biggest:-0}"
  custody_log "Scellement par chiffrement du dossier de preuve $dir ($nb fichier(s), $need octets)..."

  # --- Destination : elle doit exister et être inscriptible AVANT tout.
  # Sans cette vérification, un SEAL_DEST supprimé du disque depuis la
  # config produisait un échec openssl obscur du type "Can't open ... for
  # writing" alors que la version claire était intacte.
  local destdir vwhy vrc
  destdir="$(seal_dest_path "$dir" dir)"
  vwhy="$(seal_validate_dest "$destdir")" || vrc=$?
  if [ "$vrc" = 1 ]; then
    mkdir -p "$vwhy" 2>/dev/null || {
      seal_incident "Destination de scellement absente et création impossible : $vwhy. \
Version claire CONSERVÉE."
      return 1
    }
    destdir="$vwhy"
  elif [ "$vrc" != 0 ]; then
    seal_incident "Destination de scellement inutilisable : $vwhy. \
Version claire CONSERVÉE : $dir"
    return 1
  fi

  # --- Choix du mode selon l'espace disponible sur la destination ---
  # Archive = 1x la taille (écriture du dossier, pic 2x avec le clair restant).
  # Flux    = 1 fichier à la fois (pic = le plus gros fichier), mais produit un
  #           dossier chiffré arborescent plutôt qu'une archive unique.
  avail="$(seal_avail_bytes "$(seal_dest_path "$dir" dir)")"
  mode="stream"
  if [ "$avail" -gt $(( need + need / 10 )) ]; then
    mode="archive"
  fi

  if [ "$mode" = "stream" ] && [ "$avail" -lt $(( biggest + biggest / 10 + 16 * 1024 * 1024 )) ]; then
    seal_incident "Scellement impossible : espace insuffisant sur la destination \
($(seal_human_bytes "$avail") libres pour un dossier de $(seal_human_bytes "$need")). \
Libérez de l'espace ou renseignez la destination dans './start.sh config' \
(« Destination de l'archive chiffrée ») pour viser un autre disque. \
Version claire CONSERVÉE."
    return 1
  fi

  if [ "$mode" = "stream" ]; then
    log_warn "Espace insuffisant pour une archive unique ($(seal_human_bytes "$avail") libres \
pour $(seal_human_bytes "$need")) : chiffrement en mode flux (un fichier à la fois, \
pic $(seal_human_bytes "$biggest"))."
    log_info "Archive en flux : le dossier chiffré sera un répertoire (pas une archive .tar.gz)."
  else
    log_info "Archive unique prévue ($(seal_human_bytes "$need"), $(seal_human_bytes "$avail") \
disponibles sur la destination)."
  fi

  # Les invites vont sur stderr, le mot de passe revient sur stdout.
  pw="$(seal_read_password)" || return 1
  [ -n "$pw" ] || { seal_incident "Mot de passe non obtenu - scellement annulé. Version claire CONSERVÉE."; return 1; }

  seal_log="$(mktemp)"
  enc="$(seal_dest_path "$dir" archive)"
  streamdir="$(seal_dest_path "$dir" stream)"

  if [ "$mode" = "archive" ]; then
    log_info "Chiffrement AES-256 en cours ($dir -> $enc)..."
    # pipefail : un échec de tar NE DOIT PAS être masqué par le statut d'openssl
    # (sinon archive tronquée considérée comme valide).
    if ! ( set -o pipefail
           tar cf - -C "$(dirname "$dir")" "$(basename "$dir")" 2>>"$seal_log" \
         | gzip -1 2>>"$seal_log" \
         | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
               -pass "pass:$pw" -out "$enc" 2>>"$seal_log" ); then
      [ -s "$seal_log" ] && { log_err "Détails :"; tail -n 5 "$seal_log" >&2; }
      seal_incident "Échec du chiffrement (espace disque ?). Version claire CONSERVÉE : $dir"
      rm -f "$enc"
      rm -f "$seal_log"
      return 1
    fi
    if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass "pass:$pw" \
           -in "$enc" 2>>"$seal_log" | gzip -dc 2>>"$seal_log" | tar tf - >/dev/null 2>>"$seal_log"; then
      seal_incident "Échec de la VÉRIFICATION du déchiffrement. Version claire CONSERVÉE, \
archive supprimée : $enc"
      rm -f "$enc"
      rm -f "$seal_log"
      return 1
    fi
    local h; h="$(sha256sum "$enc" | awk '{print $1}')"
    rm -f "$seal_log"
    custody_log "Preuves scellées par chiffrement : $enc (SHA256 $h) ; clair supprimé."
    log_ok "Preuves chiffrées et vérifiées : $enc (SHA256 $h)"
    find "$dir" -type f -exec shred -u -z -n 1 {} \; 2>/dev/null
    rm -rf "$dir" 2>/dev/null
    log_ok "Version claire supprimée : $dir (preuves supprimables si besoin)."
    SEAL_RESULT="$enc"
    return 0
  fi

# ---- Mode flux : chaque fichier est chiffré, VÉRIFIÉ, puis son clair est
  # détruit immédiatement. Le pic d'espace additionnel se limite donc au plus
  # gros fichier, pas à la taille totale. La vérification est faite avant le
  # shred : aucune donnée n'est détruite sans avoir été relue et validée.
  log_info "Chiffrement AES-256 en mode flux ($dir -> $streamdir)..."
  if [ -e "$streamdir" ] && [ -n "$(ls -A "$streamdir" 2>/dev/null)" ]; then
    # On ne détruit JAMAIS un dossier chiffré existant : il peut être le seul
    # reste d'un scellement interrompu (voir le bloc d'échec plus bas).
    seal_incident "Le dossier chiffré $streamdir existe déjà et n'est pas vide. \
Refus d'écraser des preuves chiffrées. Traitement annulé, version claire conservée."
    rm -f "$seal_log"; return 1
  fi
  rm -rf "$streamdir"
  mkdir -p "$streamdir" || {
    seal_incident "Impossible de créer le dossier chiffré $streamdir. Version claire CONSERVÉE."
    rm -f "$seal_log"; return 1
  }
  local f rel dest want got ok=1 n=0
  local manifest="$streamdir/MANIFESTE.seal"
  printf '# MVT-WRAPPER — manifeste de scellement (mode flux)\n' > "$manifest" || {
    seal_incident "Écriture du manifeste de scellement impossible. Version claire CONSERVÉE."
    rm -rf "$streamdir" 2>/dev/null; rm -f "$seal_log"; return 1
  }
  while IFS= read -r -d '' f; do
    rel="${f#"$dir"/}"
    dest="$streamdir/$rel"
    mkdir -p "$(dirname "$dest")" || { ok=0; break; }
    # 1. Empreinte de l'original AVANT tout.
    want="$(sha256sum "$f" 2>/dev/null | awk '{print $1}')"
    [ -n "$want" ] || { seal_incident "Empreinte SHA256 impossible sur $rel. Ce fichier reste en clair dans $dir."; ok=0; break; }
    # 2. Chiffrement.
    if ! openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
           -pass "pass:$pw" -in "$f" -out "$dest" 2>>"$seal_log"; then
      seal_incident "Échec du chiffrement de $rel. Ce fichier reste en clair dans $dir."
      ok=0; break
    fi
    # 3. Relecture du chiffré : l'original est-il restitué à l'identique ?
    got="$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass "pass:$pw" \
            -in "$dest" 2>>"$seal_log" | sha256sum | awk '{print $1}')"
    if [ -z "$got" ] || [ "$got" != "$want" ]; then
      seal_incident "Échec de la VÉRIFICATION du déchiffrement de $rel. \
Le dossier chiffré est CONSERVÉ : $streamdir"
      rm -f "$dest" 2>/dev/null
      ok=0; break
    fi
    # 4. Vérifié : on peut détruire le clair et le consigner au manifeste.
    printf '%s  ./%s\n' "$want" "$rel" >> "$manifest"
    shred -u -z -n 1 "$f" 2>/dev/null
    n=$(( n + 1 ))
    if [ $(( n % 200 )) -eq 0 ]; then
      printf '\r  Chiffrement vérifié : %s fichiers...' "$n" >&2
    fi
  done < <(find "$dir" -type f -print0 2>/dev/null)
  printf '\r%60s\r' '' >&2

  # ÉCHEC APRÈS CHIFFREMENT : on NE SUPPRIME PAS $streamdir. Les fichiers
  # déjà chiffrés + vérifiés ont eu leur clair shredé : c'est désormais la
  # SEULE copie restante. Le rm -rf d'origine détruisait les preuves, et le
  # message annonçait à tort « version claire conservée » alors que les
  # fichiers précédents venaient d'être détruits.
  if [ "$ok" -ne 1 ]; then
    [ -s "$seal_log" ] && { log_err "Détails :"; tail -n 5 "$seal_log" >&2; }
    if [ "$n" -gt 0 ]; then
      log_err "SCELLEMENT INCOMPLET : $n fichier(s) déjà chiffrés, vérifiés puis"
      log_err "détruits en clair. Leur version chiffrée est INTACTE :"
      log_err "  $streamdir"
      log_err "Le dossier source $dir est INCOMPLET (fichiers restants en clair)."
      log_err "Relancez le scellement sur $dir pour finir le travail, ou restaurez"
      log_err "depuis $streamdir avec le même mot de passe."
      custody_log "SCELLEMENT INCOMPLET (mode flux) : $n fichier(s) chiffrés et vérifiés dans $streamdir ; le reste est encore en clair dans $dir."
      SEAL_RESULT="$streamdir"
    else
      log_err "Échec avant tout chiffrement - dossier chiffré vide supprimé."
      rm -rf "$streamdir" 2>/dev/null
      log_info "Version claire conservée : $dir"
    fi
    rm -f "$seal_log"
    return 1
  fi
  # En-tête du manifeste complété une fois le compte connu.
  printf '# %s fichier(s) chiffré(s), SHA256 des originaux (avant chiffrement)\n' "$n" >> "$manifest"

  rm -f "$seal_log"
  custody_log "Preuves scellées par chiffrement (mode flux) : $streamdir ($n fichier(s) chiffrés, vérifiés un par un, puis clairs détruits ; MANIFESTE.seal fourni)."
  log_ok "Preuves chiffrées et vérifiées : $streamdir ($n fichiers)"
  rm -rf "$dir" 2>/dev/null
  log_ok "Version claire supprimée : $dir (preuves supprimables si besoin)."
  SEAL_RESULT="$streamdir"
  return 0
}

# Décision analyste : déverrouille (chattr -i / chmod a-w) puis supprime les preuves.
# $1 = chemin du dossier ; mot de passe requis si scellé par chiffrement.
# Gère les deux dispositions produites par seal_encrypted() :
#   - archive unique  <dossier>.aes256.tar.gz
#   - dossier chiffré <dossier>.aes256.d/ (mode flux, un fichier chiffré par fichier)
unseal_and_delete() {
  local dir="$1" pw streamdir enc
  streamdir="$(seal_dest_path "$dir" stream)"
  enc="$(seal_dest_path "$dir" archive)"
  # L'archive peut avoir été produite sur un autre FS (SEAL_DEST).
  [ -f "$dir.aes256.tar.gz" ] && enc="$dir.aes256.tar.gz"

  if [ -f "$enc" ]; then
    if [ ! -t 0 ]; then
      log_err "Suppression refusée : aucun terminal pour saisir le mot de passe de scellement."
      return 1
    fi
    printf 'Mot de passe de scellement pour SUPPRIMER les preuves : ' >&2
    IFS= read -r -s pw || { echo >&2; log_err "Saisie interrompue - suppression refusée."; return 1; }
    echo >&2
    # pipefail : un déchiffrement valide doit produire un tar lisible EN ENTIER.
    if ! ( set -o pipefail
           openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass "pass:$pw" \
             -in "$enc" 2>/dev/null \
         | gzip -dc 2>/dev/null \
         | tar tf - >/dev/null 2>&1 ); then
      log_err "Mot de passe incorrect ou archive illisible - suppression refusée."
      return 1
    fi
    rm -f "$enc" 2>/dev/null
  elif [ -d "$streamdir" ]; then
    # Mode flux : on vérifie le déchiffrement d'un échantillon face au manifeste.
    if [ ! -t 0 ]; then
      log_err "Suppression refusée : aucun terminal pour saisir le mot de passe de scellement."
      return 1
    fi
    printf 'Mot de passe de scellement pour SUPPRIMER les preuves : ' >&2
    IFS= read -r -s pw || { echo >&2; log_err "Saisie interrompue - suppression refusée."; return 1; }
    echo >&2
    local sample f rel want got bad=0
    sample="$(find "$streamdir" -type f ! -name 'MANIFESTE.seal' 2>/dev/null | head -3)"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rel="${f#"$streamdir"/}"
      want="$(awk -v k="./$rel" '$2 == k {print $1}' "$streamdir/MANIFESTE.seal" 2>/dev/null | head -1)"
      got="$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass "pass:$pw" \
              -in "$f" 2>/dev/null | sha256sum | awk '{print $1}')"
      [ -n "$want" ] && [ "$got" = "$want" ] || { bad=1; break; }
    done <<< "$sample"
    if [ "$bad" -eq 1 ]; then
      log_err "Mot de passe incorrect ou dossier chiffré illisible - suppression refusée."
      return 1
    fi
    rm -rf "$streamdir" 2>/dev/null
  else
    [ -d "$dir" ] || { log_err "Dossier introuvable : $dir"; return 1; }
    if [ "$(id -u)" = 0 ] && command -v chattr >/dev/null 2>&1; then
      chattr -R -i "$dir" 2>/dev/null
    fi
    chmod -R u+w "$dir" 2>/dev/null
  fi
  rm -rf "$dir" 2>/dev/null
  custody_log "Preuves supprimées (décision analyste) : $dir"
  log_ok "Preuves supprimées : $dir"
}

# ------------------------------------------------------------------
# Consentement et périmètre (loi Godfrain - art. 323-1 à 323-7 C. pén.)
# Garde-fou légal : n'analyser QUE les appareils et comptes de la personne
# accompagnée, JAMAIS ceux d'un tiers (ni d'un agresseur présumé).
# Refus de confirmation => return 1, acquisition abandonnée sans collecte.
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
    # shellcheck disable=SC2153 # CASE_ID est un global posé par case_init() (start.sh)
    custody_log "Consentement confirmé ($platform) — référence du consentement écrit : $CASE_ID (recueilli par ${ANALYST:-$(whoami)}, structure ${STRUCTURE_NAME:-non renseignée})."
    log_ok "Périmètre validé - $platform : appareil de la personne accompagnée."
    return 0
  else
    custody_log "REFUS de consentement ($platform)"
    log_warn "Acquisition refusée : le consentement au cadre légal et la confirmation que l'appareil appartient à la personne accompagnée sont requis."
    return 1
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
    # Nom anti-collision : une reprise du même CASE_ID aurait déjà créé
    # « -QUARANTAINE_non-scellée » ; ne jamais écraser une quarantaine.
    quarantine="$dir-QUARANTAINE_non-scellée"
    if [ -e "$quarantine" ]; then
      quarantine="$quarantine-$(date '+%Y%m%d-%H%M%S')"
    fi
    if mv "$dir" "$quarantine" 2>/dev/null; then
      # Le journal de traçabilité suit le dossier : il pointe vers le nouvel
      # emplacement pour continuer à tracer dans la capture isolée.
      [ -n "${CUSTODY_FILE:-}" ] && CUSTODY_FILE="$quarantine/$(basename "$CUSTODY_FILE")"
      [ -n "${AUDIT_FILE:-}" ] && AUDIT_FILE="$quarantine/$(basename "$AUDIT_FILE")"
      log_warn "Capture partielle isolée : $(basename "$quarantine") - son SHA256 n'engage pas une preuve scellée."
      custody_log "Capture partielle isolée dans $quarantine (non scellée, non reprise)."
    else
      log_err "Impossible de déplacer la capture partielle vers $quarantine - elle reste à $(basename "$dir") (à traiter manuellement)."
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
  PYTHONPATH="$WRAPPER_DIR/lib${PYTHONPATH:+:$PYTHONPATH}" python3 - "$1" <<'PY'
import json, sys
from jsonutils import search

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
    sev = str(search(rec, ("level", "severity")) or "n/a").upper()
    if sev not in LEVELS:
        sev = "n/a"
    msg = str(search(rec, ("message", "description", "artifact")) or "n/a")
    ioc_line = ""
    sw_tag = ""
    ioc = rec.get("matched_indicator")
    if isinstance(ioc, dict):
        v = ioc.get("value") or "n/a"
        t = ioc.get("type") or ""
        c = ioc.get("name") or ioc.get("stix2_file_name") or ""
        sw = ioc.get("is_stalkerware")
        if sw is True:
            sw_tag = "  [SPYWARE AVERE]"
        elif sw is False:
            sw_tag = "  [USAGE DOUBLE LEGITIME A CORROBORER]"
        else:
            low = (str(c) + " " + str(v)).lower()
            if "stalkerware" in low:
                sw_tag = "  [SPYWARE AVERE - collection dédiée]"
        ioc_line = f"        IoC : {v}"
        if t:
            ioc_line += f"  (type: {t})"
        if c:
            ioc_line += f"  [collection: {c}]"
    elif isinstance(ioc, str) and ioc:
        ioc_line = f"        IoC : {ioc}"
    else:
        v = search(rec, ("value", "indicator", "matched_indicator_value"))
        if v not in (None, ""):
            ioc_line = f"        IoC : {str(v)[:160]}"
    ctx = evfmt(rec.get("event"))
    print(f"    {n}) [{sev}] {msg[:220]}")
    if ioc_line:
        print(ioc_line + sw_tag)
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
  PYTHONPATH="$WRAPPER_DIR/lib${PYTHONPATH:+:$PYTHONPATH}" python3 - "$dir" <<'PY'
import json, os, re, sys
from jsonutils import search
root = sys.argv[1]
parts = []
for name in ("backup_info.json", "sysdiagnose_info.json"):
    p = os.path.join(root, name)
    if os.path.isfile(p):
        try:
            d = json.load(open(p, encoding="utf-8"))
            model  = search(d, ("product_type", "product", "devicemodel", "model"))
            ver    = search(d, ("product_version", "ios_version", "version"))
            dname  = search(d, ("device_name", "name"))
            imei   = search(d, ("imei",))
            serial = search(d, ("serial_number", "serialNumber", "SerialNumber"))
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
    p = os.path.join(root, "Info.plist")
    if os.path.isfile(p):
        try:
            import base64, plistlib
            def maybe_b64(v):
                if not isinstance(v, str):
                    return v
                s = v.strip()
                if not s or len(s) % 4:
                    return v
                try:
                    raw = base64.b64decode(s, validate=True)
                    text = raw.decode("utf-8", "strict")
                except Exception:
                    return v
                if (text.isprintable()
                        and base64.b64encode(raw).decode("ascii").rstrip("=") == s.rstrip("=")):
                    return text
                return v
            with open(p, "rb") as fh:
                d = plistlib.load(fh)
            for k, l in (("Device Name", "Nom"), ("Product Type", "Modèle"),
                         ("Product Version", "OS"), ("IMEI", "IMEI"),
                         ("Serial Number", "Serial"), ("Unique Device ID", "UDID")):
                v = maybe_b64(d.get(k))
                if v not in (None, "", "unavailable"):
                    parts.append(f"{l}: {v}")
        except Exception:
            pass
if not parts:
    p = os.path.join(root, "acquisition.json")
    if os.path.isfile(p):
        try:
            d = json.load(open(p, encoding="utf-8"))
            model  = search(d, ("product_model", "model", "device_model"))
            ver    = search(d, ("device_version", "android_version", "version", "os_version"))
            manuf  = search(d, ("product_manufacturer", "manufacturer", "brand"))
            imei   = search(d, ("imei", "imei1", "Imei"))
            serial = search(d, ("serial_number", "serial", "Serial"))
            if not serial:
                adb = search(d, ("collector", "Adb"))
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
  PYTHONPATH="$WRAPPER_DIR/lib${PYTHONPATH:+:$PYTHONPATH}" python3 - "$dir" "${extra_args[@]}" <<'PY'
import base64, json, os, plistlib, re, sys
from jsonutils import search
root = sys.argv[1]
overrides = {}
for a in sys.argv[2:]:
    if "=" in a:
        k, v = a.split("=", 1)
        overrides[k] = v

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
        return APPLE_MODELS[c]
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

# --- Source iOS : plists d'une backup iTunes (Info.plist / Manifest.plist) ---
for name in ("Info.plist", "Manifest.plist"):
    pp = os.path.join(root, name)
    if not os.path.isfile(pp):
        continue
    try:
        with open(pp, "rb") as fh:
            d = plistlib.load(fh)
    except Exception:
        continue
    if name == "Info.plist":
        platform = platform or "iOS"
        model_code = model_code or d.get("Product Type") or d.get("ProductType") or d.get("Device Model")
        ver = d.get("Product Version") or d.get("ProductVersion") or d.get("iOS Version")
        build = d.get("Build Version") or d.get("BuildVersion")
        if ver:
            result["Systeme d exploitation"] = result["Systeme d exploitation"] or ("iOS " + str(ver))
        result["Build"] = result["Build"] or build
        result["Nom de l'appareil"] = result["Nom de l'appareil"] or \
            d.get("Device Name") or d.get("DeviceName")
        result["Numero de telephone"] = result["Numero de telephone"] or \
            d.get("Phone Number") or d.get("PhoneNumber")
        result["IMEI"] = result["IMEI"] or d.get("IMEI")
        result["Numero de serie"] = result["Numero de serie"] or \
            d.get("Serial Number") or d.get("SerialNumber")
        result["ICCID"] = result["ICCID"] or d.get("ICCID")
        result["MEID"] = result["MEID"] or d.get("MEID")
        result["Target identifier"] = result["Target identifier"] or \
            d.get("Unique Device ID") or d.get("UniqueDeviceID")
        result["Derniere sauvegarde"] = result["Derniere sauvegarde"] or \
            d.get("Last Backup Date") or d.get("LastBackupDate")
        result["Marque"] = result["Marque"] or "Apple"
    elif name == "Manifest.plist":
        result["Derniere sauvegarde"] = result["Derniere sauvegarde"] or \
            d.get("Date") or d.get("LastBackupDate")

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
    model_code = model_code or search(d, ("Product Type", "product_type", "ProductType", "model"))
    ver = search(d, ("Product Version", "product_version", "ProductVersion", "ios_version"))
    build = search(d, ("Build Version", "build_version", "BuildVersion"))
    if ver:
        result["Systeme d exploitation"] = result["Systeme d exploitation"] or ("iOS " + str(ver))
    result["Build"] = result["Build"] or build
    result["Nom de l'appareil"] = result["Nom de l'appareil"] or \
        b64name(search(d, ("Display Name",)) or "") or search(d, ("Device Name", "device_name", "name", "Devicename"))
    result["Numero de telephone"] = result["Numero de telephone"] or \
        search(d, ("Phone Number", "phone_number", "PhoneNumber"))
    result["IMEI"] = result["IMEI"] or search(d, ("IMEI", "imei"))
    result["Numero de serie"] = result["Numero de serie"] or \
        search(d, ("Serial Number", "serial_number", "SerialNumber", "Serial"))
    result["ICCID"] = result["ICCID"] or search(d, ("ICCID", "iccid"))
    result["MEID"] = result["MEID"] or search(d, ("MEID", "meid"))
    result["Target identifier"] = result["Target identifier"] or \
        search(d, ("Target Identifier", "target_identifier", "Unique Identifier", "unique_identifier"))
    result["Derniere sauvegarde"] = result["Derniere sauvegarde"] or \
        search(d, ("Last Backup Date", "last_backup_date", "LastBackupDate"))
    apps = search(d, ("Installed Applications", "installed_applications"))
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
        model_code = model_code or search(d, ("product_model", "model", "device_model"))
        ver = search(d, ("device_version", "android_version", "version", "os_version"))
        if ver:
            result["Systeme d exploitation"] = result["Systeme d exploitation"] or ("Android " + str(ver))
        result["Marque"] = result["Marque"] or \
            search(d, ("product_manufacturer", "manufacturer", "brand"))
        result["IMEI"] = result["IMEI"] or search(d, ("imei", "imei1", "Imei"))
        serial = result["Numero de serie"] or search(d, ("serial_number", "serial", "Serial"))
        if not serial:
            adb = search(d, ("collector", "Adb"))
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
tot, bylev, bymod, sw_tot = 0, defaultdict(int), {}, 0
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
        if isinstance(rec.get("matched_indicator"), dict) and rec["matched_indicator"].get("is_stalkerware") is True:
            sw_tot += 1
        if mod not in bymod:
            bymod[mod] = [0, ""]
        bymod[mod][0] += 1
        if not bymod[mod][1] or order[lev] > order[bymod[mod][1]]:
            bymod[mod][1] = lev
print(f"total|{tot}")
print(f"stalkerware|{sw_tot}")
for k in ("CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO"):
    print(f"level|{k}|{bylev.get(k, 0)}")
for mod, (c, mx) in sorted(bymod.items()):
    print(f"module|{mod}|{c}|{mx}")
PY
}

# Bloc de synthèse/verdict inséré en tête du rapport.
detection_synthesis() {
  local results="$1"
  local tot=0 c_crit=0 c_high=0 c_med=0 c_low=0 c_info=0 mods=0 c_sw=0
  local t a b verdict
  while IFS='|' read -r t a b; do
    case "$t" in
      total) tot="$a" ;;
      stalkerware) c_sw="$a" ;;
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
    verdict="AUCUNE détection d'IoC - preuve à priori saine (à confirmer)."
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
  echo "  Détections            : $tot"
  [ "$c_sw" -gt 0 ] && echo "  dont spyware avérés  : $c_sw"
  echo "  Répartition séverite  : CRITICAL: $c_crit | HIGH: $c_high | MEDIUM: $c_med | LOW: $c_low | INFO: $c_info"
  echo "  Modules concernés     : $mods"
  echo "  Verdict               : $verdict"
  echo ""
}

# Liste propre des IoCs utilisés
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

# Convertit un rapport texte (rapport.txt) en PDF, 100 % python stdlib
# (aucune dépendance : pas de LibreOffice/pandoc/reportlab). Police base-14
# Courier /WinAnsiEncoding : les glyphes hors CP1252 (═, ↑, …) sont
# translittérés en ASCII équivalents.
rapport_to_pdf() {
  local txt="${1:-}" pdf="${2:-}"
  [ -f "$txt" ] || return 1
  [ -n "$pdf" ] || return 1
  command -v python3 >/dev/null 2>&1 || { log_err "python3 requis pour le PDF du rapport."; return 1; }
  python3 - "$txt" "$pdf" <<'PDFPY' || { log_err "Échec de la génération PDF du rapport."; return 1; }
import sys
txt, pdf = sys.argv[1], sys.argv[2]
text = open(txt, encoding="utf-8").read()
trans = str.maketrans({
    "═": "=", "─": "-", "│": "|", "┌": "+", "┐": "+", "└": "+", "┘": "+",
    "├": "+", "┤": "+", "┬": "+", "┴": "+", "┼": "+",
    "↑": "^", "↓": "v", "≥": ">=", "✔": "+", "•": "*", "✓": "v",
})
text = text.translate(trans).encode("cp1252", "replace")

W = 92          # largeur max utile (Courier 9pt, A4, marges 46pt)
LPP = 64        # lignes de corps par page
FONT = "/F1 9 Tf"
WIDTH, HEIGHT = 595, 842
LX, TOP = 46, 792

def esc(b):
    return b.replace(b"\\", b"\\\\").replace(b"(", b"\\(").replace(b")", b"\\)")

lines = []
for raw in text.split(b"\n"):
    lines.extend(raw[i:i + W] for i in range(0, len(raw) or 1, W))
pages = [lines[i:i + LPP] for i in range(0, len(lines), LPP)] or [[]]

def content(page, num):
    out = bytearray(b"BT\n" + FONT.encode() + b"\n1 0 0 1 %d %d Tm\n" % (LX, TOP))
    for ln in page:
        out += b"(" + esc(ln) + b") Tj\n0 -11 Td\n"
    out += b"ET\n"
    foot = b"Rapport d'analyse MVT-Wrapper - page %d/%d" % (num, len(pages))
    out += b"BT\n/F1 8 Tf\n1 0 0 1 %d 40 Tm\n(%s) Tj\nET\n" % (LX, esc(foot))
    return bytes(out)

objs = [b"<< /Type /Catalog /Pages 2 0 R >>"]
objs.append(b"<< /Type /Pages /Kids [" + b" ".join(b"%d 0 R" % (4 + 2 * i) for i in range(len(pages))) + b"] /Count %d >>" % len(pages))
objs.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>")
for i in range(len(pages)):
    cont = 5 + 2 * i
    objs.append(b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] "
                b"/Resources << /Font << /F1 3 0 R >> >> /Contents %d 0 R >>" % (WIDTH, HEIGHT, cont))
    c = content(pages[i], i + 1)
    objs.append(b"<< /Length %d >>\nstream\n" % len(c) + c + b"endstream")

out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
offsets = [0]
for num, o in enumerate(objs, start=1):
    offsets.append(len(out))
    out += b"%d 0 obj\n" % num + o + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
for off in offsets[1:]:
    out += b"%010d 00000 n \n" % off
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
open(pdf, "wb").write(out)
PDFPY
  [ -s "$pdf" ] || { log_err "PDF du rapport vide : $pdf"; return 1; }
  return 0
}

make_report() {
  local case_id="$1" results="$2" platform="$3" iocs_csv="${4:-}" evidence_dir="${5:-}" analysis_type="${6:-}"
  local report="$results/rapport.txt"
  local mod desc f
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
    echo "Consentement     : référence $case_id — consentement écrit recueilli avant analyse par ${ANALYST:-$(whoami)}"
    echo "Versions outil   : wrapper ${VERSION:-n/a} / MVT $(mvt_version_local 2>/dev/null || echo n/a)"
    echo "Composants       : $(tool_versions)"
    echo "Machine          : $(hostname 2>/dev/null || uname -n)"
    echo "Base d'IoCs      : $(ioc_base_signature)"
    echo ""
    echo '--------------------------------------------------------------'
    echo '  STATUT DU RAPPORT'
    echo '--------------------------------------------------------------'
    echo "  Ce rapport est un élément technique d'aide à l'orientation et non une expertise judiciaire au sens du Code de procedure penale."
    echo "  Il ne se substitue ni à une plainte, ni à une expertise ordonnée par la juridiction ou sur requisition (art. 60, 77-1-1 et 156 C. pr. pen)."
    echo "  Il ne prejuge pas de la decision de justice."
    echo "  Methode et limites : analyses portant exclusivement sur les appareils et comptes de la personne accompagnée avec son consentement ecrit."
    echo "  Les IoCs publics sont des indicateurs et non une preuve : une detection doit être corroborer et peut présenter des faux positifs/negatifs;"
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
  echo '  Niveau de confiance : les détections sont classées par sévérité :'
  echo '  [CRITICAL/HIGH] = signal fort à investiguer en priorité.'
  echo '  [SPYWARE AVERE] = indique un rapprochement avec des collections dédiées au logiciel espion.'
  echo '  [USAGE DOUBLE LEGITIME A CORROBORER] = signale des applications ou services ayant aussi une utilisation licite (système, télémaintenance, accessibilité...).'
  echo '  Toute détection doit être corroborée.'
  echo ''
  detection_synthesis "$results"
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
      if [ -f "$evidence_dir/SHA256SUMS-acquisition.txt" ]; then
        echo "  Manifeste acquisition : $evidence_rel/SHA256SUMS-acquisition.txt"
        echo "  Empreinte (SHA256) acquisition : $(sha256sum "$evidence_dir/SHA256SUMS-acquisition.txt" 2>/dev/null | awk '{print $1}')"
      fi
      if [ -f "$evidence_dir/SHA256SUMS.txt" ]; then
        if ( cd "$evidence_dir" && sha256sum -c SHA256SUMS.txt >/dev/null 2>&1 ); then
          echo '  Intégrité finale (SHA256) : verifiée - OK'
        else
          echo '  Intégrité finale (SHA256) : À CONTRÔLER (anomalie detectée !)'
        fi
        echo "  Empreinte (SHA256) manifeste final : $(sha256sum "$evidence_dir/SHA256SUMS.txt" 2>/dev/null | awk '{print $1}')"
        echo "  Manifeste horodaté : $(head -n 1 "$evidence_dir/SHA256SUMS.txt" 2>/dev/null)"
      fi
      [ -f "$evidence_dir/chain_of_custody.txt" ] && echo "  Journal de traçabilité : $evidence_rel/chain_of_custody.txt — ${ANALYST:-$(whoami)} / ${STRUCTURE_NAME:-non renseignée}"
    else
      echo '  n/a'
    fi
    echo ''
    echo "  Note : une détection d'IoC ne signifie pas automatiquement que le dispositif est compromis ; les IoCs publics seuls ne suffisent pas à conclure."
    echo '  Chaque détection doit être investiguée par un analyste.'
    echo "  Preservation avant remediation : aucune action de remediation (dont la desinstallation d'un logiciel espion) n'engage la securite d'etre techniquement realisee sur ce terminal a ce stade."
    echo '  Orientation : 3919 (violences au sein du couple), 116 006 (France Victimes), Cybermalveillance.gouv.fr, CNIL, et un constat par commissaire de justice peut être envisagé.'
    echo ''
    echo '══════════════════════════════════════════════════════════'
  } > "$report"
  log_ok "Rapport généré : $report"
  if rapport_to_pdf "$report" "$results/rapport.pdf"; then
    log_ok "Rapport PDF : $results/rapport.pdf"
  else
    log_warn "Rapport PDF non généré (moteur Python indisponible/échec)."
  fi

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
# Volet orientation et accompagnement
orientation_accompagnement() {
  local platform="$1"
  log_info "Orientation et accompagnement proposés ($platform)."
  echo ''
  echo '--------------------------------------------------------------'
  echo '  ORIENTATION ET ACCOMPAGNEMENT '
  echo '--------------------------------------------------------------'
  echo '  3919 : violences au sein du couple (info, écoute, orientation)'
  echo '  116 006 : France Victimes - aide aux victimes (7j/7)'
  echo '  Hubertine Auclert : centre Hubertine Auclert (Île-de-France)'
  echo '  Cybermalveillance : Cybermalveillance.gouv.fr'
  echo '  Commissaire de justice : constat opposable (préservation)'
  echo '  Plainte : dépôt de plainte / main courante en brigade (3919)'
  echo ''
  echo '--------------------------------------------------------------'
  custody_log "Accompagnement proposé ($platform) : 3919, 116 006, Centre Hubertine Auclert, CNIL, Cybermalveillance, Echap, commissaire de justice."
  return 0
}

