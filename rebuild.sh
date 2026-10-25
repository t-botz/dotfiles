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

case "$(uname -s)" in
  Darwin)
    if [[ "$USER" != tibo || "$(uname -m)" != arm64 ]]; then
      echo "Mac target requires Apple Silicon and user tibo." >&2
      exit 1
    fi

    nix build "path:$DIR#darwinConfigurations.mac.system" \
      --out-link "$DIR/result"
    sudo "$DIR/result/sw/bin/darwin-rebuild" switch --flake "path:$DIR#mac"
    ;;
  Linux)
    if ! grep -qi microsoft /proc/sys/kernel/osrelease; then
      echo "Expected WSL" >&2
      exit 1
    fi

    nix build --impure "path:$DIR#homeConfigurations.wsl.activationPackage" \
      --out-link "$DIR/result"

    HOME_MANAGER_BACKUP_EXT="before-nix-$(date +%s)-$$"
    export HOME_MANAGER_BACKUP_EXT
    "$DIR/result/activate"
    ;;
  *)
    echo "Unsupported platform" >&2
    exit 1
    ;;
esac

# Install from the home directory so project configuration does not affect setup.
(
  cd "$HOME"
  mise install
)
