{ lib, ... }: {
  # A fresh root on every boot. Large downloads should go in /home, not /tmp.
  fileSystems."/" = lib.mkForce {
    device = "none";
    fsType = "tmpfs";
    options = [
      "size=25%"
      "mode=755"
    ];
  };
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/nix".neededForBoot = true;
  fileSystems."/home".neededForBoot = true;
  # The hardware scanner preserves subvolume names, not these mount options.
  fileSystems."/nix".options = lib.mkAfter [
    "compress=zstd"
    "noatime"
  ];
  fileSystems."/persist".options = lib.mkAfter [
    "compress=zstd"
    "noatime"
  ];
  fileSystems."/home".options = lib.mkAfter [
    "compress=zstd"
    "noatime"
  ];

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/etc/nixos"
      "/var/lib/nixos"
      "/var/lib/nvidia"
      "/var/lib/systemd"
      "/var/lib/NetworkManager"
      # Preserve the selected base power profile and daemon action preferences.
      "/var/lib/power-profiles-daemon"
      # Keep battery history across boots for useful health/runtime estimates.
      "/var/lib/upower"
      {
        directory = "/etc/NetworkManager/system-connections";
        mode = "0700";
      }
      {
        directory = "/var/lib/bluetooth";
        mode = "0700";
      }
      "/var/lib/AccountsService"
      "/var/lib/lightdm"
      # NixOS links /etc/cups to /var/lib/cups; persist only the target.
      "/var/lib/cups"
      "/var/log"
    ];
    files = [ "/etc/machine-id" ];
  };
  # /home and /nix are separate Btrfs mounts, so all of their contents persist.
  # Password hashes live under /persist/passwords, outside the Nix store.
}
