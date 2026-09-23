{ config, pkgs, user, ... }:
{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    ripgrep
    nerd-fonts.fira-code
  ];
  fonts.fontconfig.enable = true;

  xdg.configFile."wezterm/wezterm.lua".source = ./home/wezterm.lua;
  xdg.configFile."herdr/config.toml".source = (pkgs.formats.toml { }).generate "herdr-config" {
    keys = {
      prefix = "ctrl+b";
      focus_pane_left = "prefix+h";
      focus_pane_down = "prefix+j";
      focus_pane_up = "prefix+k";
      focus_pane_right = "prefix+l";
      split_horizontal = "prefix+double_quote";
      split_vertical = "prefix+percent";
      new_tab = "prefix+c";
      close_tab = "prefix+ampersand";
      workspace_picker = "prefix+w";
      goto = "prefix+g";
      copy_mode = "prefix+y";
    };
    ui.agent_panel_sort = "spaces";
  };

  home.file.".codex/AGENTS.md".source = ./home/AGENTS.md;
  home.file.".claude/CLAUDE.md".source = ./home/AGENTS.md;
  xdg.configFile."opencode/AGENTS.md".source = ./home/AGENTS.md;

  programs.zsh = {
    enable = true;
    dotDir = config.home.homeDirectory;
    defaultKeymap = "emacs";
    history = {
      size = 2000;
      save = 2000;
      share = true;
    };
    profileExtra = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';
    initContent = ''
      gclone() {
        if [ "$#" -ne 1 ]; then
          echo "Usage: gclone git@host:owner/repo.git" >&2
          return 2
        fi

        local url="$1"
        local host repo_path target

        case "$url" in
          git@*:* )
            host="''${url#git@}"
            host="''${host%%:*}"
            repo_path="''${url#*:}"
            ;;
          *://*/* )
            host="''${url#*://}"
            repo_path="''${host#*/}"
            host="''${host%%/*}"
            ;;
          * )
            echo "Unsupported repository URL: $url" >&2
            return 2
            ;;
        esac

        repo_path="''${repo_path%.git}"
        target="$HOME/workspace/$host/$repo_path"

        mkdir -p "''${target%/*}" &&
          git clone "$url" "$target"
      }

      eval "$(zoxide init zsh)"
    '';
  };

  # Keep the existing global Git config location.
  xdg.configFile."git/config".target = "${config.home.homeDirectory}/.gitconfig";

  programs.git = {
    enable = true;
    settings = {
      user.name = "Tibo";
      user.email = "delor.thibault@gmail.com";
      alias.co = "checkout";
      alias.br = "branch";
      alias.ci = "commit";
      alias.st = "status";
      alias.amend = "commit --amend --no-edit";
      alias.yolo = "!git add . && git commit --amend --no-edit && git push -f";
      alias."rm-merged" = "!git branch --format '%(refname:short) %(upstream:track)' | awk '$2 == \"[gone]\" { print $1 }' | xargs -r git branch -D";
      core.excludesfile = "~/.gitignore";
      core.editor = "vi";
      core.ignorecase = false;
      format.pretty = "format:%C(yellow)%h %Cgreen%<(14,trunc)%cr %<(14,trunc)%C(cyan)%aN %Creset%s";
      fetch.prune = true;
      fetch.prunetags = true;
      push.default = "current";
      push.autosetupremote = true;
      pull.rebase = true;
      branch.autosetuprebase = "always";
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      "$schema" = "https://starship.rs/config-schema.json";
      format = "$all$fill$cmd_duration $time$line_break$character";
      time = {
        disabled = false;
        format = "[$time]($style)";
        style = "fg:66";
      };
      cmd_duration = {
        show_milliseconds = true;
        min_time = 100;
        format = "[$duration](fg:101) ";
      };
      fill.symbol = " ";
      aws.disabled = true;
      python.format = "via [\${symbol}$virtualenv]($style)";
      git_status.style = "bold purple";
      git_metrics.disabled = false;
    };
  };
}
