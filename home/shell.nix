{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    bat
    btop
    fastfetch
    fd
    jq
    ripgrep
  ];

  programs.zsh = {
    enable = true;
    autocd = true;
    defaultKeymap = "emacs";
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;
    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      size = 50000;
      extended = true;
      expireDuplicatesFirst = true;
      findNoDups = true;
      ignoreAllDups = true;
      saveNoDups = true;
    };
    initContent = ''
      setopt INTERACTIVE_COMMENTS
      unsetopt BEEP
    '';
  };

  programs.starship = {
    enable = true;
    presets = [ "gruvbox-rainbow" ];
    settings.add_newline = false;
    settings.line_break.disabled = true;
  };

  programs.fzf = {
    enable = true;
    defaultCommand = "${pkgs.fd}/bin/fd --type f --hidden --follow --exclude .git";
    defaultOptions = [
      "--height=40%"
      "--layout=reverse"
      "--border=rounded"
    ];
  };

  programs.zoxide.enable = true;

  # Built-in themes/syntaxes need no Home Manager cache rebuild at every boot.
  xdg.configFile."bat/config".text = ''
    --style=numbers,changes,header
    --theme=base16
  '';

  programs.eza.enable = true;
}
