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
# Fenêtre de sélection native (zenity/kdialog). $3 = dir (défaut) | file.
# Renvoie le chemin choisi, vide si annulé ou sans GUI. Ne crée rien.
pick_gui_path() {
  local title="$1" start="${2:-$PWD}" mode="${3:-dir}" got=""
  [ -d "$start" ] || start="$PWD"
  if command -v zenity >/dev/null 2>&1; then
    local args=(--file-selection --title="$title")
    [ "$mode" = "dir" ] && args+=(--directory)
    got="$(zenity "${args[@]}" --filename="$start/" 2>/dev/null || true)"
  elif command -v kdialog >/dev/null 2>&1; then
    if [ "$mode" = "dir" ]; then
      got="$(kdialog --getexistingdirectory "$start" 2>/dev/null || true)"
    else
      got="$(kdialog --getopenfilename "$start" 2>/dev/null || true)"
    fi
  fi
  printf '%s' "$got"
}

# Fenêtre de sélection de DOSSIER (raccourci de pick_gui_path).
pick_directory_gui() {
  pick_gui_path "$1" "${2:-$PWD}" dir
}

# Utilisateur réel derrière sudo (le wrapper tourne souvent en root).
real_user() { printf '%s' "${SUDO_USER:-$USER}"; }

# Environnement graphique de l'utilisateur réel. Le wrapper tourne en root
# (sudo) et n'hérite donc pas de XAUTHORITY/DBUS/XDG_RUNTIME_DIR propres à la
# session : un gestionnaire lancé en root ne s'affiche pas. On relit ces
# variables depuis /proc/<pid>/environ d'un process de cet utilisateur (root
# peut le lire), avec repli sur des valeurs usuelles d'une session unique.
# Imprime des lignes KEY=VALUE destinées à `env`.
harvest_gui_env() {
  local u="${1:-$(real_user)}" pid home uid env
  home="$(getent passwd "$u" 2>/dev/null | cut -d: -f6)"
  uid="$(id -u "$u" 2>/dev/null)"
  for pid in $(pgrep -u "$u" 2>/dev/null); do
    [ -r "/proc/$pid/environ" ] || continue
    env="$(cat "/proc/$pid/environ" 2>/dev/null | tr '\0' '\n')"
    case "$env" in
      DISPLAY=*|*$'\n'DISPLAY=*) ;;
      *) continue ;;
    esac
    printf '%s\n' "$env" \
      | grep -aE '^(DISPLAY|WAYLAND_DISPLAY|XAUTHORITY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|XDG_SESSION_DESKTOP|KDE_FULL_SESSION|QT_QPA_PLATFORM)='
    return 0
  done
  printf 'DISPLAY=%s\n' "${DISPLAY:-:0}"
  [ -n "$uid" ] && printf 'XDG_RUNTIME_DIR=/run/user/%s\n' "$uid"
  [ -n "$uid" ] && [ -S "/run/user/$uid/bus" ] && printf 'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%s/bus\n' "$uid"
  [ -n "$home" ] && [ -f "$home/.Xauthority" ] && printf 'XAUTHORITY=%s\n' "$home/.Xauthority"
  return 0
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
# Choix du chemin d'acquisition / backup : candidats auto-détectés PUIS
# fenêtre native PUIS saisie manuelle. Retourne un chemin existant.
pick_acquisition_path() {
  local candidates=() c pf default_dir
  local title="Chemin de l'acquisition / backup"
  default_dir="${CASE_DIR:-$PWD}"
  if [ -n "$default_dir" ] && [ -d "$default_dir" ]; then
    while IFS= read -r c; do
      [ -n "$c" ] && candidates+=("$c")
    done < <(find "$default_dir" -maxdepth 2 \( -name '*.ab' -o -name '*.zip' -o -name 'Manifest.db' \) 2>/dev/null)
  fi
  pf="$(pick_gui_path "$title" "$default_dir" file)"
  [ -n "$pf" ] && candidates=( "$pf" "${candidates[@]}" )
  if [ "${#candidates[@]}" -gt 0 ]; then
    local chosen
    chosen="$(menu_select "$title :" "${candidates[@]}" "Saisie manuelle" "Ouvrir le gestionnaire de fichiers")"
    case "$chosen" in
      "Saisie manuelle")
        chosen="$(ask_input "$title (dossier, .ab, .zip) :" "")" ;;
      "Ouvrir le gestionnaire de fichiers")
        chosen="$(pick_gui_path "$title" "$default_dir" file)"
        [ -z "$chosen" ] && chosen="$(ask_input "$title (dossier, .ab, .zip) :" "")" ;;
    esac
    printf '%s' "$chosen"
  else
    ask_input "$title (dossier, .ab, .zip) :" ""
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
# SEAL_METHOD pilote le scellement : "encrypt" (défaut) chiffre puis supprime le
# clair (dossier restant supprimable) ; "lock" conserve le verrouillage a-w/+i.
lock_dir() {
  local dir="$1"
  case "${SEAL_METHOD:-encrypt}" in
    encrypt)
      seal_encrypted "$dir"
      ;;
    lock)
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

