# Installed-system composition. The flake supplies pinned external modules.
{ ... }: {
  imports = [
    ./hosts/nixos
    ./modules/system.nix
    ./modules/users.nix
    ./modules/persistence.nix
    ./modules/gaming.nix
    ./modules/desktop/xfce.nix
    ./modules/desktop/apps.nix
  ];
}
