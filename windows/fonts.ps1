$ErrorActionPreference = 'Stop'

$config = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'config.psd1')

$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$fontFile = Join-Path $fontDir 'FiraCodeNerdFont-Regular.ttf'

if (-not (Test-Path $fontFile)) {
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-font-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $tempDir | Out-Null

    try {
        $release = "https://github.com/ryanoasis/nerd-fonts/releases/download/$($config.FontVersion)"
        $checksumFile = Join-Path $tempDir 'SHA-256.txt'
        Invoke-WebRequest "$release/SHA-256.txt" -OutFile $checksumFile -UseBasicParsing
        $checksums = [IO.File]::ReadAllText($checksumFile)
        $match = [regex]::Match($checksums, '(?im)^([a-f0-9]{64})\s+\*?FiraCode\.zip\s*$')
        if (-not $match.Success) {
            throw 'FiraCode.zip is missing from the published checksums'
        }

        $archive = Join-Path $tempDir 'FiraCode.zip'
        Invoke-WebRequest "$release/FiraCode.zip" -OutFile $archive -UseBasicParsing
        if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $match.Groups[1].Value) {
            throw 'Font archive checksum mismatch'
        }

        Expand-Archive $archive (Join-Path $tempDir 'fonts')
        New-Item -ItemType Directory -Force $fontDir | Out-Null

        foreach ($font in Get-ChildItem (Join-Path $tempDir 'fonts') -Filter '*.ttf' -Recurse) {
            $destination = Join-Path $fontDir $font.Name
            Copy-Item -LiteralPath $font.FullName -Destination $destination -Force
        }
    } finally {
        $resolvedTemp = [IO.Path]::GetFullPath($tempDir)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (-not $resolvedTemp.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path $resolvedTemp -Leaf).StartsWith('dotfiles-font-')) {
            throw 'Refusing to remove a directory outside the font staging area'
        }
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}

# Register existing files too, so repeating setup repairs an incomplete install.
$registry = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
if (-not (Test-Path $registry)) {
    New-Item -Path $registry | Out-Null
}
$fontKey = Get-Item -LiteralPath $registry
$shell = New-Object -ComObject Shell.Application
$folder = $shell.Namespace($fontDir)
foreach ($font in Get-ChildItem $fontDir -Filter 'FiraCodeNerdFont*.ttf') {
    $title = [string]$folder.ParseName($font.Name).ExtendedProperty('System.Title')
    if ([string]::IsNullOrWhiteSpace($title)) {
        throw "Could not read font metadata: $($font.Name)"
    }
    $name = "$title (TrueType)"
    $current = $fontKey.GetValue($name)
    if ($current -ne $font.FullName) {
        New-ItemProperty -Path $registry -Name $name -Value $font.FullName -PropertyType String -Force | Out-Null
    }

    # Migrate only the filename-based entries written by earlier bootstrap runs.
    $legacyName = "$($font.BaseName) (TrueType)"
    $legacy = $fontKey.GetValue($legacyName)
    if ($legacyName -ne $name -and $legacy -eq $font.FullName) {
        Remove-ItemProperty -Path $registry -Name $legacyName
    }
}

$fontKey.Dispose()
