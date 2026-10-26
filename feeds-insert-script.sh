#!/bin/bash
set -euo pipefail

# CI 中 openwrt/ 是指向 /workdir/openwrt 的符号链接, 所以 ../ 无法到达 workflow 仓库.
WORKFLOW_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")" && pwd)}"

# 引入共用函数 apply_patch.
source "$WORKFLOW_ROOT/feeds-common.sh"


# golang 开始
# 用项目内 feeds-master 的 golang 替换 feed 自带的 golang(为了使用更高版本的 Go 版本).
rm -rf ./feeds/packages/lang/golang
cp -a "$WORKFLOW_ROOT/feeds-master/golang"                           ./feeds/packages/lang/golang
# golang 结束


# tailscale 开始
# 不用 feed 自带的 tailscale 包, 构建时克隆 GuNanOvO/openwrt-tailscale 的固定标签整体替换.
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

TAILSCALE_INIT="$TAILSCALE_PKG/files/tailscale.init"

# Makefile 加 PKG_BUILD_DEPENDS:=golang/host.
apply_patch "$TAILSCALE_PKG" "$WORKFLOW_ROOT/feeds-patch/tailscale/build-depends-golang-host.patch"

# Makefile 的 GO_PKG_TAGS 追加 ts_omit_flashappliance.
apply_patch "$TAILSCALE_PKG" "$WORKFLOW_ROOT/feeds-patch/tailscale/omit-flashappliance.patch"

# Makefile 去掉两处写死的 UPX 字样: 版本串 "(OpenWrt-UPX)" 改成 "(OpenWrt)", 包描述 TITLE 去掉 "(UPX Compressed)".
apply_patch "$TAILSCALE_PKG" "$WORKFLOW_ROOT/feeds-patch/tailscale/remove-upx-labels.patch"

# Makefile 删除维护者专用的 5 行导出逻辑.
apply_patch "$TAILSCALE_PKG" "$WORKFLOW_ROOT/feeds-patch/tailscale/remove-maintainer-export.patch"

# 开机时遵循 tailscale.settings.service_enabled: 为 0 时跳过启动, 并删除 /etc/rc.d/S80tailscale 链接.
# 此处通过 S80tailscale 链接调用, 直接用 rc.common 的 disable() 会作用到错误的名称上, 所以改用 init 脚本的路径.
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

# 新增 /etc/init.d/tailscale-ip-rules: 开机时(早于 network)补齐防子网劫持的 netifd ip rule 配置节.
# 先把 init 脚本复制进包的 files/, 再用补丁让 Makefile 把它安装到 /etc/init.d/.
cp "$WORKFLOW_ROOT/feeds-patch/tailscale/tailscale-ip-rules.init"      "$TAILSCALE_PKG/files/tailscale-ip-rules.init"
apply_patch "$TAILSCALE_PKG" "$WORKFLOW_ROOT/feeds-patch/tailscale/tailscale-ip-rules-install.patch"
# tailscale 结束


# zerotier 开始
# 用项目内 feeds-master 的副本替换 feed 自带的 zerotier.
rm -rf ./feeds/packages/net/zerotier
cp -a "$WORKFLOW_ROOT/feeds-master/zerotier"                         ./feeds/packages/net/zerotier
# zerotier 结束


# luci-app-zerotier 开始
ZEROTIER_LUCI_SRC='./feeds/luci/applications/luci-app-zerotier'
ZEROTIER_MENU_JSON="$ZEROTIER_LUCI_SRC/root/usr/share/luci/menu.d/luci-app-zerotier.json"

# 用项目内 feeds-master 的副本替换 feed 自带的 luci-app-zerotier.
rm -rf "$ZEROTIER_LUCI_SRC"
cp -a "$WORKFLOW_ROOT/feeds-master/luci-app-zerotier"                ./feeds/luci/applications/luci-app-zerotier

# 把菜单入口从 VPN 移到 服务(admin/vpn/zerotier -> admin/services/zerotier).
grep -qF 'admin/vpn/zerotier' "$ZEROTIER_MENU_JSON" || {
  echo "ERROR: 'admin/vpn/zerotier' not found in $ZEROTIER_MENU_JSON" >&2
  exit 1
}
sed -i 's/admin\/vpn\/zerotier/admin\/services\/zerotier/g'          "$ZEROTIER_MENU_JSON"
# luci-app-zerotier 结束


# luci-app-openclash 开始
# 用 vernesong/OpenClash 的固定标签替换 feed 自带的 luci-app-openclash, 并校验其 Makefile 的 PKG_VERSION 与标签一致.
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
# luci-app-openclash 结束


# mosdns / v2ray-geodata 开始
# 安装前先删除官方 feed 中的副本, 避免与 feeds-hcwhan(sbwml v5)冲突.
rm -rf ./feeds/packages/net/mosdns
rm -rf ./feeds/packages/net/v2ray-geodata
# mosdns / v2ray-geodata 结束


# miniupnpd 开始
# 给 miniupnpd 增加补丁: upnpsoap.c 里 "private/reserved address ... is not suitable for external IP" 这条日志由 LOG_NOTICE 降为 LOG_DEBUG.
cp "$WORKFLOW_ROOT/feeds-patch/miniupnpd/902-change-log.patch"       ./feeds/packages/net/miniupnpd/patches/
# miniupnpd 结束



# 修改字符串 开始
CPUFREQ_PO='./feeds/luci/applications/luci-app-cpufreq/po/zh_Hans/cpufreq.po'
SQM_PO='./feeds/luci/applications/luci-app-sqm/po/zh_Hans/sqm.po'
SQM_JSON='./feeds/luci/applications/luci-app-sqm/root/usr/share/luci/menu.d/luci-app-sqm.json'

# 原文和已替换后的文本都找不到时报错退出(说明上游已变更).
# 接受已替换后的文本, 是为了在已打过补丁的目录树上重复运行仍能正常工作.
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

# luci-app-cpufreq: 中文显示 "CPU 性能优化调节" 改为 "CPU 频率", "CPU 性能优化调节设置" 改为 "CPU 频率设置".
sed -i 's/msgstr "CPU 性能优化调节"/msgstr "CPU 频率"/'                 "$CPUFREQ_PO"
sed -i 's/msgstr "CPU 性能优化调节设置"/msgstr "CPU 频率设置"/'          "$CPUFREQ_PO"

# luci-app-sqm 翻译: msgid "SQM QoS" 改为 "SQM", 中文显示 "SQM 队列管理" 改为 "队列管理(SQM)".
sed -i 's/msgid "SQM QoS"/msgid "SQM"/'                              "$SQM_PO"
sed -i 's/msgstr "SQM 队列管理"/msgstr "队列管理(SQM)"/'                "$SQM_PO"

# luci-app-sqm 菜单: 标题 "SQM QoS" 改为 "SQM"(与上面 po 的 msgid 对应), 并删除 order, 使 LuCI 默认取 1000, 按名称对同级菜单排序.
sed -i 's/"title": "SQM QoS",/"title": "SQM",/'                      "$SQM_JSON"
sed -i 's/\t\t"order": 59,//'                                        "$SQM_JSON"
# 修改字符串 结束



# 只重建 index, 不 git pull
./scripts/feeds update -a -i
