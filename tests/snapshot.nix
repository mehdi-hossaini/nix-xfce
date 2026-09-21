# nix eval --impure --json --expr 'import ./tests/snapshot.nix { source = "/etc/nixos"; }'
{
  source ? null,
  # Tests may supply an evaluated configuration without creating another flake.
  configuration ? (builtins.getFlake ("path:" + source)).nixosConfigurations.nixos,
}:
let
  c = configuration.config;
  lib = configuration.lib;
  user = configuration._module.specialArgs.settings.username;
  h = c.home-manager.users.${user};
  paths = map toString;
in
{
  inherit (c.networking) hostName;
  inherit (c.system) stateVersion;
  kernel = c.boot.kernelPackages.kernel.drvPath;
  kernelModules = paths c.boot.kernelModules;
  inherit (c.boot) kernelParams extraModprobeConfig;
  sysctl = c.boot.kernel.sysctl;
  fileSystems = lib.mapAttrs (_: fs: {
    inherit (fs)
      device
      fsType
      neededForBoot
      depends
      ;
    options = paths fs.options;
  }) c.fileSystems;
  persistence = {
    directories = map (d: {
      inherit (d)
        directory
        user
        group
        mode
        ;
    }) c.environment.persistence."/persist".directories;
    files = map (f: { inherit (f) file parentDirectory; }) c.environment.persistence."/persist".files;
  };
  systemPackages = paths c.environment.systemPackages;
  fonts = paths c.fonts.packages;
  zramSwap = {
    inherit (c.zramSwap)
      enable
      algorithm
      memoryPercent
      priority
      ;
  };
  nvidia = {
    inherit (c.hardware.nvidia)
      open
      modesetting
      dynamicBoost
      powerManagement
      prime
      ;
    package = c.hardware.nvidia.package.drvPath;
  };
  scx = {
    inherit (c.services.scx) enable scheduler extraArgs;
    package = c.services.scx.package.drvPath;
  };
  users = lib.mapAttrs (_: u: {
    inherit (u)
      uid
      group
      extraGroups
      home
      isNormalUser
      hashedPasswordFile
      ;
  }) c.users.users;
  home = {
    inherit (h.home)
      username
      homeDirectory
      stateVersion
      sessionVariables
      sessionPath
      ;
    activation = h.home.activationPackage.drvPath;
    xfconf = h.xfconf.settings;
    # XDG config/data files and generated user units feed into home.file.
    # Keep source references, never read the files or password hashes here.
    files = lib.mapAttrs (_: file: {
      source = toString file.source;
      inherit (file) target executable recursive;
    }) (lib.filterAttrs (_: file: file.enable) h.home.file);
    systemd = {
      inherit (h.systemd.user) services sessionVariables;
    };
  };
  # Generated service units, /etc files and activation scripts cover the effects
  # of settings beyond the explicit high-risk fields above.
  units = lib.mapAttrs (_: u: u.text) c.systemd.units;
  etc = lib.mapAttrs (_: e: {
    source = toString e.source;
    inherit (e) mode user group;
  }) c.environment.etc;
  activation = lib.mapAttrs (
    _: a: if builtins.isString a then a else { inherit (a) text deps; }
  ) c.system.activationScripts;
  inherit (c.programs.nh) flake;
}
