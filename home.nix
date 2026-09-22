{ user, ... }:
{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "26.05";

  home.file.".gitconfig".source = ./home/gitconfig;
  home.file.".zshrc".source = ./home/zshrc;
  home.file.".zprofile".source = ./home/zprofile;
}
