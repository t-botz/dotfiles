@{
    Distribution = 'Ubuntu-26.04'
    LinuxUser = 'tibo'
    FontVersion = 'v3.5.1'
    Packages = @(
        @{ Id = 'Git.Git'; Source = 'winget' }
        @{ Id = 'Microsoft.PowerShell'; Source = 'winget' }
        @{ Id = 'Microsoft.VisualStudioCode'; Source = 'winget' }
        @{ Id = 'wez.wezterm'; Source = 'winget' }
        @{ Id = 'Bitwarden.Bitwarden'; Source = 'winget' }
        @{
            Id = 'Brave.Brave'
            Source = 'winget'
            Paths = @(
                '%ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe'
                '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\Application\brave.exe'
                '%ProgramFiles(x86)%\BraveSoftware\Brave-Browser\Application\brave.exe'
            )
        }
        @{ Id = 'Google.Chrome.EXE'; Source = 'winget' }
        @{ Id = 'OpenAI.ChatGPT'; Source = 'winget' }
        @{ Id = 'Spotify.Spotify'; Source = 'winget'; Appx = 'SpotifyAB.SpotifyMusic' }
        @{ Id = 'VideoLAN.VLC'; Source = 'winget' }
        @{ Id = '9NKSQGP7F2NH'; Source = 'msstore'; Appx = '*WhatsApp*' }
    )
}
