#!/bin/bash
set -euo pipefail

# openwrt/ is a symlink to /workdir/openwrt in CI, so ../ does not reach the workflow repo.
WORKFLOW_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")" && pwd)}"


# golang start
rm -rf ./feeds/packages/lang/golang
cp -a "$WORKFLOW_ROOT/feeds-master/golang"                           ./feeds/packages/lang/golang
# golang end


# tailscale start
TAILSCALE_SRC=/tmp/openwrt-tailscale-src
TAILSCALE_PKG='./feeds/packages/net/tailscale'
rm -rf "$TAILSCALE_PKG" "$TAILSCALE_SRC"
git clone --depth 1 https://github.com/GuNanOvO/openwrt-tailscale -b v1.104.2 "$TAILSCALE_SRC" || {
	echo "ERROR: failed to clone openwrt-tailscale (v1.104.2)" >&2
	exit 1
}
test -d "$TAILSCALE_SRC/package/tailscale" || {
	echo "ERROR: package/tailscale not found in openwrt-tailscale" >&2
	exit 1
}
cp -a "$TAILSCALE_SRC/package/tailscale"                             "$TAILSCALE_PKG"
rm -rf "$TAILSCALE_SRC"

TAILSCALE_MAKEFILE="$TAILSCALE_PKG/Makefile"
TAILSCALE_INIT="$TAILSCALE_PKG/files/tailscale.init"

# Build golang/host first so tailscale uses the feeds Go instead of the CI host Go.
test "$(grep -c '^PKG_BUILD_DIR:=' "$TAILSCALE_MAKEFILE")" = 1 && grep -qF 'PKG_BUILD_DIR:=$(BUILD_DIR)/tailscale-$(PKG_VERSION)' "$TAILSCALE_MAKEFILE" || {
	echo "ERROR: expected exactly one 'PKG_BUILD_DIR:=\$(BUILD_DIR)/tailscale-\$(PKG_VERSION)' in $TAILSCALE_MAKEFILE" >&2
	exit 1
}
sed -i '/^PKG_BUILD_DIR:=/a PKG_BUILD_DEPENDS:=golang/host'            "$TAILSCALE_MAKEFILE"

# Drop the maintainer-only export of tailscaled into bin/packages (not needed for firmware builds).
sed -i -e '/\[Maintainer Note\]/d' \
       -e '/Feel free to remove the next two lines/d' \
       -e '/可选：以下两行/d' \
       -e '/\$(TOPDIR)\/bin\/packages/d'                               "$TAILSCALE_MAKEFILE"

# Honor tailscale.settings.service_enabled at boot: when 0, skip start and remove the /etc/rc.d/S80tailscale link.
# Called via the S80tailscale link, so rc.common's bare disable() would target the wrong name; use the init path.
test "$(grep -c '^  config_load tailscale$' "$TAILSCALE_INIT")" = 1 || {
	echo "ERROR: expected exactly one '  config_load tailscale' in $TAILSCALE_INIT" >&2
	exit 1
}
sed -i '/^  config_load tailscale$/r /dev/stdin'                          "$TAILSCALE_INIT" <<'EOF'
  local service_enabled
  config_get_bool service_enabled "settings" service_enabled 1
  if [ "$service_enabled" != 1 ]; then
    /etc/init.d/tailscale disable
    logger -t tailscale "service_enabled=0, skip start and remove boot link"
    return 0
  fi
EOF

