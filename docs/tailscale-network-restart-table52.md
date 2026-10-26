
# Tailscale 运行时执行 `network restart`, 路由表 52 被清空且不恢复

`tailscaled` 运行时重启网络, 它写进内核的"去 tailnet 的路由"会被删光, 实测 41 s 内没有任何组件把路由写回. `tailscale0` 仍是 UP, `tailscale status` 仍正常, 但发往 tailnet 的流量预期不通(推演).

## 1. 说明

1. 状态: 未修复, 修复方向未决定(见第 8 节). 本文只记录问题
2. 范围: 三个构建目标(`build_AX3600`, `build_NX30Pro`, `build_x86`)的 tailscale 相关文件相同(见 `tailscale-firmware-files.md`), 是否触发取决于设备上的配置(见第 6 节)
3. 依据: NX30Pro 上的实测, 三台设备上的只读查询, 本机隔离环境复现, 设备上的 `/etc/init.d/network`, 上游源文件
4. 整理日期: 2026-10-26
5. 版本: 实测用 `tailscale` `v1.104.2`, 其他版本没测
6. 标记: `实测` 在设备或隔离环境里观察到, `读取` 从设备上的文件或上游源文件读到, `推演` 按规则逻辑得出而没有实测, `推测` 没有直接证据
7. 与本项目补丁的关系: 问题不是本项目补丁引入的. 项目的 ip rule 由 `tailscale-subnet-guard` 按需添加(见 2.3), 它只读取 table 52 和 main, 与触发条件无关(推演). 触发问题的 `tailscale` 接口由上游的"自动配置防火墙"按钮创建(见 4.2)

## 2. 背景

### 2.1 几个词

1. tailnet: Tailscale 虚拟网络. 节点地址段 IPv4 `100.64.0.0/10`, IPv6 `fd7a:115c:a1e0::/48`
2. `tailscale0`: `tailscaled` 创建的虚拟网卡, 发往 tailnet 的包从它出去
3. 路由表(table): "去某个地址走哪块网卡"的清单. 系统自带 `main`(局域网路由, 默认路由等), `tailscaled` 另建专用表 `52`
4. 规则(`ip rule`): 决定一个包依次查哪些表, 按编号(pref)从小到大, 一张表里查不到匹配的路由就继续下一条规则. 规则是全局的, 不属于任何网卡
5. netifd: OpenWrt 管理网络接口的守护进程, LuCI 的"接口"页面背后就是它

### 2.2 table 52 的内容

`tailscaled` 运行时把下面这些路由写进 table 52(设备上用 `ip route show table 52` 查看). 这些路由只存在于内核, 不在任何配置文件里:

```text
100.64.4.10 dev tailscale0      对端的 tailnet 地址, 每个对端一条
100.100.100.100 dev tailscale0  MagicDNS 地址
10.0.0.0/11 dev tailscale0      accept_routes 接受的对端子网路由(只在启用时出现)
```

数量: x86 设备上 tailscale 运行时, v4 有 8 条, v6 有 2 条(读取). NX30Pro 实测前 v4 有 10 条, v6 有 2 条(`accept_routes` 开启, 含接受的子网路由 `10.0.0.0/11` 和 `192.168.4.0/24`).

### 2.3 相关的 ip rule

| pref | 规则 | 来源 | 作用 |
|------|------|------|------|
| 1295 | `to <本地网段> lookup main suppress_prefixlength 0` | 项目 | 只在接收的子网与该本地网段重叠时存在. 先查 main 但忽略默认路由, 本地具体路由优先 |
| 5210, 5230, 5250 | 带 tailscaled 标记(fwmark `0x80000/0xff0000`)的包依次查 main, default, 否则 unreachable | tailscaled | 保护 tailscaled 自己的流量, 与本问题无关 |
| 5270 | `lookup 52` | tailscaled | 其余包再查 table 52 |
| 32766 | `lookup main` | 系统 | 普通路由, 含默认路由 |

项目的规则由 `tailscale-subnet-guard` 在 `tailscale` 运行期间按需添加, 是运行时的 ip rule, 不在配置文件里(见 `tailscale-firmware-files.md` 3.4). 它每 5 秒按 table 52 和 main 的现状对账一次: table 52 被清空时(本问题)没有重叠, 规则在下一轮被删除, 路由恢复后重新添加(推演). tailscaled 的 4 条规则只在它运行时存在: tailscale 未运行的设备上没有 5210 到 5270(读取).

