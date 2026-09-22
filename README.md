# NixOS XFCE with Impermanence

A NixOS 26.05 workstation configuration and interactive live-ISO installer, with XFCE,
LightDM, Zen Browser (beta), Codex Desktop Linux, Steam, NetworkManager,
PipeWire, Bluetooth, printing, zram, and the
CachyOS Zen 4 kernel. Requires an AMD Zen 4-compatible x86_64 CPU and UEFI;
use the x86_64 ISO. This is not a generic Intel, older AMD, or ARM build.
The laptop target is a Ryzen 5 8645HS with Radeon 760M and RTX 4050 Laptop GPU.
Disable Secure Boot unless you have separately configured signed boot support.
Internet access is required. Use a disk with at least 64 GiB to leave room for
the system, updates, and a 16 GiB persistent swap file. The disk is **unencrypted**.

## Layout and ownership

The stable output is `nixosConfigurations.nixos`, regardless of hostname.
There is no host-discovery framework: `configuration.nix` explicitly imports the
installed-system modules, and `flake.nix` wires external modules and inputs.

| Location | Owns |
| --- | --- |
| `flake.nix`, `flake.lock` | Input pins, overlay, external modules, checks, `settings` argument |
| `configuration.nix` | Installed-system module list |
| `hosts/nixos/default.nix` | Zen 4 kernel, UEFI loader, laptop NVIDIA/PRIME/Dynamic Boost |
| `hosts/nixos/hardware-configuration.nix` | Generated devices, UUIDs, initrd modules, CPU microcode |
| `hosts/nixos/settings.nix` | Hostname, username, timezone, keyboard, detected PCI IDs; no secrets |
| `modules/system.nix` | Network, locale, Nix/cache/nh, base tools, memory and diagnostic storage |
| `modules/users.nix` | Accounts, runtime password-file paths, Home Manager integration |
| `modules/persistence.nix` | Ephemeral root, early mounts, persistent state and mount policy |
| `modules/gaming.nix` | Steam, NTSync, ProtonUp-Qt, scx, gaming/battery power profiles and THP rule |
| `modules/desktop/xfce.nix` | XFCE/LightDM, audio, desktop services, fonts and stable launchers |
| `modules/desktop/apps.nix` | Zen policies, Codex Desktop and Zed |
| `home/xfce.nix` | User desktop, panel layout, shortcuts, MIME associations and terminal |
| `home/style.nix` | Home Manager styling, palette, panel sizes and wallpaper helper |
| `installer/install.sh` | Interactive ISO-only destructive workflow |
| `installer/prepare.sh`, `installer/manifest` | Shared safe staging/preflight and complete source-tree manifest |
| `tests/` | Shell/staging tests, settings-aware NixOS invariants, snapshot and validation regressions |

Keep machine changes in `hosts/nixos`. Reuse the modules with another host by
explicitly composing them and passing its `settings` attribute set. The existing
host selects the Zen 4 kernel; reusing desktop modules alone does not select it.
`home/shell.nix` and `home/style.nix` are Home Manager modules; `home/xfce.nix`
is a parameterized configuration fragment. The desktop module wires them together.

New modules inside `hosts`, `modules`, or `home` are automatically staged by the
installer. If you introduce a new top-level source directory, add it to
`installer/manifest`. Missing required files/imports fail in staging or preflight.
The root `install.sh` is only a compatibility wrapper. Never use it for checks.

## Safe maintenance checks

From `/etc/nixos`, without activating anything:

```bash
nix flake check --no-update-lock-file path:/etc/nixos
bash tests/installer.sh --evaluate
nh os build
# Equivalent full build without an output symlink:
nix build --no-link --no-update-lock-file path:/etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel
```

Check Nix formatting with the pinned formatter, excluding generated hardware:

```bash
rg --files -g '*.nix' -g '!hosts/nixos/hardware-configuration.nix' -0 |
  xargs -0 nix run --no-update-lock-file path:/etc/nixos#formatter.x86_64-linux -- --check
```

