#!/usr/bin/env bash
# Sourceable preparation only: no mount, formatting, passwords, or installation.
# Callers own temporary-directory cleanup and supply die().
stage_configuration() {
  local source_dir=$1 staging=$2
  local entry
  while IFS= read -r entry; do
    [[ -n $entry && $entry != \#* ]] || continue
    [[ -e $source_dir/$entry ]] || { die "Missing installer input: $entry"; return 1; }
    cp -R -- "$source_dir/$entry" "$staging/"
  done < "$source_dir/installer/manifest"
}

configuration_preflight() {
  local staging=$1
  cat > "$staging/hosts/nixos/hardware-configuration.nix" <<'EOF'
{ ... }: {
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/PREFLIGHT_EFI";
    fsType = "vfat";
  };
  fileSystems."/nix" = {
    device = "/dev/disk/by-label/PREFLIGHT_BTRFS";
    fsType = "btrfs";
    options = [ "subvol=nix" ];
  };
  fileSystems."/persist" = {
    device = "/dev/disk/by-label/PREFLIGHT_BTRFS";
    fsType = "btrfs";
    options = [ "subvol=persist" ];
  };
  fileSystems."/home" = {
    device = "/dev/disk/by-label/PREFLIGHT_BTRFS";
    fsType = "btrfs";
    options = [ "subvol=home" ];
  };
}
EOF
  printf 'Validating the system configuration before disk changes...\n'
  nix eval --no-update-lock-file --raw "path:$staging#nixosConfigurations.nixos.config.system.build.toplevel.drvPath" >/dev/null \
    || die 'Configuration validation failed; no target disk changes have been made.'
  rm -- "$staging/hosts/nixos/hardware-configuration.nix"
}