## 3. 现象

触发步骤: `tailscaled` 在运行, 设备上有 netifd 管理的 `tailscale` 接口(见 4.2), 执行 `/etc/init.d/network restart`(LuCI: 系统, 启动项, network 一行的"重启").

NX30Pro 实测(2026-10-25 01:10, 详见 5.1), 时间从 `network restart` 开始计:

| 时间 | 实测 |
|------|------|
| 重启前 | table 52 有 10 条 v4 和 2 条 v6 路由, `tailscale0` 为 UP |
| T+2 s | `network restart` 刚返回(耗时约 2 s). `tailscale0` 为 DOWN, table 52 为 0 / 0, 5 个目的地(局域网 4 个, 公网 1 个)返回 `Network unreachable`, ZeroTier 正常(局域网接口也在重建) |
| T+3 s | `tailscale0` 回到 UP, 局域网路由恢复, table 52 仍为 0 / 0 |
| T+5 s 到 T+33 s | 7 个采样点(5, 6, 8, 11, 15, 23, 33 s), table 52 一直为 0 / 0 |
| T+33 s 到 T+41 s | 执行 `network reload`, 2 个采样点, table 52 仍为 0 / 0 |

`tailscale0` 是 tun 设备, 正常运行时 `ip link` 的 state 显示 UNKNOWN(flags 含 UP), 本文称为 UP, state 为 DOWN 才是被关闭.

同时观察到:

1. 规则: v4 和 v6 在所有采样点都不变, 包括 tailscaled 的 5210, 5230, 5250, 5270(设备上的规则见 5.1)
2. `tailscaled` 进程号不变(7717). 日志只有 `Rebind; defIf="br-lan.1"` 和 `firewall: Reloading firewall due to ifup of tailscale (tailscale0)`
3. `tailscale status` 仍列出对端节点
4. 6 个目的地(局域网 2 个网段, ZeroTier, 公网)的路由判定: T+3 s 起的 10 个采样点(含 `network reload` 的 2 个)逐条与重启前相同

观察窗口到 T+41 s 为止, 之后测试回滚, 更久的情况没有观察.

## 4. 原因

### 4.1 因果链

```text
network restart
 → stop 阶段执行 ifdown -a, netifd 关闭它管理的所有接口
 → 其中有接口 tailscale(设备 tailscale0), tailscale0 被关闭
 → 内核: 网卡 down 时, 经过它的路由全部删除, table 52 被清空
 → start 阶段 netifd 重新拉起接口, tailscale0 回到 UP
 → netifd 只恢复它配置里的内容, table 52 的路由不在配置里, 没人写回
 → tailscaled 进程没有重启, 也没有重写路由
```

| # | 环节 | 依据 | 标记 |
|---|------|------|------|
| 1 | `network restart` 的 stop 阶段执行 `ifdown -a` | `/etc/init.d/network` 第 37 到 41 行 `stop_service`: `/sbin/wifi down`, `ifdown -a`, `sleep 1`. 该脚本没有自定义 `restart`, 沿用 rc.common 的 stop 加 start | 读取 |
| 2 | netifd 管理着 `tailscale0` | 配置里有 `network.tailscale`(`proto none`, `device tailscale0`). x86 上 `ifstatus tailscale` 为 up, 设备 `tailscale0` | 读取 |
| 3 | `tailscale0` 被关闭后重新拉起 | NX30Pro: T+2 s 为 DOWN, T+3 s 回到 UP, 日志有 `ifup of tailscale (tailscale0)` | 实测 |
| 4 | 网卡 down 时路由被内核删除, 规则不受影响 | 隔离环境: `ip link set ts0 down` 后 table 52 从 2 + 1 条变为 0 + 0 条, 规则不变(见 5.2). 设备上 table 52 同样变为 0 / 0, tailscaled 的 4 个 pref(5210, 5230, 5250, 5270)的规则全在 | 实测 |
| 5 | 接口 up 后路由不回来 | NX30Pro: T+3 s `tailscale0` 回到 UP, table 52 仍为 0 / 0. 隔离环境第 3 步相同 | 实测 |
| 6 | `tailscaled` 没有重写路由 | 进程号不变, 41 s 内 table 52 一直为空 | 实测 |
| 7 | 不重写的内部原因: `tailscaled` 的记录里这些路由仍是已安装状态, 所以不重装 | 没有直接证据 | 推测 |

