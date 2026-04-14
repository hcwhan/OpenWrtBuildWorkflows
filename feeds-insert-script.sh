#!/bin/bash



# golang start
rm -rf ./feeds/packages/lang/golang
cd ../
mv ./feeds/golang                                                    ./openwrt/feeds/packages/lang/golang
cd ./openwrt/
./scripts/feeds update packages
# golang end


# tailscale start
rm -rf ./feeds/packages/net/tailscale
cd ../
mv ./feeds/tailscale                                                 ./openwrt/feeds/packages/net/tailscale
cd ./openwrt/
./scripts/feeds update packages
# tailscale end


# miniupnpd start
cd ../
mv ./feeds/miniupnpd/902-change-log.patch                            ./openwrt/feeds/packages/net/miniupnpd/patches/
cd ./openwrt/
# miniupnpd end
