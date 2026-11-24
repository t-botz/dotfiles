# Dotfiles

My system config.

## Setup

macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/t-botz/dotfiles/main/install.sh -o /tmp/dotfiles-install.sh
bash /tmp/dotfiles-install.sh
```

From an existing checkout, run `bash bootstrap.sh`.

Windows:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/t-botz/dotfiles/main/install.ps1 -OutFile "$env:TEMP\dotfiles-install.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\dotfiles-install.ps1"
```

From an existing checkout, run `powershell -ExecutionPolicy Bypass -File bootstrap.ps1`.

## Everyday commands

```sh
bash rebuild.sh                           # apply configuration
nix flake update && bash rebuild.sh         # update Nix dependencies
mise upgrade                              # update installed runtimes
```

Windows apps: `winget upgrade --all`.

## Test

See [test setup](tests/README.md).

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\new-windows-vm.ps1 -IsoPath C:\Windows11.iso
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\test-windows.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\test-windows-installer.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\test-wsl.ps1
```
