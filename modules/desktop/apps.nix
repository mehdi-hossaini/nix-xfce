{
  pkgs,
  inputs,
  lib,
  ...
}:
{
  programs.codexDesktopLinux.enable = true;
  environment.systemPackages = [
    pkgs.zed-editor
    pkgs.vesktop
    (inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.beta.override {
      # Default browser chrome to dark with a Gruvbox selection accent.
      extraPolicies.Preferences =
        lib.mapAttrs
          (_: value: {
            Value = value;
            Status = "default";
          })
          {
            "ui.systemUsesDarkTheme" = 1;
            "browser.theme.toolbar-theme" = 0;
            "browser.theme.content-theme" = 0;
            "ui.highlight" = "#d79921";
            "ui.highlighttext" = "#282828";
          };
    })
  ];
}
