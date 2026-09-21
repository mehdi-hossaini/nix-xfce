{ pkgs, ... }:
let
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
    gpu_temp
    gpu_power
    gpu_core_clock
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
      export MANGOHUD_CONFIG="read_cfg,output_folder=$log_dir"
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
