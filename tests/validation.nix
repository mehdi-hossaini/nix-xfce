# Pure evaluation regressions; never execute the installer or activate a system.
{ configuration }:
let
  inherit (configuration) lib;
  snapshot = config: import ./snapshot.nix { configuration = config; };
  settings = configuration._module.specialArgs.settings;
  # Hyphens require escaping in Home Manager's systemd service name.
  alternateUser = "validation-user";
  alternate = configuration.extendModules {
    specialArgs.settings = settings // {
      username = alternateUser;
    };
  };
  invalid = alternate.extendModules {
    modules = [
      { users.users.${alternateUser}.hashedPasswordFile = lib.mkForce "/wrong/password-path"; }
    ];
  };
  withOptions =
    options:
    configuration
    // {
      config = configuration.config // {
        fileSystems = configuration.config.fileSystems // {
          "/home" = configuration.config.fileSystems."/home" // {
            inherit options;
          };
        };
      };
    };
  # An unrelated user that sorts first must not change the selected home.
  withEarlierUser = alternate // {
    config = alternate.config // {
      home-manager = alternate.config.home-manager // {
        users = alternate.config.home-manager.users // {
          "aaa-unrelated" = throw "Snapshot selected an unrelated Home Manager user";
        };
      };
    };
  };
in
assert lib.assertMsg (lib.all (a: a.assertion)
  alternate.config.assertions
) "Assertions must follow supplied settings without editing the host settings file";
assert lib.assertMsg (lib.any (a: a.message == "Use runtime password files" && !a.assertion)
  invalid.config.assertions
) "Assertions must reject an incorrect password path for the supplied user";
assert lib.assertMsg (
  (snapshot (withOptions [
    "ro"
    "rw"
  ])).fileSystems."/home".options != (snapshot (withOptions [
    "rw"
    "ro"
  ])).fileSystems."/home".options
) "Snapshots must preserve mount-option order";
assert lib.assertMsg (
  (snapshot withEarlierUser).home.username == alternateUser
) "Snapshots must select the configured administrator";
true
