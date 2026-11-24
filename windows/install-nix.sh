#!/usr/bin/env bash
set -euo pipefail

if [[ -x /nix/var/nix/profiles/default/bin/nix ]]; then
  exit 0
fi

installer="$(mktemp)"
trap 'rm -f "$installer"' EXIT

curl --proto '=https' --tlsv1.2 -fsSL \
  https://install.determinate.systems/nix -o "$installer"
sh "$installer" install --no-confirm
