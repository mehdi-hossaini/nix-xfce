{
  pkgs,
  lib,
  settings,
  ...
}:
let
  style = import ../../home/style.nix { inherit pkgs lib; };
in
{
  environment.systemPackages = [ style.command ];
  home-manager.users.${settings.username} = style.home;
}
