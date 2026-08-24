#!/bin/bash
set -euo pipefail

# openwrt/ is a symlink to /workdir/openwrt in CI, so ../ does not reach the workflow repo.
WORKFLOW_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")" && pwd)}"
FEEDS_HCWHAN="$WORKFLOW_ROOT/feeds-hcwhan"


# luci-app-tailscale start
rm -rf "$FEEDS_HCWHAN/luci-app-tailscale"
git clone https://github.com/asvow/luci-app-tailscale                "$FEEDS_HCWHAN/luci-app-tailscale" || {
	echo "ERROR: failed to clone luci-app-tailscale" >&2
	exit 1
}

TAILSCALE_MENU_JSON="$FEEDS_HCWHAN/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
grep -qF 'admin/vpn/tailscale' "$TAILSCALE_MENU_JSON" || {
	echo "ERROR: 'admin/vpn/tailscale' not found in $TAILSCALE_MENU_JSON" >&2
	exit 1
}
sed -i 's/admin\/vpn\/tailscale/admin\/services\/tailscale/g'          "$TAILSCALE_MENU_JSON"
# luci-app-tailscale end


# luci-app-mosdns start
rm -rf "$FEEDS_HCWHAN/mosdns"
rm -rf "$FEEDS_HCWHAN/v2ray-geodata"
git clone https://github.com/sbwml/luci-app-mosdns -b v5             "$FEEDS_HCWHAN/mosdns" || {
	echo "ERROR: failed to clone luci-app-mosdns (v5)" >&2
	exit 1
}
git clone https://github.com/sbwml/v2ray-geodata                     "$FEEDS_HCWHAN/v2ray-geodata" || {
	echo "ERROR: failed to clone v2ray-geodata" >&2
	exit 1
}

MOSDNS_CONFIG="$FEEDS_HCWHAN/mosdns/luci-app-mosdns/root/etc/mosdns/config_custom.yaml"
grep -qF -- '- exec: prefer_ipv4' "$MOSDNS_CONFIG" || {
	echo "ERROR: '- exec: prefer_ipv4' not found in $MOSDNS_CONFIG" >&2
	exit 1
}
sed -i 's/- exec: prefer_ipv4/# - exec: prefer_ipv4/'                "$MOSDNS_CONFIG"
# luci-app-mosdns end


# feeds-hcwhan start
rm -rf ./package/feeds/feeds-hcwhan
mkdir -p ./package/feeds/
cp -a "$FEEDS_HCWHAN"                                                  ./package/feeds/
# feeds-hcwhan end



# menu order start
# Drop top-level order so LuCI defaults to 1000 and sorts siblings by name.
# UPnP has no top-level order; no change needed.
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

TAILSCALE_MENU='./package/feeds/feeds-hcwhan/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json'
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
# menu order end
