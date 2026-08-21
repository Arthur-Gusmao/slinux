# slinux

a small, statically-linked linux distribution built from scratch.

slinux boots straight into a root shell. there is no systemd, no glibc,
no dynamic linking, no package manager and nothing you did not explicitly
put there. the whole userland fits in a few megabytes and every binary is
self-contained: copy it anywhere and it just runs.

the project exists because building a linux system by hand is the best way
to understand one. it follows the [suckless](https://suckless.org/)
philosophy where practical: small tools, simple code, sane defaults.

## what is inside

| component | source | role |
|---|---|---|
| linux 7.2 | [torvalds/linux](https://github.com/torvalds/linux) | kernel with ext4, ahci, nvme, usb, virtio |
| musl | [musl-libc](https://git.musl-libc.org/cgit/musl) | c library |
| sinit | fork | init (pid 1) |
| sbase + ubase | forks | core utilities |
| 9base | fork | plan 9 userland, plus `p`, our pager |
| dash | upstream | `/bin/sh` |
| neatvi | upstream | vi editor |
| zlib + minigzip | upstream | gzip/gunzip |
| bearssl | upstream | tls library; `brssl` tool and https `wget` (in sbase) |
| netbsd-curses | upstream | curses/terminfo libraries, `tput` `tset` `tabs` |
| limine | host package | uefi bootloader |

everything is cross-compiled with clang against a private sysroot
(`out/sysroot`) holding musl, the kernel uapi headers and the gcc runtime.

## host requirements

developed on alpine linux. you need:

- `clang`, `llvm` (llvm-ar), `make`, `cpio`, `rsync`
- `util-linux` (sfdisk, losetup, blkid), `dosfstools`, `e2fsprogs`
- `gcc` (its musl runtime gets mirrored into the sysroot)
- `limine` and `ovmf` for disk images and uefi testing
- `qemu-system-x86_64`
- `doas` or sudo access for loop mounts during installation

clone with submodules:

```
git clone --recurse-submodules git@github.com:Arthur-Gusmao/slinux.git
cd slinux
```

## building

run `make help` for the short version. the full pipeline:

```
make            # musl -> headers -> userland -> rootfs -> initramfs
make image      # also builds slinux.img, a bootable disk image
```

each stage only does its own work, so you can rebuild pieces in isolation
(`make userland`, `make kernel`, ...).

## running

boot the ram-only system (kernel + initramfs, nothing touches a disk):

```
make run
```

or boot the real thing, a disk image through uefi:

```
make run-image
```

login is `root` with an empty password. exit qemu with `ctrl-a x`.

## installing

`install.sh` writes slinux to an image file or a whole block device.
it creates a gpt layout with an esp (kernel + limine) and an ext4 root
partition, then copies the rootfs over:

```
./install.sh slinux.img 256     # 256M disk image
doas ./install.sh /dev/sdX      # real device - double check the name!
```

for a removable drive you can also just `dd` a generated `slinux.img`.
the machine must support uefi boot. on first boot limine shows a menu:
`slinux` boots from the ext4 partition, `slinux rescue` boots the
initramfs instead.

## repository layout

```
kernel/linux    linux source (submodule)
libc/musl       musl source (submodule)
init/sinit      init (submodule)
userland/       sbase, ubase, 9base, neatvi, zlib (submodules)
shell/dash      dash (submodule)
etc/            boot scripts and system files copied into the rootfs
install.sh      disk installer
Makefile        build orchestration
out/            sysroot and scratch space (not tracked)
rootfs/         generated root filesystem (not tracked)
```

## license

slinux itself is in the public domain. each component keeps its own
license; see the respective submodules.
