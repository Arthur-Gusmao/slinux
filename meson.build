# slinux - minimal static Linux distribution
# Meson build system (muon + samurai)
# This wraps the existing Makefile for heavy lifting,
# but uses Meson/ninja for dependency tracking and parallelism.

project('slinux', 'c',
  version: '0.1.0',
  default_options: [
    'buildtype=release',
    'optimization=s',
    'strip=true',
    'default_library=static',
    'werror=false',
  ],
  license: 'Public Domain / various'
)

# =============================================================================
# Cross-compilation toolchain
# =============================================================================
# The cross file defines the musl toolchain
# Build with: muon setup build --cross-file=meson/cross/x86_64-linux-musl.ini

# =============================================================================
# Global paths
# =============================================================================
out_root = meson.current_build_dir()
rootfs_dir = join_paths(out_root, 'rootfs')
iso_dir = join_paths(out_root, 'iso')
initramfs_file = join_paths(out_root, 'slinux.cpio.gz')
iso_file = join_paths(out_root, 'slinux.iso')
src_root = meson.source_root()

# =============================================================================
# Toolchain setup (musl sysroot)
# =============================================================================
sysroot_dir = join_paths(out_root, 'sysroot')

sysroot_stamp = custom_target(
  'sysroot',
  output: 'sysroot.stamp',
  command: [
    find_program('sh'), '-c',
    '@0@/scripts/setup-sysroot.sh @1@'
      .format(src_root, sysroot_dir)
  ],
  build_by_default: true,
  build_always_stale: true,
)

# =============================================================================
# Limine (needed for ISO)
# =============================================================================
limine_stamp = custom_target(
  'limine',
  output: 'limine.stamp',
  command: [
    find_program('sh'), '-c',
    'make -C @0@ out/host/limine/limine-uefi-cd.bin out/host/limine/BOOTX64.EFI >/dev/null && mkdir -p @1@/limine && cp -f @0@/out/host/limine/limine-uefi-cd.bin @0@/out/host/limine/BOOTX64.EFI @1@/limine/'
      .format(src_root, out_root)
  ],
  build_by_default: true,
  build_always_stale: true,
)

# =============================================================================
# Musl libc
# =============================================================================
musl_stamp = custom_target(
  'musl',
  output: 'musl.stamp',
  command: [
    find_program('sh'), '-c',
    'make -C @0@ musl >/dev/null'
      .format(src_root)
  ],
  depends: [sysroot_stamp],
  build_by_default: true,
  build_always_stale: true,
)

# =============================================================================
# Kernel
# =============================================================================
kernel_stamp = custom_target(
  'kernel',
  output: 'kernel.stamp',
  command: [
    find_program('sh'), '-c',
    'make -C @0@ kernel >/dev/null'
      .format(src_root)
  ],
  depends: musl_stamp,
  build_by_default: true,
  build_always_stale: true,
)

# =============================================================================
# Userland packages
# =============================================================================
userland_stamp = custom_target(
  'userland',
  output: 'userland.stamp',
  command: [
    find_program('sh'), '-c',
    'make -C @0@ userland >/dev/null'
      .format(src_root)
  ],
  depends: musl_stamp,
  build_by_default: true,
  build_always_stale: true,
)

# =============================================================================
# Rootfs assembly
# =============================================================================
rootfs_stamp = custom_target(
  'rootfs',
  output: 'rootfs.stamp',
  command: [
    find_program('sh'), '-c',
    '@0@/scripts/assemble-rootfs.sh @1@ @2@'
      .format(src_root, join_paths(out_root, 'rootfs'), out_root)
  ],
  depends: [musl_stamp, userland_stamp, kernel_stamp],
  build_by_default: true,
  build_always_stale: true,
)

# =============================================================================
# Initramfs
# =============================================================================
initramfs = custom_target(
  'initramfs',
  output: 'slinux.cpio.gz',
  command: [
    find_program('sh'), '-c',
    'cd @0@ && find . -print0 | LC_ALL=C sort -z | cpio --null -o -H newc --quiet --reproducible | gzip -9n > @1@'
      .format(join_paths(out_root, 'rootfs'), join_paths(out_root, 'slinux.cpio.gz'))
  ],
  depends: rootfs_stamp,
  build_by_default: true,
  build_always_stale: true,
)

# =============================================================================
# ISO
# =============================================================================
iso = custom_target(
  'iso',
  output: 'slinux.iso',
  command: [
    find_program('sh'), '-c',
    '@0@/scripts/make-iso.sh @1@ @2@ @3@'
      .format(src_root, join_paths(out_root, 'iso'), join_paths(out_root, 'slinux.cpio.gz'), join_paths(out_root, 'slinux.iso'))
  ],
  depends: [initramfs, kernel_stamp],
  build_by_default: true,
  build_always_stale: true,
)

# =============================================================================
# Default targets
# =============================================================================
default_targets = [iso]