# tailscale installs subnet routes accepted from other nodes into table 52 (pref 5270), which beats the main table.
# If another node advertises a subnet that overlaps a local one (e.g. the LAN), it would hijack that LAN.
# Look up main first at pref 1295 and ignore its default route, so specific local routes always win.
# Except the tailnet's own ranges (100.64.0.0/10, fd7a:115c:a1e0::/48): pin them to table 52 at pref 1290,
# or a CGNAT WAN route would swallow all peers.
# Packets from tailscaled itself (fwmark 0x80000/0xff0000) go to main at pref 1285, before the pin: with an exit node,
# table 52 has a default route, so the pin would loop them back into tailscale0 (e.g. non-peer CGNAT destinations).
# All three prefs sit after mwan3's iif rules (pref 1001+) and before tailscale's own rules (5210-5270, or 1310-1370
# when it detects mwan3 on OpenWrt), so they take effect whether or not tailscale detects mwan3.
test "$(grep -c '^  /usr/sbin/tailscaled --cleanup$' "$TAILSCALE_INIT")" = 2 || {
	echo "ERROR: expected exactly two '  /usr/sbin/tailscaled --cleanup' in $TAILSCALE_INIT" >&2
	exit 1
}
sed -i -e '/^start_service() {$/,/^}$/{' \
       -e '/^  \/usr\/sbin\/tailscaled --cleanup$/r /dev/stdin' \
       -e '}'                                                          "$TAILSCALE_INIT" <<'EOF'

  local fam
  for fam in -4 -6; do
    ip $fam rule del pref 1295 table main suppress_prefixlength 0 2>/dev/null
    ip $fam rule add pref 1295 table main suppress_prefixlength 0 || logger -t tailscale "failed to add ip $fam rule pref 1295"
    ip $fam rule del pref 1285 fwmark 0x80000/0xff0000 table main 2>/dev/null
    ip $fam rule add pref 1285 fwmark 0x80000/0xff0000 table main || logger -t tailscale "failed to add ip $fam rule pref 1285"
  done
  ip -4 rule del pref 1290 to 100.64.0.0/10 table 52 2>/dev/null
  ip -4 rule add pref 1290 to 100.64.0.0/10 table 52 || logger -t tailscale "failed to add ip -4 rule pref 1290"
  ip -6 rule del pref 1290 to fd7a:115c:a1e0::/48 table 52 2>/dev/null
  ip -6 rule add pref 1290 to fd7a:115c:a1e0::/48 table 52 || logger -t tailscale "failed to add ip -6 rule pref 1290"
EOF
sed -i '/^stop_service() {$/r /dev/stdin'                              "$TAILSCALE_INIT" <<'EOF'
  local fam
  for fam in -4 -6; do
    ip $fam rule del pref 1295 table main suppress_prefixlength 0 2>/dev/null
    ip $fam rule del pref 1285 fwmark 0x80000/0xff0000 table main 2>/dev/null
  done
  ip -4 rule del pref 1290 to 100.64.0.0/10 table 52 2>/dev/null
  ip -6 rule del pref 1290 to fd7a:115c:a1e0::/48 table 52 2>/dev/null
EOF
test "$(grep -c 'suppress_prefixlength 0' "$TAILSCALE_INIT")" = 3 || {
	echo "ERROR: ip rule patch not applied to start_service/stop_service in $TAILSCALE_INIT" >&2
	exit 1
}

# The ip rule patch above runs ip(8), which the package does not depend on. Add +ip (provided by ip-tiny and ip-full).
test "$(grep -c '^  DEPENDS:=' "$TAILSCALE_MAKEFILE")" = 1 || {
	echo "ERROR: expected exactly one '  DEPENDS:=' in $TAILSCALE_MAKEFILE" >&2
	exit 1
}
sed -i '/^  DEPENDS:=/s/$/ +ip/'                                       "$TAILSCALE_MAKEFILE"
# tailscale end


# zerotier start
rm -rf ./feeds/packages/net/zerotier
cp -a "$WORKFLOW_ROOT/feeds-master/zerotier"                         ./feeds/packages/net/zerotier
# zerotier end


# luci-app-zerotier start
ZEROTIER_LUCI_SRC='./feeds/luci/applications/luci-app-zerotier'
ZEROTIER_MENU_JSON="$ZEROTIER_LUCI_SRC/root/usr/share/luci/menu.d/luci-app-zerotier.json"

rm -rf "$ZEROTIER_LUCI_SRC"
cp -a "$WORKFLOW_ROOT/feeds-master/luci-app-zerotier"                ./feeds/luci/applications/luci-app-zerotier

grep -qF 'admin/vpn/zerotier' "$ZEROTIER_MENU_JSON" || {
	echo "ERROR: 'admin/vpn/zerotier' not found in $ZEROTIER_MENU_JSON" >&2
	exit 1
}
sed -i 's/admin\/vpn\/zerotier/admin\/services\/zerotier/g'          "$ZEROTIER_MENU_JSON"
# luci-app-zerotier end


