#!/bin/bash
set -euo pipefail

# CI 中 openwrt/ 是指向 /workdir/openwrt 的符号链接, 所以 ../ 无法到达 workflow 仓库.
WORKFLOW_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")" && pwd)}"
FEEDS_HCWHAN="$WORKFLOW_ROOT/feeds-hcwhan"

# 引入共用函数 apply_patch.
source "$WORKFLOW_ROOT/0.feeds-common.sh"

# 在 Makefile 的 luci.mk include 行之前加 PKG_PO_VERSION:=$(PKG_VERSION)-$(PKG_RELEASE), 使 i18n 包版本与主包一致.
# i18n 包的版本取 PKG_PO_VERSION, 默认值读 git 历史; 复制进构建树的包没有历史, 版本会变成 unknown.
# set_po_version <Makefile>: Makefile 缺少 PKG_VERSION, PKG_RELEASE 或 luci.mk 的 include 行时让构建失败.
set_po_version() {
  local mk="$1"
  grep -q '^PKG_VERSION:=' "$mk" && grep -q '^PKG_RELEASE:=' "$mk" && grep -qxF 'include $(TOPDIR)/feeds/luci/luci.mk' "$mk" || {
    echo "ERROR: PKG_VERSION, PKG_RELEASE or the luci.mk include line not found in $mk; upstream changed, review" >&2
    exit 1
  }
  sed -i 's|^include \$(TOPDIR)/feeds/luci/luci\.mk$|PKG_PO_VERSION:=$(PKG_VERSION)-$(PKG_RELEASE)\n&|' "$mk"
}


# luci-app-tailscale-community 开始
TAILSCALE_COMMUNITY_SRC=/tmp/luci-app-tailscale-community-src
rm -rf "$FEEDS_HCWHAN/luci-app-tailscale-community" "$TAILSCALE_COMMUNITY_SRC"
git clone --depth 1 https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community "$TAILSCALE_COMMUNITY_SRC" || {
  echo "ERROR: failed to clone luci-app-tailscale-community" >&2
  exit 1
}
test -d "$TAILSCALE_COMMUNITY_SRC/luci-app-tailscale-community" || {
  echo "ERROR: luci-app-tailscale-community package dir not found" >&2
  exit 1
}
cp -a "$TAILSCALE_COMMUNITY_SRC/luci-app-tailscale-community"          "$FEEDS_HCWHAN/luci-app-tailscale-community"
TAILSCALE_COMMUNITY_VERSION="$(git -C "$TAILSCALE_COMMUNITY_SRC" log -1 --abbrev=7 --date=format:%Y.%m.%d --format='%cd~%h')"
rm -rf "$TAILSCALE_COMMUNITY_SRC"

# 上游 Makefile 没有 PKG_VERSION, luci.mk 读 git 历史取版本; 复制进构建树的包没有历史, 主包版本会变成 unknown.
# 版本取克隆 HEAD 的 提交日期~短哈希, PKG_RELEASE 为 1, 写在 include rules.mk 之后. 上游已定义 PKG_VERSION 时让构建失败.
TAILSCALE_COMMUNITY_MK="$FEEDS_HCWHAN/luci-app-tailscale-community/Makefile"
grep -qxF 'include $(TOPDIR)/rules.mk' "$TAILSCALE_COMMUNITY_MK" && ! grep -q '^PKG_VERSION:=' "$TAILSCALE_COMMUNITY_MK" || {
  echo "ERROR: include rules.mk line not found, or PKG_VERSION already defined, in $TAILSCALE_COMMUNITY_MK; upstream changed, review" >&2
  exit 1
}
sed -i "s|^include \$(TOPDIR)/rules\.mk\$|&\nPKG_VERSION:=$TAILSCALE_COMMUNITY_VERSION\nPKG_RELEASE:=1|" "$TAILSCALE_COMMUNITY_MK"
set_po_version "$TAILSCALE_COMMUNITY_MK"

# 把菜单入口从 VPN 移到 服务(admin/vpn/tailscale -> admin/services/tailscale).
TAILSCALE_MENU_JSON="$FEEDS_HCWHAN/luci-app-tailscale-community/root/usr/share/luci/menu.d/luci-app-tailscale-community.json"
grep -qF 'admin/vpn/tailscale' "$TAILSCALE_MENU_JSON" || {
  echo "ERROR: 'admin/vpn/tailscale' not found in $TAILSCALE_MENU_JSON" >&2
  exit 1
}
sed -i 's/admin\/vpn\/tailscale/admin\/services\/tailscale/g'          "$TAILSCALE_MENU_JSON"

# tailscale-settings 在 tailscaled 运行时发现 service_enabled 从 0 改回 1: 上游只更新记录的值, 不恢复 /etc/rc.d/S80tailscale 开机自启链接, 配置是 1 开机却不自启. 改成这时执行 tailscale enable(只建链接, 不动进程).
apply_patch "$FEEDS_HCWHAN/luci-app-tailscale-community" "$WORKFLOW_ROOT/feeds-patch/luci-app-tailscale-community/tailscale-settings-restore-autostart.patch"

