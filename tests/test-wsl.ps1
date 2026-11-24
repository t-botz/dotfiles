[CmdletBinding()]
param([string]$WorkDir = (Join-Path $env:TEMP 'dotfiles-wsl-tests'), [switch]$Keep)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$WorkDir = [IO.Path]::GetFullPath($WorkDir)
# Fresh OS images and temporary Rust builds need room beyond the download cache.
$drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($WorkDir))
if ($drive.AvailableFreeSpace -lt 45GB) {
    throw 'Keep at least 45 GiB free on the test drive; run the Windows and WSL suites sequentially'
}
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$name = 'dotfiles-test-' + [guid]::NewGuid().ToString('N').Substring(0,12)
$disk = Join-Path $WorkDir $name
$baseline = Join-Path $WorkDir 'baseline-26.04.1-v1.tar'
$log = Join-Path $WorkDir "$name.log"
$passed = $false
$created = $false
function Wsl {
  & wsl.exe @args 2>&1 | ForEach-Object {
    if ($drive.AvailableFreeSpace -lt 10GB) {
      & wsl.exe --terminate $name 2>$null | Out-Null
      throw 'Stopped the disposable WSL guest to keep 10 GiB free on the host; free space before retrying'
    }
    Write-Host "$_"
  }
  if ($LASTEXITCODE -ne 0) { throw "WSL failed ($LASTEXITCODE): $args" }
}
function RootScript([string]$script) {
  ($script.Replace("`r`n", "`n") + "`n") | & wsl.exe -d $name -u root -- bash -c "tr -d '\r' | bash -se" 2>&1 | ForEach-Object { Write-Host "$_" }
  if ($LASTEXITCODE -ne 0) { throw 'Guest setup failed' }
}
Start-Transcript -Path $log | Out-Null
try {
  if (!(Test-Path $baseline)) {
    $image = Join-Path $WorkDir 'ubuntu-26.04.1.wsl'
    $hash = '48d56724b5c8e60f24893e83e73bbb58c60b3ca22fba3da977075420acd54104'
    if (!(Test-Path $image)) {
      Invoke-WebRequest 'https://releases.ubuntu.com/26.04.1/ubuntu-26.04.1-wsl-amd64.wsl' -OutFile $image
    }
    if ((Get-FileHash $image -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) { throw 'Ubuntu image checksum mismatch' }
    Wsl --import $name $disk $image --version 2
    $created = $true
    RootScript @'
cat >/etc/wsl.conf <<'CONF'
[boot]
systemd=true
[automount]
enabled=false
[interop]
enabled=false
appendWindowsPath=false
[user]
default=tester
CONF
'@
    Wsl --terminate $name
    RootScript @'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl sudo python3 xz-utils
id tester >/dev/null 2>&1 || useradd -m -s /bin/bash tester
echo 'tester ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/dotfiles-tester
chmod 440 /etc/sudoers.d/dotfiles-tester
if command -v git >/dev/null; then apt-get purge -y git; fi
test ! -d /nix
if command -v git; then exit 1; fi
if mount | grep -q ' on /mnt/c '; then exit 1; fi
test -z "${WSL_INTEROP:-}"
'@
    Wsl --terminate $name
    Wsl --export $name $baseline
  } else {
    Wsl --import $name $disk $baseline --version 2
    $created = $true
  }
  $payload = Join-Path $WorkDir "$name-payload"
  $fixture = Join-Path $payload 'fixture'
  New-Item -ItemType Directory -Force $fixture | Out-Null
  & tar.exe --format=ustar -cf (Join-Path $WorkDir "$name-source.tar") --exclude=.git --exclude=result -C $repo .
  if ($LASTEXITCODE -ne 0) { throw 'Source archive failed' }
  & tar.exe -xf (Join-Path $WorkDir "$name-source.tar") -C $fixture
  if ($LASTEXITCODE -ne 0) { throw 'Source extraction failed' }
  & git -C $fixture init -b main
  & git -C $fixture -c core.autocrlf=false add .
  & git -C $fixture -c user.name=Test -c user.email=test@example.invalid commit -m 'Local test candidate'
  if ($LASTEXITCODE -ne 0) { throw 'Fixture commit failed' }
  & git -C $fixture update-server-info
  if ($LASTEXITCODE -ne 0) { throw 'Fixture HTTP metadata failed' }
  Copy-Item (Join-Path $fixture 'install.sh') $payload
  $archive = Join-Path $WorkDir "$name-payload.tar"
  & tar.exe --format=ustar -cf $archive -C $payload .
  if ($LASTEXITCODE -ne 0) { throw 'Payload archive failed' }
  RootScript 'mkdir -p /tmp/payload'
  # cmd performs binary redirection; PowerShell's text pipeline corrupts tar streams.
  & cmd.exe /d /c "wsl.exe -d $name -u root -- tar -xf - -C /tmp/payload < `"$archive`""
  if ($LASTEXITCODE -ne 0) { throw 'Payload transfer failed' }
  RootScript 'chown -R tester:tester /tmp/payload'
  RootScript @'
provision=/tmp/payload/fixture/windows/provision-wsl.sh
run_provision() {
  status=0
  bash "$provision" "$1" || status=$?
  [[ "$status" == 0 || "$status" == 10 ]]
}
run_provision bootstrap-fixture
id -nG bootstrap-fixture | grep -qw sudo
test -f /home/bootstrap-fixture/.dotfiles-needs-password
run_provision tester
before="$(sha256sum /etc/wsl.conf)"
run_provision tester
test "$(sha256sum /etc/wsl.conf)" = "$before"
grep -Eq "enabled ?= ?false" /etc/wsl.conf
echo "PASS windows-linux-account-provisioning"
'@
  Wsl -d $name -u tester -- timeout 2h bash /tmp/payload/fixture/tests/wsl-scenarios.sh
  Wsl --terminate $name
  Wsl -d $name -u tester -- bash -lc 'command -v nix; command -v zsh; zsh -lic "git --version && mise --version && whence gclone"'
  Write-Output 'PASS guest-restart'
  $passed = $true
} finally {
  if ($created -and $passed -and !$Keep) {
    Wsl --terminate $name
    Wsl --unregister $name
  } elseif ($created) {
    Write-Output "Retained test distribution: $name"
    Write-Output "Inspect: wsl -d $name -u tester"
    Write-Output "Delete: wsl --unregister $name"
  }
  Stop-Transcript | Out-Null
  Write-Output "Log: $log"
}