To format an edited file, run `nix fmt -- path/to/file.nix` from the repository
as its owner.

The flake check runs ShellCheck, Bash syntax checks, staging tests and NixOS
assertions. It also evaluates `tests/validation.nix`: an alternate administrator
must pass assertions without changing the host settings file, an incorrect password
path must fail, reordered mount options must produce different snapshots, and an
unrelated Home Manager user must not change which user's home is captured.
Assertions receive the same `settings` argument as the installed-system modules.
The separate `--evaluate` suite invokes only `installer/prepare.sh`:
it tests the real preflight with valid configuration, an unknown option, a failed
assertion, an inconsistent lock, and a fresh username without the laptop GPUs. It uses temporary files
and Nix evaluation; it never runs the destructive installer or disk commands.
It needs Bash, Nix and ripgrep (`nix shell` from the locked nixpkgs can supply rg).

For comparing future refactors, save the actual working-tree source outside this
repository before editing, including relevant uncommitted changes but excluding
Git internals, build artifacts and credentials. Record checksums and Git status.
Use the **same revised snapshot expression** for both sources, especially when
the snapshot itself changes. Replace `/absolute/path/to/baseline` below with the
saved source directory containing `flake.nix`:

```bash
nix eval --impure --json --expr 'import /etc/nixos/tests/snapshot.nix { source = "/absolute/path/to/baseline"; }' > /tmp/nixos-before.json
nix eval --impure --json --expr 'import /etc/nixos/tests/snapshot.nix { source = "/etc/nixos"; }' > /tmp/nixos-after.json
cmp /tmp/nixos-before.json /tmp/nixos-after.json
```

The snapshot captures packages, mounts, passwords' *paths*, users, kernel/driver,
scx, Home Manager activation, generated units, `/etc` sources and activation
scripts. It selects the administrator from the evaluated configuration's supplied
settings and includes enabled Home Manager file sources, targets, executable and
recursive flags, session variables/path, and user service definitions. XDG files,
including desktop entries, are represented through Home Manager's `home.file`.
File contents and password hashes are not read by the snapshot expression.

Package, font, kernel-module and mount-option lists retain their evaluated order;
do not sort them when comparing. Investigate every difference, including changed
source paths: compare the referenced generated outputs before concluding they
are equivalent. Source references and successful builds alone do not prove
runtime behavior. The optional `configuration` argument is used by evaluation
regressions; ordinary comparisons continue to use `source` as shown above.

`nh os build`, `nh os switch` and `nh os boot` continue to use `path:/etc/nixos`.
Only activate when ready, with `nh os switch` or the explicit rebuild command
below. `path:` includes new files even before Git tracks them; add all new module
files when eventually committing. Never put credentials anywhere in this source
tree: path flakes copy the tree into the world-readable Nix store, regardless of
`.gitignore`. Password hashes remain at `/persist/passwords/{root,user}`, a
root-only directory outside the tree. Keep other credentials outside the tree
and reference runtime paths; do not use `builtins.readFile` on secret material.

## Persistence and first-login review

`/home`, `/nix` and `/persist` are Btrfs mounts available in the initrd. The pinned
Impermanence module binds early state before initrd activation and normal
persistent directories before `local-fs.target`. The early `/persist` mount also
makes password files available to user activation; no additional ad-hoc mount
services are needed. The generated hardware UUIDs and all persistence entries
were retained. `/etc/machine-id`, NetworkManager, Bluetooth, AccountsService,
LightDM, CUPS, logs, NixOS/systemd state and NVIDIA suspend storage are covered.
All browser, editor, Steam and keyring state under `/home` persists automatically.

The pinned Home Manager module uses `RequiresMountsFor=/home/<user>` and runs
before login sessions. Its xfconf activation starts a temporary D-Bus session
when no desktop session exists, so fresh users receive settings before their
first XFCE login. The existing autostarts reapply the dark theme and wait for
monitor-specific wallpaper keys. Those scripts and the Home Manager activation
are unchanged by the refactor.

