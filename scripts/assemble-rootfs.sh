#!/bin/sh
# assemble-rootfs.sh - collect all built packages into rootfs structure
# Usage: assemble-rootfs.sh <rootfs_dir> <build_root>

set -eu

ROOTFS="$1"
BUILD_ROOT="$2"
SRC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Assembling rootfs at $ROOTFS"

# Clean and create directories
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"/bin "$ROOTFS"/sbin "$ROOTFS"/usr/bin "$ROOTFS"/usr/sbin \
    "$ROOTFS"/lib "$ROOTFS"/etc "$ROOTFS"/var "$ROOTFS"/tmp "$ROOTFS"/mnt \
    "$ROOTFS"/dev "$ROOTFS"/proc "$ROOTFS"/sys "$ROOTFS"/home "$ROOTFS"/root \
    "$ROOTFS"/share/man/man1 "$ROOTFS"/share/man/man5 "$ROOTFS"/share/man/man8 \
    "$ROOTFS"/lib/limine "$ROOTFS"/boot "$ROOTFS"/etc/ssl/certs "$ROOTFS"/etc/ssl/private

# Copy from Makefile staging
if [ -d "$SRC_ROOT/rootfs" ]; then
    echo "Copying from Makefile rootfs staging..."
    cp -a "$SRC_ROOT/rootfs"/* "$ROOTFS/"
else
    echo "ERROR: SRC_ROOT/rootfs not found"
    exit 1
fi

# Copy libressl libraries to rootfs
if [ -d "$BUILD_ROOT/musl/usr/lib" ]; then
    cp -f "$BUILD_ROOT/musl/usr/lib/libssl.a" "$ROOTFS/lib/" 2>/dev/null || true
    cp -f "$BUILD_ROOT/musl/usr/lib/libcrypto.a" "$ROOTFS/lib/" 2>/dev/null || true
fi

# Copy limine files (needed by slinux-install)
if [ -d "$BUILD_ROOT/limine" ]; then
    cp "$BUILD_ROOT/limine/BOOTX64.EFI" "$ROOTFS/lib/limine/"
    cp "$BUILD_ROOT/limine/limine-uefi-cd.bin" "$ROOTFS/lib/limine/"
fi

# Copy kernel to /boot (needed by slinux-install)
if [ -f "$SRC_ROOT/kernel/linux/arch/x86/boot/bzImage" ]; then
    cp "$SRC_ROOT/kernel/linux/arch/x86/boot/bzImage" "$ROOTFS/boot/vmlinuz"
fi

# Build cryptpw if not present
if [ ! -f "$ROOTFS/bin/cryptpw" ]; then
    if [ -f "$SRC_ROOT/tools/cryptpw.c" ]; then
        echo "Building cryptpw..."
        cc -static -Os -s -o "$ROOTFS/bin/cryptpw" "$SRC_ROOT/tools/cryptpw.c" 2>/dev/null || \
        echo "WARNING: failed to build cryptpw"
    fi
fi

# Build getpass if not present
if [ ! -f "$ROOTFS/bin/getpass" ]; then
    if [ -f "$SRC_ROOT/tools/getpass.c" ]; then
        echo "Building getpass..."
        cc -static -Os -s -o "$ROOTFS/bin/getpass" "$SRC_ROOT/tools/getpass.c" 2>/dev/null || \
        echo "WARNING: failed to build getpass"
    fi
fi

# Copy additional files
cp -a "$SRC_ROOT/etc/rc.init" "$ROOTFS/bin/" 2>/dev/null || true
cp -a "$SRC_ROOT/etc/rc.shutdown" "$ROOTFS/bin/" 2>/dev/null || true
cp -a "$SRC_ROOT/bin/slinux-install" "$ROOTFS/bin/" 2>/dev/null || true
chmod 755 "$ROOTFS/bin/rc.init" "$ROOTFS/bin/rc.shutdown" "$ROOTFS/bin/slinux-install" 2>/dev/null || true

# Create sh symlink
ln -sf dash "$ROOTFS/bin/sh" 2>/dev/null || true

# Fix doas setuid
if [ -f "$ROOTFS/bin/doas" ]; then
    doas chown 0:0 "$ROOTFS/bin/doas" 2>/dev/null || true
    doas chmod 4755 "$ROOTFS/bin/doas" 2>/dev/null || true
fi

# Device nodes
mkdir -p "$ROOTFS/dev"
for node in console null zero random urandom tty tty1 ttyS0 ptmx; do
    [ -e "$ROOTFS/dev/$node" ] || mknod -m 666 "$ROOTFS/dev/$node" c 1 3 2>/dev/null || true
done

# Essential /etc files
mkdir -p "$ROOTFS/etc"
cat > "$ROOTFS/etc/passwd" <<'EOP'
root::0:0:root:/root:/bin/sh
EOP

cat > "$ROOTFS/etc/group" <<'EOP'
root::0:
wheel::10:
tty::5:
disk::6:
lp::7:
cdrom::11:
kmem::15:
audio::29:
video::44:
input::97:
users::100:
EOP

cat > "$ROOTFS/etc/shadow" <<'EOP'
root::0:0:99999:7:::
EOP
chmod 600 "$ROOTFS/etc/shadow"

echo "slinux" > "$ROOTFS/etc/hostname"
echo "Welcome to slinux" > "$ROOTFS/etc/motd"

# SSL certificates - create minimal CA bundle
if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
    cp /etc/ssl/certs/ca-certificates.crt "$ROOTFS/etc/ssl/certs/ca-certificates.crt"
else
    # Generate minimal CA bundle from Mozilla's list
    echo "Generating minimal CA bundle..."
    cat > "$ROOTFS/etc/ssl/certs/ca-certificates.crt" <<'CERTEOF'
# This is a placeholder - replace with actual CA certificates
# On first boot, run: update-ca-certificates
CERTEOF
fi

# Firmware
if [ -d "$SRC_ROOT/firmware" ]; then
    mkdir -p "$ROOTFS/lib/firmware"
    cp -r "$SRC_ROOT/firmware"/* "$ROOTFS/lib/firmware/"
fi

# svc directories
mkdir -p "$ROOTFS/bin/svc.d/run" "$ROOTFS/bin/svc.d/avail" "$ROOTFS/bin/svc.d/default" 2>/dev/null || true

# Permissions
chmod 1777 "$ROOTFS/tmp"
chmod 700 "$ROOTFS/root"

touch "$BUILD_ROOT/rootfs.stamp"
echo "Rootfs assembled at $ROOTFS"
