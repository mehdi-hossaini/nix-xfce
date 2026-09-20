{ pkgs, inputs, ... }: {
  programs.codexDesktopLinux.enable = true;
  environment.systemPackages = [
    pkgs.zed-editor
    (inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.beta.override {
      # Default browser chrome to dark with sage selection accents.
      extraPolicies.Preferences = {
        "ui.systemUsesDarkTheme" = {
          Value = 1;
          Status = "default";
        };
        "browser.theme.toolbar-theme" = {
          Value = 0;
          Status = "default";
        };
        "browser.theme.content-theme" = {
          Value = 0;
          Status = "default";
        };
        "ui.highlight" = {
          Value = "#a7bf9e";
          Status = "default";
        };
        "ui.highlighttext" = {
          Value = "#202624";
          Status = "default";
        };
      };
    })
  ];
}
