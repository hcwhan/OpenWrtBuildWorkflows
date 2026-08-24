#!/bin/bash
set -euo pipefail

# openwrt/ is a symlink to /workdir/openwrt in CI, so ../ does not reach the workflow repo.
WORKFLOW_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")" && pwd)}"


# golang start
rm -rf ./feeds/packages/lang/golang
mv "$WORKFLOW_ROOT/feeds-master/golang"                              ./feeds/packages/lang/golang
# golang end


# tailscale start
rm -rf ./feeds/packages/net/tailscale
mv "$WORKFLOW_ROOT/feeds-master/tailscale"                           ./feeds/packages/net/tailscale

TAILSCALE_MAKEFILE='./feeds/packages/net/tailscale/Makefile'

grep -qF '/etc/init.d/tailscale' "$TAILSCALE_MAKEFILE" || {
	echo "ERROR: '/etc/init.d/tailscale' not found in $TAILSCALE_MAKEFILE" >&2
	exit 1
}
sed -i '/\/etc\/init\.d\/tailscale/d'                                "$TAILSCALE_MAKEFILE"

grep -qF '/etc/config/tailscale' "$TAILSCALE_MAKEFILE" || {
	echo "ERROR: '/etc/config/tailscale' not found in $TAILSCALE_MAKEFILE" >&2
	exit 1
}
sed -i '/\/etc\/config\/tailscale/d'                                 "$TAILSCALE_MAKEFILE"
# tailscale end


# zerotier start
rm -rf ./feeds/packages/net/zerotier
mv "$WORKFLOW_ROOT/feeds-master/zerotier"                            ./feeds/packages/net/zerotier
# zerotier end


# luci-app-zerotier start
ZEROTIER_LUCI_SRC='./feeds/luci/applications/luci-app-zerotier'
ZEROTIER_MENU_JSON="$ZEROTIER_LUCI_SRC/root/usr/share/luci/menu.d/luci-app-zerotier.json"

rm -rf "$ZEROTIER_LUCI_SRC"
mv "$WORKFLOW_ROOT/feeds-master/luci-app-zerotier"                   ./feeds/luci/applications/luci-app-zerotier

grep -qF 'admin/vpn/zerotier' "$ZEROTIER_MENU_JSON" || {
	echo "ERROR: 'admin/vpn/zerotier' not found in $ZEROTIER_MENU_JSON" >&2
	exit 1
}
sed -i 's/admin\/vpn\/zerotier/admin\/services\/zerotier/g'          "$ZEROTIER_MENU_JSON"
# luci-app-zerotier end


# feeds-hcwhan start
mkdir -p ./package/feeds/
mv "$WORKFLOW_ROOT/feeds-hcwhan/"                                    ./package/feeds/feeds-hcwhan/
# feeds-hcwhan end


# miniupnpd start
mv "$WORKFLOW_ROOT/feeds-patch/miniupnpd/902-change-log.patch"       ./feeds/packages/net/miniupnpd/patches/
# miniupnpd end



# luci-app-tailscale start
git clone https://github.com/asvow/luci-app-tailscale                ./package/feeds/feeds-hcwhan/luci-app-tailscale

sed -i 's/admin\/vpn\/tailscale/admin\/services\/tailscale/g'        ./package/feeds/feeds-hcwhan/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json
# luci-app-tailscale end


# luci-app-mosdns start
rm -rf ./feeds/packages/net/v2ray-geodata

git clone https://github.com/sbwml/luci-app-mosdns -b v5             ./package/feeds/feeds-hcwhan/mosdns
git clone https://github.com/sbwml/v2ray-geodata                     ./package/feeds/feeds-hcwhan/v2ray-geodata

MOSDNS_CONFIG='./package/feeds/feeds-hcwhan/mosdns/luci-app-mosdns/root/etc/mosdns/config_custom.yaml'
grep -qF -- '- exec: prefer_ipv4' "$MOSDNS_CONFIG" || {
	echo "ERROR: '- exec: prefer_ipv4' not found in $MOSDNS_CONFIG" >&2
	exit 1
}
sed -i 's/- exec: prefer_ipv4/# - exec: prefer_ipv4/'                "$MOSDNS_CONFIG"
# luci-app-mosdns end


# luci-app-openclash start
OPENCLASH_TAG='v0.47.156'
OPENCLASH_SRC='./feeds/luci/applications/luci-app-openclash'
OPENCLASH_TMP='/tmp/openclash-src'

echo "Using OpenClash tag: $OPENCLASH_TAG"

rm -rf "$OPENCLASH_SRC"

git clone --depth 1 --branch "$OPENCLASH_TAG" https://github.com/vernesong/OpenClash "$OPENCLASH_TMP" || {
	echo "ERROR: failed to clone OpenClash $OPENCLASH_TAG" >&2
	exit 1
}

test -d "$OPENCLASH_TMP/luci-app-openclash" || {
	echo "ERROR: luci-app-openclash not found in OpenClash $OPENCLASH_TAG" >&2
	exit 1
}

grep -qF 'PKG_VERSION:=0.47.156' "$OPENCLASH_TMP/luci-app-openclash/Makefile" || {
	echo "ERROR: PKG_VERSION:=0.47.156 not found in luci-app-openclash Makefile ($OPENCLASH_TAG)" >&2
	exit 1
}

mv "$OPENCLASH_TMP/luci-app-openclash" "$OPENCLASH_SRC"
rm -rf "$OPENCLASH_TMP"
# luci-app-openclash end



# change string start
sed -i 's/msgstr "CPU 性能优化调节"/msgstr "CPU 频率"/'                 ./feeds/luci/applications/luci-app-cpufreq/po/zh_Hans/cpufreq.po
sed -i 's/msgstr "CPU 性能优化调节设置"/msgstr "CPU 频率设置"/'          ./feeds/luci/applications/luci-app-cpufreq/po/zh_Hans/cpufreq.po

sed -i 's/msgid "SQM QoS"/msgid "SQM"/'                              ./feeds/luci/applications/luci-app-sqm/po/zh_Hans/sqm.po
sed -i 's/msgstr "SQM 队列管理"/msgstr "队列管理(SQM)"/'                ./feeds/luci/applications/luci-app-sqm/po/zh_Hans/sqm.po

sed -i 's/"title": "SQM QoS",/"title": "SQM",/'                      ./feeds/luci/applications/luci-app-sqm/root/usr/share/luci/menu.d/luci-app-sqm.json
sed -i 's/\t\t"order": 59,//'                                        ./feeds/luci/applications/luci-app-sqm/root/usr/share/luci/menu.d/luci-app-sqm.json
# change string end



# 只重建 index，不 git pull
./scripts/feeds update -a -i
