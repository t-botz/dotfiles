$ErrorActionPreference = 'Stop'

function Initialize-WinGet {
    Write-Host 'Preparing Windows app installer...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not (Get-Module Microsoft.WinGet.Client -ListAvailable)) {
        if (-not (Get-PackageProvider NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
        }
        Install-Module Microsoft.WinGet.Client -Scope CurrentUser -Repository PSGallery -Force
    }

    Import-Module Microsoft.WinGet.Client
    # Old clients can reject Store certificates after their pinned values change.
    Repair-WinGetPackageManager -Latest
}

function Get-WinGetPath {
    # Calling the registered executable avoids AppExecutionAlias argument races.
    $app = Get-AppxPackage -Name Microsoft.DesktopAppInstaller |
        Sort-Object Version -Descending | Select-Object -First 1
    if ($app.InstallLocation) {
        $executable = Join-Path $app.InstallLocation 'winget.exe'
        if (Test-Path $executable) {
            return $executable
        }
    }
    return (Get-Command winget.exe -CommandType Application -ErrorAction Stop).Source
}
function Install-WindowsPackage {
    param([hashtable]$Package)

    foreach ($path in $Package.Paths) {
        if (Test-Path ([Environment]::ExpandEnvironmentVariables($path))) {
            Write-Host "Already installed: $($Package.Id)"
            return
        }
    }

    if ($Package.Appx -and (Get-AppxPackage -Name $Package.Appx -ErrorAction SilentlyContinue)) {
        Write-Host "Already installed: $($Package.Id)"
        return
    }

    $winget = Get-WinGetPath
    & $winget list --id $Package.Id --exact --source $Package.Source --disable-interactivity --accept-source-agreements | Out-Host
    if ($LASTEXITCODE -eq 0) {
        return
    }

    $installArgs = @(
        'install', '--id', $Package.Id, '--exact', '--source', $Package.Source
        '--no-upgrade', '--silent', '--disable-interactivity'
        '--accept-source-agreements', '--accept-package-agreements'
    )
    & $winget @installArgs | Out-Host
    # Some MSIX packages require an administrator token even for per-user setup.
    if ($LASTEXITCODE -eq -2147009240) {
        Write-Host "$($Package.Id) requires administrator access; requesting elevation."
        $installer = Start-Process $winget -Verb RunAs -ArgumentList $installArgs -WindowStyle Hidden -Wait -PassThru
        if ($installer.ExitCode -ne 0) {
            throw "Elevated installation failed for $($Package.Id): $($installer.ExitCode)"
        }
        Write-Host "Installed: $($Package.Id)"
        return
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Installation failed for $($Package.Id): $LASTEXITCODE"
    }
}

function Copy-ManagedFile {
    param([string]$Source, [string]$Destination)

    if (Test-Path $Destination) {
        if ((Get-FileHash $Source).Hash -eq (Get-FileHash $Destination).Hash) {
            return
        }

        $backup = "$Destination.before-dotfiles-$([guid]::NewGuid().ToString('N'))"
        Copy-Item -LiteralPath $Destination -Destination $backup
        Write-Host "Backed up: $backup"
    }

    New-Item -ItemType Directory -Force (Split-Path $Destination -Parent) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}
