#!/bin/sh
# make-iso.sh - create UEFI-only ISO image
# Usage: make-iso.sh <iso_dir> <initramfs_file> <output_iso>

set -eu

ISO_DIR="$1"
INITRAMFS="$2"
OUTPUT_ISO="$3"
SRC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="$(dirname "$ISO_DIR")"
LIMINE_OUT="$BUILD_ROOT/limine"

echo "Creating ISO at $OUTPUT_ISO"

# Clean and create ISO structure
rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR"/EFI/BOOT

# Copy kernel and initramfs
cp "$SRC_ROOT/kernel/linux/arch/x86/boot/bzImage" "$ISO_DIR/vmlinuz"
cp "$INITRAMFS" "$ISO_DIR/initramfs.cpio.gz"

# Copy limine UEFI files
cp "$LIMINE_OUT/limine-uefi-cd.bin" "$ISO_DIR/"
cp "$LIMINE_OUT/BOOTX64.EFI" "$ISO_DIR/EFI/BOOT/"

# Create limine.conf for live boot
cat > "$ISO_DIR/limine.conf" <<'EOF'
timeout: 5

/slinux (live)
    protocol: linux
    path: boot():/vmlinuz
    cmdline: pnpacpi=off i8042.nopnp i8042.nomux=1 console=ttyS0 console=tty0 rdinit=/bin/init
    module_path: boot():/initramfs.cpio.gz
EOF

# Create ISO with xorriso (UEFI-only)
xorriso -as mkisofs -R -r -J \
    -eltorito-alt-boot -e limine-uefi-cd.bin -no-emul-boot \
    -isohybrid-gpt-basdat -part_like_isohybrid \
    -appended_part_as_gpt \
    -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B \
        "$LIMINE_OUT/limine-uefi-cd.bin" \
    -V SLINUX -c boot.cat -o "$OUTPUT_ISO" "$ISO_DIR"

echo "ISO created: $OUTPUT_ISO"
ls -la "$OUTPUT_ISO"