#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
trap 'printf "Installation stopped at line %s. Do not reboot until installation and password setup succeed. See README.md for recovery.\n" "$LINENO" >&2' ERR

if [[ ${1:-} == --help ]]; then
  printf 'Usage: sudo bash install.sh [--mounted]\nDefault: erase a selected disk after confirmation.\n--mounted: use existing mounts at /mnt and /mnt/boot without formatting.\n'
  exit 0
fi
[[ $# -eq 0 || ( $# -eq 1 && $1 == --mounted ) ]] || die 'Unknown argument; use --help.'
[[ $EUID -eq 0 ]] || die 'Run with sudo bash install.sh.'
[[ -t 0 ]] || die 'Run interactively in a terminal.'
[[ -e /etc/NIXOS && -d /iso ]] || die 'Boot the official NixOS live ISO first.'
[[ -d /sys/firmware/efi ]] || die 'Boot the live ISO in UEFI mode. Legacy BIOS is not supported.'
[[ $(uname -m) == x86_64 ]] || die 'The CachyOS Zen 4 kernel requires x86_64. Use an x86_64 NixOS ISO on a compatible AMD Zen 4 CPU.'
printf 'This configuration uses the CachyOS Zen 4 kernel. The target CPU must support Zen 4 instructions.\n'
for command in nix nixos-install nixos-generate-config lsblk findmnt mount mountpoint parted partprobe udevadm mkfs.fat mkfs.btrfs btrfs swapon readlink awk; do
  command -v "$command" >/dev/null || die "Missing tool: $command. Use a current NixOS live ISO."
done

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=installer/prepare.sh
source "$source_dir/installer/prepare.sh"
ask() {
  local value
  read -r -p "$2 [$3]: " value
  printf -v "$1" '%s' "${value:-$3}"
}
# Assigned indirectly by ask() using printf -v; declare for static analysis.
hostname="" username="" timezone="" keyboard=""
ask hostname 'Hostname' nixos
[[ $hostname =~ ^[a-z][a-z0-9-]{0,61}[a-z0-9]$ || $hostname =~ ^[a-z]$ ]] || die 'Use a lowercase hostname, at most 63 characters, with letters, digits and internal hyphens.'
ask username 'Administrator username' user
[[ $username =~ ^[a-z][a-z0-9_-]{0,30}$ ]] || die 'Use a lowercase username beginning with a letter, at most 31 characters.'
case $username in root|nixos|nobody|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|gnats|polkituser|messagebus|avahi|cups|lightdm|nm-openvpn|systemd-*|nixbld*) die 'Choose a non-system username.' ;; esac
ask timezone 'Timezone' Europe/Stockholm
[[ $timezone =~ ^[A-Za-z0-9_+/-]+$ && $timezone != *..* && -f /etc/zoneinfo/$timezone ]] || die 'Unknown timezone (example: Europe/Stockholm or UTC).'
ask keyboard 'X11 keyboard layout (us, se, gb, etc.)' us
[[ $keyboard =~ ^[a-z]{2,8}$ ]] || die 'Use a single lowercase keyboard layout code.'

# Detect this laptop's GPUs from Linux, not Windows bus numbering.
amdgpuBusId=""
nvidiaBusId=""
pci_bus_id() {
  local address=${1##*/} domain bus device function
  IFS=':.' read -r domain bus device function <<< "$address"
  [[ $address =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$ ]] || die "Invalid PCI address: $address"
  printf 'PCI:%d@%d:%d:%d' "$((16#$bus))" "$((16#$domain))" "$((16#$device))" "$((16#$function))"
}
for gpu in /sys/bus/pci/devices/*; do
  [[ -f $gpu/class && -f $gpu/vendor && -f $gpu/device ]] || continue
  [[ $(< "$gpu/class") == 0x03* ]] || continue
  case "$(< "$gpu/vendor"):$(< "$gpu/device")" in
    0x1002:0x1900)
      [[ -z $amdgpuBusId ]] || die 'Multiple matching AMD GPUs; configure PCI IDs manually.'
      amdgpuBusId=$(pci_bus_id "$gpu") ;;
    0x10de:0x28a1)
      [[ -z $nvidiaBusId ]] || die 'Multiple matching NVIDIA GPUs; configure PCI IDs manually.'
      nvidiaBusId=$(pci_bus_id "$gpu") ;;
  esac
done
if [[ -n $nvidiaBusId ]]; then
  [[ -n $amdgpuBusId ]] || die 'RTX 4050 found without Radeon 760M. Enable hybrid/switchable graphics in firmware before installing this configuration.'
  printf 'Hybrid graphics: AMD %s, NVIDIA %s\n' "$amdgpuBusId" "$nvidiaBusId"
else
  printf 'RTX 4050 not detected. NVIDIA offload will be disabled (expected in a VM).\n'
fi

# Require the supplied lock before asking to erase anything.
staging=$(mktemp -d /tmp/nixos-installer.XXXXXXXX)
trap 'rm -rf -- "$staging"' EXIT
stage_configuration "$source_dir" "$staging"
cat > "$staging/hosts/nixos/settings.nix" <<EOF
{
  hostname = "$hostname";
  username = "$username";
  timezone = "$timezone";
  keyboard = "$keyboard";
  amdgpuBusId = "$amdgpuBusId";
  nvidiaBusId = "$nvidiaBusId";
}
EOF
export NIX_CONFIG="${NIX_CONFIG:-}
experimental-features = nix-command flakes
extra-substituters = https://attic.xuyh0120.win/lantian https://codex-desktop-linux.cachix.org
extra-trusted-public-keys = lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc= codex-desktop-linux.cachix.org-1:nX/xy6AdK9hQE24A8ALGjkCKj2ObFmcnemiL5Cid4nk="
nix flake metadata --no-update-lock-file "path:$staging" >/dev/null

configuration_preflight "$staging"

# The live ISO may omit OpenSSL even though the installed system includes it.
# Resolve it from the locked nixpkgs before any disk changes.
if command -v openssl >/dev/null; then
  openssl_bin=$(command -v openssl)
else
  printf 'OpenSSL is missing from the live ISO; fetching it with Nix.\n'
  nixpkgs_source=$(NIXOS_INSTALL_STAGING="$staging" nix eval --raw --impure --expr \
    '(builtins.getFlake ("path:" + builtins.getEnv "NIXOS_INSTALL_STAGING")).inputs.nixpkgs.outPath')
  openssl_output=$(nix build --no-link --print-out-paths "path:$nixpkgs_source#openssl^bin")
  openssl_bin="$openssl_output/bin/openssl"
fi
[[ -x $openssl_bin ]] || die 'OpenSSL could not be prepared; no disk changes have been made.'
"$openssl_bin" version >/dev/null

if [[ ${1:-} != --mounted ]]; then
  mountpoint -q /mnt && die '/mnt is already mounted. Use --mounted to resume or unmount it yourself.'
  [[ -z $(findmnt -rn -o TARGET | awk '$0 ~ /^\/mnt\//') ]] || die 'There are mounts beneath /mnt; unmount them first.'
  lsblk -d -o PATH,SIZE,MODEL,TRAN,TYPE
  read -r -p 'Full disk path to ERASE (example /dev/nvme0n1): ' disk
  [[ $disk == /dev/* && -b $disk ]] || die 'Select a block device under /dev.'
  disk=$(readlink -f -- "$disk")
  [[ $(lsblk -dnro TYPE "$disk") == disk ]] || die 'Select a whole disk, not a partition or mapped device.'
  [[ $(lsblk -dnro RO "$disk") == 0 ]] || die 'Disk is read-only.'
  (( $(lsblk -bdnro SIZE "$disk") >= 68719476736 )) || die 'Select a disk of at least 64 GiB.'
  # Reject mounted descendants (including the live USB), swap, and active mappings.
  [[ -z $(lsblk -nr -o MOUNTPOINTS "$disk" | tr -d '[:space:]') ]] || die 'Disk has mounted filesystems or active swap; refusing to erase it.'
  while read -r node type; do
    [[ $type == disk || $type == part ]] || die "Disk has an active mapping: $node ($type)."
    [[ -z $(ls -A "/sys/class/block/${node##*/}/holders") ]] || die "Device $node is in use by another block device."
    while read -r swap; do
      [[ $(readlink -f -- "$swap") != "$node" ]] || die 'Disk contains active swap.'
    done < <(swapon --noheadings --raw --show=NAME)
  done < <(lsblk -nrpo NAME,TYPE "$disk")
  lsblk -o PATH,SIZE,MODEL,FSTYPE,MOUNTPOINTS "$disk"
  printf '\nALL DATA on %s will be erased. New layout: GPT, 1 GiB FAT32 EFI, remaining space Btrfs. Root is ephemeral tmpfs; home, nix and persist are permanent Btrfs subvolumes.\n' "$disk"
  read -r -p "Type exactly 'ERASE $disk' to continue: " confirmation
  [[ $confirmation == "ERASE $disk" ]] || die 'Confirmation did not match; nothing was erased.'
  parted --script "$disk" mklabel gpt
  parted --script "$disk" mkpart ESP fat32 1MiB 1025MiB
  parted --script "$disk" set 1 esp on
  parted --script "$disk" mkpart primary btrfs 1025MiB 100%
  partprobe "$disk"
  udevadm settle
  # Ask the kernel for partition paths, supporting SATA, NVMe, and eMMC naming.
  efi=$(lsblk -nrpo NAME,PARTN "$disk" | awk '$2 == 1 {print $1}')
  root=$(lsblk -nrpo NAME,PARTN "$disk" | awk '$2 == 2 {print $1}')
  [[ -b $efi && -b $root ]] || die 'New partitions did not appear.'
  mkfs.fat -F 32 -n EFI "$efi"
  mkfs.btrfs -f -L nixos "$root"
  btrfs_top=$(mktemp -d /tmp/nixos-btrfs.XXXXXXXX)
  mount "$root" "$btrfs_top"
  for subvol in nix persist home; do btrfs subvolume create "$btrfs_top/$subvol"; done
  umount "$btrfs_top"
  rmdir "$btrfs_top"
  mkdir -p /mnt
  mount -t tmpfs -o size=25%,mode=755 none /mnt
  mkdir -p /mnt/{boot,nix,persist,home}
  for subvol in nix persist home; do
    mount -o "subvol=$subvol,compress=zstd,noatime" "$root" "/mnt/$subvol"
  done
  mount -o umask=0077 "$efi" /mnt/boot
else
  mountpoint -q /mnt || die 'Mount your target root partition at /mnt first.'
  mountpoint -q /mnt/boot || die 'Mount your EFI system partition at /mnt/boot first.'
  [[ $(findmnt -nro FSTYPE --mountpoint /mnt/boot) == vfat ]] || die '/mnt/boot must be a FAT EFI system partition.'
  [[ $(findmnt -nro FSTYPE --mountpoint /mnt) == tmpfs ]] || die 'Impermanence requires a tmpfs root at /mnt; see README.'
  for subvol in nix persist home; do
    mountpoint -q "/mnt/$subvol" || die "Mount the $subvol subvolume at /mnt/$subvol first."
    [[ $(findmnt -nro FSTYPE --mountpoint "/mnt/$subvol") == btrfs ]] || die "$subvol must be a Btrfs mount."
  done
  findmnt -R /mnt
  read -r -p "Type INSTALL to install onto these mounts (existing configuration will be backed up): " confirmation
  [[ $confirmation == INSTALL ]] || die 'Cancelled.'
fi

mkdir -p /mnt/persist/etc/nixos /mnt/etc/nixos
if [[ -f /mnt/persist/etc/nixos/configuration.nix ]]; then
  backup="/mnt/persist/etc/nixos.backup.$(date +%Y%m%d-%H%M%S).$$"
  cp -a /mnt/persist/etc/nixos "$backup"
  printf 'Existing configuration backed up to %s\n' "$backup"
fi
if mountpoint -q /mnt/etc/nixos; then
  # A resumed install may already have our bind mount. Never stage into a
  # different mount and then install the stale configuration under /persist.
  [[ /mnt/etc/nixos -ef /mnt/persist/etc/nixos ]] || die '/mnt/etc/nixos is mounted from a different directory; unmount it before resuming.'
else
  mount --bind /mnt/persist/etc/nixos /mnt/etc/nixos
fi
stage_configuration "$staging" /mnt/etc/nixos
# Impermanence owns the config bind mount; omit it from the hardware scan.
umount /mnt/etc/nixos
nixos-generate-config --root /mnt --show-hardware-config > /mnt/persist/etc/nixos/hosts/nixos/hardware-configuration.nix
mount --bind /mnt/persist/etc/nixos /mnt/etc/nixos
install -d -m 0700 /mnt/persist/passwords
for account in root user; do
  if [[ ! -s /mnt/persist/passwords/$account ]]; then
    printf '\nSet password for %s (user = %s); OpenSSL asks twice:\n' "$account" "$username"
    (umask 077; "$openssl_bin" passwd -6 > "/mnt/persist/passwords/$account.new")
    [[ -s /mnt/persist/passwords/$account.new ]] || die 'Password hash was not created.'
    mv -- "/mnt/persist/passwords/$account.new" "/mnt/persist/passwords/$account"
  fi
done
# Use path: so untracked hardware/settings files are included even inside Git.
nixos-install --root /mnt --no-root-passwd --flake path:/mnt/etc/nixos#nixos
printf '\nInstallation complete. Config: /mnt/etc/nixos\nRun: sudo umount -R /mnt && sudo reboot\nRemove the live USB when the machine restarts.\n'
