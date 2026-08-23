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
# esp size is fixed at 64MiB; SIZE is the total image size
ESPSZ=64
sfdisk "$TARGET" <<EOF
label: gpt
name="esp", size=${ESPSZ}MiB, type=uefi
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
# cp -a preserves the build host's uid/gid; everything must belong to
# root or setuid binaries elevate to the wrong (guest) user. chown
# clears the setuid bit, so re-apply it afterwards.
doas chown -hR 0:0 "$ROOTMNT"
# chown clears setuid; re-apply it to whatever was setuid in the tree
for f in $(find "$ROOT"/rootfs -perm /6000 -type f); do
	rel=${f#"$ROOT"/rootfs}
	doas chmod u+s,g+s "$ROOTMNT$rel"
done
doas touch "$ROOTMNT"/.slinux-installed

echo "configuring users"
command -v openssl >/dev/null || { echo "error: openssl missing"; exit 1; }

# prompts must print to the terminal, so passwords are collected into a
# global instead of command substitution (which both captures stdout and,
# under some shells like yash, feeds /dev/null to stdin)
askpass() {
	while :; do
		printf '%s password: ' "$1"
		stty -echo 2>/dev/null
		IFS= read -r _p1 || exit 1
		stty echo 2>/dev/null; echo
		printf 'repeat: '
		stty -echo 2>/dev/null
		IFS= read -r _p2 || exit 1
		stty echo 2>/dev/null; echo
		if [ -n "${_p1:-}" ] && [ "${_p1}" = "${_p2}" ]; then
			ASKPASS_RESULT=$_p1
			return
		fi
		echo "password empty or mismatched, try again"
	done
}

NEWUSER=
while [ -z "$NEWUSER" ]; do
	printf 'username: '
	IFS= read -r NEWUSER || { echo; exit 1; }
	case "$NEWUSER" in
	[a-z_][a-z0-9_-]*) ;;
	*) echo "invalid username (lowercase letters, digits, _, -)"; NEWUSER= ;;
	esac
done

askpass root && ROOTHASH=$(openssl passwd -6 "$ASKPASS_RESULT")
askpass "$NEWUSER" && USERHASH=$(openssl passwd -6 "$ASKPASS_RESULT")

# hashes live in /etc/shadow; passwd keeps only the x placeholder
doas sed -i 's/^root:[^:]*:/root:x:/' "$ROOTMNT"/etc/passwd
printf '%s:x:1000:100::/home/%s:/bin/sh\n' \
	"$NEWUSER" "$NEWUSER" | \
	doas tee -a "$ROOTMNT"/etc/passwd >/dev/null
printf 'root:%s:0:0:99999:7:::\n%s:%s:0:0:99999:7:::\n' \
	"$ROOTHASH" "$NEWUSER" "$USERHASH" | \
	doas tee "$ROOTMNT"/etc/shadow >/dev/null
doas chmod 600 "$ROOTMNT"/etc/shadow
doas sed -i "s/^wheel::10:/wheel::10:$NEWUSER/" "$ROOTMNT"/etc/group
doas sed -i "s/^users::100:/users::100:$NEWUSER/" "$ROOTMNT"/etc/group
doas mkdir -p "$ROOTMNT/home/$NEWUSER"
doas chown 1000:100 "$ROOTMNT/home/$NEWUSER"
echo "user $NEWUSER created (member of wheel)"

echo "installing limine and kernel"
doas mkdir -p "$ESPMNT"/EFI/BOOT
# use the artifacts this tree built and tested, not a host distro package
doas cp "$ROOT"/rootfs/lib/limine/BOOTX64.EFI "$ESPMNT"/EFI/BOOT/
# bios stage 2 is looked up by path: /boot/limine, /boot, /limine or /
# across all partitions of the boot disk. stage 2 only carries iso9660
# and fat drivers, so the copy lives on the esp fat.
doas mkdir -p "$ESPMNT"/boot/limine
doas cp "$ROOT"/rootfs/lib/limine/limine-bios.sys "$ESPMNT"/boot/limine/
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
