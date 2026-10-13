#!/usr/bin/env bash
# ============================================================
#  INSTALLATION DU WRAPPER MVT — toutes les dépendances
#  Usage : sudo ./install.sh
# ============================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$SCRIPT_DIR/config.sh" ]; then
  echo "[install] config.sh -> valeurs par défaut à configurer."
  cat > "$SCRIPT_DIR/config.sh" <<'EOF'
#!/usr/bin/env bash

# Racine du wrapper
WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Secrets : .env à la racine (gitignoré, chmod 600). Chargé s'il existe.
if [ -f "$WRAPPER_DIR/.env" ]; then
  set -a; source "$WRAPPER_DIR/.env"; set +a
fi

EVIDENCE_DIR="${WRAPPER_DIR}/evidence"
IOCS_DIR="${WRAPPER_DIR}/iocs"
IOCS_CUSTOM_DIR="${IOCS_DIR}/custom"
IOCS_MANAGED_DIR="${IOCS_DIR}/managed"
TOOLS_DIR="${WRAPPER_DIR}/tools"
ADB_EXTRA_DIR="${TOOLS_DIR}/platform-tools"
ANDROIDQF_BIN="${TOOLS_DIR}/androidqf"

# Repos git d'IoCs (mise à jour dans iocs/managed/)
IOC_REPOS=(
  "https://github.com/AssoEchap/stalkerware-indicators"
  "https://github.com/mvt-project/mvt-indicators.git"
)

# IoCs : mise à jour avant analyse / IoCs officiels
UPDATE_IOCS_BEFORE_ANALYSIS="yes"
DOWNLOAD_OFFICIAL_IOCS="yes"

# Scellement des preuves ("encrypt" | "lock" | "no")
SEAL_METHOD="encrypt"

# Destination de l'archive chiffrée : vide = à côté du dossier de preuve.
# Renseignez un autre volume si le dossier est trop volumineux pour être
# archivé en plus sur place (ex. "/media/<user>/SAUVEGARDES").
SEAL_DEST=""

DEDICATED_TERMINAL="auto"

# VirusTotal : la clé se renseigne dans le fichier .env (racine du wrapper),
# la plus simple via `./start.sh config` -> « VirusTotal : definir la cle API ».
ENABLE_VIRUSTOTAL="no"

# Analyste par défaut
ANALYST="Analyste"

# Structure / collectif
STRUCTURE_NAME=""

# Version du wrapper
VERSION="1.3.0"
EOF
  chmod 600 "$SCRIPT_DIR/config.sh"
  echo "[install] config.sh généré."
else
  echo "[install] config.sh présent."
fi

# Secrets : .env à la racine (clé VirusTotal), gitignoré, jamais dans config.sh.
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  cat > "$SCRIPT_DIR/.env" <<'EOF'
# Secrets du wrapper MVT — lu par config.sh au démarrage (gitignoré, chmod 600).
# Clé API VirusTotal : https://www.virustotal.com/gui/my-apikey
# La plus simple pour la saisir : ./start.sh config -> « VirusTotal : definir
# la cle API ». Vous pouvez aussi éditer ce fichier puis relancer ./start.sh.
MVT_VT_API_KEY=
EOF
  chmod 600 "$SCRIPT_DIR/.env"
  echo "[install] .env généré (clé VirusTotal vide)."
else
  echo "[install] .env présent."
fi
if [ ! -s "$SCRIPT_DIR/.env" ] || ! grep -q '^MVT_VT_API_KEY=' "$SCRIPT_DIR/.env"; then
  echo "[install] Pour utiliser VirusTotal : créez un compte gratuit"
  echo "[install]   https://www.virustotal.com/gui/join-us"
  echo "[install] puis définissez la clé dans le menu : ./start.sh config -> « VirusTotal : définir la clé API »."
fi

source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/lib/common.sh"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
  have sudo || die "Lancez ce script en tant que root ou avec les permissions sudo."
