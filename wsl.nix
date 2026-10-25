{ pkgs, ... }:
{
  targets.genericLinux.enable = true;
  # CLI setup only; WSL GPU integration is configured separately when needed.
  targets.genericLinux.gpu.enable = false;
  programs.home-manager.enable = true;
  programs.bash.enable = true;
  home.packages = [ pkgs.vim ];
}
