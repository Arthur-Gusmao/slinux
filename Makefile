# slinux build orchestration

ROOT      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SYSROOT   := $(ROOT)/out/sysroot
ROOTFS    := $(ROOT)/rootfs
INITRAMFS := $(ROOT)/slinux.cpio.gz
BZIMAGE   := $(ROOT)/kernel/linux/arch/x86/boot/bzImage
IMAGE     := $(ROOT)/slinux.img
ISO       := $(ROOT)/slinux.iso

CC := clang --target=x86_64-linux-musl --sysroot=$(SYSROOT)

# reproducible builds: fix timestamps for the kernel and anything that
# honors SOURCE_DATE_EPOCH (https://reproducible-builds.org/docs/source-date-epoch/)
SOURCE_DATE_EPOCH := $(shell git log -1 --format=%ct 2>/dev/null || echo 1704067200)
export SOURCE_DATE_EPOCH

INIT_DIRS   := init/sinit
USER_DIRS   := userland/sbase userland/ubase userland/9base
SHELL_DIR   := shell/dash
VI_DIR      := userland/neatvi
ZLIB_DIR    := userland/zlib
BEARSSL_DIR := userland/bearssl
CURSES_DIR  := userland/netbsd-curses
SDHCP_DIR   := userland/sdhcp
E2FSPROGS_DIR := userland/e2fsprogs
DROPBEAR_DIR  := userland/dropbear
HOSTAP_DIR    := userland/hostap
UTIL_LINUX_DIR := userland/util-linux
DOSFSTOOLS_DIR  := userland/dosfstools
FIRMWARE_DIR  := firmware
LIMINE_TOOL    := /usr/bin/limine
ZLIB_SRCS  := adler32 compress crc32 deflate gzclose gzlib gzread gzwrite \
	infback inffast inflate inftrees trees uncompr zutil

.PHONY: iso run-iso run-iso-uefi all musl headers bearssl curses sdhcp e2fsprogs dropbear wpasupplicant sfdisk mkfsfat userland rootfs initramfs run image run-image kernel clean help

all: initramfs

help:
	@echo "slinux $(shell git describe --tags --always 2>/dev/null)"
	@echo
	@echo "build targets:"
	@echo "  make musl        build musl into out/sysroot"
	@echo "  make headers     install kernel uapi headers into out/sysroot"
	@echo "  make userland    build and install every userland tool"
	@echo "  make bearssl     build bearssl (lib into sysroot, brssl)"
	@echo "  make curses      build netbsd-curses (libs, tput/tset/tabs)"
	@echo "  make sdhcp       build sdhcp (dhcp client)"
	@echo "  make e2fsprogs   build mke2fs/e2fsck/tune2fs (static)"
	@echo "  make dropbear    build dropbear ssh server + dbclient"
	@echo "  make rootfs      populate rootfs/ with binaries and etc files"
	@echo "  make initramfs   pack rootfs/ into slinux.cpio.gz"
	@echo "  make kernel      build the linux kernel"
	@echo "  make image       build slinux.img (gpt: esp + ext4 root)"
	@echo "  make iso         build slinux.iso (hybrid bios+uefi live installer)"
	@echo "  make run-iso     boot slinux.iso in qemu (bios)"
	@echo "  make run-iso-uefi boot slinux.iso in qemu (uefi)"
	@echo
	@echo "run targets:"
	@echo "  make run         boot the initramfs in qemu, serial console"
	@echo "  make run-image   boot slinux.img in qemu with uefi (ovmf)"
	@echo
	@echo "misc targets:"
	@echo "  make clean       remove build artifacts"
	@echo
	@echo "installer: ./install.sh <image-file|block-device> [size-mib]"

