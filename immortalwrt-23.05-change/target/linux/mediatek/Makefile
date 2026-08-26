# Copyright (c) 2015 OpenWrt.org
#
include $(TOPDIR)/rules.mk

ARCH:=arm
BOARD:=mediatek
BOARDNAME:=MediaTek Ralink ARM
SUBTARGETS:=mt7622 mt7623 mt7629 filogic
FEATURES:=dt-overlay emmc fpu gpio nand pci pcie rootfs-part separate_ramdisk squashfs usb

KERNEL_PATCHVER:=5.15

include $(INCLUDE_DIR)/target.mk
DEFAULT_PACKAGES += \
	kmod-leds-gpio kmod-gpio-button-hotplug \
	autocore \
      ca-certificates coreutils-nohup \
      luci-mod-rpc luci-app-autoreboot luci-app-filebrowser luci-app-filetransfer luci-app-ttyd luci-app-upnp luci-app-wolplus luci-app-zerotier luci-app-tailscale luci-theme-argon \
      htop coreutils curl vsftpd-tls openssh-sftp-server wget-ssl iperf3 ipset speedtest-go tcpdump tcping unzip ncdu \
      bash kmod-nf-tproxy kmod-nft-tproxy

$(eval $(call BuildTarget))
