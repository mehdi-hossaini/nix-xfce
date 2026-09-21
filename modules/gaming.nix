{ pkgs, ... }:
let
  batteryPython = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  gamePerformance = pkgs.writeShellApplication {
    name = "game-performance";
    runtimeInputs = [
      pkgs.power-profiles-daemon
      pkgs.gnugrep
    ];
    text = ''
      if [[ $# -eq 0 ]]; then
        echo "Usage: game-performance COMMAND [ARG...]" >&2
        exit 2
      fi
      # Release the performance request when the game exits. Concurrent games
      # get independent requests instead of overwriting the user's profile.
      if powerprofilesctl list | grep 'performance:' >/dev/null; then
        exec powerprofilesctl launch --profile performance \
          --reason "Game launched with game-performance" -- "$@"
      fi
      echo "Performance profile unavailable; using the current profile." >&2
      exec "$@"
    '';
  };
in
{
  # CPU scheduling through sched_ext; the kernel's built-in scheduler is fallback.
  services.scx = {
    enable = true;
    package = pkgs.scx.rustscheds;
    scheduler = "scx_cake";
    extraArgs = [
      "--profile"
      "esports"
    ];
  };
  programs.steam.enable = true;
  boot.kernelModules = [ "ntsync" ];
  services.power-profiles-daemon.enable = true;
  # XFCE 4.20 writes ActiveProfile on every AC transition. That releases all
  # PPD holds, including ongoing games, and races the battery hold below.
  # Leave its manual profile settings and all other power management intact;
  # give automatic AC transitions to the hold-based policy only.
  nixpkgs.overlays = [
    (_final: prev: {
      xfce4-power-manager = prev.xfce4-power-manager.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/xfpm-ppd.c --replace-fail \
            'xfpm_ppd_set_active_profile (ppd, on_battery ? ppd->profile_on_battery : ppd->profile_on_ac);' \
            '/* Automatic profiles are managed by nixos-battery-profile. */ (void) ppd;'
        '';
      });
    })
  ];
  # Power-saver holds take precedence over game-performance's performance
  # holds. Plugging back in releases only this hold, resuming an ongoing game
  # or the user's desktop profile. No polling or competing CPU governor daemon.
  services.upower.enable = true;
  systemd.user.services.battery-profile = {
    description = "Battery-aware power profile";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${batteryPython}/bin/python3 ${./battery-profile.py}";
      Restart = "always";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };
  # CachyOS THP tuning: split huge pages with excessive unused space.
  # Remove this rule and reboot to restore the kernel default (511).
  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 409"
  ];
  environment.systemPackages = [
    gamePerformance
    pkgs.protonup-qt
  ];
}
