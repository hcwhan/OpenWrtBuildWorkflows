
# Tailscale 运行时执行 `network restart`, 路由表 52 被清空且不恢复

`tailscaled` 运行时执行 `/etc/init.d/network restart`, netifd 会关闭并重新拉起 `tailscale0`, `tailscale0` 上的 tailnet 地址和路由表 52 的全部路由随之被清掉, `tailscaled` 不会重新写入. 之后 `tailscale0` 仍为 UP, `tailscale status` 和 `tailscale ping` 仍正常, 但走内核路由的 tailnet 流量不通, 直到执行 `/etc/init.d/tailscale restart` 或整机重启.

## 1. 说明

1. 状态: 未修复, 本文记录问题和修复方向. 适用 `tailscale` `v1.104.2`, 所有构建目标的相关文件相同(见 `tailscale-firmware-files.md`)
2. 与本项目补丁无关: 触发问题的 `tailscale` 接口由上游的"自动配置防火墙"按钮创建(见 4.2). `tailscale-subnet-guard`(下称守卫)只读取 table 52 和 main, 只增删自己的 pref 1295 规则

## 2. 背景

`tailscaled` 运行时向内核写入下面的内容, 它们不在任何配置文件里:

1. table 52(`ip route show table 52`, `ip -6 route show table 52`): 经 `tailscale0` 的路由, 包括每个对端的 tailnet IPv4 `/32`, MagicDNS 地址, 启用 `accept_routes` 时的对端子网, IPv6 的 `fd7a:115c:a1e0::/48` 和 MagicDNS 地址
2. `tailscale0` 上的地址: 本机的 tailnet IPv4 `/32`, tailnet IPv6 `/128`, 另有 link-local 地址

ip rule 按 pref 从小到大依次查, 查不到匹配的路由就继续下一条. IPv4 和 IPv6 各有一套, 规则相同:

| pref | 规则 | 来源 | 作用 |
|------|------|------|------|
| 1295 | `to <本地网段> lookup main suppress_prefixlength 0` | 项目 | 守卫在接收的子网与该本地网段重叠时添加(见 `tailscale-firmware-files.md` 3.3), 使本地具体路由优先于 table 52 |
| 5210, 5230, 5250 | 带 tailscaled 标记(`fwmark 0x80000/0xff0000`)的包依次查 main, default, 否则 unreachable | tailscaled | 保护 tailscaled 自己的流量, 与本问题无关 |
| 5270 | `lookup 52` | tailscaled | 其余包再查 table 52 |
| 32766 | `lookup main` | 系统 | 普通路由, 含默认路由 |

## 3. 现象

触发: 满足 5.1 的条件时执行 `/etc/init.d/network restart`, 局域网和 Wi-Fi 中断数秒后恢复.

1. `tailscale0` 先变为 DOWN, 随后回到 UP, 设备没有被重建, ifindex 不变
2. table 52 的 IPv4 和 IPv6 路由全部消失, `tailscale0` 上的 tailnet 地址(IPv4 `/32`, IPv6 `/128`)全部消失, 只剩 link-local 地址
3. netifd 启动时清空全部 ip rule 再建回系统规则, `tailscaled` 随即补回 5210 到 5270. 守卫的 1295 规则随重叠消失被删除
4. `tailscaled` 和守卫的进程号不变, `tailscale status` 仍列出对端, `tailscale ping` 仍通(走 magicsock 的 UDP, 不经 table 52)
5. 内核路径不通: 发往对端的包(本机发出的, 或经本机转发的局域网主机的)在 pref 5270 的 table 52 里没有路由, 落到 pref 32766 的 main, 命中默认路由并发给默认网关, 到不了对端. `ip route get <对端 tailnet 地址>` 显示 `via <默认网关> dev <LAN 口>`, 不是 `dev tailscale0 table 52`. 以本机 tailnet 地址为源的包返回 `Network unreachable`(`ip route get <对端 tailnet 地址> from <本机 tailnet 地址>`), 本机无法回复对端. 局域网和 ZeroTier 不受影响
6. 状态不会自行恢复, table 52 和 tailnet 地址一直缺失

`tailscale0` 是 tun 设备, 正常运行时 `ip link` 的 state 显示 UNKNOWN(flags 含 UP), 本文称为 UP, state 为 DOWN 才是被关闭.

## 4. 原因

### 4.1 因果链

1. `network restart` 沿用 rc.common 的 stop 再 start, `/etc/init.d/network` 的 `stop_service` 依次执行 `/sbin/wifi down`, `ifdown -a`, `sleep 1`
2. 配置里有 `network.tailscale`(`proto none`, `device tailscale0`), netifd 管理着 `tailscale0`: `ifdown -a` 使它变为 DOWN, netifd 重新启动后接口再 up
3. 网卡 DOWN 时内核删除 table 52 的路由和 `tailscale0` 的 IPv6 地址. 不经 netifd, 直接 `ip link set tailscale0 down` 再 `up` 同样如此, IPv4 `/32` 保留. `network restart` 期间 IPv4 tailnet 地址也被清掉
4. 接口 up 后内核不恢复路由和地址, `tailscaled` 也不重新写入: 它只对自身配置的变化(对端增减, `accept_routes` 开关等)做增量更新. table 52 为空时开启 `accept_routes` 只新增子网路由, 不补回对端的 `/32` 路由

### 4.2 补充说明

