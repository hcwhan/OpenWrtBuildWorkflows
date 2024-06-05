#!/bin/bash


cd ../

# feeds-hcwhan start
cd ./openwrt/
rm -rf ./feeds/packages/net/v2ray-geodata
rm -rf ./package/feeds/packages/v2ray-geodata
cd ../

git clone https://github.com/sbwml/luci-app-mosdns -b v5  ./feeds-hcwhan/mosdns
git clone https://github.com/sbwml/v2ray-geodata          ./feeds-hcwhan/v2ray-geodata

sed -i 's/- exec: prefer_ipv4/# - exec: prefer_ipv4/'     ./feeds-hcwhan/mosdns/luci-app-mosdns/root/etc/mosdns/config_custom.yaml
# sed -i 's/- exec: prefer_ipv4/# - exec: prefer_ipv4/'     ./feeds-hcwhan/mosdns/luci-app-mosdns/root/usr/share/mosdns/default.yaml

mv ./feeds-hcwhan/  ./openwrt/package/feeds/
# feeds-hcwhan end


# change string start
cd ./openwrt/feeds/luci/

sed -i 's/msgstr "CPU 性能优化调节"/msgstr "CPU 频率"/'         ./applications/luci-app-cpufreq/po/zh_Hans/cpufreq.po
sed -i 's/msgstr "CPU 性能优化调节设置"/msgstr "CPU 频率设置"/'  ./applications/luci-app-cpufreq/po/zh_Hans/cpufreq.po

sed -i 's/msgid "SQM QoS"/msgid "SQM"/'                      ./applications/luci-app-sqm/po/zh_Hans/sqm.po
sed -i 's/msgstr "SQM 队列管理"/msgstr "队列管理(SQM)"/'        ./applications/luci-app-sqm/po/zh_Hans/sqm.po

sed -i 's/"title": "SQM QoS",/"title": "SQM",/'               ./applications/luci-app-sqm/root/usr/share/luci/menu.d/luci-app-sqm.json
sed -i 's/\t\t"order": 59,//'                                 ./applications/luci-app-sqm/root/usr/share/luci/menu.d/luci-app-sqm.json

cd ../../../
# change string end


# miniupnpd start
mv ./feeds/miniupnpd/301-change-log.patch  ./openwrt/feeds/packages/net/miniupnpd/patches/
# miniupnpd end