### 4.2 `tailscale` 接口从哪来

上游 `luci-app-tailscale-community` 的"自动配置防火墙"按钮(`tailscale.uc` 的 `setup_firewall`, 见 `tailscale-firmware-files.md` 4.4 第 6 项)用 UCI 创建 `network.tailscale`(`proto none`, `device tailscale0`), 并把它放进防火墙区域 `tailscale`. 设备上的现状(2026-10-26, 读取): NX30Pro 和 x86 有该接口和区域, AX3600 没有.

### 4.3 上游注释里的同类现象

上游 `tailscale-settings`(master `4e20728`)的 `handle_service_state` 里有一段注释: `tailscaled` 还活着时, `tailscaled --cleanup` 清掉了 `tailscale0` 地址, table 52 路由和 netfilter 规则, 结果是节点"仍能回答 `tailscale status` 和 `tailscale ping`, 但内核里没有可用状态". 与本问题同类: 内核状态被外部清掉, 守护进程仍在运行, 状态没有被修复. 触发方式不同, 那里是 `--cleanup`, 这里是接口 down.

## 5. 证据

### 5.1 NX30Pro 实测(2026-10-25 01:10 到 01:11)

1. 环境: 本项目构建的固件, `tailscale` `v1.104.2`, 设备上有 tailscaled 的 ip rule(pref 5210, 5230, 5250, 5270). 临时把 `service_enabled` 和 `accept_routes` 设为 1 并启动 tailscale, 接受的子网路由 `10.0.0.0/11` 和 `192.168.4.0/24` 在重启前已进入 table 52
2. 步骤: 设备上的后台脚本依次执行: 启动 tailscale, 记录重启前, `network restart`, 多次采样, `network reload`, 采样, 回滚(停止并禁用 tailscale, 恢复 UCI). 回滚后 table 52 为 0 条, `tailscale0` 不存在, `S80tailscale` 链接 0 个
3. 采样项: 规则优先级(v4, v6), table 52 路由条数(v4, v6), `tailscale0` 状态, 6 个目的地的 `ip route get`
4. 结果: 见第 3 节

### 5.2 隔离环境复现(2026-10-26)

1. 方法: 本机 WSL 里用 `unshare -rn` 建临时网络命名空间, 两个 dummy 网卡(`ts0` 代表 `tailscale0`, `lan0` 代表局域网口), 手工添加 tailscaled 的规则(pref 5210, 5230, 5250, 5270, v4 和 v6 各一套)和 table 52 路由, 默认路由经 `192.168.4.1`. table 52 里只有 tailnet 地址段内的路由, 与本地网段没有重叠, `tailscale-subnet-guard` 不加规则(每一步都用它自己的 awk 对账程序核对, 输出都为空). 命名空间随进程结束销毁, 不涉及设备
2. 结果:

| 步骤 | table 52 路由条数(v4 / v6) | v4 规则 | 发往 `100.64.4.9` 的包 |
|------|----------------------------|---------|------------------------|
| 1 初始 | 2 / 1 | 7 条 | `dev ts0 table 52` |
| 2 `ip link set ts0 down` | 0 / 0 | 不变 | `via 192.168.4.1 dev lan0` |
| 3 `ip link set ts0 up` | 0 / 0 | 不变 | `via 192.168.4.1 dev lan0` |
| 4 重新写入路由(模拟 tailscaled 重装) | 2 / 1 | 不变 | `dev ts0 table 52` |

3. 说明: v4 规则 7 条 = 系统 3 条(0, 32766, 32767)加第 1 点手工添加的 4 条. 隔离环境只证明内核行为: 网卡 down 删路由, up 不恢复, 规则不受影响, 路由判定落到默认路由. netifd 和 tailscaled 的行为以 5.1 的设备实测为准

## 6. 影响范围

### 6.1 触发条件(三个同时满足)

1. `tailscaled` 在运行
2. 存在 netifd 管理的 `tailscale` 接口(见 4.2)
3. 执行 `network restart`: LuCI 的 系统, 启动项 里 network 的"重启", 命令行 `/etc/init.d/network restart`, 或其他调用它的脚本

### 6.2 不触发

