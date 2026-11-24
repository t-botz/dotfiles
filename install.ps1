# Downloadable Windows entry point. Run with built-in Windows PowerShell or PowerShell 7.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repoUrl = if ($env:DOTFILES_REPO_URL) { $env:DOTFILES_REPO_URL } else { 'https://github.com/t-botz/dotfiles.git' }
$ref = if ($env:DOTFILES_REF) { $env:DOTFILES_REF } else { 'main' }
$target = if ($env:DOTFILES_DIR) { $env:DOTFILES_DIR } else { Join-Path $HOME 'workspace\dotfiles' }

if (Test-Path $target) {
    if (-not (Test-Path (Join-Path $target '.git')) -or
        -not (Test-Path (Join-Path $target 'bootstrap.ps1'))) {
        throw "Refusing existing non-checkout: $target"
    }
} else {
    $git = Join-Path $env:ProgramFiles 'Git\cmd\git.exe'
    if (-not (Test-Path $git)) {
        Write-Host 'Preparing Windows app installer...'
        if (-not (Get-Module Microsoft.WinGet.Client -ListAvailable)) {
            if (-not (Get-PackageProvider NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
                Install-PackageProvider NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
            }
            Install-Module Microsoft.WinGet.Client -Scope CurrentUser -Repository PSGallery -Force
        }
        Import-Module Microsoft.WinGet.Client
        Repair-WinGetPackageManager -Latest

        $app = Get-AppxPackage -Name Microsoft.DesktopAppInstaller |
            Sort-Object Version -Descending | Select-Object -First 1
        $winget = if ($app.InstallLocation) {
            Join-Path $app.InstallLocation 'winget.exe'
        } else {
            (Get-Command winget.exe -CommandType Application -ErrorAction Stop).Source
        }
        & $winget install --id Git.Git --exact --source winget --no-upgrade --silent --disable-interactivity --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw 'Git installation failed'
        }
    }

    New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
    $staging = "$target-clone-$([guid]::NewGuid().ToString('N'))"
    & $git clone --branch $ref --single-branch $repoUrl $staging
    if ($LASTEXITCODE -ne 0) {
        throw "Clone failed; staging files remain at $staging"
    }
    $sourcePath = [IO.Path]::GetFullPath($staging)
    $targetPath = [IO.Path]::GetFullPath($target)
    if ((Split-Path $sourcePath -Parent) -ne (Split-Path $targetPath -Parent) -or
        -not (Split-Path $sourcePath -Leaf).StartsWith((Split-Path $targetPath -Leaf) + '-clone-')) {
        throw 'Refusing to move a checkout outside its staging parent'
    }
    Move-Item -LiteralPath $sourcePath -Destination $targetPath
}

$LASTEXITCODE = 0
& (Join-Path $target 'bootstrap.ps1')
exit $LASTEXITCODE
