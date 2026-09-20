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
    pkgs.protonup-qt
  ];
}