1. 整机重启: 开机顺序为 `S19firewall`, `S20network`, `S80tailscale`, 网络先于 tailscale 起来(读取), table 52 由新启动的 `tailscaled` 重建(推演)
2. tailscale 没有运行: table 52 本来为空(NX30Pro 和 AX3600 当前如此, 读取)
3. 没有 `tailscale` 接口: 网络重启碰不到 `tailscale0`(推演, 没有实测, 见第 7 节)

### 6.3 后果(推演, 没有端到端实测)

`tailscaled` 运行但 table 52 为空时, 发往 tailnet 对端地址(如 `100.64.4.9`)的包按规则依次查表. `tailscale-subnet-guard` 在 table 52 为空时没有规则(没有重叠, 见 2.3), 路径是:

1. pref 5210 到 5250: 只匹配带标记的包, 不匹配
2. pref 5270: 查 table 52, 没有路由, 继续
3. pref 32766: 查 main, 命中默认路由, 包发给默认网关(隔离环境里是 `192.168.4.1`), 通常到不了对端

结论: 本机访问 tailnet 对端不通. 对端访问本机, 或通过本机访问本机后面的子网(Subnet Router)时, 回包同理走错, 也不通. 局域网和 ZeroTier 不受影响(实测, 见第 3 节).

### 6.4 为什么难发现

`tailscale0` 为 UP, `tailscale status` 正常列出对端(实测), 看不出异常. 只有 `ip route show table 52` 为空, 或实际访问不通时才能发现.

### 6.5 各设备当前状态(2026-10-26, 读取)

| 设备 | tailscaled | `network.tailscale` | table 52(v4 / v6) | 结论 |
|------|------------|---------------------|-------------------|------|
| x86 | 运行 | 有 | 8 / 2 | 满足触发条件, 预期 `network restart` 会复现(没有在 x86 上实测) |
| NX30Pro | 未运行 | 有 | 0 / 0 | 启用 tailscale 后满足触发条件 |
| AX3600 | 未运行 | 无 | 0 / 0 | 当前不满足触发条件 |

## 7. 没有验证的点

1. 从另一个 tailnet 节点访问本机, 或通过本机访问子网的端到端表现(6.3 是推演)
2. `network reload` 会不会清空 table 52. LuCI 的"保存并应用"(`network` 配置变化触发 `reload_service`, 见 `/etc/init.d/network` 第 28 到 35 行和第 128 行)和"自动配置防火墙"的后台脚本(`tailscale-setup-firewall`)都会执行它. NX30Pro 的第一次测试里 `network reload` 是在 table 52 已空之后执行的, 判断不了. 2026-10-26 在 NX30Pro 上补测了没有改动配置时的 reload, 但用的是 `lo` 上的运行时测试路由, 不是 netifd 管理的 `tailscale0`, 所以这一点仍未回答:
   1. 方法: tailscale 未运行. main 表和 table 52 各加 `203.0.113.0/24 dev lo`(TEST-NET-3, 不影响真实网络), 加规则 `pref 5270 lookup 52`, 并由 `tailscale-subnet-guard` 的 `watch` 维护 `pref 1295 to 203.0.113.0/24` 规则. 执行完整的 `/etc/init.d/network reload`(不是 restart), 每秒采样, 并用 `ip monitor` 记录规则, 路由, 网卡, 地址的变化. 全程有独立的看门狗, 结束后恢复, 测试前后主命名空间快照一致, `/etc/config` 文件的哈希不变
   2. 结果(实测): 共 13 次完整 reload, 返回 0, 没有输出, 用时 0.08 到 0.27 s. 网络现状前后一致(地址, 路由, 规则, 网卡标志, 桥成员, netifd 接口状态, netifd, dnsmasq, hostapd, zerotier-one 等进程号, 无线接口), 接口运行秒数没有倒退, 即没有接口被重启. 另把 reload 拆成 `ubus call network reload` 和 `wifi reload_legacy` 各执行 1 次, 7 条不同形状的测试规则同样不变
   3. 带 `ip monitor` 的 12 次 reload 里, reload 窗口内没有任何规则或路由事件. 其中 10 次落在守卫 5 秒周期的 0.3, 1.0, 1.6, 2.1, 2.5, 2.7, 3.0, 3.9, 4.3, 4.8 s 处(从守卫上一轮对账结束算起), 还同时监视了网卡和地址, 同样 0 个事件. table 52 测试路由, main 测试路由和 pref 5270 规则在所有采样里都在. 即没有改动配置时, reload 对这些对象是空操作(只限本测试的条件)
   4. 未解之处: 第 1 次 reload(没有 `ip monitor`)里, pref 1295 的测试规则在 reload 开始约 1 s 后的采样里已经缺失, 连续 2 次采样(间隔约 1 s)缺失, 之后被 `watch` 补回, 缺失约 2 到 3 s. 同一时间 main 表和 table 52 的测试路由, pref 5270 规则都在. 守卫删除规则成功后一定会记 `del rule` 日志, 日志里没有, 所以不是守卫删的. 系统日志在这段时间除 ssh 登录和守卫记录外没有别的行. 之后的 12 次没有复现, 原因没有查明
   5. 没有测的: netifd 在 reload 时真有配置要应用的情况(LuCI "保存并应用"改了 `network` 配置, 测试期间不允许改设备配置), 以及 `tailscaled` 在主命名空间运行, `tailscale0` 由 netifd 管理时的 reload. 所以 table 52 的真实路由会不会被 reload 清掉仍是未知
