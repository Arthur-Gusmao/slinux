# slinux build orchestration

ROOT      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SYSROOT   := $(ROOT)/out/sysroot
ROOTFS    := $(ROOT)/rootfs
INITRAMFS := $(ROOT)/slinux.cpio.gz
BZIMAGE   := $(ROOT)/kernel/linux/arch/x86/boot/bzImage

CC := clang --target=x86_64-linux-musl --sysroot=$(SYSROOT)

INIT_DIRS  := init/sinit
USER_DIRS  := userland/sbase userland/ubase userland/9base
SHELL_DIR  := shell/dash
VI_DIR     := userland/neatvi

.PHONY: all musl headers userland rootfs initramfs run kernel clean

all: initramfs

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

userland: musl headers
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

rootfs: userland
	mkdir -p $(ROOTFS)/bin $(ROOTFS)/sbin $(ROOTFS)/etc
	mkdir -p $(ROOTFS)/dev $(ROOTFS)/proc $(ROOTFS)/sys $(ROOTFS)/tmp
	mkdir -p $(ROOTFS)/root $(ROOTFS)/var/run $(ROOTFS)/var/log
	chmod 1777 $(ROOTFS)/tmp
	install -m644 etc/passwd etc/group etc/hostname etc/motd etc/fstab $(ROOTFS)/etc/
	install -m755 etc/rc.init etc/rc.shutdown $(ROOTFS)/bin/
	ln -sf dash $(ROOTFS)/bin/sh
	ln -sf /bin/init $(ROOTFS)/sbin/init
	ln -sf /bin/init $(ROOTFS)/init

initramfs: rootfs
	(cd $(ROOTFS) && find . -print0 | cpio --null -o -H newc --quiet) | gzip -9 > $(INITRAMFS)

run: initramfs
	qemu-system-x86_64 -m 256M -kernel $(BZIMAGE) -initrd $(INITRAMFS) \
		-append "console=ttyS0" -nographic -no-reboot

kernel:
	$(MAKE) -C kernel/linux olddefconfig all

clean:
	-@for d in $(INIT_DIRS) $(USER_DIRS) $(SHELL_DIR) $(VI_DIR) libc/musl; do \
		[ -d $$d ] && $(MAKE) -C $$d clean; done
	rm -rf out rootfs slinux.cpio.gz
