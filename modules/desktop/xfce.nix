{
  pkgs,
  lib,
  settings,
  ...
}:
let
  uint = value: {
    type = "uint";
    inherit value;
  };
  # Stable desktop IDs for preferred applications and optional launchers.
  zenLauncher = pkgs.makeDesktopItem {
    name = "workstation-zen";
    desktopName = "Zen Browser";
    exec = "zen-beta %U";
    icon = "zen-browser";
    categories = [
      "Network"
      "WebBrowser"
    ];
    mimeTypes = [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
    noDisplay = true;
  };
  codexLauncher = pkgs.makeDesktopItem {
    name = "workstation-codex";
    desktopName = "Codex Desktop";
    exec = "codex-desktop %U";
    icon = "codex-desktop";
    categories = [ "Development" ];
    noDisplay = true;
  };
  terminalLauncher = pkgs.makeDesktopItem {
    name = "workstation-terminal";
    desktopName = "Terminal";
    exec = "alacritty";
    icon = "Alacritty";
    categories = [
      "System"
      "TerminalEmulator"
    ];
    noDisplay = true;
  };
  filesLauncher = pkgs.makeDesktopItem {
    name = "workstation-files";
    desktopName = "Files";
    exec = "thunar";
    icon = "system-file-manager";
    categories = [
      "System"
      "FileManager"
    ];
    noDisplay = true;
  };
  applyDarkTheme = pkgs.writeShellApplication {
    name = "apply-dark-theme";
    runtimeInputs = [ pkgs.xfconf ];
    text = ''
      xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s Adwaita-dark
    '';
  };
  workspaceKeys = lib.listToAttrs (
    lib.concatMap
      (n: [
        {
          name = "xfwm4/custom/<Super>${toString n}";
          value = "workspace_${toString n}_key";
        }
        {
          name = "xfwm4/custom/<Super><Shift>${toString n}";
          value = "move_window_workspace_${toString n}_key";
        }
      ])
      [
        1
        2
        3
        4
        5
      ]
  );
in
{
  services.xserver = {
    enable = true;
    xkb.layout = settings.keyboard;
    displayManager.lightdm.enable = true;
    desktopManager.xfce.enable = true;
  };
  services.libinput.enable = true;
  # Deliver left/right clicks immediately instead of waiting for a chord
  # that emulates a middle click; mice already have a physical middle button.
  services.libinput.mouse.middleEmulation = false;
  services.libinput.mouse.accelProfile = "flat";
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    # 256 frames at the default 48 kHz gives a 5.33 ms graph cycle.
    # Cap client-driven increases; allow smaller requests when needed.
    extraConfig.pipewire."92-low-latency"."context.properties" = {
      "default.clock.quantum" = 256;
      "default.clock.max-quantum" = 256;
    };
    # Avoid the two-second fallback buffer for Pulse clients that do not
    # request a size. Explicit application buffering remains unchanged.
    extraConfig.pipewire-pulse."92-low-latency"."pulse.properties" = {
      "pulse.default.req" = "256/48000";
      "pulse.default.tlength" = "1024/48000";
    };
    alsa.enable = true;
    alsa.support32Bit = pkgs.stdenv.hostPlatform.isx86_64;
    pulse.enable = true;
  };
  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.printing.enable = true;
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  programs.xfconf.enable = true;
  programs.nm-applet.enable = true;
  services.xserver.desktopManager.xfce.enableScreensaver = true;
  powerManagement.enable = true;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.lightdm.enableGnomeKeyring = true;
  environment.systemPackages = with pkgs; [
    alacritty
    rofi
    xfce4-screenshooter
    xfce4-whiskermenu-plugin
    xfce4-pulseaudio-plugin
    pavucontrol
    gnome-themes-extra
    elementary-xfce-icon-theme
    zenLauncher
    codexLauncher
    terminalLauncher
    filesLauncher
  ];
  fonts.packages = with pkgs; [
    nerd-fonts.iosevka
    dejavu_fonts
    noto-fonts-color-emoji
  ];

  home-manager.users.${settings.username} = import ../../home/xfce.nix {
    inherit
      pkgs
      settings
      uint
      workspaceKeys
      applyDarkTheme
      ;
  };
}
