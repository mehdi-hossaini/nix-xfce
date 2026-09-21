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
  benchmarkConfig = pkgs.writeText "gaming-MangoHud.conf" ''
    position=top-right
    fps
    frametime
    frame_timing
    fps_metrics=avg,0.01
    gpu_stats
    gpu_name
    gpu_temp
    gpu_power
    gpu_core_clock
    gpu_mem_clock
    cpu_stats
    cpu_temp
    cpu_mhz
    ram
    vram
    swap
    throttling_status
    log_duration=60
    log_interval=0
    benchmark_percentiles=AVG+1+0.1
    toggle_logging=Shift_L+F2
    toggle_hud=Shift_R+F12
  '';
  gameBenchmark = pkgs.writeShellApplication {
    name = "game-benchmark";
    runtimeInputs = [
      pkgs.mangohud
      pkgs.coreutils
      gamePerformance
    ];
    text = ''
      if [[ $# -eq 0 ]]; then
        echo "Usage: game-benchmark COMMAND [ARG...]" >&2
        echo "Steam: game-benchmark nvidia-offload %command%" >&2
        exit 2
      fi
      log_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/game-benchmarks"
      mkdir -p "$log_dir"
      export MANGOHUD_CONFIGFILE=${benchmarkConfig}
      # MangoHud 0.8.3 otherwise logs the first DRM GPU, even when the
      # renderer/header identifies NVIDIA. Select the offloaded GPU explicitly.
      gpu_pci="''${GAME_BENCHMARK_GPU:-}"
      if [[ -z "$gpu_pci" ]] && { [[ "''${1##*/}" == nvidia-offload ]] || [[ "''${__NV_PRIME_RENDER_OFFLOAD:-0}" == 1 ]]; }; then
        for device in /sys/bus/pci/drivers/nvidia/????:??:??.?; do
          if [[ -e "$device" ]]; then
            gpu_pci="''${device##*/}"
            break
          fi
        done
      fi
      # Colons are delimiters in MANGOHUD_CONFIG (unlike the config file).
      gpu_pci="''${gpu_pci//:/\\:}"
      export MANGOHUD_CONFIG="read_cfg,output_folder=$log_dir''${gpu_pci:+,pci_dev=$gpu_pci}''${MANGOHUD_CONFIG:+,$MANGOHUD_CONFIG}"
      exec game-performance mangohud "$@"
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
    gameBenchmark
    pkgs.mangohud
    pkgs.protonup-qt
  ];
}
