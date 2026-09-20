{
  config,
  lib,
  pkgs,
  settings,
  ...
}:
{
  imports = [ ./hardware-configuration.nix ];
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-zen4;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  # The live installer fills these IDs for the Radeon 760M + RTX 4050 laptop.
  # Leave empty for a VM without the laptop's GPUs passed through.
  services.xserver.videoDrivers = lib.mkIf (settings.nvidiaBusId != "") [
    "amdgpu"
    "nvidia"
  ];
  # VRAM suspend images must not fill the ephemeral root filesystem.
  boot.extraModprobeConfig = lib.mkIf (settings.nvidiaBusId != "") ''
    options nvidia NVreg_TemporaryFilePath=/var/lib/nvidia
  '';
  hardware.nvidia = lib.mkIf (settings.nvidiaBusId != "") {
    open = true;
    modesetting.enable = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    nvidiaSettings = true;
    # Supported by this laptop firmware; balances CPU/GPU power via nvidia-powerd.
    dynamicBoost.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    prime = {
      amdgpuBusId = settings.amdgpuBusId;
      nvidiaBusId = settings.nvidiaBusId;
      offload.enable = true;
      offload.enableOffloadCmd = true;
    };
  };

}