# luci-app-openclash start
OPENCLASH_TAG='v0.48.002'
OPENCLASH_SRC='./feeds/luci/applications/luci-app-openclash'
OPENCLASH_TMP='/tmp/openclash-src'

echo "Using OpenClash tag: $OPENCLASH_TAG"

rm -rf "$OPENCLASH_SRC" "$OPENCLASH_TMP"

git clone --depth 1 --branch "$OPENCLASH_TAG" https://github.com/vernesong/OpenClash "$OPENCLASH_TMP" || {
	echo "ERROR: failed to clone OpenClash $OPENCLASH_TAG" >&2
	exit 1
}

test -d "$OPENCLASH_TMP/luci-app-openclash" || {
	echo "ERROR: luci-app-openclash not found in OpenClash $OPENCLASH_TAG" >&2
	exit 1
}

grep -qF "PKG_VERSION:=${OPENCLASH_TAG#v}" "$OPENCLASH_TMP/luci-app-openclash/Makefile" || {
	echo "ERROR: PKG_VERSION:=${OPENCLASH_TAG#v} not found in luci-app-openclash Makefile ($OPENCLASH_TAG)" >&2
	exit 1
}

mv "$OPENCLASH_TMP/luci-app-openclash" "$OPENCLASH_SRC"
rm -rf "$OPENCLASH_TMP"
# luci-app-openclash end


# mosdns / v2ray-geodata start
# Remove official feed copies before install to avoid conflict with feeds-hcwhan (sbwml v5).
rm -rf ./feeds/packages/net/mosdns
rm -rf ./feeds/packages/net/v2ray-geodata
# mosdns / v2ray-geodata end


# miniupnpd start
cp "$WORKFLOW_ROOT/feeds-patch/miniupnpd/902-change-log.patch"       ./feeds/packages/net/miniupnpd/patches/
# miniupnpd end



# change string start
CPUFREQ_PO='./feeds/luci/applications/luci-app-cpufreq/po/zh_Hans/cpufreq.po'
SQM_PO='./feeds/luci/applications/luci-app-sqm/po/zh_Hans/sqm.po'
SQM_JSON='./feeds/luci/applications/luci-app-sqm/root/usr/share/luci/menu.d/luci-app-sqm.json'

# Fail if neither the original text nor the already replaced text is found (upstream changed).
# Accepting the replaced text keeps re-runs on an already patched tree working.
require_text() {
	grep -qF -- "$2" "$1" || grep -qF -- "$3" "$1" || {
		echo "ERROR: '$2' not found in $1" >&2
		exit 1
	}
}
require_text "$CPUFREQ_PO" 'msgstr "CPU 性能优化调节"'     'msgstr "CPU 频率"'
require_text "$CPUFREQ_PO" 'msgstr "CPU 性能优化调节设置"'  'msgstr "CPU 频率设置"'
require_text "$SQM_PO"     'msgid "SQM QoS"'               'msgid "SQM"'
require_text "$SQM_PO"     'msgstr "SQM 队列管理"'          'msgstr "队列管理(SQM)"'
require_text "$SQM_JSON"   '"title": "SQM QoS",'           '"title": "SQM",'
require_text "$SQM_JSON"   $'\t\t"order": 59,'             '"title": "SQM",'

sed -i 's/msgstr "CPU 性能优化调节"/msgstr "CPU 频率"/'                 "$CPUFREQ_PO"
sed -i 's/msgstr "CPU 性能优化调节设置"/msgstr "CPU 频率设置"/'          "$CPUFREQ_PO"

sed -i 's/msgid "SQM QoS"/msgid "SQM"/'                              "$SQM_PO"
sed -i 's/msgstr "SQM 队列管理"/msgstr "队列管理(SQM)"/'                "$SQM_PO"

sed -i 's/"title": "SQM QoS",/"title": "SQM",/'                      "$SQM_JSON"
sed -i 's/\t\t"order": 59,//'                                        "$SQM_JSON"
# change string end



# 只重建 index，不 git pull
./scripts/feeds update -a -i
