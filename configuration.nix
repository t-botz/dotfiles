{ user, ... }:
{
  # The Determinate installer manages the Nix daemon.
  nix.enable = false;
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;
  system.primaryUser = user;
  users.users.${user}.home = "/Users/${user}";
  programs.zsh = {
    enable = true;
    # Home Manager initializes completion and the Starship prompt.
    enableCompletion = false;
    promptInit = "";
  };

  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      _HIHideMenuBar = true;
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    finder.FXPreferredViewStyle = "Nlsv";
    finder.CreateDesktop = false;
    trackpad.Clicking = true;
  };

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
      "herdr"
      "mise"
      "zoxide"
    ];
    casks = [
      "bartender"
      "bitwarden"
      "brave-browser"
      "chatgpt"
      "codex"
      "expressvpn"
      "google-chrome"
      "rectangle"
      "spotify"
      "visual-studio-code"
      "vlc"
      "wezterm"
      "whatsapp"
    ];
  };
}
