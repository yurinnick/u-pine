GOFLAGS=GOARCH=arm64
PROJECT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
BUILD_DIR=$(PROJECT_DIR)/build
KBUILD_OUTPUT=$(BUILD_DIR)/linux-arm64
CROSS_FLAGS = ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- 
KERNEL_FLAGS= LOCALVERSION=-uroot INSTALL_MOD_PATH=$(BUILD_DIR)/modules KBUILD_OUTPUT=$(KBUILD_OUTPUT)

build_atm:
	git clone --depth 1 https://github.com/ARM-software/arm-trusted-firmware tmp/build_atm
	make -C tmp/arm-trusted-firmware PLAT=sun50i_a64 DEBUG=1 bl31
	cp tmp/arm-trusted-firmware/build/sun50i_a64/debug/bl31.bin $(OUTPUT_DIR)

Image board-1.2.dtb modules:
	rm -rf $(PROJECT_DIR)/tmp
	mkdir $(PROJECT_DIR)/tmp
	git clone --depth 1 https://github.com/megous/linux $(PROJECT_DIR)/tmp/linux
	cp pinephone_uroot_defconfig $(PROJECT_DIR)/tmp/linux/arch/arm64/configs/pinephone_uroot_defconfig

	rm -rf "$(KBUILD_OUTPUT)"
	mkdir -p "$(KBUILD_OUTPUT)" "$(BUILD_DIR)/modules"

	make -C $(PROJECT_DIR)/tmp/linux $(CROSS_FLAGS) pinephone_uroot_defconfig
	make -C $(PROJECT_DIR)/tmp/linux $(CROSS_FLAGS) -j8 clean
	make -C $(PROJECT_DIR)/tmp/linux $(CROSS_FLAGS) $(KERNEL_FLAGS) -j8 Image dtbs modules 
	make -C $(PROJECT_DIR)/tmp/linux $(CROSS_FLAGS) $(KERNEL_FLAGS) -j8 modules_install

	cp -f $(KBUILD_OUTPUT)/arch/arm64/boot/Image Image
	cp -f $(KBUILD_OUTPUT)/.config linux.config
	cp -f $(KBUILD_OUTPUT)/arch/arm64/boot/dts/allwinner/sun50i-a64-pinephone-1.2.dtb board-1.2.dtb

initramfs-uroot.cpio: modules
	go get github.com/u-root/u-root
	$(GOFLAGS) u-root \
	-files $(BUILD_DIR)/modules/lib/modules/5.8.13-uroot:/usr/lib/modules/5.8.13-uroot \
	core github.com/u-root/u-root/cmds/exp/modprobe
	cp /tmp/initramfs.linux_arm64.cpio initramfs-uroot.cpio

u-boot-sunxi-with-spl-pinephone.bin:
	# wget "https://gitlab.com/pine64-org/crust-meta/-/jobs/artifacts/master/raw/$@?job=build"
	wget "https://gitlab.com/pine64-org/u-boot/-/jobs/artifacts/master/raw/$@?job=build" -O $@

pinephone-uroot-base.img: Image board-1.2.dtb initramfs-uroot.cpio u-boot-sunxi-with-spl-pinephone.bin extlinux.conf
	@echo "MKFS  $@"
	@rm -f $@
	@truncate --size 80M $@
	@mkfs.fat -F32 $@
	
	@mcopy -i $@ Image ::Image
	@mcopy -i $@ board-1.2.dtb ::board-1.2.dtb
	@mcopy -i $@ initramfs-uroot.cpio ::initramfs-uroot.cpio
	@mcopy -i $@ u-boot-sunxi-with-spl-pinephone.bin ::u-boot-sunxi-with-spl-pinephone.bin
	@mmd -i $@ ::extlinux
	@mcopy -i $@ extlinux.conf ::extlinux/extlinux.conf

pinephone-uroot.img: pinephone-uroot-base.img
	rm -f $@
	truncate --size 80M $@
	parted -s $@ mktable msdos
	parted -s $@ mkpart primary fat32 2048s 100%
	parted -s $@ set 1 boot on
	dd if=u-boot-sunxi-with-spl-pinephone.bin of=$@ bs=8k seek=1
	dd if=pinephone-uroot-base.img of=$@ seek=1024 bs=1k

clean:
	rm -rf tmp/
	rm -rf build/
	rm -rf Image
	rm -rf *.img
	rm -rf *.bin
	rm -rf *.cpio
	rm -rf *.dtb