# Saisie d'un secret sans écho : invite sur stderr, valeur sur stdout.
# Refuse explicitement un stdin non interactif (sinon read renvoie EOF en
# silence et le mot de passe serait vide).
read_secret_prompt() {
  local prompt="$1" val
  if [ ! -t 0 ]; then
    log_err "Aucun terminal (stdin non interactif) pour saisir le mot de passe."
    return 1
  fi
  printf '%s' "$prompt" >&2
  IFS= read -r -s val || { echo >&2; return 1; }
  echo >&2
  printf '%s' "$val"
}

# Saisie du mot de passe (2 fois). Refuse le non-TTY explicitement au lieu de
# d'échouer en silence sur un read qui renvoie EOF.
seal_read_password() {
  local pw1 pw2
  if [ ! -t 0 ]; then
    log_err "Scellement impossible : aucun terminal (stdin non interactif) pour saisir le mot de passe."
    return 1
  fi
  pw1="$(read_secret_prompt 'Mot de passe de scellement AES-256 (≥ 8 caractères) : ')" \
    || { log_err "Saisie du mot de passe interrompue - scellement annulé."; return 1; }
  pw2="$(read_secret_prompt 'Confirmez le mot de passe : ')" \
    || { log_err "Saisie de la confirmation interrompue - scellement annulé."; return 1; }
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

  # ---- Mode flux : un fichier à la fois. Chaque fichier est chiffré, relu et
  # vérifié AVANT que son clair ne soit détruit (pic = plus gros fichier seul).
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

  # Échec en cours : $streamdir est CONSERVÉ. Les fichiers déjà chiffrés et
  # vérifiés ont eu leur clair détruit : c'est la SEULE copie restante.
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
# $1 = chemin du dossier. La suppression locale d'une affaire ne demande aucun mot
# de passe : la double confirmation explicite de cmd_purge suffit.
# Gère les deux dispositions produites par seal_encrypted() :
#   - archive unique  <dossier>.aes256.tar.gz
#   - dossier chiffré <dossier>.aes256.d/ (mode flux, un fichier chiffré par fichier)
unseal_and_delete() {
  local dir="$1" streamdir enc
  streamdir="$(seal_dest_path "$dir" stream)"
  enc="$(seal_dest_path "$dir" archive)"
  # L'archive peut avoir été produite sur un autre FS (SEAL_DEST).
  [ -f "$dir.aes256.tar.gz" ] && enc="$dir.aes256.tar.gz"

  if [ ! -e "$dir" ] && [ ! -e "$enc" ] && [ ! -d "$streamdir" ]; then
    log_err "Dossier introuvable : $dir"
    return 1
  fi
  if [ "$(id -u)" = 0 ] && command -v chattr >/dev/null 2>&1; then
    chattr -R -i "$dir" "$streamdir" 2>/dev/null
  fi
  chmod -R u+w "$dir" "$streamdir" 2>/dev/null
  rm -f "$enc" 2>/dev/null
  rm -rf "$dir" "$streamdir" 2>/dev/null
  custody_log "Preuves supprimées (décision analyste) : $dir"
  log_ok "Preuves supprimées : $dir"
}

# ------------------------------------------------------------------
# Consultation d'une affaire scellée (lecture seule, vers un temp).
# ------------------------------------------------------------------

# Énumère les affaires : evidence/ ET SEAL_DEST (archive unique, mode flux ou
# dossier clair). Sort "base<TAB>état" ; état ∈ {archive,flux,clair,verrouillé}.
# "base" est le chemin sans suffixe .aes256.* (dossier d'affaire attendu).
sealed_cases() {
  local d base state f seen=""
  local dirs=("$EVIDENCE_DIR")
  [ -n "${SEAL_DEST:-}" ] && dirs+=("$(seal_expand_tilde "$SEAL_DEST")")
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.aes256.tar.gz; do
      [ -f "$f" ] || continue
      base="${f%.aes256.tar.gz}"
      case "$seen" in *"|$base|"*) continue ;; esac
      seen="$seen|$base|"
      printf '%s\tarchive\n' "$base"
    done
    for f in "$d"/*.aes256.d; do
      [ -d "$f" ] || continue
      base="${f%.aes256.d}"
      case "$seen" in *"|$base|"*) continue ;; esac
      seen="$seen|$base|"
      printf '%s\tflux\n' "$base"
    done
    for f in "$d"/CASE-*; do
      [ -d "$f" ] || continue
      case "$f" in *.aes256.d) continue ;; esac
      base="$f"
      case "$seen" in *"|$base|"*) continue ;; esac
      seen="$seen|$base|"
      state="clair"
      if lsattr -d "$f" 2>/dev/null | grep -q '\bi\b'; then state="verrouillé"; fi
      printf '%s\t%s\n' "$base" "$state"
    done
  done
}

# Déchiffre une affaire scellée vers un dossier de travail.
#   $1 = base (chemin sans suffixe)   $2 = destination
#   $3 = "report" (results/rapport.* uniquement) | "all" (tout)
#   $4 = mot de passe
# Le mot de passe passe par l'environnement (jamais dans argv). Renvoie 0 si
# le déchiffrement a réussi, 1 sinon (mot de passe erroné ou archive illisible).
unseal_extract() {
  local base="$1" dest="$2" scope="${3:-all}" pw="$4"
  local enc streamdir rel src dst want got f
  mkdir -p "$dest" || return 1
  enc="$(seal_dest_path "$base" archive)"
  [ -f "$base.aes256.tar.gz" ] && enc="$base.aes256.tar.gz"
  streamdir="$(seal_dest_path "$base" stream)"
  [ -d "$base.aes256.d" ] && streamdir="$base.aes256.d"

  if [ -f "$enc" ]; then
    # pipefail : sans lui, un échec de gzip/tar sur un mauvais mot de passe
    # serait masqué par le statut d'openssl et l'extraction serait "réussie".
    if [ "$scope" = "report" ]; then
      ( set -o pipefail
        MVT_SEAL_PW="$pw" openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
            -pass env:MVT_SEAL_PW -in "$enc" 2>/dev/null \
        | gzip -dc 2>/dev/null \
        | tar xf - -C "$dest" --strip-components=1 --wildcards \
              '*/results/rapport.txt' '*/results/rapport.pdf' 2>/dev/null )
    else
      ( set -o pipefail
        MVT_SEAL_PW="$pw" openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
            -pass env:MVT_SEAL_PW -in "$enc" 2>/dev/null \
        | gzip -dc 2>/dev/null \
        | tar xf - -C "$dest" --strip-components=1 2>/dev/null )
    fi
    return $?
  fi

  if [ -d "$streamdir" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      rel="${f#"$streamdir"/}"
      if [ "$scope" = "report" ]; then
        case "$rel" in results/rapport.txt|results/rapport.pdf) ;; *) continue ;; esac
      fi
      src="$f"
      dst="$dest/$rel"
      mkdir -p "$(dirname "$dst")" || return 1
      MVT_SEAL_PW="$pw" openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
          -pass env:MVT_SEAL_PW -in "$src" -out "$dst" 2>/dev/null || return 1
      want="$(awk -v k="./$rel" '$2 == k {print $1}' "$streamdir/MANIFESTE.seal" 2>/dev/null | head -1)"
      if [ -n "$want" ]; then
        got="$(sha256sum "$dst" 2>/dev/null | awk '{print $1}')"
        [ "$got" = "$want" ] || return 1
      fi
    done < <(find "$streamdir" -type f ! -name 'MANIFESTE.seal' 2>/dev/null)
    return 0
  fi

  return 1
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

