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

  outputs = { nixpkgs, impermanence, nix-cachyos-kernel, codex-desktop-linux, zen-browser, home-manager, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ nix-cachyos-kernel.overlays.pinned ]; }
        ({ pkgs, ... }: {
          environment.systemPackages = [
            (zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.beta.override {
              # Default browser chrome to dark with sage selection accents.
              extraPolicies.Preferences = {
                "ui.systemUsesDarkTheme" = { Value = 1; Status = "default"; };
                "browser.theme.toolbar-theme" = { Value = 0; Status = "default"; };
                "browser.theme.content-theme" = { Value = 0; Status = "default"; };
                "ui.highlight" = { Value = "#a7bf9e"; Status = "default"; };
                "ui.highlighttext" = { Value = "#202624"; Status = "default"; };
              };
            })
          ];
        })
        codex-desktop-linux.nixosModules.default
        home-manager.nixosModules.home-manager
        impermanence.nixosModules.impermanence
        ./configuration.nix
      ];
    };
  };
}