A missing password file on a fresh machine can leave login unusable; the live
installer must finish password creation before reboot. A password change does
not automatically unlock a pre-existing GNOME login keyring with its old
password. NetworkManager secrets are under the persisted root-only connection
directory. There is currently no enabled SSH server, container service or
system database needing additional persistence. Recheck coverage before enabling
one. Volatile caches and `/tmp` remain intentionally ephemeral.

A build and evaluation do not prove a fresh graphical login, suspend/resume or
boot persistence. Those require a disposable VM/target or a later user-approved
activation and reboot. No disk installation, activation or reboot was performed
as part of this refactor.

## Install from the live ISO

1. Copy this entire folder to a second USB drive, or download it from your own
   repository after booting the live ISO. No hosted download URL is provided.
2. Boot the NixOS ISO in **UEFI mode**. Connect using the desktop network menu
   (or `sudo nmtui` from a terminal).
3. Copy the folder from your second USB into the live user's home directory,
   then open a terminal in the copied folder. For example, if named `nixos`:

   ```bash
   cd ~/nixos
   sudo bash install.sh
   ```

4. Enter the hostname, administrator username, timezone and keyboard layout.
   Defaults are `nixos`, `user`, `Europe/Stockholm`, and `us`. For a Swedish
   keyboard enter `se`. Passwords are entered with the live ISO's current
   keyboard layout; set that in the live desktop first if necessary.
5. Select a whole disk by its path, checking the displayed size and model.
   **All partitions and data on that disk will be erased.** Nothing is erased
   until you type the exact `ERASE /dev/...` phrase. Mounted disks, active swap,
   and active device mappings are rejected, including the mounted live USB.
6. Set root and user passwords when prompted. Wait for the completion message.
7. Run `sudo umount -R /mnt` then `sudo reboot`, and remove the live USB.

Before any disk changes, the installer evaluates the system configuration with
placeholder mount devices. Syntax errors, unknown options, and failed system
assertions stop installation before the erase prompt. This does not test a full
build or boot. The placeholder hardware file is discarded; the real one is
generated from the target mounts.

The installer automatically fetches OpenSSL from the locked Nixpkgs if the
live ISO does not provide it, before making any disk changes. No manual
`nix-shell` is needed.

The installer generates `hosts/nixos/hardware-configuration.nix` for your machine
and preserves the supplied `flake.lock`, including the Home Manager and application
pins. A missing or inconsistent lock fails before erasure. These are stored with your configuration
in `/persist/etc/nixos`, mounted at `/etc/nixos` on the installed system.
The `nixos` flake output name stays the same regardless of hostname.

## Desktop layout and shortcuts

`home/xfce.nix` uses Home Manager to apply the desktop settings for the username
selected by the installer. It creates one bottom panel with Whisker menu,
five numbered workspaces, open windows,
the system tray, volume control, and a 24-hour clock. Wi-Fi, Bluetooth and
battery controls stay available. LightDM remains the login screen.

The internal `eDP-1` panel starts rotated 180° for upside-down laptop use,
including LightDM. This is configured in `hosts/nixos/default.nix` through
`services.xserver.xrandrHeads`; no XFCE rotation autostart is needed.

Zen is configured as both the XDG default browser for web links and HTML files
and XFCE’s preferred web browser. Dark GTK defaults are written by Home Manager;
the standard Adwaita Dark XFCE theme is also applied at every login.

The desktop uses the stable Adwaita Dark widget theme, elementary XFCE icons, readable interface fonts,
and Iosevka in the terminal and clock. Desktop icons are hidden; maximized
windows hide their title bars. XFCE's screensaver handles locking.

Display power management explicitly switches the panel off after five minutes
of inactivity on both AC and battery, without an intermediate standby stage.
The existing screensaver and locking remain enabled. These minute-based timers
live in `home/xfce.nix`. After activation, `xset q` should report DPMS enabled,
`Standby: 0`, `Suspend: 0`, and `Off: 300` in a normal uninhibited session.
Applications that inhibit display power saving can delay this timeout.

