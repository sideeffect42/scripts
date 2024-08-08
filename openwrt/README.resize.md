# resize.sh

The [`resize.sh`](resize.sh) scripts automatically grows the root file system to make use of all available space on the disk.

This script is only useful on virtual machines or devices booting from SD card or hard drives/SSDs.
On most consumer routers OpenWrt images are tailored to the flash chips installed and already make use of all of it.

This script works on both ext4 and squashfs images as long as they use the ext4 file system for `/` or `/overlay` respectively.

## Usage

Copy the `resize.sh` script to your system and execute it.

e.g.
```sh
scp resize.sh openwrt.lan:
ssh openwrt.lan sh resize.sh
```

Rebooting after the resizing is not strictly necessary but recommended to ensure all devices have been updated to their new size, esp. on SquashFS images.
