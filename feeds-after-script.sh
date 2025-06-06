#!/bin/bash


# feeds-hcwhan start
cd ../
mv ./feeds-hcwhan/                                                   ./openwrt/package/feeds/
cd ./openwrt/
# feeds-hcwhan end


# luci-app-mosdns start
rm -rf ./feeds/packages/net/v2ray-geodata
rm -rf ./package/feeds/packages/v2ray-geodata

git clone https://github.com/sbwml/luci-app-mosdns -b v5             ./package/feeds/feeds-hcwhan/mosdns
git clone https://github.com/sbwml/v2ray-geodata                     ./package/feeds/feeds-hcwhan/v2ray-geodata

sed -i 's/- exec: prefer_ipv4/# - exec: prefer_ipv4/'                ./package/feeds/feeds-hcwhan/mosdns/luci-app-mosdns/root/etc/mosdns/config_custom.yaml
# luci-app-mosdns end


git --version
# golang start
rm -rf ./feeds/packages/lang/golang
cd ../
mv ./feeds/golang                                                    ./openwrt/feeds/packages/lang/golang
cd ./openwrt/
# golang end


# tailscale start
rm -rf ./feeds/packages/net/tailscale
cd ../
mv ./feeds/tailscale                                                 ./openwrt/feeds/packages/net/tailscale
cd ./openwrt/
# tailscale end


# luci-app-tailscale start
sed -i '/\/etc\/init\.d\/tailscale/d;/\/etc\/config\/tailscale/d;'   ./feeds/packages/net/tailscale/Makefile

git clone https://github.com/asvow/luci-app-tailscale                ./package/feeds/feeds-hcwhan/luci-app-tailscale
# luci-app-tailscale end



# miniupnpd start
cd ../
mv ./feeds/miniupnpd/301-change-log.patch                            ./openwrt/feeds/packages/net/miniupnpd/patches/
cd ./openwrt/
# miniupnpd end



# change string start
cd ./feeds/luci/

sed -i 's/admin\/vpn\/zerotier/admin\/services\/zerotier/'           ./applications/luci-app-zerotier/root/usr/share/luci/menu.d/luci-app-zerotier.json

sed -i 's/msgstr "CPU 性能优化调节"/msgstr "CPU 频率"/'                 ./applications/luci-app-cpufreq/po/zh_Hans/cpufreq.po
sed -i 's/msgstr "CPU 性能优化调节设置"/msgstr "CPU 频率设置"/'          ./applications/luci-app-cpufreq/po/zh_Hans/cpufreq.po

sed -i 's/msgid "SQM QoS"/msgid "SQM"/'                              ./applications/luci-app-sqm/po/zh_Hans/sqm.po
sed -i 's/msgstr "SQM 队列管理"/msgstr "队列管理(SQM)"/'                ./applications/luci-app-sqm/po/zh_Hans/sqm.po

sed -i 's/"title": "SQM QoS",/"title": "SQM",/'                      ./applications/luci-app-sqm/root/usr/share/luci/menu.d/luci-app-sqm.json
sed -i 's/\t\t"order": 59,//'                                        ./applications/luci-app-sqm/root/usr/share/luci/menu.d/luci-app-sqm.json

cd ../../
# change string end