# Fichiers IoCs (.stix2/.json) d'un dossier, dépôts git et état exclus.
_ioc_find_in() {
  find "$1" \( -path '*/.git' -o -path '*/.state' \) -prune -o \
      -type f \( -name '*.stix2' -o -name '*.json' \) -print 2>/dev/null \
    | LC_ALL=C sort -u
}

# ------------------------------------------------------------------
# IoCs : liste des fichiers STIX2 disponibles et construction de MVT_STIX2
# ------------------------------------------------------------------
find_ioc_files() {
  _ioc_find_in "$IOCS_CUSTOM_DIR"
  _ioc_find_in "$IOCS_MANAGED_DIR"
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
# Infos device (modèle, version, ...) — parseur unique : lib/deviceinfo.py
# ------------------------------------------------------------------
# Lignes structurées "champ: valeur" pour le rapport juridique.
#   $1 = dossier d'analyse   $2.. = paires Cle=Valeur surchargées
extract_device_details() {
  local k v
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] && printf '%s: %s\n' "$k" "$v"
  done < <(_device_tsv "$@" 2>/dev/null)
}

# Résumé sur une ligne (nom, modèle, OS, IMEI, série) pour la console.
device_info_from() {
  local k v out=""
  while IFS=$'\t' read -r k v; do
    case "$k" in
      "Nom de l'appareil")      out="${out}${out:+ ; }Nom: $v" ;;
      "Modele")                 out="${out}${out:+ ; }Modèle: $v" ;;
      "Systeme d exploitation") out="${out}${out:+ ; }OS: $v" ;;
      "IMEI")                   out="${out}${out:+ ; }IMEI: $v" ;;
      "Numero de serie")        out="${out}${out:+ ; }Serial: $v" ;;
    esac
  done < <(_device_tsv "$@" 2>/dev/null)
  printf '%s' "$out"
}

