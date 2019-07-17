ISA ?= rv64imafdc
ABI ?= lp64d

srcdir := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
srcdir := $(srcdir:/=)
confdir := $(srcdir)/conf
wrkdir := $(CURDIR)/work

buildroot_srcdir := $(srcdir)/buildroot
buildroot_initramfs_wrkdir := $(wrkdir)/buildroot_initramfs

# TODO: make RISCV be able to be set to alternate toolchain path
RISCV ?= $(buildroot_initramfs_wrkdir)/host
RVPATH := $(RISCV)/bin:$(PATH)
GITID := $(shell git describe --dirty --always)

# The second option is the more standard version, however in
# the interest of reproducibility, use the buildroot version that
# we compile so as to minimize unepected surprises. 
target := riscv64-sifive-linux-gnu
#target := riscv64-linux-gnu

CROSS_COMPILE := $(RISCV)/bin/$(target)-

tftp := /var/lib/tftpboot
test_export := $(wrkdir)/hifive-test-$(GITID)
test_export_tar := $(wrkdir)/hifive-test-$(GITID).tar.gz

buildroot_initramfs_tar := $(buildroot_initramfs_wrkdir)/images/rootfs.tar
buildroot_initramfs_config := $(confdir)/buildroot_initramfs_config
buildroot_initramfs_sysroot_stamp := $(wrkdir)/.buildroot_initramfs_sysroot
buildroot_initramfs_sysroot := $(wrkdir)/buildroot_initramfs_sysroot
buildroot_ltp_ramfs_tar := $(buildroot_ltp_ramfs_wrkdir)/images/rootfs.tar
buildroot_ltp_ramfs_config := $(confdir)/buildroot_ltp_ramfs_config
buildroot_ltp_ramfs_sysroot_stamp := $(wrkdir)/.buildroot_ltp_ramfs_sysroot
buildroot_ltp_ramfs_sysroot := $(wrkdir)/buildroot_ltp_ramfs_sysroot

linux_srcdir := $(srcdir)/linux
linux_wrkdir := $(wrkdir)/linux
linux_defconfig := $(confdir)/linux_52_defconfig

vmlinux := $(linux_wrkdir)/vmlinux
vmlinux_stripped := $(linux_wrkdir)/vmlinux-stripped
vmlinux_bin := $(wrkdir)/vmlinux.bin
uImage := $(wrkdir)/uImage

flash_image := $(wrkdir)/hifive-unleashed-$(GITID).gpt
vfat_image := $(wrkdir)/hifive-unleashed-vfat.part
#ext_image := $(wrkdir)  # TODO

initramfs := $(wrkdir)/initramfs.cpio.gz
ltp_ramfs := $(wrkdir)/ltp_ramfs.cpio.gz

pk_srcdir := $(srcdir)/riscv-pk
pk_wrkdir := $(wrkdir)/riscv-pk
pk_payload_wrkdir := $(wrkdir)/riscv-payload-pk
bbl := $(pk_wrkdir)/bbl
bbl_payload :=$(pk_payload_wrkdir)/bbl
bbl_bin := $(wrkdir)/bbl.bin
fit := $(wrkdir)/image-$(GITID).fit
ltp_fit := $(wrkdir)/image-ltp-$(GITID).fit

fesvr_srcdir := $(srcdir)/riscv-fesvr
fesvr_wrkdir := $(wrkdir)/riscv-fesvr
libfesvr := $(fesvr_wrkdir)/prefix/lib/libfesvr.so

spike_srcdir := $(srcdir)/riscv-isa-sim
spike_wrkdir := $(wrkdir)/riscv-isa-sim
spike := $(spike_wrkdir)/prefix/bin/spike

qemu_srcdir := $(srcdir)/riscv-qemu
qemu_wrkdir := $(wrkdir)/riscv-qemu
qemu := $(qemu_wrkdir)/prefix/bin/qemu-system-riscv64

uboot_srcdir := $(srcdir)/u-boot-m
uboot_wrkdir := $(wrkdir)/u-boot-m
uboot := $(uboot_wrkdir)/u-boot.bin

