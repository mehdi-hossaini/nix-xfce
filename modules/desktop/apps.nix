{
  pkgs,
  inputs,
  lib,
  ...
}:
let
  siteoneCrawler =
    let
      pname = "siteone-crawler";
      version = "1.0.8";
      src = pkgs.fetchurl {
        url = "https://github.com/janreges/siteone-crawler-gui/releases/download/v${version}/SiteOne-Crawler-linux-x64-${version}.AppImage";
        hash = "sha256-KG9z0+mscbwQR4gS3fDIAGQAkfRR4/82WcH7oPH39Ow=";
      };
      appimageContents = pkgs.appimageTools.extractType2 {
        inherit pname src version;
      };
    in
    pkgs.appimageTools.wrapType2 {
      inherit pname src version;
      extraInstallCommands = ''
        install -m 444 -D \
          ${appimageContents}/siteone-crawler.desktop \
          $out/share/applications/siteone-crawler.desktop
        install -m 444 -D \
          ${appimageContents}/siteone-crawler.png \
          $out/share/icons/hicolor/512x512/apps/siteone-crawler.png
        substituteInPlace $out/share/applications/siteone-crawler.desktop \
          --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=siteone-crawler --no-sandbox %U'
      '';
      meta = {
        description = "Desktop website crawler, analyzer, and offline exporter";
        homepage = "https://crawler.siteone.io/";
        mainProgram = "siteone-crawler";
        platforms = [ "x86_64-linux" ];
      };
    };
in
{
  programs.codexDesktopLinux.enable = true;
  environment.systemPackages = [
    pkgs.zed-editor
    pkgs.vesktop
    siteoneCrawler
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
