{ config, lib, pkgs, ... }:
let
  settings = import ./settings.nix;
  gamePerformance = pkgs.writeShellApplication {
    name = "game-performance";
    runtimeInputs = [ pkgs.power-profiles-daemon pkgs.gnugrep ];
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
in {
  imports = [ ./hardware-configuration.nix ./impermanence.nix ./desktop.nix ./style.nix ];

  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-zen4;
  # CPU scheduling through sched_ext; the kernel's built-in scheduler is fallback.
  services.scx = {
    enable = true;
    package = pkgs.scx.rustscheds;
    scheduler = "scx_cake";
    extraArgs = [ ];
  };
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = settings.hostname;
  networking.networkmanager.enable = true;
  # Keep Wi-Fi awake to avoid power-save latency during online games.
  networking.networkmanager.wifi.powersave = false;
  networking.firewall.enable = true;
  time.timeZone = settings.timezone;
  i18n.defaultLocale = "en_US.UTF-8";
  console.useXkbConfig = true;

  services.xserver = {
    enable = true;
    xkb.layout = settings.keyboard;
    displayManager.lightdm.enable = true;
    desktopManager.xfce.enable = true;
  };
  services.libinput.enable = true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.enableRedistributableFirmware = true;

  # The live installer fills these IDs for the Radeon 760M + RTX 4050 laptop.
  # Leave empty for a VM without the laptop's GPUs passed through.
  nixpkgs.config.allowUnfree = true;
  services.xserver.videoDrivers = lib.mkIf (settings.nvidiaBusId != "") [ "amdgpu" "nvidia" ];
  # VRAM suspend images must not fill the ephemeral root filesystem.
  boot.extraModprobeConfig = lib.mkIf (settings.nvidiaBusId != "") ''
    options nvidia NVreg_TemporaryFilePath=/var/lib/nvidia
  '';
  hardware.nvidia = lib.mkIf (settings.nvidiaBusId != "") {
    open = true;
    modesetting.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    nvidiaSettings = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    prime = {
      amdgpuBusId = settings.amdgpuBusId;
      nvidiaBusId = settings.nvidiaBusId;
      offload.enable = true;
      offload.enableOffloadCmd = true;
    };
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = pkgs.stdenv.hostPlatform.isx86_64;
    pulse.enable = true;
  };
  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.printing.enable = true;
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  users.users.${settings.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    hashedPasswordFile = "/persist/passwords/user";
  };
  users.mutableUsers = false;
  users.users.root.hashedPasswordFile = "/persist/passwords/root";
  programs.codexDesktopLinux.enable = true;
  programs.steam.enable = true;
  # Wine/Proton must also support NTSync to use this device.
  boot.kernelModules = [ "ntsync" ];
  services.power-profiles-daemon.enable = true;
  # CachyOS THP tuning: split huge pages with excessive unused space.
  # Remove this rule and reboot to restore the kernel default (511).
  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 409"
  ];
  programs.nh = {
    enable = true;
    flake = "path:/etc/nixos";
  };
  environment.systemPackages = with pkgs; [ git nano wget curl htop unzip openssl gamePerformance zed-editor protonup-qt ];
  fonts.packages = with pkgs; [ dejavu_fonts noto-fonts-color-emoji ];
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    # Logical swap capacity, allocated/compressed on demand; not reserved RAM.
    memoryPercent = 50;
    priority = 100;
  };
  # ZRAM already compresses swap; avoid adding a second compression cache.
  boot.kernelParams = [ "zswap.enabled=0" ];
  boot.kernel.sysctl = {
    "vm.swappiness" = 150;
    "vm.page-cluster" = 0;
  };

  # /var/log is persistent under Impermanence.
  services.journald.storage = "persistent";
  services.journald.extraConfig = ''
    SystemMaxUse=250M
    RuntimeMaxUse=50M
  '';
  systemd.coredump = {
    enable = true;
    settings.Coredump = {
      Storage = "external";
      Compress = true;
      ProcessSizeMax = "256M";
      ExternalSizeMax = "256M";
      MaxUse = "512M";
      KeepFree = "1G";
    };
  };
  # Sort before upstream systemd.conf so its two-week rule does not win.
  # The normal systemd-tmpfiles-clean timer performs age-based cleanup.
  environment.etc."tmpfiles.d/00-workstation-coredump.conf".text = ''
    d /var/lib/systemd/coredump 0755 root root 3d
  '';
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  # Upstream caches; the installer also enables them in the live ISO.
  nix.settings.substituters = [
    "https://attic.xuyh0120.win/lantian"
    "https://codex-desktop-linux.cachix.org"
  ];
  nix.settings.trusted-public-keys = [
    "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
    "codex-desktop-linux.cachix.org-1:nX/xy6AdK9hQE24A8ALGjkCKj2ObFmcnemiL5Cid4nk="
  ];

  # Keep this at the original installation version when upgrading nixpkgs.
  system.stateVersion = "26.05";
}
