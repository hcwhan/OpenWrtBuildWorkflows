
# Tailscale 运行时执行 `network restart`, 路由表 52 被清空且不恢复

`tailscaled` 运行时执行 `/etc/init.d/network restart`, netifd 把 `tailscale0` 关闭后重新拉起, `tailscale0` 上的 tailnet 地址和路由表 52 的全部路由被清掉, `tailscaled` 不重新写入. 此后 `tailscale0` 仍为 UP, `tailscale status` 和 `tailscale ping` 仍正常, 发往 tailnet 的内核路径流量不通, 直到执行 `/etc/init.d/tailscale restart` 或整机重启.

## 1. 说明

1. 状态: 未修复, 修复方向见第 7 节. 本文只记录问题
2. 范围: 所有构建目标的 tailscale 相关文件相同(见 `tailscale-firmware-files.md`), 是否触发取决于设备上的配置(见第 5 节)
3. 适用版本: `tailscale` `v1.104.2`
4. 与本项目补丁的关系: 问题不是本项目补丁引入的. `tailscale-subnet-guard` 只读取 table 52 和 main, 并在重叠消失后删除自己的规则(见 2.3); 触发问题的 `tailscale` 接口由上游的"自动配置防火墙"按钮创建(见 4.2 第 1 点)

## 2. 背景

### 2.1 路由表和规则

路由表(table)是"去某个地址走哪块网卡"的清单, 系统自带 `main`, `tailscaled` 另建专用表 `52`. 规则(`ip rule`)决定包依次查哪些表, 按 pref 从小到大, 查不到匹配的路由就继续下一条, 规则是全局的, 不属于任何网卡.

### 2.2 table 52 和 tailscale0 的内容

`tailscaled` 运行时把下面这些路由写进 table 52(`ip route show table 52`, `ip -6 route show table 52`), 并把本机的 tailnet 地址配在 `tailscale0` 上. 它们只存在于内核, 不在任何配置文件里:

```text
100.x.y.z dev tailscale0              每个对端的 tailnet IPv4 地址, 每个对端一条
100.100.100.100 dev tailscale0        MagicDNS 地址
<对端子网> dev tailscale0             accept_routes 接受的对端子网路由(只在启用时出现)
fd7a:115c:a1e0::/48 dev tailscale0    IPv6: tailnet 网段
fd7a:115c:a1e0::53 dev tailscale0     IPv6: MagicDNS 地址
```

`tailscale0` 上的地址: 本机的 tailnet IPv4 `/32`(`100.x.y.z`), tailnet IPv6 `/128`(`fd7a:115c:a1e0::...`), 另有 link-local 地址.

### 2.3 相关的 ip rule

IPv4 和 IPv6 各有一套, 规则相同:

| pref | 规则 | 来源 | 作用 |
|------|------|------|------|
| 1295 | `to <本地网段> lookup main suppress_prefixlength 0` | 项目 | 只在接收的子网与该本地网段重叠时存在, 使本地具体路由优先于 table 52 |
| 5210, 5230, 5250 | 带 tailscaled 标记(`fwmark 0x80000/0xff0000`)的包依次查 main, default, 否则 unreachable | tailscaled | 保护 tailscaled 自己的流量, 与本问题无关 |
| 5270 | `lookup 52` | tailscaled | 其余包再查 table 52 |
| 32766 | `lookup main` | 系统 | 普通路由, 含默认路由 |

pref 1295 的规则由 `tailscale-subnet-guard` 在运行时按需添加, 不在配置文件里(见 `tailscale-firmware-files.md` 3.3). 重叠依赖 table 52 里的子网路由: table 52 被清空后重叠消失, 守卫删除规则, 守卫进程不变; `tailscale restart` 恢复路由后约 1 秒补回.

## 3. 现象

触发步骤: `tailscaled` 在运行, 设备上有 netifd 管理的 `tailscale` 接口(见 4.2 第 1 点), 执行 `/etc/init.d/network restart`.

