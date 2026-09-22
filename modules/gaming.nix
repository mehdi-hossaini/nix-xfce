{ pkgs, ... }:
let
  batteryPython = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
  # scx v1.1.3 contains the rewritten scx_cake 1.2.x. Keep the existing
  # nixpkgs package available as a one-line rollback while this is evaluated.
  useScxCakeNext = true;
  scxNextSrc = pkgs.fetchFromGitHub {
    owner = "sched-ext";
    repo = "scx";
    tag = "v1.1.3";
    hash = "sha256-LK0go5blWgCtDpS5xm9BQc7C2NvbfrW+Jp66ImIThxA=";
  };
  scxNext = pkgs.scx.rustscheds.overrideAttrs (old: {
    pname = "scx-rustscheds-next";
    version = "1.1.3";
    src = scxNextSrc;
    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      src = scxNextSrc;
      hash = "sha256-vEsbpor52DEUpYO5OubFPMzRltO5kUXjqAoO/9hsKXc=";
    };
    # The upstream release adds scheduler binaries not listed by nixpkgs 26.05.
    doInstallCheck = false;
  });
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
    package = if useScxCakeNext then scxNext else pkgs.scx.rustscheds;
    scheduler = "scx_cake";
    # scx_cake 1.2.x is fully adaptive and intentionally has no profiles.
    extraArgs =
      if useScxCakeNext then
        [ ]
      else
        [
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
