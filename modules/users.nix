{ pkgs, settings, ... }:
{
  programs.zsh.enable = true;
  users.users.${settings.username} = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    hashedPasswordFile = "/persist/passwords/user";
  };
  users.mutableUsers = false;
  users.users.root.hashedPasswordFile = "/persist/passwords/root";
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "before-xfce-setup";
}
