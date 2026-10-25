#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

case "$(uname -s)" in
  Darwin)
    ;;
  Linux)
    if ! grep -qi microsoft /proc/sys/kernel/osrelease; then
      echo "Expected WSL" >&2
      exit 1
    fi
    ;;
  *)
    echo "Unsupported platform" >&2
    exit 1
    ;;
esac

if [[ "$(id -u)" == 0 ]]; then
  echo "Run as your normal user, not root." >&2
  exit 1
fi

if ! command -v nix >/dev/null 2>&1 &&
  [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

if ! command -v nix >/dev/null 2>&1; then
  installer="$(mktemp)"
  trap 'rm -f "$installer"' EXIT

  curl --proto '=https' --tlsv1.2 -fsSL \
    https://install.determinate.systems/nix -o "$installer"
  sh "$installer" install --no-confirm

  rm -f "$installer"
  trap - EXIT
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

exec bash "$DIR/rebuild.sh"