1. `tailscale` 接口的来源: 上游 `luci-app-tailscale-community` 的"自动配置防火墙"按钮(`tailscale.uc` 的 `setup_firewall`, 见 `tailscale-firmware-files.md` 4.1)用 UCI 创建 `network.tailscale` 并放进防火墙区域 `tailscale`. 固件的出厂配置和本项目的脚本不创建它
2. 同类现象: 对运行中的服务执行 `/etc/init.d/tailscale start`, init 脚本先执行 `tailscaled --cleanup`, 进程不重启, `tailscale0` 的 tailnet 地址, table 52 的 IPv4 路由, netfilter 的 `ts-*` 链被清掉, 内核路径不通, `tailscale restart` 恢复. 上游 `tailscale-settings` 因此不对运行中的服务执行 `start`

## 5. 影响范围

### 5.1 触发条件(同时满足)

1. `tailscaled` 在运行
2. 存在 netifd 管理的 `tailscale` 接口(见 4.2 第 1 点)
3. 执行 `network restart`: LuCI 的"系统 → 启动项"里 network 的"重启", 命令行 `/etc/init.d/network restart`, 或其他调用它的脚本

让 `tailscale0` 单独变为 DOWN 再 UP(`ifdown tailscale` 再 `ifup tailscale`, 或 `ip link set tailscale0 down` 再 `up`)同样清空 table 52, ip rule 保持不变.

### 5.2 不触发

1. 整机重启: 网络先于 tailscale 起来(`S20network`, `S80tailscale`), table 52, 规则和 tailnet 地址由新启动的 `tailscaled` 建立, 开机后内核路径可用
2. tailscale 没有运行(table 52 本来为空), 或没有 `tailscale` 接口(方案 A 的配置, `network restart` 不触碰 `tailscale0`)
3. `network reload`(包括新增或删除无关接口, 修改 `network.tailscale` 自己的选项)和 `firewall reload`: 不重建 `tailscale0`, table 52, 地址和规则不变. "自动配置防火墙"的后台脚本(`tailscale-setup-firewall`)执行的就是这两个 reload

## 6. 恢复办法

1. `/etc/init.d/tailscale restart`: 重启 `tailscaled` 和守卫, 重建 `tailscale0`, table 52, 5210 到 5270 规则, tailnet 地址和 netfilter 链, 守卫的 1295 规则在路由回来后补回. 重启期间 netifd 的 `tailscale` 接口随设备重建 down 再 up 一次, 防火墙重载一次
2. 整机重启
3. 只让 `tailscale0` 变为 DOWN 再 UP 时: `tailscale down` 再 `tailscale up` 恢复 table 52 和地址
4. 不能完整恢复: `network restart` 之后的 `tailscale down` 再 `tailscale up` 只恢复 table 52 的路由, 不恢复 tailnet 地址; `network reload`, `firewall reload`, `tailscale-settings reload` 不恢复; 对运行中的服务执行 `/etc/init.d/tailscale start` 反而清掉地址和 table 52 的 IPv4 路由(见 4.2 第 2 点)

## 7. 修复方向(未决定, 未实施)

1. 方案 A, 让 netifd 不再管理 `tailscale0`: 删除 `network.tailscale`, 防火墙区域 `tailscale` 去掉 `network` 引用并改为 `list device 'tailscale0'`, `ifdown -a` 就碰不到它
   1. 效果: `network restart`, `network reload`, `firewall reload`, 新增或删除无关接口时, `tailscale0` 不产生链路事件, table 52 和 tailnet 地址保持不变. netifd 清空的 ip rule 中, 5210 到 5270 由 `tailscaled` 随即补回, 1295 随 LAN 路由消失被删除, LAN 恢复后由守卫约 1 秒补回. fw4 的区域规则仍匹配 `tailscale0`, flowtable 的 `devices` 列表不再包含它, 其余规则相同
   2. 迁移: 在 tailscale 运行时删除 `network.tailscale` 并 reload, netifd 把该接口 down, table 52 被清空, 需要 `/etc/init.d/tailscale restart` 恢复
   3. 代价: 上游"自动配置防火墙"按钮在没有 `network.tailscale` 时会重新创建接口, 并给区域补上 `network` 引用(保留已有的 `device`), 即撤销方案 A, 需要构建时给 `tailscale.uc` 打补丁, 或约定不点这个按钮. 已有设备的 `network` 和 `firewall` 配置(含备份)要手工改
2. 方案 B, hotplug 自动恢复: `tailscale` 接口 up 后发现 table 52 为空就执行 `tailscale restart`. 它会让 `tailscale0` 重新创建, 再次触发接口 up, 需要防抖避免循环, 复杂度最高
3. 方案 C, 约定: 改网络配置后用 `network reload`, 不用 `restart`. 不改固件, 拦不住别人和脚本

## 8. 设备上核对

```sh
# 1. table 52 路由条数, tailscale 运行时大于 0, 触发后变为 0
ip route show table 52 | wc -l
ip -6 route show table 52 | wc -l

# 2. tailscale0 上的地址, 运行时有 100.x 的 IPv4 /32 和 fd7a:115c:a1e0:: 的 IPv6 /128, 触发后只剩 fe80:: 地址
ip -o addr show dev tailscale0

# 3. 是否有 netifd 管理的 tailscale 接口(输出 proto 和 device), 以及防火墙里引用它的区域
uci show network.tailscale
uci show firewall | grep -i tailscale

# 4. 规则, tailscale 运行时有 5210 5230 5250 5270, 另有重叠时才出现的 pref 1295 规则
ip rule show

# 5. 内核路径对 tailnet 对端的判定, 正常时为 dev tailscale0 table 52, 触发后经默认网关
ip route get <对端 tailnet 地址>
```
