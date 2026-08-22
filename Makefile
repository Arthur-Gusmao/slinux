# slinux build orchestration

ROOT      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SYSROOT   := $(ROOT)/out/sysroot
ROOTFS    := $(ROOT)/rootfs
INITRAMFS := $(ROOT)/slinux.cpio.gz
BZIMAGE   := $(ROOT)/kernel/linux/arch/x86/boot/bzImage
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
SMDEV_DIR   := userland/smdev
NLDEV_DIR   := userland/nldev
SVC_DIR     := userland/svc
SUP_DIR     := userland/sup
CURL_DIR    := userland/curl
LIBRESSL_DIR  := userland/libressl
IPUTILS_DIR   := userland/iputils
NET_TOOLS_DIR := userland/net-tools
OPENRDATE_DIR := userland/openrdate
MANDOC_DIR    := userland/mandoc
WGET_DIR      := userland/wget
FIRMWARE_DIR  := firmware
LIMINE_TOOL    := /usr/bin/limine
ZLIB_SRCS  := adler32 compress crc32 deflate gzclose gzlib gzread gzwrite \
	infback inffast inflate inftrees trees uncompr zutil

.PHONY: iso all musl headers bearssl curses sdhcp e2fsprogs dropbear wpasupplicant sfdisk mkfsfat smdev nldev svc sup curl zlib libressl iputils nettools rdate mandoc wget userland rootfs initramfs kernel clean help

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
	@echo "  make wpasupplicant  build wpa_supplicant/wpa_cli (static)"
	@echo "  make sfdisk      build sfdisk (static, partitioning)"
	@echo "  make mkfsfat     build mkfs.fat/fsck.fat (static)"
	@echo "  make smdev       build smdev (device manager)"
	@echo "  make nldev       build nldev/nltrigger (hotplug daemon)"
	@echo "  make svc         install svc(8) service framework"
	@echo "  make sup         build sup (hardcoded sudo, suid)"
	@echo "  make curl        build curl (static, BearSSL TLS)"
	@echo "  make zlib        build zlib (lib into sysroot)"
	@echo "  make libressl    build libressl (libs into sysroot)"
	@echo "  make iputils     build ping/ping6/tracepath/arping (static)"
	@echo "  make nettools    build ifconfig/route/netstat/arp/nameif (static)"
	@echo "  make rdate       build rdate (sntp, static)"
	@echo "  make mandoc      build man/apropos/whatis/makewhatis"
	@echo "  make wget        build GNU wget (static, LibreSSL TLS)"
	@echo "  make rootfs      populate rootfs/ with binaries and etc files"
	@echo "  make initramfs   pack rootfs/ into slinux.cpio.gz"
	@echo "  make kernel      build the linux kernel"
	@echo "  make iso         build slinux.iso (hybrid bios+uefi live installer)"
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
	mkdir -p $(SYSROOT)/usr/include $(ROOTFS)/bin
	cp -f $(BEARSSL_DIR)/inc/bearssl.h $(BEARSSL_DIR)/inc/bearssl_*.h \
		$(SYSROOT)/usr/include/
	cp -f $(BEARSSL_DIR)/build/libbearssl.a $(SYSROOT)/usr/lib/
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
	cd $(E2FSPROGS_DIR) && CC='$(CC)' CFLAGS='-D_GNU_SOURCE -O2' ./configure --prefix=/usr \
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

zlib: musl
	@test -d $(ZLIB_DIR) || { \
		echo "$(ZLIB_DIR) missing: add the submodule first"; exit 1; }
	@for f in $(ZLIB_SRCS); do \
		$(CC) -Os -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN \
			-c $(ZLIB_DIR)/$$f.c -o $(ZLIB_DIR)/$$f.o || exit; done
	llvm-ar rcs $(ZLIB_DIR)/libz.a $(addprefix $(ZLIB_DIR)/,$(ZLIB_SRCS:=.o))
	mkdir -p $(SYSROOT)/usr/include $(SYSROOT)/usr/lib
	cp -f $(ZLIB_DIR)/zlib.h $(ZLIB_DIR)/zconf.h $(SYSROOT)/usr/include/
	cp -f $(ZLIB_DIR)/libz.a $(SYSROOT)/usr/lib/