1. `tailscale0` 先变为 DOWN, 随后回到 UP. 设备没有被重建, ifindex 不变
2. table 52 的 IPv4 和 IPv6 路由全部消失
3. `tailscale0` 上的 tailnet 地址(IPv4 `/32`, IPv6 `/128`)全部消失, 只剩 link-local 地址
4. netifd 重新启动时清空全部 ip rule(含 `local`, `main`, `default` 和 tailscaled 的 5210 到 5270), 再建回系统规则; `tailscaled` 随即重新添加 5210, 5230, 5250, 5270. 守卫的 1295 规则随重叠消失被删除
5. `tailscaled` 和守卫的进程号不变, `tailscale status` 仍列出对端, `tailscale ping` 对端仍通(走 magicsock 的 UDP, 不经 table 52)
6. 内核路径不通: `ip route get <对端 tailnet 地址>` 命中默认路由(`via <默认网关> dev <LAN 口>`), 不是 `dev tailscale0 table 52`; `ip route get <对端 tailnet 地址> from <本机 tailnet 地址>` 返回 `Network unreachable`; 本机 ping 对端不通
7. 局域网和 Wi-Fi 在命令执行期间中断, 之后恢复; ZeroTier 地址保持
8. 日志有 `Interface 'tailscale' is now down`, `Network device 'tailscale0' link is down`, `firewall: Reloading firewall due to ifup of tailscale (tailscale0)`
9. 状态不会自行恢复: table 52 和 tailnet 地址一直缺失. `network reload`, `firewall reload`, `tailscale-settings reload` 都不恢复它们

`tailscale0` 是 tun 设备, 正常运行时 `ip link` 的 state 显示 UNKNOWN(flags 含 UP), 本文称为 UP, state 为 DOWN 才是被关闭.

## 4. 原因

### 4.1 因果链

| # | 环节 | 依据 |
|---|------|------|
| 1 | `network restart` 的 stop 阶段执行 `ifdown -a` | `/etc/init.d/network` 的 `stop_service`: `/sbin/wifi down`, `ifdown -a`, `sleep 1`; 没有自定义 `restart`, 沿用 rc.common 的 stop 加 start |
| 2 | netifd 管理着 `tailscale0` | 配置里有 `network.tailscale`(`proto none`, `device tailscale0`) |
| 3 | `tailscale0` 被关闭后重新拉起 | `ifdown` 使 `tailscale0` 变为 DOWN, netifd 重新启动后接口再 up, 日志有 `ifup of tailscale` |
| 4 | 网卡 DOWN 时内核删除 table 52 的路由和 `tailscale0` 的 IPv6 地址 | 不经 netifd, 直接 `ip link set tailscale0 down` 再 `up`, table 52 同样清空, IPv6 tailnet 地址消失, IPv4 `/32` 保留 |
| 5 | `network restart` 期间 IPv4 tailnet 地址也被清掉 | `network restart` 之后 `tailscale0` 只剩 link-local 地址 |
| 6 | 接口 up 后内核不恢复路由和地址 | table 52 和地址保持缺失 |
| 7 | `tailscaled` 不重新写入 | `tailscaled` 只对自身配置的变化(对端增减, `accept_routes` 开关等)做增量更新, 不因内核里的路由和地址被删除而重新写入: table 52 为空时开启 `accept_routes` 只新增子网路由, 不补回对端的 `/32` 路由; 进程号不变 |

### 4.2 补充说明

1. `tailscale` 接口从哪来: 上游 `luci-app-tailscale-community` 的"自动配置防火墙"按钮(`tailscale.uc` 的 `setup_firewall`, 见 `tailscale-firmware-files.md` 4.1)用 UCI 创建 `network.tailscale`(`proto none`, `device tailscale0`), 并把它放进防火墙区域 `tailscale`. 固件的出厂配置和本项目的脚本不创建这个接口
2. 同类现象: 对运行中的服务执行 `/etc/init.d/tailscale start` 时, init 脚本先执行 `tailscaled --cleanup`, 而进程不重启: `tailscaled` 和守卫的进程号不变, `tailscale0` 的 tailnet 地址, table 52 的 IPv4 路由, netfilter 的 `ts-*` 链被清掉, table 52 的 IPv6 路由和 5210 到 5270 规则保留. 节点仍回答 `tailscale status` 和 `tailscale ping`, 内核路径不通, `tailscale restart` 恢复. 上游 `tailscale-settings` 的注释描述了同样的结果, 所以它不对运行中的服务执行 `start`. 触发方式不同, 同样是内核状态被外部清掉, 守护进程不修复