3. 重启 tailscale(`/etc/init.d/tailscale restart`)能否恢复 table 52. 没有测过, 上游 `tailscale-settings` 的注释提示对运行中的服务执行 `start`, 或没有理由的 `restart`, 有风险(见 4.3)
4. 4.1 第 7 环("不重写"的内部原因)是推测
5. 没有 `tailscale` 接口(下面的方案 A)时, `network restart` 是否不再清空 table 52
6. 只测了 `tailscale` `v1.104.2`
7. `tailscale-subnet-guard` 与 `network restart` 的配合(2.3: table 52 被清空后规则被删除, 路由恢复后补回). 只在隔离环境里测过规则随 table 52 内容增删, 没有在设备上结合 `network restart` 测过

## 8. 修复方向(未决定, 未实施)

1. 方案 A, 让 netifd 不再管理 `tailscale0`: 删除 `network.tailscale`, 防火墙区域 `tailscale` 改为直接引用设备(`list device 'tailscale0'`), 这样 `ifdown -a` 碰不到它
   1. 好处: 从根上避开(推演, 没有验证)
   2. 代价: 上游的"自动配置防火墙"按钮会重新创建接口, 需要构建时给 `tailscale.uc` 打补丁, 或约定不点这个按钮. 已有设备的 `network` 和 `firewall` 配置(含备份)要手工改
2. 方案 B, hotplug 自动恢复: `tailscale` 接口 up 后发现 table 52 为空就恢复. 风险: 恢复手段(重启 `tailscaled`)会让 `tailscale0` 重新出现, 再次触发接口 up, 需要防抖避免循环. 复杂度最高
3. 方案 C, 约定: 改网络配置后用 `network reload`, 不用 `restart`. 不改固件. 拦不住别人和脚本, `reload` 是否安全只验证了没改配置, 且没有真实 `tailscale0` 的情况, 改了配置时的 reload 和真实 `tailscale0` 都没验证(第 7 节第 2 点)
4. 方案 D, 只记录: 即本文. 目前能确定的恢复办法只有整机重启(推演, 见 6.2 第 1 点), `tailscale restart` 待验证(第 7 节第 3 点)

## 9. 设备上核对

```sh
# 1. table 52 路由条数, tailscale 运行时应大于 0, 重启网络后变为 0 即触发了本问题
ip route show table 52 | wc -l
ip -6 route show table 52 | wc -l

# 2. 是否有 netifd 管理的 tailscale 接口, 有则输出 proto 和 device
uci show network.tailscale

# 3. 防火墙里是否有引用该接口的区域
uci show firewall | grep -i tailscale

# 4. 规则, tailscale 运行时预期有 5210 5230 5250 5270
#    另有 pref 1295 的 to <本地网段> 规则, 只在接收的子网与本地网段重叠时出现
ip rule show

# 5. tailscale 自己的视角, 触发本问题后仍正常
tailscale status | head -n 5

# 6. 开机顺序, 预期 S19firewall S20network S80tailscale
ls /etc/rc.d | grep -E '^S[0-9]+(network|firewall|tailscale)'
```

复现(会短暂中断局域网, NX30Pro 上 T+3 s 已恢复), 在 tailscale 运行且有 `network.tailscale` 的设备上:

```sh
/etc/init.d/network restart
sleep 5
ip route show table 52 | wc -l   # 预期 0
ip -o link show tailscale0       # 预期 state 为 UNKNOWN(flags 含 UP), 不是 DOWN
```
