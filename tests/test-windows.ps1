[CmdletBinding()]
param(
    [string]$WorkDir = (Join-Path $env:LOCALAPPDATA 'dotfiles-vm-tests'),
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'
$vbox = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
$WorkDir = [IO.Path]::GetFullPath($WorkDir)
# Fresh OS images and temporary Rust builds need room beyond the download cache.
$drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($WorkDir))
if ($drive.AvailableFreeSpace -lt 45GB) {
    throw 'Keep at least 45 GiB free on the test drive; run the Windows and WSL suites sequentially'
}
$base = Get-Content (Join-Path $WorkDir 'base.json') -Raw | ConvertFrom-Json
$name = 'dotfiles-windows-test-' + [guid]::NewGuid().ToString('N').Substring(0,12)
$repo = Split-Path $PSScriptRoot -Parent
$created = $false
$passed = $false
$uuid = $null

function VBox {
    & $vbox @args 2>&1 | ForEach-Object { Write-Host "$_" }
    if ($LASTEXITCODE -ne 0) {
        throw "VirtualBox command failed: $($args[0])"
    }
}

function Assert-TestDiskSpace {
    if ($drive.AvailableFreeSpace -lt 10GB) {
        & $vbox controlvm $name pause 2>$null | Out-Null
        throw 'Paused the disposable VM to keep 10 GiB free on the host; free space before resuming'
    }
}
function Wait-Guest {
    # Count polls so a suspended laptop does not consume the boot budget.
    for ($attempt = 0; $attempt -lt 48; $attempt++) {
        Assert-TestDiskSpace
        $version = & $vbox guestproperty get $name /VirtualBox/GuestAdd/Version 2>$null
        if ($LASTEXITCODE -eq 0 -and $version -match '^Value:') {
            & $vbox guestcontrol $name run --profile --exe 'C:\Windows\System32\cmd.exe' --username tester --passwordfile $base.PasswordFile '--' /c exit 0 2>$null
            if ($LASTEXITCODE -eq 0) {
                return
            }
        }
        Start-Sleep -Seconds 10
    }
    throw 'The disposable Windows guest did not become ready'
}

function Stop-Guest {
    $manager = New-Object -ComObject VirtualBox.VirtualBox
    $workerId = $manager.FindMachine($uuid).SessionPID
    $worker = $null
    if ($workerId -gt 0 -and $workerId -lt [uint32]::MaxValue) {
        $worker = Get-Process -Id $workerId -ErrorAction SilentlyContinue
        if ($worker) { $workerStartedAt = $worker.StartTime }
    }

    $state = & $vbox showvminfo $name --machinereadable
    if ($state -contains 'VMState="running"') {
        & $vbox guestcontrol $name run --profile --exe 'C:\Windows\System32\shutdown.exe' --username tester --passwordfile $base.PasswordFile '--' /s /f /t 0 2>&1 | ForEach-Object { Write-Host "$_" }
        for ($attempt = 0; $attempt -lt 24; $attempt++) {
            Start-Sleep -Seconds 5
            $state = & $vbox showvminfo $name --machinereadable
            if ($state -contains 'VMState="poweroff"') { break }
        }
        if ($state -notcontains 'VMState="poweroff"') {
            VBox controlvm $name poweroff
            $state = & $vbox showvminfo $name --machinereadable
        }
    }

    # VirtualBox can report poweroff while its worker still holds guest memory.
    if ($state -contains 'VMState="poweroff"' -and $worker -and -not $worker.WaitForExit(15000)) {
        $remaining = Get-Process -Id $workerId -ErrorAction SilentlyContinue
        $state = & $vbox showvminfo $name --machinereadable
        if ($remaining -and $remaining.ProcessName -eq 'VBoxHeadless' -and
            $remaining.StartTime -eq $workerStartedAt -and
            $state -contains 'VMState="poweroff"') {
            Stop-Process -InputObject $remaining -Force
        }
    }
}