`home/style.nix` adds Gruvbox dark (`#282828`) and yellow (`#d79921`) colors to the standard theme, a slim
opaque panel, matching Rofi and Alacritty colors, and a generated 4K hills
wallpaper. GTK selection accents use Gruvbox yellow. Zen Browser receives dark theme
and selection-color defaults; existing profile overrides and workspace themes
can take precedence. Notification sounds and transition effects are disabled,
while alerts stay enabled with a five-second default timeout.

The wallpaper is applied to detected monitor settings on each XFCE login.
After connecting a new display, run `apply-quiet-wallpaper` to apply it there.
Change the palette and wallpaper in `home/style.nix`, then rebuild and log in again.
GTK applications may need restarting to load the updated CSS. Individual
applications can use their own theme and may not follow all system colors.

| Shortcut | Action |
| --- | --- |
| Super + Enter | Alacritty terminal |
| Super + D | Rofi application launcher |
| Super + E | Thunar files |
| Super + B | Zen Browser |
| Super + C | Codex Desktop |
| Super + Q | Close window |
| Super + F | Toggle maximization |
| Super + Left / Right | Tile window to that side |
| Super + 1–5 | Switch workspace |
| Super + Shift + 1–5 | Move window to workspace |
| Super + S | Region screenshot to clipboard |
| Print Screen | Screenshot dialog |
| Super + L | Lock screen |
| Alt + Tab | Cycle windows |
| Volume / mute keys | Adjust output volume or mute |

Super is the Windows/logo key. Microphone mute is supported when the keyboard
has that key. Save changes you want to keep in `home/xfce.nix`: GUI changes to
declared settings can be overwritten on the next rebuild. Other settings and
user files remain under persistent `/home`.

For an existing installation, keep the entire module tree together, preserving
`hosts/nixos/settings.nix` and `hosts/nixos/hardware-configuration.nix`. Rebuild
normally, then log out and back in to reload panel plugins. Home Manager backs
up conflicting managed files with `.before-xfce-setup`; an existing backup of
the same name can stop activation. Inspect and move that backup before retrying,
rather than deleting it blindly. Check `systemctl status home-manager-mehti`
(substitute your username) if desktop setup fails.

## What survives reboot

| Location | Behavior |
| --- | --- |
| `/` | Fresh tmpfs every boot; limited to 25% of RAM |
| `/home` | All personal files and XFCE/application settings persist |
| `/nix` | Store, installed generations, and Nix state persist |
| `/persist` | Selected system state and password hashes persist |
| `/boot` | 1 GiB FAT32 EFI partition; boot entries persist |
| `/tmp` and other unlisted root paths | Discarded on reboot |

The remaining disk space is one Btrfs filesystem with `home`, `nix`, and
`persist` subvolumes. All three declare `compress=zstd` and `noatime` in
`modules/persistence.nix` so these options survive reboot. Compression applies to new
writes; existing files are not automatically recompressed. Root lives in memory, so no destructive boot-time rollback
script is needed. Store large temporary downloads/build files under your home
directory if the root tmpfs runs short of space. Zram is enabled, not hibernation.

`modules/persistence.nix` declares persistent system paths, including configuration,
machine ID, Wi-Fi connections, Bluetooth pairings, printer state, and logs.
Add application/service data paths there **before** rebooting if you need them
to survive. Persistence is not a backup; back up `/home`, `/persist`, and your
configuration independently.

Passwords use root-only hash files at `/persist/passwords/root` and
`/persist/passwords/user`, outside the Nix store. Users are declarative; to
change the administrator's password permanently:

```bash
sudo sh -c 'umask 077; openssl passwd -6 > /persist/passwords/user.new && mv /persist/passwords/user.new /persist/passwords/user'
sudo nixos-rebuild switch --flake path:/etc/nixos#nixos
```

Use `root` instead of `user` for the root password. A plain `passwd` change
does not replace the persistent hash and will be reset by activation.

## Change or update the system

