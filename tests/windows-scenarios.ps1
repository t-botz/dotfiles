$ErrorActionPreference = 'Stop'

$machine = Get-CimInstance Win32_ComputerSystem
if ($machine.Model -notmatch 'VirtualBox' -or -not (Test-Path 'C:\dotfiles-test-vm')) {
    throw 'These destructive fixture scenarios must run only in the disposable test VM'
}

$repo = Split-Path $PSScriptRoot -Parent
$config = Import-PowerShellDataFile (Join-Path $repo 'windows\config.psd1')
$terminalConfig = Join-Path $HOME '.wezterm.lua'
$font = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts\FiraCodeNerdFont-Regular.ttf'
$log = Join-Path $HOME 'dotfiles-windows-test.log'

$passed = $false
Start-Transcript $log
try {
    foreach ($program in @('Git\cmd\git.exe', 'PowerShell\7\pwsh.exe', 'WezTerm\wezterm.exe')) {
        if (Test-Path (Join-Path $env:ProgramFiles $program)) {
            throw "Expected a clean Windows baseline without $program"
        }
    }

    if (Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction SilentlyContinue) {
        throw 'Expected a clean Windows baseline without PowerShell 7'
    }

    if (Test-Path $terminalConfig) {
        throw 'Expected a clean Windows baseline without terminal configuration'
    }
    if (Test-Path $font) {
        throw 'Expected a clean Windows baseline without the managed font'
    }

    $fontRegistry = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path $fontRegistry)) {
        New-Item -Path $fontRegistry | Out-Null
    }
    $unrelatedFont = Join-Path $env:WINDIR 'Fonts\consola.ttf'
    New-ItemProperty -Path $fontRegistry -Name 'Consolas (TrueType)' -Value $unrelatedFont -PropertyType String -Force | Out-Null

    [IO.File]::WriteAllText($terminalConfig, '-- original user configuration')
    $sentinel = Join-Path $HOME 'unrelated-user-file.txt'
    [IO.File]::WriteAllText($sentinel, 'keep me')

    & (Join-Path $repo 'windows\setup.ps1')
    Write-Host 'PASS fresh-windows-setup'

    $sourceHash = (Get-FileHash (Join-Path $repo 'home\wezterm.lua')).Hash
    if ((Get-FileHash $terminalConfig).Hash -ne $sourceHash -or -not (Test-Path $font)) {
        throw 'Terminal configuration or font is missing'
    }

    $backups = @(Get-ChildItem "$terminalConfig.before-dotfiles-*")
    if ($backups.Count -ne 1 -or [IO.File]::ReadAllText($backups[0].FullName) -ne '-- original user configuration') {
        throw 'Original configuration backup was not preserved'
    }
    Write-Host 'PASS configuration-backup'
    if ((Get-ItemPropertyValue $fontRegistry -Name 'Consolas (TrueType)') -ne $unrelatedFont) {
        throw 'An unrelated font registration was changed'
    }
    Write-Host 'PASS existing-font-registration-preserved'

    & (Join-Path $env:ProgramFiles 'Git\cmd\git.exe') --version
    if ($LASTEXITCODE -ne 0) { throw 'Git is not runnable' }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    & (Get-Command pwsh.exe -ErrorAction Stop).Source -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
    if ($LASTEXITCODE -ne 0) { throw 'PowerShell is not runnable' }
    $fontOutput = & (Join-Path $env:ProgramFiles 'WezTerm\wezterm.exe') --config-file $terminalConfig ls-fonts --text Dotfiles
    if ($LASTEXITCODE -ne 0 -or -not ($fontOutput -match 'FIRACODENERDFONT-REGULAR.TTF')) {
        throw 'WezTerm could not load the shared configuration and managed font'
    }
    Write-Host 'PASS native-tools-and-terminal'

    $fontHash = (Get-FileHash $font).Hash
    & (Join-Path $repo 'windows\setup.ps1')
    if (@(Get-ChildItem "$terminalConfig.before-dotfiles-*").Count -ne 1 -or
        (Get-FileHash $font).Hash -ne $fontHash) {
        throw 'An unchanged rerun modified configuration or font state'
    }
    if ([IO.File]::ReadAllText($sentinel) -ne 'keep me') {
        throw 'An unrelated user file was modified'
    }
    Write-Host 'PASS idempotent-windows-rerun'
    Write-Host 'ALL WINDOWS SCENARIOS PASSED'
    $passed = $true
} catch {
    Write-Host ($_ | Out-String)
    throw
} finally {
    Stop-Transcript
    [IO.File]::WriteAllText((Join-Path $HOME 'dotfiles-windows-result.txt'), [string]$passed)
}