# 新增 /etc/init.d/tailscale-boot-gate: 开机时(早于 S80tailscale)service_enabled=0 就删掉 tailscale 的开机链接, 这次开机不启动 tailscaled.
# 放进包的 root/ 下, luci.mk 会随包安装; 用 install -m 0755 保证有可执行权限.
install -D -m 0755 "$WORKFLOW_ROOT/feeds-patch/luci-app-tailscale-community/tailscale-boot-gate.init" "$FEEDS_HCWHAN/luci-app-tailscale-community/root/etc/init.d/tailscale-boot-gate"
# luci-app-tailscale-community 结束


# luci-app-mosdns 开始
rm -rf "$FEEDS_HCWHAN/mosdns"
rm -rf "$FEEDS_HCWHAN/v2ray-geodata"
git clone --depth 1 https://github.com/sbwml/luci-app-mosdns -b v5   "$FEEDS_HCWHAN/mosdns" || {
  echo "ERROR: failed to clone luci-app-mosdns (v5)" >&2
  exit 1
}
git clone --depth 1 https://github.com/sbwml/v2ray-geodata           "$FEEDS_HCWHAN/v2ray-geodata" || {
  echo "ERROR: failed to clone v2ray-geodata" >&2
  exit 1
}
# 删除嵌套的 .git, 避免这些克隆被识别为独立仓库, 也避免被复制进构建树.
rm -rf "$FEEDS_HCWHAN/mosdns/.git" "$FEEDS_HCWHAN/v2ray-geodata/.git"
set_po_version "$FEEDS_HCWHAN/mosdns/luci-app-mosdns/Makefile"
# luci-app-mosdns 结束


# feeds-hcwhan 开始
rm -rf ./package/feeds/feeds-hcwhan
mkdir -p ./package/feeds/
cp -a "$FEEDS_HCWHAN"                                                  ./package/feeds/
# feeds-hcwhan 结束



# 菜单顺序 开始
# 删除顶层 order, 使 LuCI 默认取 1000, 并按名称对同级菜单排序.
# UPnP 没有顶层 order, 无需修改.
FILEBROWSER_MENU='./package/feeds/luci/luci-app-filebrowser/root/usr/share/luci/menu.d/luci-app-filebrowser.json'
grep -qF '"title": "FileBrowser",' "$FILEBROWSER_MENU" || {
  echo "ERROR: '\"title\": \"FileBrowser\",' not found in $FILEBROWSER_MENU" >&2
  exit 1
}
sed -i '/"order": 30,/d'                                             "$FILEBROWSER_MENU"

MOSDNS_MENU='./package/feeds/feeds-hcwhan/mosdns/luci-app-mosdns/root/usr/share/luci/menu.d/luci-app-mosdns.json'
grep -qF '"title": "MosDNS",' "$MOSDNS_MENU" || {
  echo "ERROR: '\"title\": \"MosDNS\",' not found in $MOSDNS_MENU" >&2
  exit 1
}
sed -i '/"title": "MosDNS",/{n;/"order":/d;}'                       "$MOSDNS_MENU"

OPENCLASH_LUA='./package/feeds/luci/luci-app-openclash/luasrc/controller/openclash.lua'
grep -qF 'page = entry({"admin", "services", "openclash"}' "$OPENCLASH_LUA" || {
  echo "ERROR: openclash top-level entry not found in $OPENCLASH_LUA" >&2
  exit 1
}
sed -i '/page = entry({"admin", "services", "openclash"}/s/, 50)/)/'     "$OPENCLASH_LUA"

TAILSCALE_MENU='./package/feeds/feeds-hcwhan/luci-app-tailscale-community/root/usr/share/luci/menu.d/luci-app-tailscale-community.json'
grep -qF '"title": "Tailscale",' "$TAILSCALE_MENU" || {
  echo "ERROR: '\"title\": \"Tailscale\",' not found in $TAILSCALE_MENU" >&2
  exit 1
}
sed -i '/"title": "Tailscale",/{n;/"order":/d;}'                       "$TAILSCALE_MENU"

WOLPLUS_LUA='./package/feeds/feeds-hcwhan/luci-app-wolplus/luasrc/controller/wolplus.lua'
grep -qF 'entry({"admin", "services", "wolplus"}, cbi("wolplus")' "$WOLPLUS_LUA" || {
  echo "ERROR: wolplus top-level entry not found in $WOLPLUS_LUA" >&2
  exit 1
}
sed -i '/entry({"admin", "services", "wolplus"}, cbi("wolplus")/s/, 95)/)/' "$WOLPLUS_LUA"

ZEROTIER_MENU='./package/feeds/luci/luci-app-zerotier/root/usr/share/luci/menu.d/luci-app-zerotier.json'
grep -qF '"title": "ZeroTier",' "$ZEROTIER_MENU" || {
  echo "ERROR: '\"title\": \"ZeroTier\",' not found in $ZEROTIER_MENU" >&2
  exit 1
}
sed -i '/"title": "ZeroTier",/{n;/"order":/d;}'                       "$ZEROTIER_MENU"
# 菜单顺序 结束
