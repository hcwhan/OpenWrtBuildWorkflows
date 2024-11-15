#!/bin/bash

echo 1
pwd
ls -al

echo 2
cd ../
pwd
ls -al

echo 3
cd ./openwrt/
pwd
ls -al

# feeds-hcwhan start
mv ../feeds-hcwhan/                                                   ./package/feeds/
# feeds-hcwhan end


# luci-app-mosdns start
rm -rf ./feeds/packages/net/v2ray-geodata
rm -rf ./package/feeds/packages/v2ray-geodata

git clone https://github.com/sbwml/luci-app-mosdns -b v5             ./package/feeds/feeds-hcwhan/mosdns
git clone https://github.com/sbwml/v2ray-geodata                     ./package/feeds/feeds-hcwhan/v2ray-geodata

sed -i 's/- exec: prefer_ipv4/# - exec: prefer_ipv4/'                ./package/feeds/feeds-hcwhan/mosdns/luci-app-mosdns/root/etc/mosdns/config_custom.yaml
# luci-app-mosdns  end


# luci-app-tailscale start
sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;'   ./feeds/packages/net/tailscale/Makefile

git clone https://github.com/asvow/luci-app-tailscale                ./package/feeds/feeds-hcwhan/luci-app-tailscale
# luci-app-tailscale  end


# change string start
cd ./feeds/luci/

sed -i 's/msgstr "CPU 性能优化调节"/msgstr "CPU 频率"/'                 ./applications/luci-app-cpufreq/po/zh_Hans/cpufreq.po
sed -i 's/msgstr "CPU 性能优化调节设置"/msgstr "CPU 频率设置"/'          ./applications/luci-app-cpufreq/po/zh_Hans/cpufreq.po

sed -i 's/msgid "SQM QoS"/msgid "SQM"/'                              ./applications/luci-app-sqm/po/zh_Hans/sqm.po
sed -i 's/msgstr "SQM 队列管理"/msgstr "队列管理(SQM)"/'                ./applications/luci-app-sqm/po/zh_Hans/sqm.po

sed -i 's/"title": "SQM QoS",/"title": "SQM",/'                      ./applications/luci-app-sqm/root/usr/share/luci/menu.d/luci-app-sqm.json
sed -i 's/\t\t"order": 59,//'                                        ./applications/luci-app-sqm/root/usr/share/luci/menu.d/luci-app-sqm.json

cd ../../
# change string end


# miniupnpd start
mv ../feeds/miniupnpd/301-change-log.patch                           ./feeds/packages/net/miniupnpd/patches/
# miniupnpd end