dropbear: musl zlib
	@test -d $(DROPBEAR_DIR) || { \
		echo "$(DROPBEAR_DIR) missing: add the submodule first"; exit 1; }
	cd $(DROPBEAR_DIR) && CC='$(CC)' ./configure --prefix=/usr \
		CFLAGS='-Os' LDFLAGS='-s -static'
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
	$(MAKE) -C $(HOSTAP_DIR)/wpa_supplicant clean >/dev/null 2>&1 || true
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
	cd $(UTIL_LINUX_DIR) && PATH=/usr/bin:/bin autoreconf -fi >/dev/null 2>&1
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
	cd $(DOSFSTOOLS_DIR) && PATH=/usr/bin:/bin autoreconf -fi >/dev/null 2>&1
	cd $(DOSFSTOOLS_DIR) && CC='$(CC)' ./configure --prefix=/usr \
		--disable-nls LDFLAGS='-static -s'
	$(MAKE) -C $(DOSFSTOOLS_DIR)
	mkdir -p $(ROOTFS)/bin
	install -m755 $(DOSFSTOOLS_DIR)/src/mkfs.fat $(ROOTFS)/bin/mkfs.fat
	install -m755 $(DOSFSTOOLS_DIR)/src/fsck.fat $(ROOTFS)/bin/fsck.fat

smdev: musl
	@test -d $(SMDEV_DIR) || { \
		echo "$(SMDEV_DIR) missing: add the submodule first"; exit 1; }
	cp -f $(SMDEV_DIR)/config.def.h $(SMDEV_DIR)/config.h
	$(MAKE) -C $(SMDEV_DIR) CC='$(CC)' LDFLAGS='-s -static'
	mkdir -p $(ROOTFS)/bin
	install -m755 $(SMDEV_DIR)/smdev $(ROOTFS)/bin/smdev

nldev: musl
	@test -d $(NLDEV_DIR) || { \
		echo "$(NLDEV_DIR) missing: add the submodule first"; exit 1; }
	$(MAKE) -C $(NLDEV_DIR) CC='$(CC)' INCS='-I.' LIBS='-lc' \
		LDFLAGS='-static -s'
	mkdir -p $(ROOTFS)/bin
	install -m755 $(NLDEV_DIR)/nldev $(ROOTFS)/bin/nldev
	install -m755 $(NLDEV_DIR)/nltrigger $(ROOTFS)/bin/nltrigger

svc:
	@test -d $(SVC_DIR) || { \
		echo "$(SVC_DIR) missing: add the submodule first"; exit 1; }
	mkdir -p $(ROOTFS)/bin/svc.d/avail $(ROOTFS)/bin/svc.d/default \
		$(ROOTFS)/bin/svc.d/run
	install -m755 $(SVC_DIR)/bin/svc $(SVC_DIR)/bin/service $(ROOTFS)/bin/
	install -m755 $(SVC_DIR)/svc.d/bare.sh $(ROOTFS)/bin/svc.d/

sup: musl
	@test -d $(SUP_DIR) || { \
		echo "$(SUP_DIR) missing: add the submodule first"; exit 1; }
	$(MAKE) -C $(SUP_DIR) CC='$(CC)' \
		CFLAGS='-std=c99 -D_DEFAULT_SOURCE -Os -static' LDFLAGS='-static -s'
	mkdir -p $(ROOTFS)/bin
	install -m4755 $(SUP_DIR)/sup $(ROOTFS)/bin/sup

curl: musl bearssl
	@test -d $(CURL_DIR) || { \
		echo "$(CURL_DIR) missing: add the submodule first"; exit 1; }
	cd $(CURL_DIR) && PATH=/usr/bin:/bin autoreconf -fi >/dev/null 2>&1
	cd $(CURL_DIR) && PATH=/usr/bin:/bin ./configure --host=x86_64-linux-musl \
		--prefix=/usr --disable-shared --enable-static \
		--with-bearssl=$(SYSROOT) --without-openssl --without-zlib \
		--without-libpsl --without-libidn2 --without-nghttp2 \
		--without-brotli --without-zstd --without-libssh2 --disable-ldap \
		--disable-ldaps --enable-optimize=-Os --disable-manual \
		--disable-dependency-tracking --with-ca-bundle=/etc/ssl/cert.pem \
		CC='$(CC)' LD='$(CC)' CFLAGS='-Os' LDFLAGS='-static'
	$(MAKE) -C $(CURL_DIR) -j$$(nproc) LDFLAGS='-all-static'
	mkdir -p $(ROOTFS)/bin
	install -m755 $(CURL_DIR)/src/curl $(ROOTFS)/bin/curl

