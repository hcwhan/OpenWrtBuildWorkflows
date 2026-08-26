# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2011 OpenWrt.org

include $(TOPDIR)/rules.mk

ARCH:=i386
BOARD:=x86
BOARDNAME:=x86
FEATURES:=squashfs ext4 vdi vmdk vhdx pcmcia targz fpu boot-part rootfs-part
SUBTARGETS:=64 generic legacy geode

KERNEL_PATCHVER:=5.15

KERNELNAME:=bzImage

include $(INCLUDE_DIR)/target.mk

DEFAULT_PACKAGES += alsa-utils partx-utils mkf2fs fdisk kmod-button-hotplug kmod-usb-hid kmod-e1000e \
		    kmod-i40e kmod-igb kmod-igbvf kmod-igc kmod-ixgbe kmod-ixgbevf kmod-pcnet32 \
		    kmod-tulip kmod-vmxnet3 kmod-r8101 kmod-r8125 kmod-r8126 kmod-r8168 kmod-8139cp \
		    kmod-8139too kmod-fs-f2fs kmod-ac97 kmod-sound-hda-core kmod-sound-hda-codec-realtek \
		    kmod-sound-hda-codec-via kmod-sound-via82xx kmod-sound-hda-intel kmod-sound-hda-codec-hdmi \
		    kmod-sound-i8x0 kmod-usb-audio kmod-usb-net kmod-usb-net-asix kmod-usb-net-asix-ax88179 \
		    kmod-usb-net-rtl8150 kmod-usb-net-rtl8152-vendor grub2-bios-setup intel-igpu-firmware-dmc \
		    autocore automount \
      ca-certificates coreutils-nohup \
      luci-mod-rpc luci-app-autoreboot luci-app-filebrowser luci-app-filetransfer luci-app-ttyd luci-app-upnp luci-app-wolplus luci-app-zerotier luci-app-tailscale luci-theme-argon \
      htop coreutils curl vsftpd-tls openssh-sftp-server wget-ssl iperf3 ipset speedtest-go tcpdump tcping unzip ncdu \
      pciutils kmod-bnx2x luci-app-mosdns luci-app-openclash

$(eval $(call BuildTarget))

$(eval $(call $(if $(CONFIG_ISO_IMAGES),SetupHostCommand,Ignore),mkisofs, \
	Please install mkisofs. , \
	mkisofs -v 2>&1 , \
	genisoimage -v 2>&1 | grep genisoimage, \
	xorrisofs -v 2>&1 | grep xorriso \
))