GCC_MUSL_DIR := $(firstword $(foreach d,$(wildcard /usr/lib/gcc/x86_64-linux-musl/*),$(d)))

musl:
	@test -d libc/musl || { \
		echo "libc/musl missing: add the submodule first"; exit 1; }
	cd libc/musl && CC=clang ./configure --prefix=/usr --syslibdir=/lib
	$(MAKE) -C libc/musl
	$(MAKE) -C libc/musl DESTDIR=$(SYSROOT) install
	@test -n "$(GCC_MUSL_DIR)" || { \
		echo "gcc runtime x86_64-linux-musl not found on host"; exit 1; }
	mkdir -p $(SYSROOT)/usr/lib/gcc/x86_64-linux-musl
	cp -r $(GCC_MUSL_DIR) $(SYSROOT)/usr/lib/gcc/x86_64-linux-musl/
	cp -f /usr/lib/libssp_nonshared.a $(SYSROOT)/usr/lib/

headers:
	$(MAKE) -C kernel/linux INSTALL_HDR_PATH=$(SYSROOT)/usr headers_install

bearssl: musl
	@test -d $(BEARSSL_DIR) || { \
		echo "$(BEARSSL_DIR) missing: add the submodule first"; exit 1; }
	$(MAKE) -C $(BEARSSL_DIR) CC='$(CC)' AR=llvm-ar LD='$(CC)' \
		CFLAGS='-W -Wall -Os' LDFLAGS='-s -static' DLL=no TESTS=no lib tools
	mkdir -p $(SYSROOT)/usr/include/bearssl $(ROOTFS)/bin
	cp -f $(BEARSSL_DIR)/inc/bearssl.h $(BEARSSL_DIR)/inc/bearssl_*.h \
		$(SYSROOT)/usr/include/bearssl/
	cp -f $(BEARSSL_DIR)/build/libbearssl.a $(SYSROOT)/usr/lib/
	install -m755 $(BEARSSL_DIR)/build/brssl $(ROOTFS)/bin/brssl

curses: musl
	@test -d $(CURSES_DIR) || { \
		echo "$(CURSES_DIR) missing: add the submodule first"; exit 1; }
	$(MAKE) -C $(CURSES_DIR) CC='$(CC)' AR=llvm-ar RANLIB=llvm-ranlib \
		CFLAGS='-Os' LDFLAGS='-s -static' LDFLAGS_HOST='-s -static' \
		PREFIX=/usr DESTDIR=$(SYSROOT) all-static install-static
	$(MAKE) -C $(CURSES_DIR) terminfo/terminfo.cdb
	mkdir -p $(ROOTFS)/bin $(ROOTFS)/usr/share
	install -m755 $(SYSROOT)/usr/bin/tput $(SYSROOT)/usr/bin/tset \
		$(SYSROOT)/usr/bin/tabs $(ROOTFS)/bin/
	install -m644 $(CURSES_DIR)/terminfo/terminfo.cdb \
		$(ROOTFS)/usr/share/terminfo.cdb

sdhcp: musl
	@test -d $(SDHCP_DIR) || { \
		echo "$(SDHCP_DIR) missing: add the submodule first"; exit 1; }
	$(MAKE) -C $(SDHCP_DIR) CC='$(CC)' LD='$(CC)' AR=llvm-ar \
		RANLIB=llvm-ranlib CPPFLAGS='-D_DEFAULT_SOURCE' \
		CFLAGS='-Os' LDFLAGS='-s -static' all
	mkdir -p $(ROOTFS)/bin
	install -m755 $(SDHCP_DIR)/sdhcp $(ROOTFS)/bin/sdhcp

e2fsprogs: musl
	@test -d $(E2FSPROGS_DIR) || { \
		echo "$(E2FSPROGS_DIR) missing: add the submodule first"; exit 1; }
	cd $(E2FSPROGS_DIR) && CC='$(CC)' ./configure --prefix=/usr \
		--disable-nls --disable-shared --disable-e2scrub \
		--disable-uuidd --disable-profile LDFLAGS='-s -static'
	$(MAKE) -C $(E2FSPROGS_DIR) libs progs
	mkdir -p $(ROOTFS)/bin $(ROOTFS)/etc
	install -m755 $(E2FSPROGS_DIR)/misc/mke2fs $(E2FSPROGS_DIR)/misc/tune2fs \
		$(E2FSPROGS_DIR)/misc/dumpe2fs $(E2FSPROGS_DIR)/misc/logsave \
		$(E2FSPROGS_DIR)/e2fsck/e2fsck $(ROOTFS)/bin/
	install -m644 $(E2FSPROGS_DIR)/misc/mke2fs.conf $(ROOTFS)/etc/
	for t in ext2 ext3 ext4; do \
		ln -sf mke2fs $(ROOTFS)/bin/mkfs.$$t; \
		ln -sf e2fsck $(ROOTFS)/bin/fsck.$$t; done

dropbear: musl
	@test -d $(DROPBEAR_DIR) || { \
		echo "$(DROPBEAR_DIR) missing: add the submodule first"; exit 1; }
	rm -f $(ZLIB_DIR)/libz.a
	@for f in $(ZLIB_SRCS); do \
		$(CC) -Os -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN \
			-c $(ZLIB_DIR)/$$f.c -o $(ZLIB_DIR)/$$f.o || exit; done
	llvm-ar rcs $(ZLIB_DIR)/libz.a $(addprefix $(ZLIB_DIR)/,$(ZLIB_SRCS:=.o))
	cd $(DROPBEAR_DIR) && CC='$(CC)' ./configure --prefix=/usr \
		CFLAGS='-Os -I$(ROOT)/$(ZLIB_DIR)' \
		LDFLAGS='-s -static -L$(ROOT)/$(ZLIB_DIR)'
	$(MAKE) -C $(DROPBEAR_DIR) MULTI=1
	mkdir -p $(ROOTFS)/bin
	install -m755 $(DROPBEAR_DIR)/dropbearmulti $(ROOTFS)/bin/dropbearmulti
	for t in dropbear dbclient dropbearkey scp; do \
		ln -sf dropbearmulti $(ROOTFS)/bin/$$t; done
	ln -sf dbclient $(ROOTFS)/bin/ssh

wpasupplicant: musl
	@test -d $(HOSTAP_DIR) || { \
		echo "$(HOSTAP_DIR) missing: add the submodule first"; exit 1; }
	cp /dev/null $(HOSTAP_DIR)/wpa_supplicant/.config
	printf '%s\n' \
		'CONFIG_BACKEND=file' \
		'CONFIG_CTRL_IFACE=y' \
		'CONFIG_IEEE8021X_EAPOL=y' \
		'CONFIG_EAP_PEAP=y' 'CONFIG_EAP_MSCHAPV2=y' \
		'CONFIG_EAP_TTLS=y' 'CONFIG_EAP_TLS=y' \
		'CONFIG_TLS=internal' \
		'CONFIG_INTERNAL_LIBTOMMATH=y' \
		'CONFIG_CRYPTO_INTERNAL=y' \
		> $(HOSTAP_DIR)/wpa_supplicant/.config
	$(MAKE) -C $(HOSTAP_DIR)/wpa_supplicant CC='$(CC)' \
		LDFLAGS='-s -static' BINDIR=/bin LIBDIR=/lib wpa_supplicant wpa_cli
	mkdir -p $(ROOTFS)/bin
	install -m755 $(HOSTAP_DIR)/wpa_supplicant/wpa_supplicant \
		$(HOSTAP_DIR)/wpa_supplicant/wpa_cli $(ROOTFS)/bin/

sfdisk: musl
	@test -d $(UTIL_LINUX_DIR) || { \
		echo "$(UTIL_LINUX_DIR) missing: add the submodule first"; exit 1; }
	@test -f $(ROOT)/out/sysroot/usr/lib/libgcc_s.a || \
		ar rcs $(SYSROOT)/usr/lib/libgcc_s.a
	cd $(UTIL_LINUX_DIR) && CC='$(CC)' ./configure --prefix=/usr \
		--disable-shared --enable-static --enable-static-programs=sfdisk \
		--without-systemdsystemunitdir --without-systemd \
		--without-python --without-tinfo --without-ncurses --without-ncursesw \
		--disable-bash-completion --disable-nls --without-libcrypto \
		--without-libz --without-libcap-ng --without-readline \
		--without-utempter \
		--disable-all-programs --enable-fdisks=check --enable-libfdisk \
		--enable-libblkid --enable-libuuid --enable-libsmartcols LDFLAGS='-s'
	$(MAKE) -C $(UTIL_LINUX_DIR) sfdisk.static
	mkdir -p $(ROOTFS)/bin
	install -m755 $(UTIL_LINUX_DIR)/sfdisk.static $(ROOTFS)/bin/sfdisk

mkfsfat: musl
	@test -d $(DOSFSTOOLS_DIR) || { \
		echo "$(DOSFSTOOLS_DIR) missing: add the submodule first"; exit 1; }
	cd $(DOSFSTOOLS_DIR) && CC='$(CC)' ./configure --prefix=/usr \
		--disable-nls LDFLAGS='-static -s'
	$(MAKE) -C $(DOSFSTOOLS_DIR)
	mkdir -p $(ROOTFS)/bin
	install -m755 $(DOSFSTOOLS_DIR)/src/mkfs.fat $(ROOTFS)/bin/mkfs.fat
	install -m755 $(DOSFSTOOLS_DIR)/src/fsck.fat $(ROOTFS)/bin/fsck.fat

userland: musl headers bearssl curses sdhcp e2fsprogs dropbear wpasupplicant sfdisk mkfsfat
	$(MAKE) -C $(INIT_DIRS) CC='$(CC)'
	$(MAKE) -C $(INIT_DIRS) install DESTDIR=$(ROOTFS) PREFIX=/
	mv -f $(ROOTFS)/bin/sinit $(ROOTFS)/bin/init
	@for d in userland/sbase userland/ubase; do \
		$(MAKE) -C $$d CC='$(CC)' LDLIBS= LDFLAGS='-s -static' || exit; \
		$(MAKE) -C $$d install DESTDIR=$(ROOTFS) PREFIX=/ || exit; \
	done
	$(MAKE) -C userland/9base CC='$(CC)' PREFIX=/usr/plan9
	$(MAKE) -C userland/9base install DESTDIR=$(ROOTFS) PREFIX=/usr/plan9
	cd $(SHELL_DIR) && CC='$(CC)' LDFLAGS='-s -static' ./configure \
		--prefix=/ --sysconfdir=/etc \
		--build=x86_64-alpine-linux-musl --host=x86_64-linux-musl
	$(MAKE) -C $(SHELL_DIR) LDFLAGS='-s -static'
	$(MAKE) -C $(SHELL_DIR) install DESTDIR=$(ROOTFS)
	$(MAKE) -C $(VI_DIR) clean
	$(MAKE) -C $(VI_DIR) CC='$(CC)' CFLAGS='-Wall -O2 -Wno-format-truncation' LDFLAGS='-s -static'
	install -m755 $(VI_DIR)/vi $(ROOTFS)/bin/vi
	rm -f $(ZLIB_DIR)/*.o $(ZLIB_DIR)/libz.a $(ZLIB_DIR)/minigzip
	@for f in $(ZLIB_SRCS); do \
		$(CC) -O2 -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN \
			-c $(ZLIB_DIR)/$$f.c -o $(ZLIB_DIR)/$$f.o || exit; done
	llvm-ar rcs $(ZLIB_DIR)/libz.a $(addprefix $(ZLIB_DIR)/,$(ZLIB_SRCS:=.o))
	$(CC) -O2 -I$(ZLIB_DIR) -s -static -o $(ZLIB_DIR)/minigzip \
		$(ZLIB_DIR)/test/minigzip.c $(ZLIB_DIR)/libz.a
	install -m755 $(ZLIB_DIR)/minigzip $(ROOTFS)/bin/gzip
	printf '#!/bin/sh\nexec /bin/gzip -d "$$@"\n' > $(ROOTFS)/bin/gunzip
	chmod 755 $(ROOTFS)/bin/gunzip
	printf '#!/bin/sh\nexec /bin/halt -p\n' > $(ROOTFS)/bin/poweroff
	printf '#!/bin/sh\nexec /bin/halt -r\n' > $(ROOTFS)/bin/reboot
	chmod 755 $(ROOTFS)/bin/poweroff $(ROOTFS)/bin/reboot

rootfs: userland
	mkdir -p $(ROOTFS)/bin $(ROOTFS)/sbin $(ROOTFS)/etc
	mkdir -p $(ROOTFS)/dev $(ROOTFS)/proc $(ROOTFS)/sys $(ROOTFS)/tmp
	mkdir -p $(ROOTFS)/root $(ROOTFS)/mnt $(ROOTFS)/var/run $(ROOTFS)/var/log
	chmod 1777 $(ROOTFS)/tmp
	install -m644 etc/passwd etc/group etc/hostname etc/motd etc/fstab \
		etc/resolv.conf etc/hosts etc/services $(ROOTFS)/etc/
	mkdir -p $(ROOTFS)/etc/ssl
	@if [ -f /etc/ssl/certs/ca-certificates.crt ]; then \
		install -m644 /etc/ssl/certs/ca-certificates.crt \
			$(ROOTFS)/etc/ssl/cert.pem; \
	else \
		echo "warning: no host CA bundle found"; \
		touch $(ROOTFS)/etc/ssl/cert.pem; \
	fi
	mkdir -p $(ROOTFS)/lib/firmware
	cp -r firmware/. $(ROOTFS)/lib/firmware/
	mkdir -p $(ROOTFS)/bin $(ROOTFS)/lib/limine
	install -m755 bin/slinux-install $(ROOTFS)/bin/slinux-install
	install -m644 bootloader/limine/BOOTX64.EFI \
		bootloader/limine/limine-bios.sys $(ROOTFS)/lib/limine/
ifneq ($(wildcard $(BZIMAGE)),)
	mkdir -p $(ROOTFS)/boot
	install -m644 $(BZIMAGE) $(ROOTFS)/boot/vmlinuz
endif
	install -m755 etc/rc.init etc/rc.shutdown $(ROOTFS)/bin/
	ln -sf dash $(ROOTFS)/bin/sh
	ln -sf /bin/init $(ROOTFS)/sbin/init
	ln -sf /bin/init $(ROOTFS)/init

initramfs: rootfs
	find $(ROOTFS) -print0 | xargs -0 touch -h -d @$(SOURCE_DATE_EPOCH)
	fakeroot -- sh -c 'chown -R 0:0 $(ROOTFS) && \
		cd $(ROOTFS) && find . -print0 | LC_ALL=C sort -z | \
		cpio --null -o -H newc --quiet --reproducible' | gzip -9n > $(INITRAMFS)

run: initramfs
	qemu-system-x86_64 -m 256M -kernel $(BZIMAGE) -initrd $(INITRAMFS) \
		-append "console=ttyS0" -nographic -no-reboot

image: initramfs
	./install.sh $(IMAGE) 256

run-image: image
	@test -f out/OVMF_VARS.fd || cp /usr/share/OVMF/OVMF_VARS.fd out/OVMF_VARS.fd
	qemu-system-x86_64 -m 512M \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
		-drive if=pflash,format=raw,file=out/OVMF_VARS.fd \
		-drive file=$(IMAGE),format=raw,if=virtio -nographic

# hybrid iso: boots on bios (el torito) and uefi (embedded efi image);
# dd-able to usb sticks as well. the live system ships slinux-install(8)
iso: initramfs $(LIMINE_TOOL)
	@command -v xorriso >/dev/null || { echo "xorriso missing"; exit 1; }
	rm -rf out/iso && mkdir -p out/iso/EFI/BOOT
	cp $(BZIMAGE) out/iso/vmlinuz
	cp $(INITRAMFS) out/iso/initramfs.cpio.gz
	install -m644 bootloader/limine/limine-bios.sys \
		bootloader/limine/limine-bios-cd.bin \
		bootloader/limine/limine-uefi-cd.bin out/iso/
	install -m644 bootloader/limine/BOOTX64.EFI out/iso/EFI/BOOT/
	printf 'timeout: 5\n\n/slinux (live)\n    protocol: linux\n    path: boot():/vmlinuz\n    cmdline: console=ttyS0 console=tty0\n    module_path: boot():/initramfs.cpio.gz\n' \
		> out/iso/limine.conf
	xorriso -as mkisofs -r -J -V SLINUX_LIVE \
		-b limine-bios-cd.bin -no-emul-boot -boot-load-size 4 \
		-boot-info-table --protective-msdos-label \
		--efi-boot limine-uefi-cd.bin -efi-boot-part --efi-boot-image \
		out/iso -o $(ISO)
	$(LIMINE_TOOL) bios-install $(ISO)
	@echo "wrote $(ISO)"

run-iso: iso
	qemu-system-x86_64 -m 768M -cdrom $(ISO) -nographic -no-reboot

run-iso-uefi: iso
	@test -f out/OVMF_VARS.fd || cp /usr/share/OVMF/OVMF_VARS.fd out/OVMF_VARS.fd
	qemu-system-x86_64 -m 768M \
		-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
		-drive if=pflash,format=raw,file=out/OVMF_VARS.fd \
		-cdrom $(ISO) -nographic -no-reboot

kernel:
	cp kernel/config kernel/linux/.config
	$(MAKE) -C kernel/linux olddefconfig all

clean:
	-@for d in $(INIT_DIRS) $(USER_DIRS) $(SHELL_DIR) $(VI_DIR) libc/musl \
		$(BEARSSL_DIR) $(CURSES_DIR); do \
		[ -d $$d ] && $(MAKE) -C $$d clean; done
	rm -rf out rootfs slinux.cpio.gz
	rm -f $(ZLIB_DIR)/*.o $(ZLIB_DIR)/libz.a $(ZLIB_DIR)/minigzip $(IMAGE)
