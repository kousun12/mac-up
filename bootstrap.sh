#!/bin/bash
# Bootstrap the current user on a Mac. No Homebrew or existing Git required.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--dry-run] [--skip-clt] [--always-on] [--hostname NAME]
       ./bootstrap.sh --doctor

  --dry-run        Print the planned changes without making them or using the network.
  --skip-clt       Skip Apple's Command Line Tools install/update check on this run.
  --always-on      Keep this Mac awake on AC power and guide remote access setup.
  --hostname NAME  Set this Mac's network name (Bonjour, SMB, and Tailscale if present).
  --doctor         Check local tools, apps, and preferences without changing anything.
EOF
}

DRY_RUN=0
SKIP_CLT=0
ALWAYS_ON=0
DOCTOR=0
HOSTNAME_TARGET=
while (( $# )); do
  case $1 in
    --dry-run) DRY_RUN=1 ;;
    --skip-clt) SKIP_CLT=1 ;;
    --always-on) ALWAYS_ON=1 ;;
    --hostname)
      shift
      if (( ! $# )) || [[ -z $1 ]]; then
        usage >&2
        exit 64
      fi
      HOSTNAME_TARGET=$1
      ;;
    --hostname=*)
      HOSTNAME_TARGET=${1#--hostname=}
      if [[ -z $HOSTNAME_TARGET ]]; then
        usage >&2
        exit 64
      fi
      ;;
    --doctor) DOCTOR=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac
  shift
done

if (( DOCTOR && (DRY_RUN || SKIP_CLT || ALWAYS_ON) )) ||
   { (( DOCTOR )) && [[ -n $HOSTNAME_TARGET ]]; }; then
  usage >&2
  exit 64
fi

if [[ -n $HOSTNAME_TARGET ]]; then
  if (( ${#HOSTNAME_TARGET} > 63 )) ||
     [[ ! $HOSTNAME_TARGET =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]; then
    printf 'Invalid hostname: %s (use 1-63 ASCII letters, digits, or internal hyphens).\n' "$HOSTNAME_TARGET" >&2
    exit 64
  fi
fi

if [[ $(/usr/bin/uname -s) != Darwin ]]; then
  printf 'mac-up only runs on macOS.\n' >&2
  exit 1
fi

if (( DRY_RUN )); then
  if (( ! SKIP_CLT )); then
    printf '%s\n' '• Start Apple’s Command Line Tools installer or install the newest stable CLT update offered for this macOS.'
  fi
  printf '%s\n' \
    '• Set /bin/zsh as the login shell if needed; add a managed config without replacing .zshrc.' \
    '• Install nvm, uv, uvx, fx, rg, jq, fzf, gh, and zsh-syntax-highlighting if missing.' \
    '• Configure gh as Git’s GitHub HTTPS credential helper if signed in.' \
    '• Install Ghostty, Rectangle, and current stable Google Chrome if missing.' \
    '• Restore Rectangle shortcuts and configure Rectangle to open at login.' \
    '• Restore fast repeat with a short initial delay and mouse/trackpad tracking speeds.' \
    '• Set Caps Lock to Control for detected keyboards without replacing existing modifier mappings.' \
    '• Install Tailscale if missing.'
  if [[ -n $HOSTNAME_TARGET ]]; then
    printf '• Set ComputerName, LocalHostName, SMB NetBIOSName, and Tailscale hostname to %s.\n' "$HOSTNAME_TARGET"
  fi
  if (( ALWAYS_ON )); then
    printf '%s\n' \
      '• Disable idle system sleep on AC power and enable restart after power loss if supported.' \
      '• Finish manually in System Settings > General > Sharing: enable Remote Login and Screen Sharing for selected users.'
  fi
  exit 0
fi

if (( EUID == 0 )); then
  printf 'Run this as your normal logged-in user, not with sudo.\n' >&2
  exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source "$ROOT/lib/settings.sh"
warn() { printf 'Warning: %s\n' "$*" >&2; }

MACOS_VERSION=$(/usr/bin/sw_vers -productVersion)
MACOS_MAJOR=${MACOS_VERSION%%.*}
if (( DOCTOR )); then
  source "$ROOT/lib/doctor.sh"
  run_doctor
  exit 0
fi

source "$ROOT/lib/install.sh"
if (( MACOS_MAJOR < 14 )); then
  warn 'mac-up requires macOS 14 or later for the full app setup.'
  exit 1
fi
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mac-up.XXXXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
CLT_PENDING=0

if (( ! SKIP_CLT )); then
  configure_clt
fi
login_shell
install_zsh_config
install_developer_tools
install_portable_tools
install_fzf
install_github_cli
configure_github_credentials
install_apps
configure_rectangle
input_preferences
configure_caps_lock
install_tailscale
if [[ -n $HOSTNAME_TARGET ]]; then
  configure_hostname "$HOSTNAME_TARGET"
fi
if (( ALWAYS_ON )); then
  configure_always_on
fi

printf '\nOpen a new terminal tab for zsh changes. Log out and back in for keyboard and pointer settings.\n'
printf 'At Rectangle’s first launch, grant Accessibility permission and choose the Rectangle preset if asked.\n'
printf 'Open Tailscale, approve its VPN setup, and sign in to your tailnet.\n'
if (( ALWAYS_ON )); then
  always_on_sharing_instructions
fi
if (( CLT_PENDING )); then
  warn 'Command Line Tools are pending. Finish Apple’s install/update, then rerun ./bootstrap.sh.'
  exit 2
fi