### Memory and diagnostic storage

ZRAM uses Zstd, a logical capacity of 50% of RAM, and swap priority 100.
Capacity is allocated on demand, not reserved at startup. Swappiness is 150
and swap read-ahead (`vm.page-cluster`) is zero. Zswap is disabled to avoid
putting another compression cache in front of ZRAM. These are starting settings
for compressed swap, not a guaranteed speedup for every workload.
An additional 16 GiB Btrfs swap file at `/persist/swapfile` has priority 0, so
it is used after ZRAM fills. NixOS creates it on the persistent NVMe mount.

Persistent journals have a `250M` budget; runtime journals have `50M`.
Compressed crash dumps have a `512M` total storage budget, `256M` per-dump
processing/storage limits, and a `1G` free-space target. Large crashes can
therefore lack a full dump. These systemd budgets are cleanup limits, not hard
filesystem quotas: active logs and dumps being processed can temporarily exceed
them. `M` and `G` use systemd's binary units.

The regular tmpfiles cleanup timer removes crash dumps eligible under a
three-day age rule. It runs periodically, rather than exactly 72 hours after
each crash. Dumps persist under the existing `/var/lib/systemd` mount.

After installation or a rebuild and reboot, inspect the active settings with:

```bash
zramctl
swapon --show
sysctl vm.swappiness vm.page-cluster
cat /sys/module/zswap/parameters/enabled
journalctl --disk-usage
systemd-analyze cat-config systemd/coredump.conf
systemctl list-timers systemd-tmpfiles-clean.timer
```

### Applications and kernel

The installer detects the laptop's Radeon 760M (`1002:1900`) and RTX 4050
(`10de:28a1`) directly from Linux PCI sysfs and saves their decimal PRIME bus
IDs in `hosts/nixos/settings.nix`. Keep firmware graphics mode set to hybrid/switchable.
The AMD GPU runs XFCE; the NVIDIA GPU is available on demand through PRIME
offload. NVIDIA's open kernel module, proprietary userspace, 32-bit graphics,
runtime power management and suspend support are enabled when the RTX is found.
The driver package comes from the selected CachyOS kernel's package set.
VRAM suspend storage is under persistent `/var/lib/nvidia`, not root tmpfs.

Run a game on the NVIDIA GPU with `nvidia-offload <game-command>`.
Steam is installed through the NixOS Steam module. Open it from the XFCE menu
and sign in. Use `nvidia-offload %command%` in a game's launch options to run
it on the RTX 4050. Steam's default library and settings under `/home` persist
across reboots. For Windows games, select a Proton compatibility tool in the
game's Properties → Compatibility when needed.
Check the driver after installation with `nvidia-smi`.
An external monitor connected directly to the RTX may keep it awake; external
display routing and suspend/resume need testing on the laptop.

In a VM without these GPUs, the installer leaves NVIDIA disabled. Do not reuse
that VM's empty GPU settings for the real laptop. On an existing installation,
preserve the detected PCI IDs in `hosts/nixos/settings.nix` when updating other files.

`services.scx` starts **scx_cake** automatically at boot. The configuration
overrides the locked NixOS Rust scheduler package with SCX 1.1.3, whose
rewritten Cake scheduler runs without a profile or extra arguments. No verbose
TUI or individual tuning overrides are enabled.
This changes CPU scheduling, not the disk I/O scheduler or network queueing.

After booting the CachyOS kernel, verify:

```bash
systemctl status scx.service
cat /sys/kernel/sched_ext/state
cat /sys/kernel/sched_ext/root/ops
scx_cake --version
journalctl -b -u scx.service
```

The sched_ext state should be `enabled` and the ops name should identify Cake.
A missing `/sys/kernel/sched_ext` means the running kernel lacks sched_ext
support; the service is then skipped. Stopping the service returns scheduling
to the kernel's built-in scheduler:

```bash
sudo systemctl stop scx.service
# Start again when ready:
sudo systemctl start scx.service
```

