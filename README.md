# Dotfiles

My system config.

## Setup

macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/t-botz/dotfiles/main/install.sh -o /tmp/dotfiles-install.sh
bash /tmp/dotfiles-install.sh
```

From an existing checkout, run `bash bootstrap.sh`.

## Everyday commands

```sh
bash rebuild.sh                           # apply configuration
nix flake update && bash rebuild.sh         # update Nix dependencies
mise upgrade                              # update installed runtimes
```

## Test

```powershell
pwsh -NoProfile -File .\tests\test-wsl.ps1
```
