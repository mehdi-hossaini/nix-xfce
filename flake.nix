{
  description = "NixOS XFCE Impermanence workstation with CachyOS Zen 4 kernel";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.impermanence.url = "github:nix-community/impermanence";
  inputs.impermanence.inputs.nixpkgs.follows = "nixpkgs";
  inputs.impermanence.inputs.home-manager.follows = "";
  # Keep the kernel project's own nixpkgs pin to match its prebuilt kernels.
  inputs.nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
  # Retain each application's upstream nixpkgs pin for its packaging dependencies.
  inputs.codex-desktop-linux.url = "github:ilysenko/codex-desktop-linux";
  inputs.zen-browser.url = "github:0xc000022070/zen-browser-flake/beta";
  inputs.home-manager.url = "github:nix-community/home-manager/release-26.05";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    inputs@{
      nixpkgs,
      impermanence,
      nix-cachyos-kernel,
      codex-desktop-linux,
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      formatter.${system} = pkgs.nixfmt;
      checks.${system} = {
        validation =
          assert import ./tests/validation.nix {
            configuration = inputs.self.nixosConfigurations.nixos;
          };
          pkgs.runCommand "validation-checks" { } ''touch "$out"'';
        installer =
          pkgs.runCommand "installer-checks"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.python3
                pkgs.shellcheck
                pkgs.ripgrep
              ];
            }
            ''
              cp -R ${./.} source
              chmod -R u+w source
              cd source
              shellcheck -x install.sh installer/*.sh tests/*.sh
              for script in install.sh installer/*.sh tests/*.sh; do bash -n "$script"; done
              bash tests/installer.sh
              python3 tests/battery_profile.py
              touch "$out"
            '';
      };
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          settings = import ./hosts/nixos/settings.nix;
        };
        modules = [
          { nixpkgs.overlays = [ nix-cachyos-kernel.overlays.pinned ]; }
          codex-desktop-linux.nixosModules.default
          home-manager.nixosModules.home-manager
          impermanence.nixosModules.impermanence
          (
            {
              config,
              lib,
              settings,
              utils,
              ...
            }:
            {
              assertions = import ./tests/invariants.nix {
                inherit
                  config
                  lib
                  settings
                  utils
                  ;
              };
            }
          )
          ./configuration.nix
        ];
      };
    };
}
