$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'windows\setup.ps1')
& (Join-Path $PSScriptRoot 'windows\setup-wsl.ps1')
if ($LASTEXITCODE -eq 3010) {
    exit 3010
}