# Appel du parseur commun (renvoie des lignes "champ<TAB>valeur").
_device_tsv() {
  PYTHONPATH="$WRAPPER_DIR/lib${PYTHONPATH:+:$PYTHONPATH}" \
    python3 "$WRAPPER_DIR/lib/deviceinfo.py" "$@"
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

# Convertit un rapport texte (rapport.txt) en PDF structuré, 100 % python
# stdlib (moteur dans lib/report_pdf.py : titres, tableaux, pastilles de
# sévérité, verdict, pagination). Aucune dépendance externe.
rapport_to_pdf() {
  local txt="${1:-}" pdf="${2:-}"
  [ -f "$txt" ] || return 1
  [ -n "$pdf" ] || return 1
  command -v python3 >/dev/null 2>&1 || { log_err "python3 requis pour le PDF du rapport."; return 1; }
  python3 "$WRAPPER_DIR/lib/report_pdf.py" "$txt" "$pdf" \
    || { log_err "Échec de la génération PDF du rapport."; return 1; }
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
        echo '  Intégrité finale (SHA256) : Vérifiée - OK'
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
  echo "  Note : une détection d'IoC ne signifie pas automatiquement que le dispositif est compromis ; les IoCs publics seuls ne suffisent pas à conclure. Chaque détection doit être investiguée par un analyste."
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

