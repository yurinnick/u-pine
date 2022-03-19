PROJECT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
BUILD_DIR=$(PROJECT_DIR)/build
OUTPUT_DIR=$(PROJECT_DIR)/output
TMP_DIR=$(PROJECT_DIR)/tmp

KBUILD_OUTPUT=$(BUILD_DIR)/linux-arm64

LINUX_CHECKOUT_DIR=$(TMP_DIR)/linux
ATF_CHECKOUT_DIR=$(TMP_DIR)/build_atm

CCACHE_EXISTS := $(shell ccache -V)
ifdef CCACHE_EXISTS
    CC := ccache $(CC)
    CXX := ccache $(CXX)
endif

GCC_CROSS_FLAGS = ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
GCC_KERNEL_BUILD_FLAGS= INSTALL_MOD_PATH=$(OUTPUT_DIR) KBUILD_OUTPUT=$(KBUILD_OUTPUT)
GCC_THREATS_NUM=$(shell grep -c ^processor /proc/cpuinfo)

MAKE_CMD=make -C $(LINUX_CHECKOUT_DIR) $(GCC_CROSS_FLAGS) -j$(GCC_THREATS_NUM)

GO_FLAGS=GOARCH=arm64 GO111MODULE=off

build_atm:
	[ -d "$(ATF_CHECKOUT_DIR)" ] || git clone --depth 1 https://github.com/ARM-software/arm-trusted-firmware $(ATF_CHECKOUT_DIR)
	make -C $(ATF_CHECKOUT_DIR) PLAT=sun50i_a64 DEBUG=1 bl31
	cp $(ATF_CHECKOUT_DIR)/build/sun50i_a64/debug/bl31.bin $(OUTPUT_DIR)

Image board-1.2.dtb modules:
	mkdir -p $(TMP_DIR)
	mkdir -p $(BUILD_DIR)
	mkdir -p $(KBUILD_OUTPUT)

	[ -d "$(LINUX_CHECKOUT_DIR)" ] || git clone --depth 1 https://github.com/megous/linux $(LINUX_CHECKOUT_DIR)
	cp configs/pinephone_uroot_defconfig $(LINUX_CHECKOUT_DIR)/arch/arm64/configs/pinephone_uroot_defconfig

	$(MAKE_CMD) pinephone_uroot_defconfig O=$(KBUILD_OUTPUT)
	$(MAKE_CMD) clean
	$(MAKE_CMD) $(GCC_KERNEL_BUILD_FLAGS) Image dtbs modules
	$(MAKE_CMD) $(GCC_KERNEL_BUILD_FLAGS) modules_install

	cp -f $(KBUILD_OUTPUT)/arch/arm64/boot/Image $(OUTPUT_DIR)/Image
	cp -f $(KBUILD_OUTPUT)/.config $(OUTPUT_DIR)/linux.config
	cp -f $(KBUILD_OUTPUT)/arch/arm64/boot/dts/allwinner/sun50i-a64-pinephone-1.2.dtb $(OUTPUT_DIR)/board-1.2.dtb

initramfs-uroot.cpio: modules
	GO111MODULE=off go get github.com/u-root/u-root
	$(GO_FLAGS) u-root \
		-files $(OUTPUT_DIR)/lib/modules:/lib/modules \
		core \
		boot \
		github.com/u-root/u-root/cmds/exp/modprobe

	cp /tmp/initramfs.linux_arm64.cpio $(OUTPUT_DIR)/initramfs-uroot.cpio

u-boot-sunxi-with-spl-pinephone.bin:
	wget "https://gitlab.com/pine64-org/u-boot/-/jobs/artifacts/master/raw/$@?job=build" -O $(OUTPUT_DIR)/$@

pinephone-uroot-base.img: Image board-1.2.dtb initramfs-uroot.cpio u-boot-sunxi-with-spl-pinephone.bin configs/extlinux.conf
	@echo "MKFS  $(OUTPUT_DIR)/$@"
	@rm -f $(OUTPUT_DIR)/$@
	@truncate --size 80M $(OUTPUT_DIR)/$@
	@mkfs.fat -F32 $(OUTPUT_DIR)/$@

	@mcopy -i $(OUTPUT_DIR)/$@ $(OUTPUT_DIR)/Image ::Image
	@mcopy -i $(OUTPUT_DIR)/$@ $(OUTPUT_DIR)/board-1.2.dtb ::board-1.2.dtb
	@mcopy -i $(OUTPUT_DIR)/$@ $(OUTPUT_DIR)/initramfs-uroot.cpio ::initramfs-uroot.cpio
	@mcopy -i $(OUTPUT_DIR)/$@ $(OUTPUT_DIR)/u-boot-sunxi-with-spl-pinephone.bin ::u-boot-sunxi-with-spl-pinephone.bin
	@mmd -i $(OUTPUT_DIR)/$@ ::extlinux
	@mcopy -i $(OUTPUT_DIR)/$@ configs/extlinux.conf ::extlinux/extlinux.conf

pinephone-uroot.img: pinephone-uroot-base.img
	rm -f $(OUTPUT_DIR)/$@
	truncate --size 80M $(OUTPUT_DIR)/$@
	parted -s $(OUTPUT_DIR)/$@ mktable msdos
	parted -s $(OUTPUT_DIR)/$@ mkpart primary fat32 2048s 100%
	parted -s $(OUTPUT_DIR)/$@ set 1 boot on
	dd if=$(OUTPUT_DIR)/u-boot-sunxi-with-spl-pinephone.bin of=$(OUTPUT_DIR)/$@ bs=8k seek=1
	dd if=$(OUTPUT_DIR)/pinephone-uroot-base.img of=$(OUTPUT_DIR)/$@ seek=1024 bs=1k

clean:
	rm -rf $(TMP_DIR)
	rm -rf $(BUILD_DIR)
	rm -rf $(OUTPUT_DIR)