uboot_s_srcdir := $(srcdir)/u-boot
uboot_s_wrkdir := $(wrkdir)/u-boot-smode
uboot_s := $(uboot_s_wrkdir)/u-boot.bin

opensbi_srcdir := $(srcdir)/opensbi
opensbi_wrkdir := $(wrkdir)/opensbi
opensbi := $(opensbi_wrkdir)/platform/sifive/fu540/firmware/fw_payload.bin

openocd_srcdir := $(srcdir)/riscv-openocd
openocd_wrkdir := $(wrkdir)/riscv-openocd
openocd := $(openocd_wrkdir)/src/openocd

rootfs := $(wrkdir)/rootfs.bin

target_gcc := $(CROSS_COMPILE)gcc
target_gdb := $(CROSS_COMPILE)gdb

.PHONY: all
all: $(fit) $(flash_image) $(test_export_tar)
	@echo
	@echo "GPT (for SPI flash or SDcard) and U-boot Image files have"
	@echo "been generated for an ISA of $(ISA) and an ABI of $(ABI)"
	@echo
	@echo $(fit)
	@echo $(flash_image)
	@echo
	@echo "To completely erase, reformat, and program a disk sdX, run:"
	@echo "  make DISK=/dev/sdX format-boot-loader"
	@echo "  ... you will need gdisk and e2fsprogs installed"
	@echo "  Please note this will not currently format the SDcard ext4 partition"
	@echo "  This can be done manually if needed"
	@echo

# TODO: depracated for now
#ifneq ($(RISCV),$(buildroot_initramfs_wrkdir)/host)
#$(target_gcc):
#	$(error The RISCV environment variable was set, but is not pointing at a toolchain install tree)
#else
#$(target_gcc): $(buildroot_initramfs_tar)
#endif

$(buildroot_initramfs_wrkdir)/.config: $(buildroot_srcdir)
	rm -rf $(dir $@)
	mkdir -p $(dir $@)
	cp $(buildroot_initramfs_config) $@
	$(MAKE) -C $< RISCV=$(RISCV) O=$(buildroot_initramfs_wrkdir) olddefconfig 

# buildroot_initramfs provides gcc
$(buildroot_initramfs_tar): $(buildroot_srcdir) $(buildroot_initramfs_wrkdir)/.config $(buildroot_initramfs_config)
	$(MAKE) -C $< RISCV=$(RISCV) O=$(buildroot_initramfs_wrkdir)

.PHONY: buildroot_initramfs-menuconfig
buildroot_initramfs-menuconfig: $(buildroot_initramfs_wrkdir)/.config $(buildroot_srcdir)
	$(MAKE) -C $(dir $<) O=$(buildroot_initramfs_wrkdir) menuconfig
	$(MAKE) -C $(dir $<) O=$(buildroot_initramfs_wrkdir) savedefconfig
	cp $(dir $<)/defconfig conf/buildroot_initramfs_config

# use buildroot_initramfs toolchain
# TODO: fix path and conf/buildroot_ltp_config
$(buildroot_ltp_ramfs_wrkdir)/.config: $(buildroot_srcdir) $(target_gcc)
	rm -rf $(dir $@)
	mkdir -p $(dir $@)
	cp $(buildroot_ltp_config) $@
	$(MAKE) -C $< RISCV=$(RISCV) PATH=$(RVPATH) O=$(buildroot_ltp_ramfs_wrkdir) olddefconfig

$(buildroot_ltp_ramfs_tar): $(buildroot_srcdir) $(buildroot_ltp_ramfs_wrkdir)/.config $(target_gcc) $(buildroot_ltp_ramfs_config)
	$(MAKE) -C $< RISCV=$(RISCV) PATH=$(RVPATH) O=$(buildroot_ltp_wrkdir)

