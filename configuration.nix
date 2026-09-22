{ user, ... }:
{
  # The Determinate installer manages the Nix daemon.
  nix.enable = false;
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;
  system.primaryUser = user;
  users.users.${user}.home = "/Users/${user}";
  programs.zsh.enable = true;

  nix-homebrew = {
    enable = true;
    inherit user;
    autoMigrate = true;
  };

  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "none";
      autoUpdate = false;
      upgrade = false;
    };
    brews = [
      "gh"
      "zoxide"
    ];
    casks = [
      "bitwarden"
      "brave-browser"
      "chatgpt"
      "codex"
      "expressvpn"
      "google-chrome"
      "spotify"
      "visual-studio-code"
      "vlc"
      "whatsapp"
    ];
  };
}
