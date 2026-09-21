#!/usr/bin/env bash
# Safe by construction: never source or execute installer/install.sh.
set -Eeuo pipefail
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=installer/prepare.sh
source "$source_dir/installer/prepare.sh"
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/staged"
stage_configuration "$source_dir" "$work/staged"
# Every Nix file used by the installed system must survive the copy.
while IFS= read -r file; do
  cmp "$source_dir/$file" "$work/staged/$file"
done < <(cd "$source_dir" && find hosts modules home -type f -name '*.nix')
cmp "$source_dir/flake.lock" "$work/staged/flake.lock"
mkdir "$work/incomplete" "$work/rejected"
cp -R "$source_dir/installer" "$work/incomplete/"
if (stage_configuration "$work/incomplete" "$work/rejected") 2>/dev/null; then
  die 'Incomplete installer source was accepted'
fi
[[ ${1:-} != --evaluate ]] && { echo 'Installer staging tests passed'; exit 0; }
configuration_preflight "$work/staged"
[[ ! -e $work/staged/hosts/nixos/hardware-configuration.nix ]]
cmp "$source_dir/flake.lock" "$work/staged/flake.lock"
# The same production helper must reject invalid options AND assertions.
cp "$work/staged/configuration.nix" "$work/valid.nix"
printf '{ ... }: { imports = [ ./valid.nix ]; invalidInstallerOption = true; }\n' > "$work/staged/configuration.nix"
cp "$work/valid.nix" "$work/staged/valid.nix"
if (configuration_preflight "$work/staged") >"$work/invalid.log" 2>&1; then
  die 'Unknown NixOS option passed preflight'
fi
rg -q 'invalidInstallerOption.*does not exist' "$work/invalid.log"
printf '{ ... }: { imports = [ ./valid.nix ]; assertions = [{ assertion = false; message = "installer-test-assertion"; }]; }\n' > "$work/staged/configuration.nix"
if (configuration_preflight "$work/staged") >"$work/assertion.log" 2>&1; then
  die 'Failed system assertion passed preflight'
fi
rg -q 'installer-test-assertion' "$work/assertion.log"
cp "$work/valid.nix" "$work/staged/configuration.nix"
# An input declaration that disagrees with the lock must fail, not resolve anew.
cp "$work/staged/flake.nix" "$work/locked-flake.nix"
sed -i 's@nixos-26.05@nixos-25.11@' "$work/staged/flake.nix"
if (configuration_preflight "$work/staged") >"$work/lock.log" 2>&1; then
  die 'An inconsistent lock passed preflight'
fi
rg -q 'lock file.*changes|requires lock file changes' "$work/lock.log"
cmp "$source_dir/flake.lock" "$work/staged/flake.lock"
cp "$work/locked-flake.nix" "$work/staged/flake.nix"
# Exercise the VM/no-GPU branch and a valid username requiring systemd escaping.
sed -i -e 's/username = ".*"/username = "test-user"/' \
  -e 's/amdgpuBusId = ".*"/amdgpuBusId = ""/' \
  -e 's/nvidiaBusId = ".*"/nvidiaBusId = ""/' "$work/staged/hosts/nixos/settings.nix"
configuration_preflight "$work/staged"
echo 'Installer valid, invalid-option, failed-assertion, inconsistent-lock, and fresh-user/no-GPU preflights passed'
