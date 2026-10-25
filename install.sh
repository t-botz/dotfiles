#!/usr/bin/env bash
# Downloadable entry point. No Git or pre-existing checkout required.
set -euo pipefail

if [[ "$(id -u)" == 0 ]]; then
  echo "Run as your normal user, not root." >&2
  exit 1
fi

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

repo="${DOTFILES_REPO_URL:-https://github.com/t-botz/dotfiles.git}"
ref="${DOTFILES_REF:-main}"
target="${DOTFILES_DIR:-$HOME/workspace/github.com/t-botz/dotfiles}"

if [[ -e "$target" ]]; then
  if [[ ! -d "$target/.git" || ! -f "$target/bootstrap.sh" ]]; then
    echo "Refusing existing non-checkout: $target" >&2
    exit 1
  fi
else
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

  mkdir -p "$(dirname "$target")"

  # Stage the clone so a failed download leaves no partial target.
  staging="$(mktemp -d "$(dirname "$target")/.dotfiles-clone.XXXXXX")"
  trap 'rm -rf "$staging"' EXIT

  nix --extra-experimental-features 'nix-command flakes' \
    shell nixpkgs#git --command \
    git clone --branch "$ref" --single-branch "$repo" "$staging"

  mv "$staging" "$target"
  trap - EXIT
fi

exec bash "$target/bootstrap.sh"
