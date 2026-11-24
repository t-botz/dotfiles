$ErrorActionPreference = 'Stop'

$config = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'config.psd1')
$distribution = $config.Distribution
$linuxUser = $config.LinuxUser
$repo = Split-Path $PSScriptRoot -Parent

if ($distribution -notmatch '^[A-Za-z0-9._-]+$' -or $linuxUser -notmatch '^[a-z_][a-z0-9_-]*$') {
    throw 'Invalid WSL distribution or Linux username'
}

$feature = Get-CimInstance Win32_OptionalFeature | Where-Object Name -eq 'VirtualMachinePlatform'
if (-not $feature -or $feature.InstallState -ne 1) {
    $process = Start-Process wsl.exe -ArgumentList '--install','--no-distribution' -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -notin 0,3010) {
        throw "WSL feature installation failed: $($process.ExitCode)"
    }
    Write-Host 'Restart Windows, then run bootstrap again to finish WSL setup.'
    exit 3010
}

$null = & wsl.exe --version 2>$null
if ($LASTEXITCODE -ne 0) {
    $process = Start-Process wsl.exe -ArgumentList '--install','--no-distribution' -Verb RunAs -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -eq 3010) {
        Write-Host 'Restart Windows, then run bootstrap again to finish WSL setup.'
        exit 3010
    }
    if ($process.ExitCode -ne 0) {
        throw "WSL runtime installation failed: $($process.ExitCode)"
    }
}

$installed = @(& wsl.exe --list --quiet | ForEach-Object { ($_ -replace [char]0, '').Trim() })
if ($LASTEXITCODE -ne 0) {
    throw 'Could not list WSL distributions'
}

if ($distribution -notin $installed) {
    & wsl.exe --install --distribution $distribution --no-launch --web-download
    if ($LASTEXITCODE -ne 0) {
        throw 'Ubuntu installation failed. If Windows requests a restart, rerun bootstrap afterward.'
    }
}

$provision = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'provision-wsl.sh'))
($provision + "`n") | & wsl.exe --distribution $distribution --user root --exec bash -c "tr -d '\r' | bash -s -- $linuxUser"
if ($LASTEXITCODE -eq 10) {
    & wsl.exe --terminate $distribution
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not restart the configured WSL distribution'
    }
} elseif ($LASTEXITCODE -ne 0) {
    throw 'Linux account and base-package setup failed'
}

& wsl.exe --distribution $distribution --user root --exec test -e "/home/$linuxUser/.dotfiles-needs-password"
if ($LASTEXITCODE -eq 0) {
    Write-Host 'Set the new Linux account password in the window that opens.'
    $password = Start-Process wsl.exe -ArgumentList '--distribution',$distribution,'--user','root','--exec','passwd',$linuxUser -WindowStyle Normal -Wait -PassThru
    if ($password.ExitCode -ne 0) {
        throw 'Linux password setup was not completed; rerun bootstrap to retry.'
    }
    & wsl.exe --distribution $distribution --user root --exec rm "/home/$linuxUser/.dotfiles-needs-password"
}

$nixInstaller = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'install-nix.sh'))
($nixInstaller + "`n") | & wsl.exe --distribution $distribution --user root --exec bash -c "tr -d '\r' | bash -se"
if ($LASTEXITCODE -ne 0) {
    throw 'Nix installation failed'
}

# Use the checkout that invoked bootstrap, so subsequent edits are applied too.
$linuxRepo = (& wsl.exe --distribution $distribution --user $linuxUser --exec wslpath -u $repo).Trim()
if ($LASTEXITCODE -ne 0 -or -not $linuxRepo) {
    throw 'Could not resolve the Windows checkout in WSL'
}
& wsl.exe --distribution $distribution --user $linuxUser --exec test -f "$linuxRepo/bootstrap.sh"
if ($LASTEXITCODE -ne 0) {
    throw 'The Windows checkout is not accessible from WSL. Enable Windows drive mounting or run bootstrap.sh from a Linux checkout.'
}
& wsl.exe --distribution $distribution --user $linuxUser --exec bash "$linuxRepo/bootstrap.sh"
if ($LASTEXITCODE -ne 0) {
    throw 'Linux bootstrap failed'
}

$linuxShell = "/home/$linuxUser/.nix-profile/bin/zsh"
& wsl.exe --distribution $distribution --user root --exec test -x $linuxShell
if ($LASTEXITCODE -ne 0) {
    throw 'The configured Linux shell is missing'
}
& wsl.exe --distribution $distribution --user root --exec /usr/sbin/usermod --shell $linuxShell $linuxUser
if ($LASTEXITCODE -ne 0) {
    throw 'Could not select the configured Linux shell'
}

& wsl.exe --set-default $distribution
if ($LASTEXITCODE -ne 0) {
    throw 'Could not select the configured default distribution'
}

Write-Host "$distribution is configured. Other WSL distributions have been preserved."
exit 0