.PHONY: buildroot_ltp-menuconfig
buildroot_ltp_ramfs-menuconfig: $(buildroot_ltp_ramfs_wrkdir)/.config $(buildroot_srcdir)
	$(MAKE) -C $(dir $<) O=$(buildroot_ltp_ramfs_wrkdir) menuconfig
	$(MAKE) -C $(dir $<) O=$(buildroot_ltp_ramfs_wrkdir) savedefconfig
	cp $(dir $<)/defconfig conf/buildroot_ltp_ramfs_config

$(buildroot_initramfs_sysroot_stamp): $(buildroot_initramfs_tar)
	mkdir -p $(buildroot_initramfs_sysroot)
	tar -xpf $< -C $(buildroot_initramfs_sysroot) --exclude ./dev --exclude ./usr/share/locale
	touch $@

$(buildroot_ltp_ramfs_sysroot_stamp): $(buildroot_ltp_ramfs_tar)
	mkdir -p $(buildroot_ltp_ramfs_sysroot)
	tar -xpf $< -C $(buildroot_ltp_ramfs_sysroot) --exclude ./dev --exclude ./usr/share/locale
	touch $@


$(linux_wrkdir)/.config: $(linux_defconfig) $(linux_srcdir)
	mkdir -p $(dir $@)
	cp -p $< $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv olddefconfig
ifeq (,$(filter rv%c,$(ISA)))
	sed 's/^.*CONFIG_RISCV_ISA_C.*$$/CONFIG_RISCV_ISA_C=n/' -i $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv olddefconfig
endif
ifeq ($(ISA),$(filter rv32%,$(ISA)))
	sed 's/^.*CONFIG_ARCH_RV32I.*$$/CONFIG_ARCH_RV32I=y/' -i $@
	sed 's/^.*CONFIG_ARCH_RV64I.*$$/CONFIG_ARCH_RV64I=n/' -i $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv olddefconfig
endif

$(vmlinux): $(linux_srcdir) $(linux_wrkdir)/.config $(target_gcc)
	$(MAKE) -C $< O=$(linux_wrkdir) \
		ARCH=riscv \
		CROSS_COMPILE=$(CROSS_COMPILE) \
		PATH=$(RVPATH) \
		vmlinux

.PHONY: initrd
initrd: $(initramfs)

$(initramfs).d: $(buildroot_initramfs_sysroot)
	$(linux_srcdir)/usr/gen_initramfs_list.sh -l $(confdir)/initramfs.txt $(buildroot_initramfs_sysroot) > $@

$(initramfs): $(buildroot_initramfs_sysroot) $(vmlinux)
	cd $(linux_wrkdir) && \
		$(linux_srcdir)/usr/gen_initramfs_list.sh \
		-o $@ -u $(shell id -u) -g $(shell id -g) \
		$(confdir)/initramfs.txt \
		$(buildroot_initramfs_sysroot) 

$(ltp_ramfs): $(buildroot_ltp_ramfs_sysroot) $(vmlinux)
	cd $(linux_wrkdir) && \
		$(linux_srcdir)/usr/gen_initramfs_list.sh \
		-o $@ -u $(shell id -u) -g $(shell id -g) \
		$(confdir)/initramfs.txt \
		$(buildroot_ltp_ramfs_sysroot) 

$(vmlinux_stripped): $(vmlinux)
	PATH=$(RVPATH) $(target)-strip -o $@ $<

$(vmlinux_bin): $(vmlinux)
	PATH=$(RVPATH) $(target)-objcopy -O binary $< $@

$(uImage): $(vmlinux_bin)
	$(uboot_wrkdir)/tools/mkimage -A riscv -O linux -T kernel -C "none" -a 80200000 -e 80200000 -d $< $@

.PHONY: linux-menuconfig
linux-menuconfig: $(linux_wrkdir)/.config
	$(MAKE) -C $(linux_srcdir) O=$(dir $<) ARCH=riscv menuconfig
	$(MAKE) -C $(linux_srcdir) O=$(dir $<) ARCH=riscv savedefconfig
	cp $(dir $<)/defconfig conf/linux_defconfig

