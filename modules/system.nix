{ pkgs, settings, ... }:
{
  networking.hostName = settings.hostname;
  networking.networkmanager.enable = true;
  # Keep Wi-Fi awake to avoid power-save latency during online games.
  networking.networkmanager.wifi.powersave = false;
  networking.firewall.enable = true;
  time.timeZone = settings.timezone;
  i18n.defaultLocale = "en_US.UTF-8";
  console.useXkbConfig = true;

  hardware.enableRedistributableFirmware = true;
  nixpkgs.config.allowUnfree = true;
  programs.nh = {
    enable = true;
    flake = "path:/etc/nixos";
  };
  environment.systemPackages = with pkgs; [
    git
    nano
    wget
    curl
    htop
    unzip
    openssl
  ];
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
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
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
