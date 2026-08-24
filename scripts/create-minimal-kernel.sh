#!/bin/sh
# Create a minimal, Unix-philosophy kernel config for slinux
# Philosophy: "Do one thing well" - minimal core, maximum modularity

cd /home/aw/slinux/kernel/linux
make mrproper

# Start from tinyconfig (absolute minimum)
make O=/tmp/kernel_minimal tinyconfig

# Now add what slinux needs via a fragment
cat > /tmp/slinux-kernel-fragment.config <<'EOF'
# =============================================================================
# slinux kernel fragment - Unix philosophy: minimal core, maximum modularity
# =============================================================================

# ---- Core: Modules (Unix philosophy: composability) ----
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_MODULE_FORCE_LOAD=y
CONFIG_MODULE_SRCVERSION_ALL=y
CONFIG_MODULE_SIG=n
CONFIG_MODULE_ALLOW_MISSING_NAMESPACE_IMPORTS=y

# ---- Core: Initramfs (Unix philosophy: everything is a file) ----
CONFIG_BLK_DEV_INITRD=y
CONFIG_INITRAMFS_SOURCE=""
CONFIG_RD_GZIP=y
CONFIG_RD_XZ=y

# ---- Core: IPC (Unix philosophy: composable tools) ----
CONFIG_SYSVIPC=y
CONFIG_POSIX_MQUEUE=y
CONFIG_CROSS_MEMORY_ATTACH=y

# ---- Core: Timers (high-res for modern userspace) ----
CONFIG_HIGH_RES_TIMERS=y
CONFIG_NO_HZ_IDLE=y
CONFIG_NO_HZ=y

# ---- Core: BPF (for modern observability) ----
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y

# ---- Core: Auditing ----
CONFIG_AUDIT=y

# ---- Memory: SLUB (not SLAB/SLUB_TINY - better for general use) ----
CONFIG_SLUB_DEBUG=y

# ---- Core: Kallsyms (for debugging) ----
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y

# ---- Core: Printk (early console) ----
CONFIG_EARLY_PRINTK=y

# ---- Core: Magic SysRq (for debugging) ----
CONFIG_MAGIC_SYSRQ=y
CONFIG_MAGIC_SYSRQ_DEFAULT_ENABLE=0x1

# =============================================================================
# Filesystems (Unix philosophy: everything is a file)
# =============================================================================
CONFIG_FS_IOMAP=y

# Pseudo filesystems (essential for Unix)
CONFIG_PROC_FS=y
CONFIG_PROC_SYSCTL=y
CONFIG_PROC_CHILDREN=y
CONFIG_SYSFS=y
CONFIG_TMPFS=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_TMPFS_XATTR=y
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y

# Real filesystems
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_VFAT_FS=y
CONFIG_FAT_DEFAULT_CODEPAGE=437
CONFIG_FAT_DEFAULT_IOCHARSET="utf8"

# =============================================================================
# Block devices (minimal built-in, rest modular)
# =============================================================================
CONFIG_BLK_DEV_LOOP=y
CONFIG_BLK_DEV_RAM=y
CONFIG_BLK_DEV_RAM_COUNT=16
CONFIG_BLK_DEV_RAM_SIZE=65536

# Virtio (for QEMU/cloud)
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_MMIO=y

# ATA/SATA (minimal)
CONFIG_ATA=y
CONFIG_ATA_BMDMA=y
CONFIG_ATA_PIIX=y

# =============================================================================
# Network (minimal built-in, rest modular)
# =============================================================================
CONFIG_NET=y
CONFIG_PACKET=y
CONFIG_UNIX=y
CONFIG_INET=y
CONFIG_IP_PNP=y
CONFIG_IP_PNP_DHCP=y

# Ethernet drivers (built-in for boot)
CONFIG_NET_VENDOR_INTEL=y
CONFIG_E1000=y
CONFIG_E1000E=y

# Virtio net
CONFIG_VIRTIO_NET=y

# =============================================================================
# Character devices
# =============================================================================
CONFIG_TTY=y
CONFIG_VT=y
CONFIG_CONSOLE_TRANSLATIONS=y
CONFIG_VT_CONSOLE=y
CONFIG_HW_CONSOLE=y
CONFIG_UNIX98_PTYS=y
CONFIG_LEGACY_PTYS=y
CONFIG_LEGACY_PTY_COUNT=256

# Serial (8250 for QEMU/real hardware)
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_PCI=y
CONFIG_SERIAL_8250_NR_UARTS=4
CONFIG_SERIAL_8250_RUNTIME_UARTS=4

# =============================================================================
# Input (minimal)
# =============================================================================
CONFIG_INPUT=y
CONFIG_INPUT_MOUSEDEV=y
CONFIG_INPUT_MOUSEDEV_SCREEN_X=1024
CONFIG_INPUT_MOUSEDEV_SCREEN_Y=768

