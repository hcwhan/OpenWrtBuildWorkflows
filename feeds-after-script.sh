#!/bin/bash
set -euo pipefail

# CI 中 openwrt/ 是指向 /workdir/openwrt 的符号链接, 所以 ../ 无法到达 workflow 仓库.
WORKFLOW_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")" && pwd)}"
FEEDS_HCWHAN="$WORKFLOW_ROOT/feeds-hcwhan"


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
rm -rf "$TAILSCALE_COMMUNITY_SRC"

TAILSCALE_MENU_JSON="$FEEDS_HCWHAN/luci-app-tailscale-community/root/usr/share/luci/menu.d/luci-app-tailscale-community.json"
grep -qF 'admin/vpn/tailscale' "$TAILSCALE_MENU_JSON" || {
	echo "ERROR: 'admin/vpn/tailscale' not found in $TAILSCALE_MENU_JSON" >&2
	exit 1
}
sed -i 's/admin\/vpn\/tailscale/admin\/services\/tailscale/g'          "$TAILSCALE_MENU_JSON"

# tailscale 是用 ts_omit_clientupdate 构建的, 因此已保存的 AutoUpdate.Apply=true 会导致每次 'tailscale set' 都失败.
# 在真正的 'tailscale set' 之前, 先用 'tailscale set --auto-update=false' 重置它(tailscaled 只会拒绝结果仍为 Apply=true 的修改).
TAILSCALE_SETTINGS_INIT="$FEEDS_HCWHAN/luci-app-tailscale-community/root/etc/init.d/tailscale-settings"
grep -qF -- '--auto-update' "$TAILSCALE_SETTINGS_INIT" && {
	echo "ERROR: '--auto-update' already present in $TAILSCALE_SETTINGS_INIT; upstream changed, review and drop this patch" >&2
	exit 1
}
test "$(grep -cxF $'\tlogger -t "$NAME" "Applying settings"' "$TAILSCALE_SETTINGS_INIT")" = 1 || {
	echo "ERROR: expected exactly one 'Applying settings' logger line in $TAILSCALE_SETTINGS_INIT" >&2
	exit 1
}
sed -i '/^\tlogger -t "\$NAME" "Applying settings"$/r /dev/stdin' "$TAILSCALE_SETTINGS_INIT" <<'EOF'
	[ "$("$ts_bin" get auto-update 2>/dev/null)" = true ] && {
		logger -t "$NAME" "AutoUpdate.Apply=true is unsupported in this build, resetting it"
		"$ts_bin" set --auto-update=false \
			|| logger -t "$NAME" "Failed to reset auto-update (exit code: $?)"
	}
EOF
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

MOSDNS_CONFIG="$FEEDS_HCWHAN/mosdns/luci-app-mosdns/root/etc/mosdns/config_custom.yaml"
grep -qF -- '- exec: prefer_ipv4' "$MOSDNS_CONFIG" || {
	echo "ERROR: '- exec: prefer_ipv4' not found in $MOSDNS_CONFIG" >&2
	exit 1
}
sed -i 's/- exec: prefer_ipv4/# - exec: prefer_ipv4/'                "$MOSDNS_CONFIG"
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


# rootfs 覆盖层 开始
# Buildroot 会把顶层的 files/ 目录复制进固件的 rootfs.
rm -rf ./files
cp -a "$WORKFLOW_ROOT/files"                                           ./files
# rootfs 覆盖层 结束
