#!/bin/sh
# slinux installer: writes the system to a disk image or block device.
# usage: install.sh <image-file|block-device> [size-mib]

set -eu

TARGET=${1:?usage: install.sh <image-file|block-device> [size-mib]}
SIZE=${2:-256}
ROOT=$(cd "$(dirname "$0")" && pwd)

[ -d "$ROOT/rootfs/bin" ] || { echo "error: run make rootfs first"; exit 1; }
[ -f "$ROOT/kernel/linux/arch/x86/boot/bzImage" ] || { echo "error: build the kernel first"; exit 1; }
[ -f "$ROOT/rootfs/lib/limine/limine-bios.sys" ] || { echo "error: limine stages missing, rebuild rootfs"; exit 1; }

case "$TARGET" in
/dev/*) IMG=0 ;;
*) IMG=1; truncate -s "${SIZE}M" "$TARGET" ;;
esac

echo "partitioning $TARGET (gpt: esp + bios + root)"
sfdisk "$TARGET" <<EOF
label: gpt
name="esp", size=64MiB, type=uefi
name="bios", size=1MiB, type=21686148-6449-6E6F-744E-656564454649
name="root", type=linux
EOF

LOOP=
ROOTMNT=
ESPMNT=
cleanup() {
	[ -n "$ESPMNT" ] && doas umount "$ESPMNT"
	[ -n "$ROOTMNT" ] && doas umount "$ROOTMNT"
	[ -n "$LOOP" ] && doas losetup -d "$LOOP"
	[ -n "$ESPMNT" ] && rmdir "$ESPMNT" "$ROOTMNT"
}
trap cleanup EXIT INT TERM

if [ "$IMG" = 1 ]; then
	LOOP=$(doas losetup -fP --show "$TARGET")
	PARTS="$LOOP"p
else
	PARTS="$TARGET"
	case "$PARTS" in *nvme*|*mmcblk*) PARTS="$PARTS"p ;; esac
fi

echo "creating filesystems"
doas mkfs.vfat -F32 -n SLINUX "$PARTS"1 >/dev/null
doas mkfs.ext4 -q -L slinux "$PARTS"3
ROOTUUID=$(doas blkid -s PARTUUID -o value "$PARTS"3)

ROOTMNT=$(mktemp -d)
ESPMNT=$(mktemp -d)
doas mount "$PARTS"3 "$ROOTMNT"
doas mount "$PARTS"1 "$ESPMNT"

echo "copying rootfs"
doas cp -a "$ROOT"/rootfs/. "$ROOTMNT"/
doas touch "$ROOTMNT"/.slinux-installed

echo "installing limine and kernel"
doas mkdir -p "$ESPMNT"/EFI/BOOT
# use the artifacts this tree built and tested, not a host distro package
doas cp "$ROOT"/rootfs/lib/limine/BOOTX64.EFI "$ESPMNT"/EFI/BOOT/
doas cp "$ROOT"/rootfs/lib/limine/limine-bios.sys "$ESPMNT"/EFI/BOOT/
doas cp "$ROOT"/kernel/linux/arch/x86/boot/bzImage "$ESPMNT"/vmlinuz
doas cp "$ROOT"/slinux.cpio.gz "$ESPMNT"/initramfs.cpio.gz

# legacy bios boot: stage 1 in the mbr points at the esp copy of
# limine-bios.sys; uefi boots straight from EFI/BOOT/BOOTX64.EFI
doas "$ROOT"/rootfs/bin/limine bios-install "$TARGET"

doas tee "$ESPMNT"/EFI/BOOT/limine.conf >/dev/null <<EOF
timeout: 3

/slinux
    protocol: linux
    path: boot():/vmlinuz
    cmdline: root=PARTUUID=$ROOTUUID rw rootwait console=ttyS0 console=tty0

/slinux rescue
    protocol: linux
    path: boot():/vmlinuz
    cmdline: console=ttyS0
    module_path: boot():/initramfs.cpio.gz
EOF

sync
echo "done: slinux installed on $TARGET"
