include $(TOPDIR)/rules.mk

ARCH:=aarch64
BOARD:=ipq807x
BOARDNAME:=Qualcomm Atheros IPQ807x
FEATURES:=squashfs ramdisk fpu nand rtc emmc
KERNELNAME:=Image dtbs
CPU_TYPE:=cortex-a53
SUBTARGETS:=generic

KERNEL_PATCHVER:=5.15

include $(INCLUDE_DIR)/target.mk
DEFAULT_PACKAGES += \
	kmod-usb3 kmod-usb-dwc3 kmod-usb-dwc3-qcom \
	kmod-leds-gpio kmod-gpio-button-hotplug \
	kmod-qca-nss-dp qca-ssdk-shell kmod-phy-aquantia \
	ath11k-firmware-ipq8074 kmod-ath11k-ahb wpad-openssl \
	uboot-envtools automount losetup \
	autocore luci-app-cpufreq \
      ca-certificates coreutils-nohup \
      luci-mod-rpc luci-app-autoreboot luci-app-filebrowser luci-app-filetransfer luci-app-ttyd luci-app-upnp luci-app-wolplus luci-app-zerotier luci-app-tailscale-community luci-theme-argon \
      htop coreutils curl vsftpd-tls openssh-sftp-server wget-ssl iperf3 ipset speedtest-go tcpdump tcping unzip ncdu \
      luci-app-mosdns luci-app-openclash

$(eval $(call BuildTarget))