libressl: musl
	@test -d $(LIBRESSL_DIR) || { \
		echo "$(LIBRESSL_DIR) missing: add the submodule first"; exit 1; }
	@test -f $(SYSROOT)/usr/lib/libgcc_s.a || ar rcs $(SYSROOT)/usr/lib/libgcc_s.a
	cd $(LIBRESSL_DIR) && autoreconf -fi >/dev/null 2>&1
	cd $(LIBRESSL_DIR) && CC='$(CC)' CFLAGS='-Os' ./configure \
		--prefix=/usr --disable-shared --disable-tests
	$(MAKE) -C $(LIBRESSL_DIR)/crypto -j$$(nproc)
	$(MAKE) -C $(LIBRESSL_DIR)/ssl -j$$(nproc)
	mkdir -p $(SYSROOT)/usr/include/openssl $(SYSROOT)/usr/lib/pkgconfig
	cp -f $(LIBRESSL_DIR)/include/openssl/*.h $(SYSROOT)/usr/include/openssl/
	cp -f $(LIBRESSL_DIR)/crypto/.libs/libcrypto.a \
		$(LIBRESSL_DIR)/ssl/.libs/libssl.a $(SYSROOT)/usr/lib/
	printf 'Name: OpenSSL\nDescription: LibreSSL (OpenSSL-compatible)\nVersion: 4.3.2\nRequires: libssl libcrypto\n' \
		> $(SYSROOT)/usr/lib/pkgconfig/openssl.pc
	printf 'Name: LibreSSL\nVersion: 4.3.2\nLibs: -lssl -lcrypto\nCflags:\n' \
		> $(SYSROOT)/usr/lib/pkgconfig/libssl.pc
	printf 'Name: LibreSSL crypto\nVersion: 4.3.2\nLibs: -lcrypto\nCflags:\n' \
		> $(SYSROOT)/usr/lib/pkgconfig/libcrypto.pc

iputils: musl headers
	@test -d $(IPUTILS_DIR) || { \
		echo "$(IPUTILS_DIR) missing: add the submodule first"; exit 1; }
	@if [ ! -f $(IPUTILS_DIR)/build/build.ninja ]; then \
		cd $(IPUTILS_DIR) && CC='$(CC)' LDFLAGS='-static' \
		meson setup build --prefix=/usr -DUSE_CAP=false -DUSE_IDN=false \
		-DUSE_GETTEXT=false -DBUILD_MANS=false > /dev/null; fi
	ninja -C $(IPUTILS_DIR)/build >/dev/null
	mkdir -p $(ROOTFS)/bin
	install -m755 $(IPUTILS_DIR)/build/ping/ping $(ROOTFS)/bin/ping
	install -m755 $(IPUTILS_DIR)/build/arping $(IPUTILS_DIR)/build/tracepath \
		$(ROOTFS)/bin/
	ln -sf ping $(ROOTFS)/bin/ping6
	ln -sf tracepath $(ROOTFS)/bin/tracepath6

nettools: musl headers
	@test -d $(NET_TOOLS_DIR) || { \
		echo "$(NET_TOOLS_DIR) missing: add the submodule first"; exit 1; }
	@awk 'BEGIN{split("n y y y n n n n n n n n n n y n n n n n n n n n n n n n n n n n n n n n y n n n n n n n",a," ");for(i=1;i<=44;i++)print a[i]}' | \
		(cd $(NET_TOOLS_DIR) && bash ./configure.sh config.in) >/dev/null
	$(MAKE) -C $(NET_TOOLS_DIR) CC='$(CC)' COPTS='-Os' LDFLAGS='-Llib -static -s'
	mkdir -p $(ROOTFS)/bin
	install -m755 $(NET_TOOLS_DIR)/ifconfig $(NET_TOOLS_DIR)/route \
		$(NET_TOOLS_DIR)/netstat $(NET_TOOLS_DIR)/arp \
		$(NET_TOOLS_DIR)/nameif $(ROOTFS)/bin/

rdate: musl
	@test -d $(OPENRDATE_DIR) || { \
		echo "$(OPENRDATE_DIR) missing: add the submodule first"; exit 1; }
	cd $(OPENRDATE_DIR) && ./autogen.sh >/dev/null 2>&1 || true
	cd $(OPENRDATE_DIR) && CC='$(CC)' CFLAGS='-Os -D_GNU_SOURCE' \
		CPPFLAGS='-I$(ROOT)/patches/openrdate-musl' ./configure \
		--prefix=/usr LDFLAGS='-static -s'
	$(MAKE) -C $(OPENRDATE_DIR)/src CFLAGS='-Os -D_GNU_SOURCE' \
		rdate_LDADD=librdate.a
	mkdir -p $(ROOTFS)/bin
	install -m755 $(OPENRDATE_DIR)/src/rdate $(ROOTFS)/bin/rdate

mandoc: musl zlib
	@test -d $(MANDOC_DIR) || { \
		echo "$(MANDOC_DIR) missing: add the submodule first"; exit 1; }
	printf '%s\n' \
		'CC="$(CC)"' \
		'AR="llvm-ar"' \
		'CFLAGS="-Os"' \
		'LDFLAGS="-static -s"' \
		'PREFIX="/usr"' \
		'HAVE_WCHAR=1' \
		'LN="ln -sf"' \
		'BINM_PAGER="/usr/plan9/bin/p"' \
		'MANPATH_DEFAULT="/usr/share/man"' \
		> $(MANDOC_DIR)/configure.local
	cd $(MANDOC_DIR) && ./configure
	$(MAKE) -C $(MANDOC_DIR) -j$$(nproc)
	mkdir -p $(ROOTFS)/bin $(ROOTFS)/etc
	install -m755 $(MANDOC_DIR)/mandoc $(MANDOC_DIR)/demandoc \
		$(MANDOC_DIR)/soelim $(ROOTFS)/bin/
	ln -sf mandoc $(ROOTFS)/bin/man
	ln -sf mandoc $(ROOTFS)/bin/apropos
	ln -sf mandoc $(ROOTFS)/bin/whatis
	ln -sf mandoc $(ROOTFS)/bin/makewhatis

wget: musl zlib libressl
	@test -d $(WGET_DIR) || { \
		echo "$(WGET_DIR) missing: add the submodule first"; exit 1; }
	cd $(WGET_DIR) && PKG_CONFIG_PATH=$(SYSROOT)/usr/lib/pkgconfig \
		CC='$(CC)' ./configure --host=x86_64-linux-musl --prefix=/usr \
		--sysconfdir=/etc \
		--with-ssl=openssl --disable-nls --without-libpsl --disable-iri \
		--disable-pcre2 --disable-pcre LDFLAGS='-static -s'
	$(MAKE) -C $(WGET_DIR) -j$$(nproc)
	mkdir -p $(ROOTFS)/bin
	install -m755 $(WGET_DIR)/src/wget $(ROOTFS)/bin/wget

userland: musl headers bearssl curses sdhcp e2fsprogs dropbear wpasupplicant sfdisk mkfsfat smdev nldev svc sup curl libressl iputils nettools rdate mandoc wget
	$(MAKE) -C $(INIT_DIRS) CC='$(CC)'
	$(MAKE) -C $(INIT_DIRS) install DESTDIR=$(ROOTFS) PREFIX=/
	mv -f $(ROOTFS)/bin/sinit $(ROOTFS)/bin/init
	@for d in userland/sbase userland/ubase; do \
		$(MAKE) -C $$d CC='$(CC)' LDLIBS= LDFLAGS='-s -static' || exit; \
		$(MAKE) -C $$d install DESTDIR=$(ROOTFS) PREFIX=/ || exit; \
	done
	$(MAKE) -C userland/9base CC='$(CC)' PREFIX=/usr/plan9
	$(MAKE) -C userland/9base install DESTDIR=$(ROOTFS) PREFIX=/usr/plan9
	cd $(SHELL_DIR) && PATH=/usr/bin:/bin autoreconf -fi >/dev/null 2>&1
	cd $(SHELL_DIR) && CC='$(CC)' LDFLAGS='-s -static' ./configure \
		--prefix=/ --sysconfdir=/etc \
		--build=x86_64-alpine-linux-musl --host=x86_64-linux-musl
	$(MAKE) -C $(SHELL_DIR) LDFLAGS='-s -static'
	$(MAKE) -C $(SHELL_DIR) install DESTDIR=$(ROOTFS)
	$(MAKE) -C $(VI_DIR) clean
	$(MAKE) -C $(VI_DIR) CC='$(CC)' CFLAGS='-Wall -O2 -Wno-format-truncation' LDFLAGS='-s -static'
	install -m755 $(VI_DIR)/vi $(ROOTFS)/bin/vi
	$(CC) -O2 -I$(SYSROOT)/usr/include -s -static -o $(ZLIB_DIR)/minigzip \
		$(ZLIB_DIR)/test/minigzip.c -L$(SYSROOT)/usr/lib -lz
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
	printf 'ca_certificate = /etc/ssl/cert.pem\n' > $(ROOTFS)/etc/wgetrc
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
	mkdir -p $(ROOTFS)/bin/svc.d/run
	cp -a etc/svc.d/avail etc/svc.d/default $(ROOTFS)/bin/svc.d/
	ln -sf ../avail/dropbear $(ROOTFS)/bin/svc.d/run/dropbear
	ln -sf dash $(ROOTFS)/bin/sh
	ln -sf /bin/init $(ROOTFS)/sbin/init
	ln -sf /bin/init $(ROOTFS)/init
	mkdir -p $(ROOTFS)/usr/share/man/man1 \
		$(ROOTFS)/usr/share/man/man5 $(ROOTFS)/usr/share/man/man8
	@for d in userland/sbase userland/ubase; do \
		for p in $$d/*.1; do [ -e $$p ] && install -m644 $$p \
			$(ROOTFS)/usr/share/man/man1/ || exit; done; \
		for p in $$d/*.8; do [ -e $$p ] || continue; \
			install -m644 $$p $(ROOTFS)/usr/share/man/man8/ || exit; done; done
	install -m644 userland/9base/p/p.1 $(ROOTFS)/usr/share/man/man1/
	install -m644 $(MANDOC_DIR)/mandoc.1 $(MANDOC_DIR)/demandoc.1 \
		$(MANDOC_DIR)/soelim.1 $(MANDOC_DIR)/man.1 \
		$(MANDOC_DIR)/apropos.1 $(ROOTFS)/usr/share/man/man1/
	install -m644 $(MANDOC_DIR)/man.conf.5 \
		$(ROOTFS)/usr/share/man/man5/
	install -m644 $(MANDOC_DIR)/makewhatis.8 $(ROOTFS)/usr/share/man/man8/
	install -m644 userland/wget/doc/wget.1 $(ROOTFS)/usr/share/man/man1/
	install -m644 userland/openrdate/docs/rdate.8 \
		$(NET_TOOLS_DIR)/man/en_US/ifconfig.8 \
		$(NET_TOOLS_DIR)/man/en_US/route.8 \
		$(NET_TOOLS_DIR)/man/en_US/netstat.8 \
		$(NET_TOOLS_DIR)/man/en_US/arp.8 \
		$(NET_TOOLS_DIR)/man/en_US/nameif.8 \
		$(ROOTFS)/usr/share/man/man8/
	$(ROOTFS)/bin/makewhatis $(ROOTFS)/usr/share/man >/dev/null
	printf '#!/bin/sh\nPATH=$$PATH:/usr/plan9/bin\nexport PATH\n' \
		> $(ROOTFS)/etc/profile

initramfs: rootfs
	find $(ROOTFS) -print0 | xargs -0 touch -h -d @$(SOURCE_DATE_EPOCH)
	fakeroot -- sh -c 'chown -R 0:0 $(ROOTFS) && \
		cd $(ROOTFS) && find . -print0 | LC_ALL=C sort -z | \
		cpio --null -o -H newc --quiet --reproducible' | gzip -9n > $(INITRAMFS)

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
	@printf '%s\n' \
'timeout: 5' \
'' \
'/slinux (live)' \
'    protocol: linux' \
'    path: boot():/vmlinuz' \
'    cmdline: pnpacpi=off i8042.nopnp i8042.nomux=1 console=ttyS0 console=tty0' \
'    module_path: boot():/initramfs.cpio.gz' \
		> out/iso/limine.conf

kernel:
	cp kernel/config kernel/linux/.config
	$(MAKE) -C kernel/linux olddefconfig all

clean:
	-@for d in $(INIT_DIRS) $(USER_DIRS) $(SHELL_DIR) $(VI_DIR) libc/musl \
		$(BEARSSL_DIR) $(CURSES_DIR); do \
		[ -d $$d ] && $(MAKE) -C $$d clean; done
	-@for d in $(LIBRESSL_DIR) $(NET_TOOLS_DIR) $(OPENRDATE_DIR); do \
		[ -d $$d ] && $(MAKE) -C $$d distclean 2>/dev/null; done
	-[ -d $(MANDOC_DIR) ] && { $(MAKE) -C $(MANDOC_DIR) clean 2>/dev/null; \
		rm -f $(MANDOC_DIR)/config.h $(MANDOC_DIR)/config.log \
			$(MANDOC_DIR)/config.h.old $(MANDOC_DIR)/config.log.old \
			$(MANDOC_DIR)/configure.local $(MANDOC_DIR)/Makefile.local; }
	-[ -d $(WGET_DIR) ] && { $(MAKE) -C $(WGET_DIR) clean 2>/dev/null; \
		rm -f $(WGET_DIR)/config.h $(WGET_DIR)/config.log \
			$(WGET_DIR)/config.status $(WGET_DIR)/Makefile \
			$(WGET_DIR)/*/Makefile $(WGET_DIR)/po/POTFILES \
			$(WGET_DIR)/po/stamp-po; }
	-rm -rf $(IPUTILS_DIR)/build
	rm -f $(ZLIB_DIR)/*.o $(ZLIB_DIR)/libz.a $(ZLIB_DIR)/minigzip
	rm -rf out rootfs slinux.cpio.gz