# =============================================================================
# Graphics (none built-in - use framebuffer/DRM modules)
# =============================================================================

# =============================================================================
# USB (none built-in - all modular)
# =============================================================================

# =============================================================================
# Power management (minimal)
# =============================================================================
CONFIG_PM=y
CONFIG_PM_SLEEP=y
CONFIG_ACPI=y
CONFIG_ACPI_BUTTON=y
CONFIG_ACPI_PROCFS=y
CONFIG_ACPI_PROCFS_POWER=y

# =============================================================================
# CPU frequency (modular)
# =============================================================================

# =============================================================================
# Bus options
# =============================================================================
CONFIG_PCI=y
CONFIG_PCI_DIRECT=y
CONFIG_PCI_MMCONFIG=y
CONFIG_PCI_DOMAINS=y

# =============================================================================
# Executable file formats
# =============================================================================
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
CONFIG_COREDUMP=y

# =============================================================================
# Security (minimal)
# =============================================================================
CONFIG_SECURITY=y
CONFIG_SECURITY_WRITABLE_HOOKS=y
CONFIG_SECURITY_NETWORK=y
CONFIG_LSM="capability,landlock"

# =============================================================================
# Cryptography (minimal built-in)
# =============================================================================
CONFIG_CRYPTO=y
CONFIG_CRYPTO_ALGAPI=y
CONFIG_CRYPTO_ALGAPI2=y
CONFIG_CRYPTO_AEAD=y
CONFIG_CRYPTO_AEAD2=y
CONFIG_CRYPTO_BLKCIPHER=y
CONFIG_CRYPTO_BLKCIPHER2=y
CONFIG_CRYPTO_HASH=y
CONFIG_CRYPTO_HASH2=y
CONFIG_CRYPTO_RNG=y
CONFIG_CRYPTO_RNG2=y
CONFIG_CRYPTO_RNG_DEFAULT=y
CONFIG_CRYPTO_AKCIPHER2=y
CONFIG_CRYPTO_KPP2=y
CONFIG_CRYPTO_ACOMP2=y
CONFIG_CRYPTO_MANAGER=y
CONFIG_CRYPTO_MANAGER2=y
CONFIG_CRYPTO_MANAGER_DISABLE_TESTS=y
CONFIG_CRYPTO_NULL=y
CONFIG_CRYPTO_WORKQUEUE=y
CONFIG_CRYPTO_CRYPTD=y
CONFIG_CRYPTO_AUTHENC=y
CONFIG_CRYPTO_SIMD=y

# AES, SHA256, HMAC, AES-GCM (for TLS/SSH)
CONFIG_CRYPTO_AES=y
CONFIG_CRYPTO_AES_X86_64=y
CONFIG_CRYPTO_SHA256=y
CONFIG_CRYPTO_SHA512=y
CONFIG_CRYPTO_HMAC=y
CONFIG_CRYPTO_GHASH=y
CONFIG_CRYPTO_GCM=y

# =============================================================================
# Library routines
# =============================================================================
CONFIG_BITREVERSE=y
CONFIG_GENERIC_STRNCPY_FROM_USER=y
CONFIG_GENERIC_STRNLEN_USER=y
CONFIG_GENERIC_NET_UTILS=y
CONFIG_CRC32=y
CONFIG_CRC32_SLICEBY8=y
CONFIG_XXHASH=y
CONFIG_ZLIB_INFLATE=y
CONFIG_ZLIB_DEFLATE=y
CONFIG_LZO_COMPRESS=y
CONFIG_LZO_DECOMPRESS=y
CONFIG_XZ_DEC=y
CONFIG_XZ_DEC_X86=y
CONFIG_XZ_DEC_POWERPC=y
CONFIG_XZ_DEC_IA64=y
CONFIG_XZ_DEC_ARM=y
CONFIG_XZ_DEC_ARMTHUMB=y
CONFIG_XZ_DEC_SPARC=y
CONFIG_XXHASH=y

# =============================================================================
# Kernel hacking (minimal)
# =============================================================================
CONFIG_DEBUG_KERNEL=n
CONFIG_DEBUG_INFO=n
CONFIG_DEBUG_INFO_SPLIT=n
CONFIG_DEBUG_INFO_COMPRESSED=n

# =============================================================================
# Disable bloat
# =============================================================================
# No debugfs, no ftrace, no perf, no kprobes
# No sound, no video, no wireless
# No raid, no lvm, no dm
# No nfs, no cifs
# No bluetooth, no irda
# No isdn, no appletalk
# No hamradio, no can
EOF

# Merge fragment into tinyconfig
cd /tmp/kernel_minimal
cat /tmp/slinux-kernel-fragment.config >> .config

# Run olddefconfig to resolve dependencies
make olddefconfig

echo "=== Config summary ==="
wc -l .config
grep -c '=y' .config