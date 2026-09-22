{
  pkgs,
  settings,
  uint,
  workspaceKeys,
  applyDarkTheme,
  ...
}:
{

  home.stateVersion = "26.05";
  home.username = settings.username;
  home.homeDirectory = "/home/${settings.username}";
  fonts.fontconfig.enable = true;
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "elementary-xfce-dark";
      package = pkgs.elementary-xfce-icon-theme;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };
  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
  # Also apply inside the real XFCE session on first login.
  xdg.configFile."autostart/dark-theme.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Dark theme
    Exec=${applyDarkTheme}/bin/apply-dark-theme
    OnlyShowIn=XFCE;
    NoDisplay=true
    Terminal=false
  '';
  home.sessionVariables.BROWSER = "zen-beta";
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "workstation-zen.desktop" ];
      "x-scheme-handler/http" = [ "workstation-zen.desktop" ];
      "x-scheme-handler/https" = [ "workstation-zen.desktop" ];
    };
  };
  # XFCE's preferred browser is separate from XDG MIME associations.
  xdg.configFile."xfce4/helpers.rc".text = ''
    WebBrowser=workstation-zen
  '';
  xdg.dataFile."xfce4/helpers/workstation-zen.desktop".text = ''
    [Desktop Entry]
    Type=X-XFCE-Helper
    Name=Zen Browser
    Icon=zen-browser
    NoDisplay=true
    X-XFCE-Category=WebBrowser
    X-XFCE-Binaries=zen-beta;
    X-XFCE-Commands=%B;
    X-XFCE-CommandsWithParameter=%B "%s";
  '';
  programs.alacritty = {
    enable = true;
    settings = {
      font.normal.family = "Iosevka Nerd Font";
      font.size = 12;
      window.padding = {
        x = 8;
        y = 8;
      };
      window.dynamic_padding = true;
      scrolling.history = 100000;
      cursor = {
        style = {
          shape = "Beam";
          blinking = "On";
        };
        blink_interval = 500;
        unfocused_hollow = true;
      };
      mouse.hide_when_typing = true;
      selection.save_to_clipboard = true;
    };
  };

  # Xfconf remains writable by XFCE. Rebuilds restore these declared values.
  xfconf.settings = {
    xsettings = {
      "Net/ThemeName" = "Adwaita-dark";
      "Net/IconThemeName" = "elementary-xfce-dark";
      "Gtk/FontName" = "DejaVu Sans 11";
      "Gtk/MonospaceFontName" = "Iosevka Nerd Font 12";
      "Gtk/CursorThemeName" = "Adwaita";
    };
    xfwm4 = {
      "general/theme" = "Default";
      "general/title_font" = "DejaVu Sans Bold 11";
      "general/titleless_maximize" = true;
      "general/workspace_count" = 5;
      "general/workspace_names" = [
        "1"
        "2"
        "3"
        "4"
        "5"
      ];
      "general/easy_click" = "Super";
      "general/tile_on_move" = true;
      "general/use_compositing" = true;
    };
    xfce4-desktop."desktop-icons/style" = 0;
    keyboards = {
      "Default/KeyRepeat" = true;
      "Default/KeyRepeat/Delay" = 200;
      "Default/KeyRepeat/Rate" = 35;
    };
    xfce4-session = {
      "general/SaveOnExit" = false;
      "general/LockCommand" = "${pkgs.xfce4-screensaver}/bin/xfce4-screensaver-command --lock";
    };
    xfce4-power-manager = {
      # Minutes of inactivity: power the panel off when the screensaver starts.
      # Skip the intermediate standby stage; keep the existing screen lock.
      "xfce4-power-manager/dpms-enabled" = true;
      "xfce4-power-manager/dpms-on-ac-sleep" = uint 0;
      "xfce4-power-manager/dpms-on-ac-off" = uint 5;
      "xfce4-power-manager/dpms-on-battery-sleep" = uint 0;
      "xfce4-power-manager/dpms-on-battery-off" = uint 5;
      "xfce4-power-manager/lock-screen-suspend-hibernate" = true;
      "xfce4-power-manager/show-tray-icon" = true;
    };
    xfce4-keyboard-shortcuts = {
      "commands/custom/override" = true;
      "commands/custom/<Super>Return" = "${pkgs.alacritty}/bin/alacritty";
      "commands/custom/<Super>d" = "${pkgs.rofi}/bin/rofi -show drun";
      "commands/custom/<Super>e" = "thunar";
      "commands/custom/<Super>b" = "zen-beta";
      "commands/custom/<Super>c" = "codex-desktop";
      "commands/custom/<Super>l" = "${pkgs.xfce4-screensaver}/bin/xfce4-screensaver-command --lock";
      "commands/custom/<Super>s" = "${pkgs.xfce4-screenshooter}/bin/xfce4-screenshooter -r -c";
      "commands/custom/Print" = "${pkgs.xfce4-screenshooter}/bin/xfce4-screenshooter";
      "commands/custom/XF86AudioRaiseVolume" =
        "${pkgs.wireplumber}/bin/wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+";
      "commands/custom/XF86AudioLowerVolume" =
        "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
      "commands/custom/XF86AudioMute" =
        "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
      "commands/custom/XF86AudioMicMute" =
        "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
      "xfwm4/custom/override" = true;
      "xfwm4/custom/<Super>q" = "close_window_key";
      "xfwm4/custom/<Super>f" = "maximize_window_key";
      "xfwm4/custom/<Super>Left" = "tile_left_key";
      "xfwm4/custom/<Super>Right" = "tile_right_key";
      "xfwm4/custom/<Alt>Tab" = "cycle_windows_key";
      "xfwm4/custom/<Alt><Shift>Tab" = "cycle_reverse_windows_key";
      "xfwm4/custom/<Alt>F4" = "close_window_key";
      "xfwm4/custom/Escape" = "cancel_key";
    }
    // workspaceKeys;
    xfce4-panel = {
      "configver" = 2;
      "panels" = [ 1 ];
      "panels/dark-mode" = true;
      "panels/panel-1/position" = "p=10;x=0;y=0";
      "panels/panel-1/position-locked" = true;
      "panels/panel-1/length" = uint 100;
      "panels/panel-1/nrows" = uint 1;
      "panels/panel-1/plugin-ids" = [
        1
        2
        3
        8
        9
        10
        11
        12
      ];
      "plugins/plugin-1" = "whiskermenu";
      "plugins/plugin-2" = "pager";
      "plugins/plugin-2/rows" = uint 1;
      "plugins/plugin-2/miniature-view" = false;
      "plugins/plugin-3" = "separator";
      "plugins/plugin-3/style" = uint 0;
      "plugins/plugin-8" = "tasklist";
      # Compact running-app icons; window titles remain available on hover.
      "plugins/plugin-8/grouping" = true;
      "plugins/plugin-8/show-labels" = false;
      "plugins/plugin-8/flat-buttons" = true;
      "plugins/plugin-8/show-handle" = false;
      "plugins/plugin-8/show-tooltips" = true;
      "plugins/plugin-9" = "separator";
      "plugins/plugin-9/expand" = true;
      "plugins/plugin-9/style" = uint 0;
      "plugins/plugin-10" = "systray";
      "plugins/plugin-10/square-icons" = true;
      "plugins/plugin-11" = "pulseaudio";
      # Xfconf owns media keys above; avoid a second handler in the plugin.
      "plugins/plugin-11/enable-keyboard-shortcuts" = false;
      "plugins/plugin-12" = "clock";
      "plugins/plugin-12/mode" = uint 2;
      "plugins/plugin-12/digital-layout" = uint 3;
      "plugins/plugin-12/digital-time-format" = "%H:%M";
      "plugins/plugin-12/digital-time-font" = "Iosevka Nerd Font Bold 12";
    };
  };

}
