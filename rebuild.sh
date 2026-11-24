#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if ! command -v nix >/dev/null 2>&1 &&
  [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "Run ./bootstrap.sh first." >&2
  exit 1
fi

USER="$(id -un)"
export USER

# Escape URI syntax while preserving the directory path.
flake_dir="${DIR//%/%25}"
flake_dir="${flake_dir// /%20}"
flake_dir="${flake_dir//#/%23}"
flake_dir="${flake_dir//\?/%3F}"

case "$(uname -s)" in
  Darwin)
    if [[ "$USER" != tibo || "$(uname -m)" != arm64 ]]; then
      echo "Mac target requires Apple Silicon and user tibo." >&2
      exit 1
    fi

    nix build "path:$flake_dir#darwinConfigurations.mac.system" \
      --out-link "$DIR/result"
    sudo "$DIR/result/sw/bin/darwin-rebuild" switch --flake "path:$flake_dir#mac"
    profile_bin="/etc/profiles/per-user/$USER/bin"
    ;;
  Linux)
    if ! grep -qi microsoft /proc/sys/kernel/osrelease; then
      echo "Expected WSL" >&2
      exit 1
    fi

    result="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/result"
    mkdir -p "$(dirname "$result")"
    nix build --impure "path:$flake_dir#homeConfigurations.wsl.activationPackage" \
      --out-link "$result"

    HOME_MANAGER_BACKUP_EXT="before-nix-$(date +%s)-$$"
    export HOME_MANAGER_BACKUP_EXT
    "$result/activate"
    profile_bin="$HOME/.nix-profile/bin"
    ;;
  *)
    echo "Unsupported platform" >&2
    exit 1
    ;;
esac

# Newly activated tools must also be available in this running shell.
export PATH="$profile_bin:$PATH"

# Install from the home directory so project configuration does not affect setup.
(
  cd "$HOME"
  mise install
)
