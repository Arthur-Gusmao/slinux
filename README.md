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
| linux 7.x | [torvalds/linux](https://github.com/torvalds/linux) | kernel: ext4, ahci, nvme, usb storage, virtio, framebuffer, wifi |
| musl | [musl-libc](https://git.musl-libc.org/cgit/musl) | c library |
| sinit | fork | init (pid 1) |
| sbase + ubase | forks | core utilities |
| 9base | fork | plan 9 userland, plus `p`, our pager |
| dash | upstream | `/bin/sh` |
| neatvi | upstream | vi editor |
| zlib + minigzip | upstream | gzip/gunzip |
| bearssl | upstream | tls library; `brssl` tool (used by curl) |
| netbsd-curses | upstream | curses/terminfo libraries, `tput` `tset` `tabs` |
| sdhcp | upstream | dhcp client, started by rc.init |
| e2fsprogs | upstream | static `mkfs.ext4`, `fsck.ext4`, `tune2fs` |
| dropbear | upstream | ssh server (`dropbear`) + client (`dbclient`/`ssh`/`scp`) |
| wpa_supplicant | [hostap](https://w1.fi/hostap.git) 2.12 | static, internal crypto, wpa2-psk and eap |
| util-linux | upstream | static `sfdisk` (partitioning) |
| dosfstools | upstream | static `mkfs.fat`, `fsck.fat` (esp) |
| libressl | upstream | tls library (static), used by `wget` |
| GNU wget 1.25 | upstream | full-featured `wget` with https over libressl |
| iputils 20250605 | upstream | `ping`, `ping6`, `tracepath`, `arping` |
| net-tools 2.10 | upstream | classic `ifconfig`, `route`, `netstat`, `arp`, `nameif` |
| openrdate | upstream | `rdate` (sntp), musl shim in `patches/` |
| mandoc 1.14.6 | vendored snapshot | `man`, `apropos`, `whatis`, `makewhatis`; pager is plan9 `p` |
| ubase extras | ours | `syslogd`, `logger` |
| smdev | fork | device manager: `smdev -s` coldplug; slinux rules baked into the fork |
| nldev | mirror | netlink hotplug daemon feeding uevents to smdev |
| svc | mirror | service framework (`svc -s/-k/-r/-a/-d/-l`, `service start/stop/restart`) |
| curl 8.14.1 | upstream | static https client over BearSSL (last release with the bearssl backend) |
| limine 12.6 | upstream | bootloader (submodule); bios+uefi stages built from source |

wifi firmware blobs live in `firmware/`: intel 9000/9560/ax201/ax210/ax211,
realtek rtw88/rtw89 and mediatek mt7921 - matching the drivers built into
the kernel.

everything is cross-compiled with clang against a private sysroot
(`out/sysroot`) holding musl, the kernel uapi headers and stub gcc
runtime archives. every target binary is statically linked.

## two ways to boot

- **live (ram)**: kernel + initramfs only. nothing touches a disk. this is
  what the iso boots; the installer runs from here.
- **installed (disk)**: limine loads the kernel straight off the esp with
  `root=PARTUUID=...`; the kernel mounts the ext4 root itself, no
  initramfs involved. requires ext4 and all storage drivers built into
  the kernel (they are).

## host requirements

developed on alpine linux. you need:

- `clang`, `llvm` (llvm-ar), `make`, `rsync`
- `cpio` — the GNU one; busybox cpio silently produces a broken initramfs
- `meson`, `ninja` (iputils), `nasm` + `mtools` + `autoconf`/`automake`/
  `libtool` (libressl and limine bootstrap at build time)
- `gcc` (runtime archives mirrored into the sysroot), `musl-cross` not
  required - clang targets the sysroot directly
- `util-linux` (sfdisk, losetup, blkid), `dosfstools`, `e2fsprogs`
- `xorriso` (iso), `fakeroot` (root-owned initramfs)
- `doas` or sudo access for loop mounts during usb writing

clone with submodules:

```
git clone --recurse-submodules https://github.com/Arthur-Gusmao/slinux.git
cd slinux
```

## building

run `make help` for the short version. main targets:

```
make              # musl -> headers -> userland -> rootfs -> slinux.cpio.gz
make kernel       # build the linux kernel from kernel/config
make iso          # slinux.iso: hybrid bios+uefi live installer (~60m)
make clean        # remove build artifacts
```

stages can be rebuilt in isolation (`make userland`, `make rootfs`,
`make initramfs`, ...). builds are reproducible: everything is stamped
with `SOURCE_DATE_EPOCH` from the last commit, the initramfs file list is
sorted and packed under fakeroot so all files are uid 0/gid 0.

## installing on real hardware (baremetal)

1. **build and write the usb stick**

   ```
   make iso
   doas dd if=slinux.iso of=/dev/sdX bs=4M status=progress && sync
   ```

   the iso is hybrid: dd to a usb stick or burn to cd, both work.

2. **boot the machine from the stick** via the firmware boot menu
   (f12/f11/esc/del depending on vendor). prefer the **uefi** entry -
   it is the path we can actually test.

3. **log in as root** (empty password) and install:

   ```
   ls /sys/block                 # find the target disk: sda, nvme0n1...
   slinux-install /dev/sda       # double-check the name!
   ```

   confirm with `y`. the installer partitions the disk (gpt: 256mib esp +
   1mib bios boot + ext4 root), formats them, copies the whole system
   over, installs limine for both uefi and bios, writes `limine.conf`
   with `root=PARTUUID=` and asks for the root password plus a regular
   user (member of `wheel`; use `doas` to run commands as root).

4. **reboot without the stick** - the system boots from disk.

### after installing

| what | how |
|---|---|
| become root | `doas sh` (your user password; you were added to `wheel` at install time) |
| ssh access | dropbear already listens on :22; put keys in `/root/.ssh/authorized_keys` |
| wired network | automatic (`sdhcp` at boot) |
| wifi | create `/etc/wpa_supplicant.conf` and reboot; rc.init associates and dhcp's every wlan interface found |
| clock | `rdate pool.ntp.org` |
| https | `curl https://...` (bearssl) or `wget https://...` (libressl); ca bundle at `/etc/ssl/cert.pem` |
| icmp | `ping -c 3 host` (`iputils`) |
| routing | `ifconfig`, `route`, `netstat`, `arp` (net-tools) |
| man pages | `man ls`, `apropos network` (mandoc; db ships prebuilt) |

### services

daemons are managed by svc(8); services live in `/bin/svc.d`, enabled
ones are symlinked from `run/`. dropbear ships enabled:

    svc -l              # list running services
    svc -a foo          # enable a service (avail/foo must exist)
    svc -s foo          # start
    svc -k foo          # stop
    svc -r foo          # restart
    service stop sshd   # sysv-style alias: service start|stop|restart

a service is either an executable script in `avail/` or an empty file
(run the like-named binary with the params from `default/<name>`).
site-specific boot customisation belongs in `/etc/rc.local`
(create it; rc.init runs it last if executable).

### bios-only machines

the on-target installer prefers uefi but works from a bios boot too: it
writes a gpt with an esp and a 1mib bios boot partition, copies
`limine-bios.sys` to the esp and runs `limine bios-install` to embed the
bios stages. caveat: bios booting from disk is currently untestable in
qemu/seabios (limine 12.6 hangs there even with stock binaries; the iso
and uefi paths are unaffected), so on real hardware verify before
wiping anything you care about. alternatively, install from another
linux box with this repository checked out:

```
./install.sh /dev/sdX           # writes gpt + limine bios stages directly
```

## repository layout

```
kernel/linux        linux source (submodule)
kernel/config       our kernel configuration
libc/musl           musl source (submodule)
init/sinit          init (submodule)
userland/           sbase, ubase, 9base, neatvi, zlib, bearssl,
                    netbsd-curses, sdhcp, e2fsprogs, dropbear, hostap,
                    util-linux, dosfstools, libressl (+ libressl-openbsd
                    source feed), iputils, net-tools, openrdate, wget,
                    limine (submodules)
userland/mandoc     vendored mandoc snapshot (man/apropos)
patches/            musl compat shims (openrdate)
shell/dash          dash (submodule)
etc/                boot scripts (rc.init), motd, services, fstab
bin/slinux-install  on-target installer (runs from the live system)
firmware/           wifi firmware blobs
install.sh          host-side disk/image installer
Makefile            build orchestration
out/                sysroot and scratch space (not tracked)
rootfs/             generated root filesystem (not tracked)
slinux.iso          build output (not tracked)
```

## boot flow

`sinit` (pid 1) spawns `/etc/rc.init`, which mounts proc/sys/dev, starts
`syslogd`, sets the hostname, brings up loopback and dhcp on eth0, joins
wifi networks if `/etc/wpa_supplicant.conf` exists, starts dropbear and
respawns getty on ttyS0 and tty1. when booted with `root=` from the live
initramfs, rc.init instead fscks and switch_roots into the real root
first (see `etc/rc.init`).

## limitations

- x86_64 only.
- no package manager, by design: rebuild from source or rsync files.
- on-target installer wipes the whole disk; no dual boot, no custom
  partitioning (edit `bin/slinux-install` if you need it).
- wpa3/sae unsupported (internal crypto lacks bignum math); wpa2-psk and
  common eap networks work.
- on-target installer prefers uefi; bios-from-disk is untested in
  emulators (see above) and unverified on real hardware.

## license

slinux itself is in the public domain. each component keeps its own
license; see the respective submodules.