$(bbl): $(pk_srcdir)
	rm -rf $(pk_wrkdir)
	mkdir -p $(pk_wrkdir)
	cd $(pk_wrkdir) && PATH=$(RVPATH) $</configure \
		--host=$(target) \
		--enable-logo \
		--with-logo=$(abspath conf/sifive_logo.txt)
	CFLAGS="-mabi=$(ABI) -march=$(ISA)" $(MAKE) PATH=$(RVPATH) -C $(pk_wrkdir)

# Workaround for SPIKE until it can support loading bbl and
# kernel as separate images like qemu and uboot. Unfortuately
# at this point this means no easy way to have an initrd for spike
$(bbl_payload): $(pk_srcdir) $(vmlinux_stripped) 
	rm -rf $(pk_payload_wrkdir)
	mkdir -p $(pk_payload_wrkdir)
	cd $(pk_payload_wrkdir) && PATH=$(RVPATH) $</configure \
		--host=$(target) \
		--enable-logo \
		--with-payload=$(vmlinux_stripped) \
		--with-logo=$(abspath conf/sifive_logo.txt)
	CFLAGS="-mabi=$(ABI) -march=$(ISA)" $(MAKE) PATH=$(RVPATH) -C $(pk_payload_wrkdir)


$(bbl_bin): $(bbl)
	PATH=$(RVPATH) $(target)-objcopy -S -O binary --change-addresses -0x80000000 $< $@

$(fit): $(bbl_bin) $(vmlinux_bin) $(uboot) $(initramfs) $(confdir)/uboot-fit-image.its
	$(uboot_wrkdir)/tools/mkimage -f $(confdir)/uboot-fit-image.its -A riscv -O linux -T flat_dt $@

$(ltp_fit): $(bbl_bin) $(vmlinux_bin) $(uboot) $(ltp_ramfs) $(confdir)/uboot-fit-image.its
	$(uboot_wrkdir)/tools/mkimage -f $(confdir)/uboot-fit-image.its -A riscv -O linux -T flat_dt $@

$(libfesvr): $(fesvr_srcdir)
	rm -rf $(fesvr_wrkdir)
	mkdir -p $(fesvr_wrkdir)
	mkdir -p $(dir $@)
	cd $(fesvr_wrkdir) && $</configure \
		--prefix=$(dir $(abspath $(dir $@)))
	$(MAKE) -C $(fesvr_wrkdir)
	$(MAKE) -C $(fesvr_wrkdir) install
	touch -c $@

$(spike): $(spike_srcdir) $(libfesvr)
	rm -rf $(spike_wrkdir)
	mkdir -p $(spike_wrkdir)
	mkdir -p $(dir $@)
	cd $(spike_wrkdir) && PATH=$(RVPATH) $</configure \
		--prefix=$(dir $(abspath $(dir $@))) \
		--with-fesvr=$(dir $(abspath $(dir $(libfesvr))))
	$(MAKE) PATH=$(RVPATH) -C $(spike_wrkdir)
	$(MAKE) -C $(spike_wrkdir) install
	touch -c $@

$(qemu): $(qemu_srcdir)
	rm -rf $(qemu_wrkdir)
	mkdir -p $(qemu_wrkdir)
	mkdir -p $(dir $@)
	which pkg-config
	# pkg-config from buildroot blows up qemu configure 
	cd $(qemu_wrkdir) && $</configure \
		--prefix=$(dir $(abspath $(dir $@))) \
		--target-list=riscv64-softmmu
	$(MAKE) -C $(qemu_wrkdir)
	$(MAKE) -C $(qemu_wrkdir) install
	touch -c $@

$(uboot): $(uboot_srcdir) $(target_gcc)
	rm -rf $(uboot_wrkdir)
	mkdir -p $(uboot_wrkdir)
	mkdir -p $(dir $@)
	cp $(confdir)/uboot-fsbl-citest_defconfig $(uboot_wrkdir)/.config
	$(MAKE) -C $(uboot_srcdir) O=$(uboot_wrkdir) olddefconfig
	#$(MAKE) -C $(uboot_srcdir) O=$(uboot_wrkdir) sifive_fu540_fsbl_defconfig
	#echo 'CONFIG_BOOTCOMMAND="dhcp; env import -t \${fileaddr} \${filesize}; run boot2"' >> $(uboot_wrkdir)/.config
	$(MAKE) -C $(uboot_srcdir) O=$(uboot_wrkdir) CROSS_COMPILE=$(CROSS_COMPILE)

