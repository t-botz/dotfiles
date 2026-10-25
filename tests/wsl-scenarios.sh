#!/usr/bin/env bash
set -euo pipefail

[[ "$(id -un)" == tester ]]
[[ ! -d /nix ]]
if command -v git; then
  echo 'Expected no Git' >&2
  exit 1
fi
if mount | grep -q ' on /mnt/c '; then
  echo 'Windows drive is mounted' >&2
  exit 1
fi
[[ -z "${WSL_INTEROP:-}" ]]

cd /tmp/payload
python3 -m http.server 8765 --bind 127.0.0.1 >/tmp/dotfiles-http.log 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT

for ((attempt = 0; attempt < 30; attempt++)); do
  if curl -fsS http://127.0.0.1:8765/install.sh -o /tmp/install.sh 2>/dev/null; then
    break
  fi
  sleep 1
done
test -s /tmp/install.sh
export DOTFILES_REPO_URL=http://127.0.0.1:8765/fixture/.git
export DOTFILES_DIR="$HOME/workspace/dotfiles"
export DOTFILES_REF=main
mkdir -p "$HOME/.config"
printf 'original zsh config\n' > "$HOME/.zshrc"
bash /tmp/install.sh
echo 'PASS fresh-install'

. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
# Home Manager's generated session script expects ordinary shell semantics.
set +u
. "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
set -u
export PATH="$HOME/.nix-profile/bin:$PATH"
zsh -lic '
  set -e
  git --version
  mise --version
  starship --version
  zoxide --version
  whence -w gclone
  alias ll
'
echo 'PASS new-shell'
grep -q 'original zsh config' "$HOME"/.zshrc.before-nix-*
echo 'PASS conflict-backup'

printf '\n# local test edit\n' >> "$DOTFILES_DIR/home.nix"
printf 'keep me\n' > "$DOTFILES_DIR/local-note"
bash /tmp/install.sh
first="$(readlink "$DOTFILES_DIR/result")"
grep -q '# local test edit' "$DOTFILES_DIR/home.nix"
[[ "$(cat "$DOTFILES_DIR/local-note")" == 'keep me' ]]
echo 'PASS rerun-preserves-local-edits'

# Refuse an unrelated directory and leave its contents intact.
mkdir "$HOME/not-a-checkout"
printf 'sentinel\n' > "$HOME/not-a-checkout/file"
if DOTFILES_DIR="$HOME/not-a-checkout" bash /tmp/install.sh; then
  exit 1
fi
grep -qx sentinel "$HOME/not-a-checkout/file"
echo 'PASS unrelated-directory-refusal'

# Controlled failure after Nix installation, before clone completes.
if DOTFILES_DIR="$HOME/recovery" DOTFILES_REF=missing-branch bash /tmp/install.sh; then
  exit 1
fi
[[ ! -e "$HOME/recovery" ]]
DOTFILES_DIR="$HOME/recovery" bash /tmp/install.sh
echo 'PASS failed-clone-recovery'

mkdir "$HOME/tiny-project"
cd "$HOME/tiny-project"
# Exercise one runtime without installing all globally declared AI toolchains.
# Go uses official Go downloads/checksums, independent of GitHub's API quota.
printf '%s\n' \
  'package main' \
  'import "fmt"' \
  'func main() { fmt.Println(6 * 7) }' > main.go
actual="$(CGO_ENABLED=0 mise --no-config exec go@latest -- go run main.go)"
[[ "$actual" == 42 ]]
echo 'PASS runtime-project'

# Repeat activation with unchanged source and verify the generation output.
bash "$DOTFILES_DIR/rebuild.sh"
[[ "$(readlink "$DOTFILES_DIR/result")" == "$first" ]]
echo 'PASS unchanged-build-output'
echo 'ALL SCENARIOS PASSED'