fi

# Téléchargement d'AndroidQF
install_androidqf() {
  local arch="${ANDROIDQF_ARCH:-}" tag asset_name url api
  [ -n "$arch" ] || case "$(uname -m)" in
    x86_64|amd64)  arch="amd64" ;;
    aarch64|arm64) arch="arm64"  ;;
    *)             arch="amd64"  ;;
  esac
  log_info "Téléchargement d'AndroidQF (linux $arch) depuis GitHub..."
  api="https://api.github.com/repos/mvt-project/androidqf/releases/latest"
  tag="$(curl -fsSL "$api" | python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"])')" \
    || die "Impossible d'interroger l'API GitHub."
  asset_name="$(python3 - "$api" "$arch" <<'PY'
import sys, urllib.request, json
url, arch = sys.argv[1], sys.argv[2]
try:
    data = json.load(urllib.request.urlopen(url, timeout=30))
except Exception:
    sys.exit(1)
for a in sorted(data.get("assets", []), key=lambda x: x["name"]):
    n = a["name"]
    if arch in n and "linux" in n and not any(s in n for s in (".sig", ".sha256", "unsigned", ".exe")):
        print(n)
        break
PY
)" || true
  [ -n "$asset_name" ] || die "Aucun binaire AndroidQF linux/$arch dans la dernière release."
  url="https://github.com/mvt-project/androidqf/releases/download/$tag/$asset_name"
  log_info "Téléchargement de $asset_name ..."
  curl -fSL -o "$ANDROIDQF_BIN" "$url" || die "Téléchargement d'AndroidQF échoué."
  chmod +x "$ANDROIDQF_BIN"
  log_ok "AndroidQF installé : $ANDROIDQF_BIN"
}

# Fallback : Google Platform Tools (adb) si le paquet système est absent.
install_platform_tools() {
  log_info "Téléchargement des Platform Tools Android (Google)..."
  mkdir -p "$ADB_EXTRA_DIR"
  local zip="$TOOLS_DIR/platform-tools-latest.zip"
  curl -fSL -o "$zip" "https://dl.google.com/android/repository/platform-tools-latest-linux.zip" || { rm -f "$zip"; log_warn "Téléchargement des platform-tools échoué."; return 1; }
  unzip -q -o "$zip" -d "$TOOLS_DIR"
  rm -f "$zip"
  chmod +x "$ADB_EXTRA_DIR/adb" "$ADB_EXTRA_DIR/fastboot" 2>/dev/null || true
  if [ -x "$ADB_EXTRA_DIR/adb" ]; then
    log_ok "adb (platform-tools) : $ADB_EXTRA_DIR/adb"
  else
    log_warn "Échec du téléchargement des platform-tools."
  fi
}

mkdir -p "$EVIDENCE_DIR" "$IOCS_CUSTOM_DIR" "$IOCS_MANAGED_DIR" "$TOOLS_DIR"

banner '============================================'
banner '  INSTALLATION : MVT / AndroidQF / Dépendances'
banner '============================================'
. /etc/os-release 2>/dev/null || true
log_info "OS : $(uname -s) — ${PRETTY_NAME:-inconnu}"
python3 -c 'import sys; assert sys.version_info >= (3, 6)' 2>/dev/null || die "Python 3.6+ requis."

# ------------------------------------------------------------------
# 1. Paquets système
# ------------------------------------------------------------------
log_info "Installation des paquets système utilisés pour la compilation et les IoCs..."
apt_log="$($SUDO apt-get update -qq 2>&1 || true)"
if printf '%s' "$apt_log" | grep -qiE 'not signed|pas signé|non signé|NO_PUBKEY|Missing key|OpenPGP'; then
  log_warn "apt-get update : dépôt(s) tiers non signé(s). Aucun impact sur l'outil."
fi

