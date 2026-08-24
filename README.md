# slinux

Minimal, statically-linked Linux distribution for modern hardware (ThinkPad T480 reference).

## Build

```bash
# One-time setup
muon setup build --cross-file=meson/cross/x86_64-linux-musl.ini

# Build ISO
samu -C build

# Incremental rebuilds
samu -C build
```

Output: `build/slinux.iso`

## Install

```bash
# Boot ISO on target (UEFI only)
# Login: root (no password)

# Install to disk
slinux-install /dev/nvme0n1
```

## Hardware Support (T480 reference)

| Component | Driver |
|-----------|--------|
| Graphics | i915 (UHD 620) |
| WiFi | iwlwifi (8265/9260) |
| Storage | nvme + ext4 |
| Audio | snd_hda_intel |
| TrackPoint/Trackpad | i8042 + rmi4 |
| ThinkPad ACPI | thinkpad_acpi |
| Thunderbolt 3 | thunderbolt |
| USB-C/3.1 | xhci_pci |
| Webcam | uvcvideo |

## Philosophy

- Static linking (musl, BearSSL)
- No package manager (rebuild or pkgsrc/Nix)
- UEFI only (no legacy BIOS)
- Minimal kernel (~1200 options)
- initramfs for root mounting (Unix philosophy)
- BSD-style init (~20 lines)

## Structure

```
bin/            # On-target installer (slinux-install)
etc/            # Base /etc files
init/           # sinit + rc.init
kernel/         # Linux config (T480)
meson.build     # Build definition
meson/cross/    # Cross-compilation config
scripts/        # Build helpers (assemble-rootfs, make-iso)
scripts/assemble-rootfs.sh
scripts/make-iso.sh
scripts/setup-sysroot.sh
```

## Requirements

- musl cross-compiler (`x86_64-linux-musl`)
- muon, samurai (ninja)
- xorriso, cpio, gzip
- nasm, mtools (for limine)