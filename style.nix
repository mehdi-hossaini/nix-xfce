{ pkgs, lib, ... }:
let
  settings = import ./settings.nix;
  palette = {
    background = "#202624";
    surface = "#29312d";
    foreground = "#e2e7df";
    muted = "#a3afa5";
    accent = "#a7bf9e";
    border = "#46534a";
  };
  wallpaperSvg = pkgs.writeText "quiet-hills.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" width="3840" height="2160" viewBox="0 0 3840 2160">
      <defs><linearGradient id="sky" x2="0" y2="1">
        <stop stop-color="#202624"/><stop offset="1" stop-color="#303d35"/>
      </linearGradient></defs>
      <rect width="3840" height="2160" fill="url(#sky)"/>
      <circle cx="2910" cy="620" r="115" fill="#a7bf9e"/>
      <path d="M0 1570 Q760 1140 1570 1550 T3840 1410 V2160 H0Z" fill="#35463c"/>
      <path d="M0 1790 Q990 1410 2060 1790 T3840 1610 V2160 H0Z" fill="#29372f"/>
      <path d="M0 1950 Q1250 1700 2550 1960 T3840 1870 V2160 H0Z" fill="#202b25"/>
    </svg>
  '';
  wallpaper = pkgs.runCommand "quiet-hills.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
    rsvg-convert ${wallpaperSvg} -o "$out"
  '';
  applyWallpaper = pkgs.writeShellApplication {
    name = "apply-quiet-wallpaper";
    runtimeInputs = [ pkgs.xfconf pkgs.xrandr pkgs.gnugrep pkgs.gnused pkgs.gawk ];
    text = ''
      # Xfdesktop creates monitor-specific keys after login. Use those keys first.
      properties=""
      for _ in {1..20}; do
        properties=$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '^/backdrop/screen[0-9]+/monitor.*/workspace[0-9]+/last-image$' || true)
        [[ -n "$properties" ]] && break
        sleep 1
      done
      if [[ -z "$properties" ]]; then
        properties=$(xrandr --query | awk '/ connected/ {print "/backdrop/screen0/monitor" $1 "/workspace0/last-image"}')
      fi
      while IFS= read -r property; do
        [[ -n "$property" ]] || continue
        base="''${property%/last-image}"
        xfconf-query -c xfce4-desktop -p "$property" -n -t string -s '${wallpaper}'
        xfconf-query -c xfce4-desktop -p "$base/image-style" -n -t int -s 5
        xfconf-query -c xfce4-desktop -p "$base/backdrop-cycle-enable" -n -t bool -s false
      done <<< "$properties"
    '';
  };
  gtkCss = ''
    @define-color theme_selected_bg_color ${palette.accent};
    @define-color theme_selected_fg_color ${palette.background};
    @define-color selected_bg_color ${palette.accent};
    @define-color selected_fg_color ${palette.background};
    @define-color accent_bg_color ${palette.accent};
    @define-color accent_fg_color ${palette.background};
    @define-color accent_color ${palette.accent};
    window, dialog, .background { background-color: ${palette.background}; color: ${palette.foreground}; }
    headerbar, menubar, toolbar { background: ${palette.surface}; color: ${palette.foreground}; }
    selection, row:selected { background-color: ${palette.accent}; color: ${palette.background}; }
    button:checked { background: ${palette.accent}; color: ${palette.background}; }
    progressbar progress, scale highlight { background: ${palette.accent}; border-color: ${palette.accent}; }
    .xfce4-panel { background: ${palette.background}; color: ${palette.foreground}; border-top: 1px solid ${palette.border}; }
    .xfce4-panel button { background: transparent; border: 0; border-radius: 4px; box-shadow: none; padding: 2px 6px; }
    .xfce4-panel button:hover { background: ${palette.surface}; }
    .xfce4-panel button:checked { background: ${palette.surface}; color: ${palette.accent}; border-bottom: 2px solid ${palette.accent}; }
    #whiskermenu-window { background: ${palette.background}; color: ${palette.foreground}; }
  '';
