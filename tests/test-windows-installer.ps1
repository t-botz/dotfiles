[CmdletBinding()]
param([string]$WorkDir = (Join-Path $env:TEMP 'dotfiles-installer-tests'))

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$WorkDir = [IO.Path]::GetFullPath($WorkDir)
$name = 'dotfiles-installer-' + [guid]::NewGuid().ToString('N')
$root = Join-Path $WorkDir $name
$origin = Join-Path $root 'source repo'
$target = Join-Path $root 'installed config'
$entry = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
$legacyPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$git = Join-Path $env:ProgramFiles 'Git\cmd\git.exe'
$passed = $false
$saved = @{}

if (-not (Test-Path $git)) {
    throw 'Run this checkout-contract test on a machine with Git; clean Git installation is covered by the VM suite'
}
New-Item -ItemType Directory -Force $origin | Out-Null
foreach ($variable in @('DOTFILES_REPO_URL', 'DOTFILES_DIR', 'DOTFILES_REF')) {
    $saved[$variable] = [Environment]::GetEnvironmentVariable($variable, 'Process')
}

Start-Transcript (Join-Path $WorkDir "$name.log")
try {
    # A small fixture checks clone and bootstrap dispatch independently of WSL.
    $bootstrap = 'Set-Content -LiteralPath (Join-Path $PSScriptRoot ''bootstrap-ran'') -Value ''called'''
    [IO.File]::WriteAllText((Join-Path $origin 'bootstrap.ps1'), $bootstrap + "`n")
    & $git -C $origin init -b main
    if ($LASTEXITCODE) { throw 'Fixture initialization failed' }
    & $git -C $origin -c core.autocrlf=false add .
    if ($LASTEXITCODE) { throw 'Fixture staging failed' }
    & $git -C $origin -c user.name=Test -c user.email=test@example.invalid commit -m 'Installer fixture'
    if ($LASTEXITCODE) { throw 'Fixture commit failed' }

    $env:DOTFILES_REPO_URL = $origin
    $env:DOTFILES_DIR = $target
    $env:DOTFILES_REF = 'main'
    & $legacyPowerShell -NoProfile -ExecutionPolicy Bypass -File $entry
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $target 'bootstrap-ran'))) {
        throw 'Fresh clone or bootstrap dispatch failed'
    }
    Write-Host 'PASS windows-installer-clone-and-dispatch'

    Add-Content -LiteralPath (Join-Path $target 'bootstrap.ps1') -Value '# local edit'
    [IO.File]::WriteAllText((Join-Path $target 'local-note'), 'keep me')
    & $legacyPowerShell -NoProfile -ExecutionPolicy Bypass -File $entry
    if ($LASTEXITCODE -ne 0 -or
        -not ((Get-Content (Join-Path $target 'bootstrap.ps1')) -contains '# local edit') -or
        [IO.File]::ReadAllText((Join-Path $target 'local-note')) -ne 'keep me') {
        throw 'Existing checkout edits were not preserved'
    }
    Write-Host 'PASS windows-installer-preserves-local-edits'

    $statusTarget = Join-Path $root 'status checkout'
    New-Item -ItemType Directory (Join-Path $statusTarget '.git') | Out-Null
    $env:DOTFILES_DIR = $statusTarget
    foreach ($status in @(3010, 17)) {
        [IO.File]::WriteAllText((Join-Path $statusTarget 'bootstrap.ps1'), "exit $status")
        & $legacyPowerShell -NoProfile -ExecutionPolicy Bypass -File $entry
        if ($LASTEXITCODE -ne $status) {
            throw "Bootstrap status $status was not returned by the installer"
        }
    }
    Write-Host 'PASS windows-installer-propagates-bootstrap-status'

    $unrelated = Join-Path $root 'unrelated directory'
    New-Item -ItemType Directory $unrelated | Out-Null
    [IO.File]::WriteAllText((Join-Path $unrelated 'file'), 'sentinel')
    $env:DOTFILES_DIR = $unrelated
    & $legacyPowerShell -NoProfile -ExecutionPolicy Bypass -File $entry 2>&1 | ForEach-Object { Write-Host "$_" }
    if ($LASTEXITCODE -eq 0 -or [IO.File]::ReadAllText((Join-Path $unrelated 'file')) -ne 'sentinel') {
        throw 'An unrelated directory was not safely refused'
    }
    Write-Host 'PASS windows-installer-unrelated-directory-refusal'

    $env:DOTFILES_DIR = Join-Path $root 'recovery checkout'
    $env:DOTFILES_REF = 'missing-branch'
    & $legacyPowerShell -NoProfile -ExecutionPolicy Bypass -File $entry 2>&1 | ForEach-Object { Write-Host "$_" }
    if ($LASTEXITCODE -eq 0 -or (Test-Path $env:DOTFILES_DIR)) {
        throw 'A failed clone left an active destination'
    }
    $env:DOTFILES_REF = 'main'
    & $legacyPowerShell -NoProfile -ExecutionPolicy Bypass -File $entry
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $env:DOTFILES_DIR 'bootstrap-ran'))) {
        throw 'Clone recovery failed'
    }
    Write-Host 'PASS windows-installer-failed-clone-recovery'
    $passed = $true
} finally {
    foreach ($variable in $saved.Keys) {
        [Environment]::SetEnvironmentVariable($variable, $saved[$variable], 'Process')
    }
    Stop-Transcript
    if ($passed) {
        $resolved = [IO.Path]::GetFullPath($root)
        if ((Split-Path $resolved -Parent) -ne $WorkDir -or (Split-Path $resolved -Leaf) -ne $name) {
            throw 'Refusing cleanup outside the generated installer fixture'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    } else {
        Write-Host "Retained installer fixture: $root"
    }
}