## 5. 影响范围

### 5.1 触发条件(三个同时满足)

1. `tailscaled` 在运行
2. 存在 netifd 管理的 `tailscale` 接口(见 4.2 第 1 点)
3. 执行 `network restart`: LuCI 的 系统, 启动项 里 network 的"重启"(调用 `luci.setInitAction` 的 `restart`, 即 stop 加 start), 命令行 `/etc/init.d/network restart`, 或其他调用它的脚本

让 `tailscale0` 单独变为 DOWN 再 UP 的操作(`ifdown tailscale` 加 `ifup tailscale`, `ip link set tailscale0 down` 加 `up`)同样清空 table 52, ip rule 保持不变.

### 5.2 不触发

1. 整机重启: 开机顺序为 `S19firewall`, `S20network`, `S70tailscale-boot-gate`, `S80tailscale`, `S99tailscale-settings`, 网络先于 tailscale 起来, table 52, 规则和 tailnet 地址由新启动的 `tailscaled` 建立, 开机后内核路径可用
2. tailscale 没有运行: table 52 本来为空
3. 没有 `tailscale` 接口(方案 A 的配置): `network restart` 不触碰 `tailscale0`, table 52 和 tailnet 地址保持不变
4. `network reload`(含配置没有改动, 新增或删除无关接口, 修改 `network.tailscale` 自己的选项)和 `firewall reload`: 不重建 `tailscale0`, table 52, 地址和规则保持不变. LuCI 的"自动配置防火墙"的后台脚本(`tailscale-setup-firewall`)执行的就是这两个 reload

### 5.3 后果

`tailscaled` 运行但 table 52 为空, tailnet 地址丢失时:

1. 本机发往 tailnet 对端的包: pref 5210 到 5250 只匹配带标记的包, 不匹配; pref 5270 查 table 52 没有路由, 继续; pref 32766 查 main, 命中默认路由, 包发给默认网关, 到不了对端
2. 以本机 tailnet 地址为源的包没有可用路由(`Network unreachable`), 本机无法回复对端
3. 局域网主机发往对端的包(经本机转发): `ip route get <对端> from <局域网主机地址> iif <LAN 口>` 命中默认路由, 不进 `tailscale0`
4. 局域网和 ZeroTier 不受影响

难发现: `tailscale0` 为 UP, `tailscale status` 正常列出对端, `tailscale ping` 正常. 只有 `ip route show table 52` 为空, `ip addr show tailscale0` 没有 tailnet 地址, 或实际访问不通时才能发现.

## 6. 恢复办法

1. `/etc/init.d/tailscale restart`: 重启 `tailscaled` 和守卫, `tailscale0` 被重新创建, table 52, 5210 到 5270 规则, tailnet 地址, netfilter 链全部重建, 守卫的 1295 规则在路由回来后补回, 内核路径恢复. 重启期间 netifd 的 `tailscale` 接口随设备重建 down 再 up 一次, 防火墙重载一次
2. 整机重启
3. 只让 `tailscale0` 变为 DOWN 再 UP 时(`ifdown tailscale` 加 `ifup tailscale`): `tailscale down` 加 `tailscale up` 恢复 table 52 和地址
4. 不能完整恢复的操作:
   1. `network restart` 之后执行 `tailscale down` 加 `tailscale up`: 恢复 table 52 的路由, 不恢复 tailnet 地址, 内核路径仍不通
   2. `network reload`, `firewall reload`, `tailscale-settings reload`: 不恢复
   3. 对运行中的服务执行 `/etc/init.d/tailscale start`: 不是恢复办法, 反而清掉地址和 table 52 的 IPv4 路由(见 4.2 第 2 点)