For a permanent fallback, set `services.scx.enable = false` in
`modules/gaming.nix` and rebuild. If troubleshooting at boot, add
`systemd.mask=scx.service` to the kernel command line for that boot.
The NixOS service limits repeated startup failures; sched_ext can detach a
misbehaving scheduler and fall back to the built-in scheduler. Hardware/runtime
compatibility and gaming performance still need testing on the actual machine.

[Upstream Cake documentation](https://github.com/sched-ext/scx/tree/main/scheds/rust/scx_cake)
now describes a rewritten design, so the older four-tier description should
not be assumed to describe every release. This configuration pins SCX 1.1.3
rather than tracking upstream `main` independently.

Codex Desktop is installed through the NixOS module from
[ilysenko/codex-desktop-linux](https://github.com/ilysenko/codex-desktop-linux).
Launch it from the **ChatGPT Community** menu entry or run `codex-desktop`.
The configuration uses its default feature set and bundled CLI. Its signed
Cachix cache is enabled for the live installer and installed system.

Zen Browser uses the **beta** package from the
[community Zen flake](https://github.com/0xc000022070/zen-browser-flake).
Launch it from the XFCE applications menu. Both applications' profiles and
Codex project state under your home directory survive reboots because all of
`/home` persists. Keep projects there as well.

To update just these applications, run:

```bash
sudo nix flake update codex-desktop-linux zen-browser --flake path:/etc/nixos
sudo nixos-rebuild switch --flake path:/etc/nixos#nixos
```

Application versions are controlled by `flake.lock` and system rebuilds.

The kernel is `pkgs.cachyosKernels.linuxPackages-cachyos-latest-zen4` from
[xddxdd/nix-cachyos-kernel](https://github.com/xddxdd/nix-cachyos-kernel).
It uses upstream's `release` branch and `pinned` overlay, retaining the kernel
project's own nixpkgs revision to match its binary cache. The maintainer's
signed cache is enabled both during installation and on the installed system.
If a cached build is unavailable, Nix may compile the kernel locally, which
requires substantial time and temporary disk space. After reboot, `uname -r`
shows the running kernel; the exact kernel version is determined by `flake.lock`.

Edit the owning module listed below, then:

```bash
sudo nixos-rebuild switch --flake path:/etc/nixos#nixos
```

Update pinned packages within the configured release:

```bash
sudo nix flake update --flake path:/etc/nixos
sudo nixos-rebuild switch --flake path:/etc/nixos#nixos
```

Keep `system.stateVersion` at the original installation version when upgrading.
Earlier generations are available in the boot menu.

The boot menu has no automatic delay; hold Space during startup to open it.
Bat uses its built-in themes and syntaxes, avoiding a cache rebuild during
Home Manager activation on every boot. To compare boot times after changes,
run `systemd-analyze time` and `systemd-analyze critical-chain` after reboot.

## Resume an interrupted installation

Do **not** choose erase again. If `/mnt`, `/mnt/boot`, `/mnt/nix`, `/mnt/home`,
and `/mnt/persist` are still mounted, rerun `sudo bash install.sh --mounted`
with the same username/settings. Existing hashes are reused and configuration
is backed up under `/persist/etc/nixos.backup.*` before replacement.

After rebooting the live ISO, identify the existing EFI and Btrfs partitions
using `lsblk -f`. Replace `/dev/YOUR_BTRFS_PARTITION` and
`/dev/YOUR_EFI_PARTITION` below with those **partitions**, not whole disks:

```bash
sudo mount -t tmpfs -o size=25%,mode=755 none /mnt
sudo mkdir -p /mnt/{boot,nix,home,persist}
sudo mount -o subvol=nix,compress=zstd /dev/YOUR_BTRFS_PARTITION /mnt/nix
sudo mount -o subvol=home,compress=zstd /dev/YOUR_BTRFS_PARTITION /mnt/home
sudo mount -o subvol=persist,compress=zstd /dev/YOUR_BTRFS_PARTITION /mnt/persist
sudo mount /dev/YOUR_EFI_PARTITION /mnt/boot
sudo mkdir -p /mnt/etc/nixos
sudo mount --bind /mnt/persist/etc/nixos /mnt/etc/nixos
sudo env NIX_CONFIG='experimental-features = nix-command flakes
extra-substituters = https://attic.xuyh0120.win/lantian https://codex-desktop-linux.cachix.org
extra-trusted-public-keys = lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc= codex-desktop-linux.cachix.org-1:nX/xy6AdK9hQE24A8ALGjkCKj2ObFmcnemiL5Cid4nk=' \
  nixos-install --root /mnt --no-root-passwd --flake path:/mnt/etc/nixos#nixos
```

This resumes the saved configuration without repartitioning. If interrupted
before configuration/password creation finished, run `install.sh --mounted`
instead. After success, unmount and reboot as above.

## Validation and references

This configuration was originally written on Windows and is now installed on
this NixOS laptop. The architecture review on 2026-09-20 checked the pinned module implementations,
evaluated before/after settings, shell checks, safe installer preparation, active
persistence mounts, service health, and full system builds.
No system or user services were failed at the time of the review. These are
historical observations, not guarantees about subsequent boots or activations.
The commands under **Safe maintenance checks** are the reproducible checks to
rerun after edits; they do not perform a fresh login, reboot or suspend test.

The installer preflight was tested in an isolated temporary directory with
valid and deliberately invalid configurations, without running disk commands.
The current installer has not been rerun end-to-end on a disposable disk or VM;
suspend/resume and a reboot persistence test still need separate verification.
Regression checks cover hyphenated usernames, including installer preflight;
the mount-order assertion uses the same service-name escaping as Home Manager.
After installation, create one file in your home and one in `/tmp`; reboot and
confirm only the home file survives. Check saved Wi-Fi connections and
`/etc/nixos` as well.

Keep `install.sh` writable only by its owner (mode `0644` when invoking it with
`sudo bash install.sh`). Do not make this root-executed script world-writable.

- [Official NixOS installation manual](https://nixos.org/manual/nixos/stable/#sec-installation)
- [Impermanence module and persistence documentation](https://github.com/nix-community/impermanence)

## Gaming performance and memory tuning

The system loads `ntsync` for compatible Wine/Proton versions and enables
Power Profiles Daemon. Run `game-performance COMMAND [ARG...]` to request
performance mode for the command's lifetime. In Steam launch options, use:

```text
game-performance %command%
```

To also request NVIDIA offloading, use:

```text
game-performance nvidia-offload %command%
```

The wrapper falls back to the current profile if performance mode is unavailable.
The performance request is released when the command exits; heat and power
consumption may increase while it is active.

CachyOS-inspired THP tuning sets `khugepaged/max_ptes_none` to `409` rather
than `511` to split sparsely used huge pages more readily. Treat this as a trial:
compare your usual games and memory-heavy workloads. To undo it, remove the
THP tmpfiles rule in `modules/gaming.nix`, rebuild, and reboot.

## ProtonUp-Qt

ProtonUp-Qt is installed to manage Steam compatibility tools through its GUI.
Open it from the application menu after rebuilding.

### Refactor verification (2026-09-20)

The pre-refactor working tree (including the existing esports and Dynamic Boost
edits) was saved to `/home/mehti/nixos-review-baseline`. `flake.lock` and generated
hardware remained byte-identical. Evaluated package paths, Home Manager
activation, user identity, kernel/driver, scx, desktop settings and mount policy
matched after restoring the original font and mount-option order. The rebuilt
system profile had 17,555 entries with identical file contents and symlink targets.
Remaining generated-unit and D-Bus differences reference the equivalent profile
at a new store path; D-Bus configuration is otherwise identical.

Both baseline and refactored systems built successfully. Flake evaluation,
ShellCheck, Bash syntax, installer staging and positive/negative preflight tests
passed. The reviewed runtime had no failed system or user services. This does
not replace the fresh-login, reboot and suspend tests described above.
