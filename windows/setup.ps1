$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')
$config = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'config.psd1')
$repo = Split-Path $PSScriptRoot -Parent

Initialize-WinGet

foreach ($package in $config.Packages) {
    Install-WindowsPackage $package
}

& (Join-Path $PSScriptRoot 'fonts.ps1')

Copy-ManagedFile (Join-Path $repo 'home\wezterm.lua') (Join-Path $HOME '.wezterm.lua')
foreach ($destination in @('.codex\AGENTS.md', '.claude\CLAUDE.md', '.config\opencode\AGENTS.md')) {
    Copy-ManagedFile (Join-Path $repo 'home\AGENTS.md') (Join-Path $HOME $destination)
}
Write-Host 'Windows apps, font and terminal configuration are ready.'