## 7. 修复方向(未决定, 未实施)

1. 方案 A, 让 netifd 不再管理 `tailscale0`: 删除 `network.tailscale`, 防火墙区域 `tailscale` 去掉 `network` 引用, 改为 `list device 'tailscale0'`, 这样 `ifdown -a` 碰不到它
   1. 效果: `network restart` 时 `tailscale0` 不产生链路事件, table 52 和 tailnet 地址保持不变, 内核路径保持可用. netifd 清空的 ip rule 中, 5210 到 5270 由 `tailscaled` 随即补回, 1295 随 LAN 路由消失被删除, LAN 恢复后由守卫约 1 秒补回
   2. 效果: `network reload`, `firewall reload`, 新增或删除无关接口后, table 52 与规则保持不变
   3. 效果: fw4 的区域规则仍匹配 `tailscale0`(`input_tailscale` 等链存在), fw4 flowtable 的 `devices` 列表不再包含 `tailscale0`, 其余规则相同
   4. 迁移: 在 tailscale 运行时删除 `network.tailscale` 并 reload, netifd 把该接口 down, table 52 被清空, 需要 `/etc/init.d/tailscale restart` 恢复
   5. 代价: 上游的"自动配置防火墙"按钮在没有 `network.tailscale` 时会重新创建接口, 并给区域补上 `network` 引用(保留已有的 `device`), 即撤销方案 A, 需要构建时给 `tailscale.uc` 打补丁, 或约定不点这个按钮; 已有设备的 `network` 和 `firewall` 配置(含备份)要手工改
2. 方案 B, hotplug 自动恢复: `tailscale` 接口 up 后发现 table 52 为空就恢复. 恢复手段是 `tailscale restart`, 它会让 `tailscale0` 重新创建, 再次触发接口 up, 需要防抖避免循环, 复杂度最高
3. 方案 C, 约定: 改网络配置后用 `network reload`, 不用 `restart`. `reload` 不重建 `tailscale0`, table 52 保持. 不改固件, 拦不住别人和脚本
4. 方案 D, 只记录: 即本文. 恢复办法见第 6 节

## 8. 设备上核对

```sh
# 1. table 52 路由条数, tailscale 运行时大于 0, 重启网络后变为 0 即触发了本问题
ip route show table 52 | wc -l
ip -6 route show table 52 | wc -l

# 2. tailscale0 上的地址, tailscale 运行时有 100.x 的 IPv4 /32 和 fd7a:115c:a1e0:: 的 IPv6 /128, 触发本问题后只剩 fe80:: 地址
ip -o addr show dev tailscale0

# 3. 是否有 netifd 管理的 tailscale 接口, 有则输出 proto 和 device
uci show network.tailscale

# 4. 防火墙里引用该接口或设备的区域
uci show firewall | grep -i tailscale

# 5. 规则, tailscale 运行时有 5210 5230 5250 5270
#    另有 pref 1295 的 to <本地网段> 规则, 只在接收的子网与本地网段重叠时出现
ip rule show

# 6. 内核路径对 tailnet 对端的判定, 正常时为 dev tailscale0 table 52, 触发本问题后经默认网关
ip route get <对端 tailnet 地址>

# 7. tailscale 自己的视角, 触发本问题后仍正常
tailscale status | head -n 5

# 8. 开机顺序, 输出 S19firewall S20network S70tailscale-boot-gate S80tailscale S99tailscale-settings
#    (service_enabled 为 0 时开机会删掉 S80tailscale)
ls /etc/rc.d | grep -E '^S[0-9]+(network|firewall|tailscale)'
```

触发方式(局域网和 Wi-Fi 中断数秒), 在 tailscale 运行且有 `network.tailscale` 的设备上:

```sh
/etc/init.d/network restart
# 局域网恢复后重新连接, 再执行:
ip route show table 52 | wc -l   # 0
ip -o addr show dev tailscale0   # 只有 fe80:: 地址
ip -o link show tailscale0       # state 为 UNKNOWN(flags 含 UP), 不是 DOWN
/etc/init.d/tailscale restart    # 恢复
```