$(openocd): $(openocd_srcdir)
	rm -rf $(openocd_wrkdir)
	mkdir -p $(openocd_wrkdir)
	mkdir -p $(dir $@)
	cd $(openocd_srcdir) && ./bootstrap
	cd $(openocd_wrkdir) && $</configure
	$(MAKE) -C $(openocd_wrkdir)

$(uboot_s): $(uboot_s_srcdir) $(target_gcc)
	rm -rf $(uboot_s_wrkdir)
	mkdir -p $(uboot_s_wrkdir)
	mkdir -p $(dir $@)
	cp $(confdir)/uboot-smode-citest_defconfig $(uboot_s_wrkdir)/.config
	$(MAKE) -C $(uboot_s_srcdir) O=$(uboot_s_wrkdir) olddefconfig
	$(MAKE) -C $(uboot_s_srcdir) O=$(uboot_s_wrkdir) CROSS_COMPILE=$(CROSS_COMPILE)

$(opensbi): $(uboot_s) $(target_gcc)
	rm -rf $(opensbi_wrkdir)
	mkdir -p $(opensbi_wrkdir)
	mkdir -p $(dir $@)
	$(MAKE) -C $(opensbi_srcdir) O=$(opensbi_wrkdir) CROSS_COMPILE=$(CROSS_COMPILE) \
		PLATFORM=sifive/fu540 FW_PAYLOAD_PATH=$(uboot_s)

$(ltp): $(buildroot_ltp_ext)
	cp $< $@

$(buildroot_initramfs_sysroot): $(buildroot_initramfs_sysroot_stamp)

.PHONY: buildroot_initramfs_sysroot vmlinux bbl fit
buildroot_initramfs_sysroot: $(buildroot_initramfs_sysroot)
vmlinux: $(vmlinux)
bbl: $(bbl)
fit: $(fit)

.PHONY: openocd
openocd: $(openocd)
	$(openocd) -f $(confdir)/u540-openocd.cfg


terminfo := $(buildroot_initramfs_wrkdir)/host/share/terminfo

$(terminfo): $(target_gdb)
	mkdir -p $(terminfo)
	# hack for problems with https://git.buildroot.org/buildroot/commit/?id=b35ad5d0b45e5288f4019aeaa06b87ef0f2ef016
	$(buildroot_initramfs_wrkdir)/host/bin/tic \
		$(buildroot_initramfs_wrkdir)/build/ncurses-6.1/misc/terminfo.src \
		-o $(terminfo)

.PHONY: gdb gdb-u-boot
gdb: $(target_gdb) $(terminfo)

gdb-u-boot: $(target_gdb) $(terminfo)
	$(target_gdb) -ex "set remotetimeout 240" -ex "target extended-remote localhost:3333" u-boot/u-boot

.PHONY: clean
clean:
	rm -rf -- $(wrkdir) $(toolchain_dest)

.PHONY: sim
sim: $(spike) $(bbl_payload)
	$(spike) --isa=$(ISA) -p4 $(bbl_payload)

.PHONY: qemu
qemu: $(qemu) $(bbl) $(vmlinux) $(initramfs)
	$(qemu) -nographic -machine virt -bios $(bbl) -kernel $(vmlinux) -initrd $(initramfs) \
		-netdev user,id=net0 -device virtio-net-device,netdev=net0

.PHONY: qemu-ltp
qemu-ltp: $(qemu) $(bbl) $(vmlinux) $(initramfs) $(rootfs)
	$(qemu) -nographic -machine virt -bios $(bbl) -kernel $(vmlinux) -initrd $(initramfs) \
		-drive file=$(rootfs),format=raw,id=hd0 -device virtio-blk-device,drive=hd0 \
		-netdev user,id=net0 -device virtio-net-device,netdev=net0


.PHONY: uboot
uboot: $(uboot) $(uboot_s)