Start-Transcript (Join-Path $WorkDir "$name.log")
try {
    VBox clonevm $base.UUID --snapshot clean --name $name --basefolder $WorkDir --mode machine --options link --register
    $created = $true

    $info = & $vbox showvminfo $name --machinereadable
    $uuid = (($info | Where-Object { $_ -match '^UUID=' }) -split '=',2)[1] | ConvertFrom-Json
    $configPath = (($info | Where-Object { $_ -match '^CfgFile=' }) -split '=',2)[1] | ConvertFrom-Json
    $expected = Join-Path (Join-Path $WorkDir $name) "$name.vbox"
    if ([IO.Path]::GetFullPath($configPath) -ne [IO.Path]::GetFullPath($expected)) {
        throw "VM configuration is outside this run's test directory"
    }
    if ($info | Where-Object { $_ -match '^SharedFolderName' }) {
        throw 'Test guests must not have shared host directories'
    }

    # WHPX firmware can hang with exactly two virtual CPUs (VirtualBox #799).
    VBox modifyvm $uuid --cpus 3
    VBox startvm $uuid --type headless
    Wait-Guest

    VBox guestcontrol $uuid mkdir --username tester --passwordfile $base.PasswordFile --parents 'C:\dotfiles-test-vm'
    $archive = Join-Path $WorkDir "$name-source.tar"
    & tar.exe --format=ustar -cf $archive --exclude=.git --exclude=result -C $repo .
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not archive the candidate configuration'
    }
    $guestArchive = 'C:\dotfiles-test-vm\candidate.tar'
    VBox guestcontrol $uuid copyto --username tester --passwordfile $base.PasswordFile $archive $guestArchive
    VBox guestcontrol $uuid mkdir --username tester --passwordfile $base.PasswordFile --parents 'C:\dotfiles-test-vm\repo'
    VBox guestcontrol $uuid run --profile --username tester --passwordfile $base.PasswordFile --exe 'C:\Windows\System32\tar.exe' --wait-stdout --wait-stderr '--' -xf $guestArchive -C 'C:\dotfiles-test-vm\repo'
    # Long installer output can time out the Guest Control pipe. Run independently
    # and collect the scenario's result file instead of keeping that pipe open.
    VBox guestcontrol $uuid start --profile --username tester --passwordfile $base.PasswordFile --exe 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' --timeout 0 '--' -NoProfile -ExecutionPolicy Bypass -File 'C:\dotfiles-test-vm\repo\tests\windows-scenarios.ps1'
    $resultFile = Join-Path $WorkDir "$name-result.txt"
    for ($attempt = 0; $attempt -lt 480; $attempt++) {
        Assert-TestDiskSpace
        Start-Sleep -Seconds 15
        & $vbox guestcontrol $uuid run --profile --username tester --passwordfile $base.PasswordFile --exe 'C:\Windows\System32\cmd.exe' '--' /c 'if exist C:\Users\tester\dotfiles-windows-result.txt (exit /b 0) else (exit /b 1)' 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            VBox guestcontrol $uuid copyfrom --username tester --passwordfile $base.PasswordFile 'C:\Users\tester\dotfiles-windows-result.txt' $resultFile
            break
        }
    }
    if (-not (Test-Path $resultFile) -or [IO.File]::ReadAllText($resultFile) -ne 'True') {
        throw 'Windows scenarios failed or exceeded their time budget; inspect the guest log'
    }

    VBox guestcontrol $uuid copyfrom --username tester --passwordfile $base.PasswordFile 'C:\Users\tester\dotfiles-windows-test.log' (Join-Path $WorkDir "$name-guest.log")
    Stop-Guest
    VBox startvm $uuid --type headless
    Wait-Guest
    $fonts = & $vbox guestcontrol $uuid run --profile --username tester --passwordfile $base.PasswordFile --exe 'C:\Program Files\WezTerm\wezterm.exe' --wait-stdout --wait-stderr '--' ls-fonts --text Dotfiles
    if ($LASTEXITCODE -ne 0 -or -not ($fonts -match 'FIRACODENERDFONT-REGULAR.TTF')) {
        throw 'WezTerm or the managed font failed after guest restart'
    }
    Write-Host 'PASS windows-guest-restart'
    $passed = $true
} catch {
    if ($created) {
        & $vbox guestcontrol $uuid copyfrom --username tester --passwordfile $base.PasswordFile 'C:\Users\tester\dotfiles-windows-test.log' (Join-Path $WorkDir "$name-guest.log") 2>$null | Out-Null
    }
    throw
} finally {
    if ($created -and $passed -and -not $Keep) {
        Stop-Guest
        # Delete only the UUID created here, after checking its exact configuration path.
        VBox unregistervm $uuid --delete
    } elseif ($created) {
        Write-Host "Retained test VM: $name"
    }
    Stop-Transcript
}
