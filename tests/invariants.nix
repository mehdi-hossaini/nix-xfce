{
  config,
  lib,
  settings,
  utils,
}:
let
  c = config;
  inherit (settings) username;
  persistent = map (d: d.directory) c.environment.persistence."/persist".directories;
  ensure = condition: message: {
    assertion = condition;
    inherit message;
  };
in
[
  (ensure (c.fileSystems."/".fsType == "tmpfs") "Root must remain ephemeral")
  (ensure (lib.all (p: c.fileSystems.${p}.neededForBoot) [
    "/home"
    "/nix"
    "/persist"
  ]) "Persistent mounts must be available during boot")
  (ensure (lib.all (p: builtins.elem p persistent) [
    "/etc/nixos"
    "/var/lib/nixos"
    "/var/lib/systemd"
    "/var/lib/nvidia"
    "/var/lib/NetworkManager"
    "/var/log"
  ]) "Required system state must persist")
  (ensure (
    c.users.users.${username}.hashedPasswordFile == "/persist/passwords/user"
    && c.users.users.root.hashedPasswordFile == "/persist/passwords/root"
  ) "Use runtime password files")
  (ensure (lib.all
    (
      u:
      u.hashedPassword == null
      && u.password == null
      && u.initialPassword == null
      && u.initialHashedPassword == null
    )
    [
      c.users.users.${username}
      c.users.users.root
    ]
  ) "Passwords and hashes must stay out of the store")
  (ensure (c.programs.nh.flake == "path:/etc/nixos") "Preserve nh entry point")
  (ensure (
    c.home-manager.users.${username}.home.homeDirectory == "/home/${username}"
  ) "Home Manager must use persistent home")
  (ensure (
    c.systemd.services."home-manager-${utils.escapeSystemdPath username}".unitConfig.RequiresMountsFor
    == "/home/${username}"
  ) "Home Manager must wait for home mount")
]
