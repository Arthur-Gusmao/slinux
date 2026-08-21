# slinux build orchestration

ROOT      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SYSROOT   := $(ROOT)/out/sysroot
ROOTFS    := $(ROOT)/rootfs
INITRAMFS := $(ROOT)/slinux.cpio.gz
BZIMAGE   := $(ROOT)/kernel/linux/arch/x86/boot/bzImage
IMAGE     := $(ROOT)/slinux.img

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
ZLIB_SRCS  := adler32 compress crc32 deflate gzclose gzlib gzread gzwrite \
	infback inffast inflate inftrees trees uncompr zutil

.PHONY: all musl headers bearssl curses sdhcp userland rootfs initramfs run image run-image kernel clean help

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
	@echo "  make rootfs      populate rootfs/ with binaries and etc files"
	@echo "  make initramfs   pack rootfs/ into slinux.cpio.gz"
	@echo "  make kernel      build the linux kernel"
	@echo "  make image       build slinux.img (gpt: esp + ext4 root)"
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

userland: musl headers bearssl curses sdhcp
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

rootfs: userland
	mkdir -p $(ROOTFS)/bin $(ROOTFS)/sbin $(ROOTFS)/etc
	mkdir -p $(ROOTFS)/dev $(ROOTFS)/proc $(ROOTFS)/sys $(ROOTFS)/tmp
	mkdir -p $(ROOTFS)/root $(ROOTFS)/var/run $(ROOTFS)/var/log
	chmod 1777 $(ROOTFS)/tmp
	install -m644 etc/passwd etc/group etc/hostname etc/motd etc/fstab \
		etc/resolv.conf etc/hosts etc/services $(ROOTFS)/etc/
	mkdir -p $(ROOTFS)/etc/ssl
	@if [ -f /etc/ssl/certs/ca-certificates.crt ]; then \
		install -m644 /etc/ssl/certs/ca-certificates.crt \
			$(ROOTFS)/etc/ssl/cert.pem; \
	else \
		echo "warning: host has no CA bundle"; \
		echo "warning: https validation will fail until you provide one"; \
		touch $(ROOTFS)/etc/ssl/cert.pem; \
	fi
	install -m755 etc/rc.init etc/rc.shutdown $(ROOTFS)/bin/
	ln -sf dash $(ROOTFS)/bin/sh
	ln -sf /bin/init $(ROOTFS)/sbin/init
	ln -sf /bin/init $(ROOTFS)/init

initramfs: rootfs
	find $(ROOTFS) -print0 | xargs -0 touch -h -d @$(SOURCE_DATE_EPOCH)
	(cd $(ROOTFS) && find . -print0 | LC_ALL=C sort -z | \
		cpio --null -o -H newc --quiet --reproducible) | gzip -9n > $(INITRAMFS)

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

kernel:
	cp kernel/config kernel/linux/.config
	$(MAKE) -C kernel/linux olddefconfig all

clean:
	-@for d in $(INIT_DIRS) $(USER_DIRS) $(SHELL_DIR) $(VI_DIR) libc/musl \
		$(BEARSSL_DIR) $(CURSES_DIR); do \
		[ -d $$d ] && $(MAKE) -C $$d clean; done
	rm -rf out rootfs slinux.cpio.gz
	rm -f $(ZLIB_DIR)/*.o $(ZLIB_DIR)/libz.a $(ZLIB_DIR)/minigzip $(IMAGE)