.PHONY: test
test: $(test_export)
	# this does way more than it needs to right now
	cp -v $(test_export)/uEnv-net.txt $(tftp)/uEnv.txt
	cp -v $(test_export)/hifiveu.fit $(tftp)/
	test/jtag-boot.sh $(test_export)/u-boot.bin

.PHONY: test_s
test_s: $(test_export)
	# this does way more than it needs to right now
	cp -v $(test_export)/uEnv-osbi.txt $(tftp)/uEnv.txt
	cp -v $(test_export)/uEnv-smode.txt $(tftp)/
	cp -v $(test_export)/uImage $(tftp)/
	cp -v $(test_export)/fw_payload.bin $(tftp)/
	test/jtag-boot.sh $(test_export)/u-boot.bin

.PHONY: test_export
test_export: $(test_export_tar)

$(test_export): $(fit) $(uboot) $(uboot_s) $(opensbi) $(uImage) $(initramfs)
	rm -rf $(test_export)
	mkdir $(test_export)
	cp -v $(confdir)/uEnv-net.txt $(test_export)/
	cp -v $(fit) $(test_export)/hifiveu.fit
	cp -v $(confdir)/uEnv-osbi.txt $(test_export)/
	cp -v $(confdir)/uEnv-smode.txt $(test_export)/
	cp -v $(uImage) $(test_export)/
	cp -v $(uboot) $(test_export)/
	cp -v $(opensbi) $(test_export)/

$(test_export_tar): $(test_export)
	tar zcvf $(test_export_tar) -C $(wrkdir) `basename $(test_export)`

# Relevant partition type codes
BBL		= 2E54B353-1271-4842-806F-E436D6AF6985
VFAT            = EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
LINUX		= 0FC63DAF-8483-4772-8E79-3D69D8477DE4
#FSBL		= 5B193300-FC78-40CD-8002-E86C45580B47
UBOOT		= 5B193300-FC78-40CD-8002-E86C45580B47
UBOOTENV	= a09354ac-cd63-11e8-9aff-70b3d592f0fa
UBOOTDTB	= 070dd1a8-cd64-11e8-aa3d-70b3d592f0fa
UBOOTFIT	= 04ffcafa-cd65-11e8-b974-70b3d592f0fa

flash.gpt: $(flash_image)

VFAT_START=2048
VFAT_END=65502
VFAT_SIZE=63454
UBOOT_START=1024
UBOOT_END=2047
UBOOT_SIZE=1023
UENV_START=900
UENV_END=1000

$(vfat_image): $(fit) $(confdir)/uEnv.txt
	@if [ `du --apparent-size --block-size=512 $(uboot) | cut -f 1` -ge $(UBOOT_SIZE) ]; then \
		echo "Uboot is too large for partition!!\nReduce uboot or increase partition size"; \
		rm $(flash_image); exit 1; fi
	dd if=/dev/zero of=$(vfat_image) bs=512 count=$(VFAT_SIZE)
	/sbin/mkfs.vfat $(vfat_image)
	PATH=$(RVPATH) MTOOLS_SKIP_CHECK=1 mcopy -i $(vfat_image) $(fit) ::hifiveu.fit
	PATH=$(RVPATH) MTOOLS_SKIP_CHECK=1 mcopy -i $(vfat_image) $(confdir)/uEnv.txt ::uEnv.txt

$(flash_image): $(uboot) $(fit) $(vfat_image)
	dd if=/dev/zero of=$(flash_image) bs=1M count=32
	/sbin/sgdisk --clear  \
		--new=1:$(VFAT_START):$(VFAT_END)  --change-name=1:"Vfat Boot"	--typecode=1:$(VFAT)   \
		--new=3:$(UBOOT_START):$(UBOOT_END)   --change-name=3:uboot	--typecode=3:$(UBOOT) \
		--new=4:$(UENV_START):$(UENV_END)   --change-name=4:uboot-env	--typecode=4:$(UBOOTENV) \
		$(flash_image)
	dd conv=notrunc if=$(vfat_image) of=$(flash_image) bs=512 seek=$(VFAT_START)
	dd conv=notrunc if=$(uboot) of=$(flash_image) bs=512 seek=$(UBOOT_START) count=$(UBOOT_SIZE)