APKS=(
  python3 python3-venv python3-pip sqlite3
  libusb-1.0-0 libimobiledevice-utils usbmuxd
  pipx git curl wget unzip
)
for p in "${APKS[@]}"; do
  if dpkg-query -W -f='${Status}\n' "$p" 2>/dev/null | grep -q 'install ok installed'; then
    log_ok "  $p déjà installé."
  else
    log_info "  Installation de $p ..."
    if $SUDO apt-get install -y "$p" >/dev/null 2>&1; then
      log_ok "  $p installé."
    else
      log_warn "   Échec de l'installation de $p"
    fi
  fi
done

# ADB : adb (Ubuntu >= 20.10) ou android-tools-adb (Debian) … sinon platform-tools
if ! have adb; then
  log_info "Installation d'ADB (Android Debug Bridge)..."
  if ! $SUDO apt-get install -y adb >/dev/null 2>&1; then
    if ! $SUDO apt-get install -y android-tools-adb >/dev/null 2>&1; then
      log_warn "adb/apt ne fournit pas adb → téléchargement des Platform Tools Google"
      install_platform_tools
    fi
  fi
fi
have adb && log_ok "  adb : $(adb version | head -n 1)"

# ------------------------------------------------------------------
# pipx + PATH
# ------------------------------------------------------------------
log_info "Configuration de pipx ($HOME/.local/bin)..."
have pipx || die "pipx n'a pas pu être installé."
pipx ensurepath >/dev/null 2>&1 || true
export PATH="$HOME/.local/bin:$PATH"

# ------------------------------------------------------------------
# 3. MVT depuis le dépôt git
# ------------------------------------------------------------------
if have mvt; then
  log_ok "MVT déjà installé : $(command -v mvt)"
  log_info "Mise à jour forcée vers la dernière version git ..."
  pipx install --force git+https://github.com/mvt-project/mvt.git >/dev/null || log_warn "pipx install MVT a échoué."
else
  log_info "Installation de MVT depuis git (pipx)..."
  pipx install --force git+https://github.com/mvt-project/mvt.git
fi

export PATH="$HOME/.local/bin:$PATH"
for c in mvt mvt-ios mvt-android; do
  have "$c" && log_ok "  $c : $(command -v "$c")"
done

# ------------------------------------------------------------------
# 4. AndroidQF (analyse Android)
# ------------------------------------------------------------------
if [ -x "$ANDROIDQF_BIN" ]; then
  log_ok "AndroidQF déjà présent : $ANDROIDQF_BIN"
else
  install_androidqf
fi

# ------------------------------------------------------------------
# 5. Vérifications finales
# ------------------------------------------------------------------
banner '==== Vérifications ===='
ok=1
if have mvt; then
  log_ok "  MVT           OK ($(command -v mvt))"
else
  log_err "  MVT manquant"
  ok=0
fi
if have adb; then
  log_ok "  adb           OK ($(command -v adb))"
else
  log_warn "  adb manquant → configurez ADB_EXTRA_DIR dans config.sh"
fi
if have ideviceinfo; then
  log_ok "  libimobiledevice OK ($(command -v ideviceinfo))"
else
  log_warn "  libimobiledevice manquant → mvt-ios ne pourra pas créer de backups iTunes"
fi
if [ -x "$ANDROIDQF_BIN" ]; then
  log_ok "  AndroidQF     OK ($ANDROIDQF_BIN)"
else
  log_warn "  AndroidQF manquant"
fi

if [ "$ok" -eq 1 ]; then
  banner '==== Installation terminée ===='
else
  banner '==== Installation terminée (avec avertissements) ===='
fi

cat <<EOF

${C_CYAN}Étapes à faire avant l'analyse :${C_RESET}

  Sur ANDROID : 
    -> Activez le débogueur USB sur le téléphone (Paramètres > Options développeur).
  
  Sur IOS : 
    -> Branchez l'iPhone, acceptez le jumelage, rentrer le code PIN si demandé.
  
  Pour lancer une analyse : sudo ./start.sh

EOF