in {
  environment.systemPackages = [ applyWallpaper ];
  home-manager.users.${settings.username} = {
    # Explicit managed CSS, without modifying the upstream GTK theme package.
    xdg.configFile."gtk-3.0/gtk.css".text = gtkCss;
    xdg.configFile."gtk-4.0/gtk.css".text = gtkCss;
    xdg.dataFile."backgrounds/quiet-hills.png".source = wallpaper;
    xdg.configFile."autostart/quiet-wallpaper.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Quiet wallpaper
      Exec=${applyWallpaper}/bin/apply-quiet-wallpaper
      OnlyShowIn=XFCE;
      NoDisplay=true
      Terminal=false
    '';
    programs.rofi = {
      enable = true;
      font = "DejaVu Sans 12";
      terminal = "${pkgs.alacritty}/bin/alacritty";
      modes = [ "drun" ];
      extraConfig = {
        show-icons = true;
        display-drun = "Open";
        drun-display-format = "{name}";
        icon-theme = "elementary-xfce-dark";
      };
      theme = let literal = value: { _type = "literal"; inherit value; }; in {
        "*" = {
          background-color = literal palette.background;
          text-color = literal palette.foreground;
          border-color = literal palette.border;
        };
        window = { width = literal "540px"; border = literal "1px"; border-radius = literal "10px"; padding = literal "18px"; };
        mainbox = { spacing = literal "12px"; children = map literal [ "inputbar" "listview" ]; };
        inputbar = { spacing = literal "10px"; padding = literal "8px"; children = map literal [ "prompt" "entry" ]; };
        prompt.text-color = literal palette.accent;
        entry = { placeholder = "Search applications"; placeholder-color = literal palette.muted; };
        listview = { lines = 7; columns = 1; fixed-height = false; scrollbar = false; spacing = literal "4px"; };
        element = { padding = literal "10px"; border-radius = literal "5px"; spacing = literal "10px"; };
        "element selected.normal" = { background-color = literal palette.accent; text-color = literal palette.background; };
        "element-icon, element-text" = { background-color = literal "inherit"; text-color = literal "inherit"; };
        element-icon.size = literal "22px";
      };
    };
    programs.alacritty.settings = {
      window.opacity = 1.0;
      bell.duration = 0;
      colors = {
        primary = { background = lib.mkForce palette.background; foreground = lib.mkForce palette.foreground; };
        cursor = { cursor = palette.accent; text = palette.background; };
        selection = { background = palette.accent; text = palette.background; };
        normal = { black = "#29312d"; red = "#cb9290"; green = "#a7bf9e"; yellow = "#c9bb91"; blue = "#92afb9"; magenta = "#b5a0bd"; cyan = "#91b9ab"; white = "#d1d9ce"; };
        bright = { black = "#708075"; red = "#dfa8a2"; green = "#bfd4b7"; yellow = "#ded0a6"; blue = "#aac7d0"; magenta = "#cab6d1"; cyan = "#aed0c1"; white = "#eef1e9"; };
      };
    };
    xfconf.settings = {
      xsettings = {
        "Net/EnableEventSounds" = false;
        "Net/EnableInputFeedbackSounds" = false;
        "Gtk/EnableAnimations" = false;
      };
      xfwm4 = {
        "general/frame_opacity" = 100;
        "general/inactive_opacity" = 100;
        "general/move_opacity" = 100;
        "general/resize_opacity" = 100;
        "general/popup_opacity" = 100;
        "general/show_dock_shadow" = false;
      };
      xfce4-desktop."backdrop/single-workspace-mode" = true;
      xfce4-panel = {
        "panels/panel-1/size" = lib.mkForce { type = "uint"; value = 32; };
        "panels/panel-1/icon-size" = lib.mkForce { type = "uint"; value = 22; };
        "panels/panel-1/enter-opacity" = { type = "uint"; value = 100; };
        "panels/panel-1/leave-opacity" = { type = "uint"; value = 100; };
      };
      xfce4-notifyd = {
        "initial-opacity" = 1.0;
        "mute-sounds" = true;
        "do-not-disturb" = false;
        "expire-timeout" = 5;
        "expire-timeout-enabled" = true;
        "do-fadeout" = false;
        "do-slideout" = false;
      };
    };
  };
}
