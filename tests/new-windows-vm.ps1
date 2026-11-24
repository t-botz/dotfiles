[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [string]$WorkDir = (Join-Path $env:LOCALAPPDATA 'dotfiles-vm-tests'),
    [string]$Name = 'dotfiles-windows-base'
)

$ErrorActionPreference = 'Stop'
$vbox = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
$WorkDir = [IO.Path]::GetFullPath($WorkDir)
$IsoPath = (Resolve-Path $IsoPath).Path

if ($Name -notmatch '^dotfiles-windows-base[a-zA-Z0-9-]*$') {
    throw 'Use a dotfiles-windows-base name for disposable test machines'
}
if (-not (Test-Path $vbox)) {
    throw 'Install Oracle VirtualBox before creating the test VM'
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
$passwordFile = Join-Path $WorkDir 'test-password.txt'

function VBox {
    & $vbox @args 2>&1 | Where-Object { "$_" -notmatch '(?i)password\s*=' } | ForEach-Object { Write-Host "$_" }
    if ($LASTEXITCODE -ne 0) {
        throw "VirtualBox command failed: $($args[0])"
    }
}

$info = & $vbox showvminfo $Name --machinereadable 2>$null
if ($LASTEXITCODE -ne 0) {
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($WorkDir))
    if ($drive.AvailableFreeSpace -lt 45GB) {
        throw 'Keep at least 45 GiB free on the test drive before creating a Windows baseline'
    }

    if (-not (Test-Path $passwordFile)) {
        [IO.File]::WriteAllText($passwordFile, [guid]::NewGuid().ToString('N') + 'aA1!')
    }

    VBox createvm --name $Name --ostype Windows11_64 --basefolder $WorkDir --register
    # Avoid the two-vCPU EFI hang on WHPX: VirtualBox issue #799.
    VBox modifyvm $Name --memory 4096 --cpus 3 --firmware efi64 --tpm-type 2.0 --graphicscontroller vboxsvga --vram 128 --nic1 nat --clipboard-mode disabled --drag-and-drop disabled --nested-hw-virt off

    $disk = Join-Path (Join-Path $WorkDir $Name) 'system.vdi'
    VBox createmedium disk --filename $disk --size 65536 --format VDI
    VBox storagectl $Name --name SATA --add sata --controller IntelAhci
    VBox storageattach $Name --storagectl SATA --port 0 --device 0 --type hdd --medium $disk
    # Test-only automatic installer consent; the host retains its normal UAC policy.
    $postInstall = 'reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f && shutdown.exe /s /f /t 5'
    VBox unattended install $Name --iso $IsoPath --user tester --user-password-file $passwordFile --full-user-name 'Dotfiles Test' --hostname dotfiles-base.test --locale en_US --country AU --time-zone UTC --image-index 1 --install-additions --post-install-command $postInstall --start-vm headless
} else {
    $expected = Join-Path (Join-Path $WorkDir $Name) "$Name.vbox"
    if (-not ($info -contains ('CfgFile="' + $expected.Replace('\','\\') + '"')) -and
        -not ($info -contains ('CfgFile="' + $expected + '"'))) {
        throw 'An existing VM with this name is outside the requested test directory'
    }
    if (-not (Test-Path $passwordFile)) {
        throw 'The disposable account password file is missing'
    }
    $snapshots = & $vbox snapshot $Name list --machinereadable 2>$null
    if ($snapshots -contains 'SnapshotName="clean"') {
        Write-Host "Clean baseline already exists: $Name"
        return
    }
    if ($info -contains 'VMState="poweroff"') {
        VBox modifyvm $Name --cpus 3
        VBox startvm $Name --type headless
    }
}

Write-Host 'Waiting for Windows installation and Guest Additions...'
$ready = $false
for ($attempt = 0; $attempt -lt 160; $attempt++) {
    $state = & $vbox showvminfo $Name --machinereadable
    if ($state -contains 'VMState="poweroff"') {
        VBox modifyvm $Name --cpus 3
        VBox startvm $Name --type headless
    }
    $version = & $vbox guestproperty get $Name /VirtualBox/GuestAdd/Version 2>$null
    if ($LASTEXITCODE -eq 0 -and $version -match '^Value:') {
        & $vbox guestcontrol $Name run --profile --exe 'C:\Windows\System32\cmd.exe' --username tester --passwordfile $passwordFile '--' /c exit 0 2>$null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
    }
    Start-Sleep -Seconds 15
}
if (-not $ready) {
    throw 'Windows setup did not become ready; the VM is retained for inspection'
}

$state = @(& $vbox showvminfo $Name --machinereadable)
$uuidLine = $state | Where-Object { $_ -match '^UUID=' }
$uuid = ($uuidLine -split '=',2)[1].Trim('"')
$metadata = @{ Name = $Name; UUID = $uuid; PasswordFile = $passwordFile; WorkDir = $WorkDir }
$metadata | ConvertTo-Json | Set-Content (Join-Path $WorkDir 'base.json') -Encoding UTF8

# Shutdown can close the guest service before it reports the process exit.
# Verify the resulting VM state rather than treating that disconnect as failure.
& $vbox guestcontrol $Name run --profile --exe 'C:\Windows\System32\shutdown.exe' --username tester --passwordfile $passwordFile '--' /s /f /t 0 2>&1 | ForEach-Object { Write-Host "$_" }
for ($attempt = 0; $attempt -lt 36; $attempt++) {
    Start-Sleep -Seconds 5
    $state = & $vbox showvminfo $Name --machinereadable
    if ($state -contains 'VMState="poweroff"') { break }
}

if ($state -notcontains 'VMState="poweroff"') {
    throw 'The guest did not shut down cleanly'
}

VBox modifyvm $Name --cpus 3
VBox snapshot $Name take clean --description 'Windows, Guest Additions and test-only installer consent; no dotfiles apps'
Write-Host "Clean baseline ready: $Name"
