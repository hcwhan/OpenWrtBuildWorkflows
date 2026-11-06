# Copyright (C) 2016 Openwrt.org
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for wolplus
LUCI_DEPENDS:=+luci-compat +etherwake
LUCI_PKGARCH:=all
PKG_VERSION:=1.2
PKG_PO_VERSION=$(PKG_VERSION)-$(PKG_RELEASE)

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