DEMO_END=11718750

#$(demo_image): $(uboot) $(fit) $(vfat_image) $(ext_image)
#	dd if=/dev/zero of=$(flash_image) bs=512 count=$(DEMO_END)
#	/sbin/sgdisk --clear  \
#		--new=1:$(VFAT_START):$(VFAT_END)  --change-name=1:"Vfat Boot"	--typecode=1:$(VFAT)   \
#		--new=3:$(UBOOT_START):$(UBOOT_END)   --change-name=3:uboot	--typecode=3:$(UBOOT) \
#		--new=2:264192:$(DEMO_END) --change-name=2:root	--typecode=2:$(LINUX) \
#		--new=4:1024:1247   --change-name=4:uboot-env	--typecode=4:$(UBOOTENV) \
#		$(flash_image)
#	dd conv=notrunc if=$(vfat_image) of=$(flash_image) bs=512 seek=$(VFAT_START)
#	dd conv=notrunc if=$(uboot) of=$(flash_image) bs=512 seek=$(UBOOT_START) count=$(UBOOT_SIZE)

.PHONY: format-boot-loader
format-boot-loader: $(bbl_bin) $(uboot) $(fit) $(vfat_image)
	@test -b $(DISK) || (echo "$(DISK): is not a block device"; exit 1)
	/sbin/sgdisk --clear  \
		--new=1:$(VFAT_START):$(VFAT_END)  --change-name=1:"Vfat Boot"	--typecode=1:$(VFAT)   \
		--new=2:264192:$(DEMO_END) --change-name=2:root	--typecode=2:$(LINUX) \
		--new=3:$(UBOOT_START):$(UBOOT_END)   --change-name=3:uboot	--typecode=3:$(UBOOT) \
		--new=4:$(UENV_START):$(UENV_END)  --change-name=4:uboot-env	--typecode=4:$(UBOOTENV) \
		$(DISK)
	-/sbin/partprobe
	@sleep 1
ifeq ($(DISK)p1,$(wildcard $(DISK)p1))
	@$(eval PART1 := $(DISK)p1)
	@$(eval PART2 := $(DISK)p2)
	@$(eval PART3 := $(DISK)p3)
	@$(eval PART4 := $(DISK)p4)
else ifeq ($(DISK)s1,$(wildcard $(DISK)s1))
	@$(eval PART1 := $(DISK)s1)
	@$(eval PART2 := $(DISK)s2)
	@$(eval PART3 := $(DISK)s3)
	@$(eval PART4 := $(DISK)s4)
else ifeq ($(DISK)1,$(wildcard $(DISK)1))
	@$(eval PART1 := $(DISK)1)
	@$(eval PART2 := $(DISK)2)
	@$(eval PART3 := $(DISK)3)
	@$(eval PART4 := $(DISK)4)
else
	@echo Error: Could not find bootloader partition for $(DISK)
	@exit 1
endif
	dd if=$(uboot) of=$(PART3) bs=4096
	dd if=$(vfat_image) of=$(PART1) bs=4096

DEMO_IMAGE	:= sifive-debian-demo-mar7.tar.xz
DEMO_URL	:= https://github.com/tmagik/freedom-u-sdk/releases/download/hifiveu-2.0-alpha.1/

format-demo-image: format-boot-loader
	@echo "Done setting up basic initramfs boot. We will now try to install"
	@echo "a Debian snapshot to the Linux partition, which requires sudo"
	@echo "you can safely cancel here"
	/sbin/mke2fs -t ext4 $(PART2)
	-mkdir tmp-mnt
	-sudo mount $(PART2) tmp-mnt && cd tmp-mnt && \
		sudo wget $(DEMO_URL)$(DEMO_IMAGE) && \
		sudo tar -Jxvf $(DEMO_IMAGE)
	sudo umount tmp-mnt

-include $(initramfs).d
