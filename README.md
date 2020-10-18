u-root for Pinephone
--------------------

[u-root](https://github.com/u-root/u-root) - a fully Go userland with Linux bootloaders. U-root is a part of [LinuxBoot](https://www.linuxboot.org/) project meant to replace UEFI firmware with Linux kernel and runtime.

## Flow

![u-root flow](http://www.plantuml.com/plantuml/proxy?src=https://raw.githubusercontent.com/yurinnick/pinephone-uroot/main/diagram.txt)


## Dependencies
- Go 1.13
- aarch64-linux-gnu toolchain
- mtools

## How-to
- `make pinephone-uroot.img`
- `sudo dd if=pinephone-uroot.img of=/dev/sdX bs=1M status=progress conv=fsync`


