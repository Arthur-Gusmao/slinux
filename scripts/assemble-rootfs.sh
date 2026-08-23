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
mkdir -p "$ROOTFS"/bin "$ROOTFS"/sbin "$ROOTFS"/usr/bin "$ROOTFS"/usr/sbin "$ROOTFS"/lib "$ROOTFS"/etc "$ROOTFS"/var "$ROOTFS"/tmp "$ROOTFS"/mnt "$ROOTFS"/dev "$ROOTFS"/proc "$ROOTFS"/sys "$ROOTFS"/home "$ROOTFS"/root "$ROOTFS"/share/man/man1 "$ROOTFS"/share/man/man5 "$ROOTFS"/share/man/man8
echo "Created rootfs directories: $(ls -la $ROOTFS)"

# The Makefile builds and installs everything to SRC_ROOT/rootfs/
# Copy from there
if [ -d "$SRC_ROOT/rootfs" ]; then
    echo "Copying from Makefile rootfs staging..."
    cp -a "$SRC_ROOT/rootfs"/* "$ROOTFS/"
else
    echo "ERROR: SRC_ROOT/rootfs not found"
    exit 1
fi

# ---- Device nodes (static) ----
mkdir -p "$ROOTFS/dev"
for node in console null zero random urandom tty tty1 ttyS0 ptmx; do
    [ -e "$ROOTFS/dev/$node" ] || mknod -m 666 "$ROOTFS/dev/$node" c 1 3 2>/dev/null || true
done

# ---- Essential /etc files ----
mkdir -p "$ROOTFS/etc"
cat > "$ROOTFS/etc/passwd" <<'EOF'
root::0:0:root:/root:/bin/sh
EOF

cat > "$ROOTFS/etc/group" <<'EOF'
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
EOF

# ---- Firmware ----
if [ -d "$SRC_ROOT/firmware" ]; then
    mkdir -p "$ROOTFS/lib/firmware"
    cp -r "$SRC_ROOT/firmware"/* "$ROOTFS/lib/firmware/"
fi

# ---- Set permissions ----
chmod 1777 "$ROOTFS/tmp"
chmod 700 "$ROOTFS/root"

# ---- Touch stamp file ----
touch "$BUILD_ROOT/rootfs.stamp"

echo "Rootfs assembled at $ROOTFS"