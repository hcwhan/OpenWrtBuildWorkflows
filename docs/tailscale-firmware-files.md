
# 固件中的 Tailscale 相关文件清单

编译完成后, `tailscale`(GuNanOvO)和 `luci-app-tailscale-community`(Tokisaki-Galaxy)两个来源在固件里提供的文件, 以及每个文件的功能和作用.

## 1. 说明

1. 范围: `build_AX3600`, `build_NX30Pro`, `build_x86` 三个工作流, 三个目标的文件清单相同
2. 依据: 上游 Makefile 与源文件, 本项目补丁脚本, 三份 `.config-*`. 8.1 的部分项在安装固件的设备上核对过, 静态推断的内容已单独标注
3. 整理日期: 2026-10-26
4. 版本:
   1. `tailscale`: GuNanOvO/openwrt-tailscale 标签 `v1.104.2`(固定), 编译的源码为 tailscale/tailscale `v1.104.2`
   2. `luci-app-tailscale-community`: Tokisaki-Galaxy `master`(未固定, 每次构建取最新), 文件清单可能随上游变化
5. 标记: `上游` 原样, `补丁` 上游文件被本项目脚本修改, `项目` 本项目新增
6. 权限: GuNanOvO 包由 Makefile 的 `$(INSTALL_BIN)`/`$(INSTALL_DATA)` 安装, 权限由 Makefile 决定. LuCI 应用由 `luci.mk` 用 `cp -pR` 安装, 权限沿用上游仓库的 git 权限

## 2. 总览

### 2.1 包与来源

| # | 包 | 来源 | 文件数 |
|---|----|------|--------|
| 1 | `tailscale` | [GuNanOvO/openwrt-tailscale](https://github.com/GuNanOvO/openwrt-tailscale) | 6 |
| 2 | `luci-app-tailscale-community` | [Tokisaki-Galaxy/luci-app-tailscale-community](https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community) | 7 |
| 3 | `luci-i18n-tailscale-community-zh-cn` | 同 2, 只构建简体中文 | 2 |

合计 15 个文件(含 1 个符号链接). 三份 `.config-*` 里这三个包均为 `=y`.

### 2.2 文件总表

| # | 路径 | 权限 | 标记 | 作用 |
|---|------|------|------|------|
| 1 | `/usr/sbin/tailscaled` | 0755 | 上游+补丁 | 守护进程, 内置命令行 |
| 2 | `/usr/sbin/tailscale` | 符号链接 | 上游 | 命令行入口, 指向 `tailscaled` |
| 3 | `/etc/init.d/tailscale` | 0755 | 上游+补丁 | 守护进程的 procd 启动脚本, 启停时带动 `tailscale-subnet-guard` |
| 4 | `/etc/init.d/tailscale-subnet-guard` | 0755 | 项目 | 随 tailscale 启停, 按需增删 ip rule, 防子网劫持 |
| 5 | `/etc/config/tailscale` | 0644 | 上游 | UCI 配置 |
| 6 | `/lib/upgrade/keep.d/tailscale` | 0644 | 上游 | sysupgrade 保留清单, 内容为 `/etc/tailscale/` |
| 7 | `/www/luci-static/resources/view/tailscale.js` | 0644 | 上游 | LuCI 页面前端 |
| 8 | `/usr/share/luci/menu.d/luci-app-tailscale-community.json` | 0644 | 上游+补丁 | 菜单注册 |
| 9 | `/usr/share/rpcd/acl.d/luci-app-tailscale-community.json` | 0644 | 上游 | 权限声明 |
| 10 | `/usr/share/rpcd/ucode/tailscale.uc` | 0755 | 上游 | 后端, ubus 对象 `tailscale` |
| 11 | `/etc/init.d/tailscale-settings` | 0755 | 上游 | 把 LuCI 设置应用到 tailscale |
| 12 | `/usr/libexec/tailscale-setup-firewall` | 0755 | 上游 | "自动配置防火墙"的后台执行者 |
| 13 | `/etc/init.d/tailscale-boot-gate` | 0755 | 项目 | 开机时按 `service_enabled` 决定 tailscale 是否自启 |
| 14 | `/usr/lib/lua/luci/i18n/community.zh-cn.lmo` | - | 上游 | 简体中文翻译 |
| 15 | `/etc/uci-defaults/luci-i18n-tailscale-community-zh-cn` | - | 上游 | 首次开机登记语言名 |

权限为 `-` 的两个文件由 `luci.mk` 在构建时生成. 第 6 项由 ImmortalWrt 的构建系统生成, 不是上游 Makefile 安装的, 见 3.6.

## 3. `tailscale` 包(GuNanOvO)

依赖: `ca-bundle`, `kmod-tun`, `ip-full`(均来自 ImmortalWrt 自身). 上游只依赖前两项, `ip-full` 由 `tailscale-subnet-guard-install.patch` 加到 `DEPENDS` 末尾: 3.4 的 IPv6 对账要靠它的 `table` 过滤, BusyBox 自带的 `ip` 不支持, IPv6 会静默不生效.

### 3.1 `/usr/sbin/tailscaled`

> 标记: 上游+补丁 | 权限: 0755

**作用**: 守护进程本体, 已去符号(`-s -w`), 并内置命令行(构建标签 `ts_include_cli`). 负责创建 `tailscale0` 网卡, 连接控制服务器, 与对端建立 WireGuard 隧道(含 NAT 穿透和 DERP 中继), 写 nftables 规则和路由, 通过 unix socket 提供本地 API.

**补丁**: 构建标签在上游 14 个的基础上追加 `ts_omit_flashappliance`, 共 15 个(`feeds-patch/tailscale/omit-flashappliance.patch`, 由 `2.feeds-insert-script.sh` 的 `# tailscale` 段应用). 原因: 仅用 `ts_omit_clientupdate` 时, flash-appliance 的命令行子命令仍会链接 `tailscale.com/clientupdate`, 使 `CanAutoUpdate()` 保持为 true, tailscaled 启动时无法清除已保存的 `AutoUpdate.Apply=true`.

**补丁(版本串)**: 版本串由 `1.104.2-1 (OpenWrt-UPX)` 改为 `1.104.2-1 (OpenWrt)`, 包描述 `TITLE` 里的 `(UPX Compressed)` 一并去掉(`feeds-patch/tailscale/remove-upx-labels.patch`, 由 `2.feeds-insert-script.sh` 的 `# tailscale` 段应用). 原因: 这两处是上游写死的字样, 而本项目构建并未压缩.

**压缩**: 上游 Makefile 只在 `$(TOPDIR)/upx/upx` 存在时才用 UPX 压缩, ImmortalWrt 23.05 和本项目 CI 都没有提供, 所以未压缩. 安装固件的设备上已验证, 见 8.1.

### 3.2 `/usr/sbin/tailscale`

> 标记: 上游 | 类型: 符号链接, 指向 `tailscaled`

**作用**: 同一个二进制以 `tailscale` 名字调用时进入命令行模式(`status`, `login`, `logout`, `set`, `get` 等). LuCI 后端 `tailscale.uc` 和 `tailscale-settings` 都通过它操作守护进程.

### 3.3 `/etc/init.d/tailscale`

> 标记: 上游+补丁 | 权限: 0755 | START=80

**作用**: procd 服务脚本. 启动前和停止时执行 `tailscaled --cleanup`; 读取 `/etc/config/tailscale` 后拼出 `tailscaled --port <port> --state <state_file>`; 用环境变量 `TS_DEBUG_FIREWALL_MODE` 传入防火墙模式; 设置 `TS_NO_LOGS_NO_SUPPORT=true` 关闭日志上传; 异常退出自动重启(respawn).

**补丁**: 末尾追加 `service_started` 和 `service_stopped` 两个钩子, 分别执行 `/etc/init.d/tailscale-subnet-guard start` 和 `stop`, 使 `tailscale` 启停时一并启停 `tailscale-subnet-guard`(`feeds-patch/tailscale/tailscale-subnet-guard-service-hooks.patch`, 由 `2.feeds-insert-script.sh` 的 `# tailscale` 段应用). `rc.common` 在 `start`, `stop`, `restart` 时调用这两个钩子(`start` 在 `start_service` 之后, `stop` 在进程被终止之后); procd 自动重启崩溃的 `tailscaled` 时不会调用, 此时 `tailscale-subnet-guard` 的常驻进程保持运行. 钩子在设备上用替身服务验证过, 还没有在装有本补丁的固件和真实的 `tailscaled` 上验证, 见 3.4 的验证和 8.1 第 5 项.

**自启**: 脚本里没有"是否自启"的配置项, 自启只取决于镜像构建时由 `default_postinst` 生成的 `/etc/rc.d/S80tailscale` 链接. 补丁不涉及自启, 开机时是否保留这个链接由 `luci-app-tailscale-community` 里新增的 `tailscale-boot-gate`(见 4.7)按 `service_enabled` 决定.

### 3.4 `/etc/init.d/tailscale-subnet-guard`

> 标记: 项目 | 权限: 0755 | 无 START, 不生成开机链接 | 源文件: `feeds-patch/tailscale/tailscale-subnet-guard.init`

**作用**: `tailscale` 运行期间, 只有接收到的子网与本地网段重叠时才添加 ip rule, 防止路由表 52(pref 5270)劫持本地网段的流量; 重叠消失或 `tailscale` 停止时删除. 每个被覆盖的本地网段一条, IPv4 和 IPv6 各自独立:

`pref 1295 to <本地网段> lookup main suppress_prefixlength 0`

即先查 main 表并忽略其默认路由, 使该网段的具体本地路由优先于路由表 52. 没有重叠时不添加任何规则. 规则是运行时的 ip rule, 不写入 `/etc/config/network`, LuCI 里看不到, 也不改动配置文件.

**运行方式**:

1. 启停: 没有 START/STOP, 开机时不单独启动, 由 3.3 的钩子随 `tailscale` 启停(`start` 之后启动, `stop` 之后停止, `restart` 先停后启). 也可以手动执行 `/etc/init.d/tailscale-subnet-guard start|stop|restart`
2. 常驻对账: `start` 让 procd 托管一个常驻进程(`/etc/init.d/tailscale-subnet-guard watch`, 异常退出自动重启), 每 5 秒按路由表 52 和 main 表的现状对账一次: 缺则补, 多则删. 添加和删除最多延迟 5 秒
3. 停止: `service_stopped` 先等 1 秒, 再删除全部形如 `pref 1295 to <网段> lookup main suppress_prefixlength 0` 的规则, 不等下一轮. 等这 1 秒是因为 procd 只给 `watch` 主进程发 SIGTERM, 对账管道里的子进程会变成孤儿继续跑完, 其中的 `ip rule add` 可能晚于清理而留下 1 条规则. 一轮对账超过 1 秒(路由数量极大)时仍可能漏掉, 漏掉的规则由下次 `start` 的首轮对账纠正(重叠已消失就删除, 仍在就保留)
4. 日志: 每次增删记一条系统日志, 标签 `tailscale-subnet-guard`, 内容为 `add rule: to <网段>` 或 `del rule: to <网段>`
5. 运行依赖: `ip`(`ip-full`, 由 `tailscale` 包的 `DEPENDS` 带入, 三份配置也已选上), awk, `logger`(BusyBox 自带)

**判定**(IPv4 和 IPv6 各自独立):

1. 接收路由 R: 路由表 52 里的路由, 不含默认路由, `throw`/`blackhole`/`unreachable`/`prohibit` 等特殊路由, 以及落在 tailnet 地址段(`100.64.0.0/10`, `fd7a:115c:a1e0::/48`)内的路由
2. 本地网段 L: main 表里的非默认路由, 同样不含特殊路由. 前缀短于 IPv4 的 /8 或 IPv6 的 /16 的不算: 例如 OpenVPN 的拆分默认路由 `0.0.0.0/1` 加 `128.0.0.0/1` 会与任何 R 重叠, 而 `suppress_prefixlength 0` 抑制不了 /1, 给它们加规则会把 tailnet 的流量也抢到 main
3. L 与任一 R 相等或互相包含, 就对该 L 加规则. R 只覆盖 L 的一部分时, 这一部分主机同样会被劫持, 所以也算
4. "`tailscale` 已启动且开启了接收子网"由路由表 52 的内容隐含: 只有开启接收路由, `tailscale` 才会为对端的子网装路由. 唯一的例外: 出口节点且未允许访问本地网络(LuCI 会强制允许, 只有命令行能设成这样)时, `tailscale` 会把本机的本地网段装成路由表 52 的普通路由, 同样被判为重叠并加规则, 效果是本机仍可访问本地网段
5. 只处理形如 `from all to <网段> lookup main suppress_prefixlength 0` 的 pref 1295 规则, 不动其他规则

**规则范围**: 规则的 `to` 是被覆盖的 L 本身(取 main 表里的前缀), 不是 R, 也不是 L 与 R 的交集, 每个 L 一条. 以本地网段 `192.168.1.0/24` 为例:

1. R 与 L 相等: 规则管 L
2. R 比 L 大(`192.168.0.0/16`): 规则只管 L, R 里 L 之外的地址(如 `192.168.5.5`)仍走 tailnet
3. R 比 L 小(`192.168.1.128/25`): 规则仍管整个 L, 包括 R 之外的部分, 不是只管交集
4. 多个 R 覆盖同一个 L 时仍只有一条; 一个 R 覆盖多个 L 时(如 `192.168.0.0/16` 同时覆盖本地的 `192.168.1.0/24` 和 `192.168.2.0/24`), 每个 L 各一条
5. L 越宽规则越宽: L 不限于接口的直连网段, main 里的静态路由也算. main 里有 `10.0.0.0/8` 这类宽静态路由时, 只要有 R 落在其中(如对端通告的 `10.8.0.0/24`, 它比 main 里的路由更具体), 整个 `10.0.0.0/8` 都会优先走 main, 该 R 整段用不上

**设计要点**:

1. 用运行时 ip rule, 不写 `/etc/config/network`: 不改动配置文件, 也不会在 LuCI 里显示成用户自己的路由规则条目
2. 常驻对账: netifd 进程启动时会清空所有 ip rule, 而 `tailscaled` 只恢复自己 pref 范围内的规则; 接收的子网也会随对端变化. `network restart` 清空路由表 52 时(见 `docs/tailscale-network-restart-table52.md`)没有了重叠, 规则会随之被删除, 路由回来后最多 5 秒补回
3. 按网段添加: 只影响被覆盖的本地网段, main 里其他目的地不会因此提前走 main 而绕过 mwan3(pref 2001+, 固件没有选 `mwan3`)等策略规则; tailnet 地址段内的接收路由不参与判定, main 里 CGNAT 地址段(与 tailnet 同为 `100.64.0.0/10`)的路由也不会抢走 tailnet 流量
4. 写法: 只用 awk 和 ash 语法, 前缀先转成位串再比较, 兼容 BusyBox awk
5. `watch` 开头关闭 fd 1000: `watch` 由 procd 另起一个 `rc.common` 进程执行, `rc.common` 加载 `procd.sh` 时会在 fd 1000 上取得 `/var/lock/procd_tailscale-subnet-guard.lock` 的锁, 而 `watch` 常驻不退出. 不关闭的话, 之后手动执行本脚本的 `start`, `stop`, `restart` 等任何动作都会卡在取锁上(设备上复现过), `watch` 的子进程 `sleep` 也会继承这把锁

**验证**: 在 WSL 的私有网络命名空间里用真实 iproute2(6.1, 以及与固件同版本的 6.3.0)做过端到端测试(重叠判定, 增删, 幂等, 清空后补回, 停止清理, 与其他规则共存, IPv4 和 IPv6); awk 判定逻辑在 gawk, mawk 和按固件配置编译的 BusyBox 1.36.1 的 awk 上与独立实现逐例对照, ash 也用该 BusyBox 跑过端到端. procd 托管和 3.3 的钩子在一台装有 ImmortalWrt 23.05 的设备(NX30Pro)上用它自带的 `rc.common`, `procd.sh` 和 `ip-full` 6.3.0 做过隔离测试: procd 里起一个替身服务并带上与 3.3 相同的钩子, 规则在私有网络命名空间里增删, 覆盖 `start`, `stop`, `restart` 时钩子的调用时机, 重复 `start` 不重复起进程, 替身服务崩溃重启时不调用钩子, `watch` 被强杀后约 5 秒被 procd 拉起, 常驻期间手动执行 `start`, `stop`, `restart` 不卡住, 以及按 opkg 的 `default_postinst`, `default_prerm` 遍历 `/etc/init.d/*` 的方式模拟安装, 升级, 卸载(两种遍历顺序)都不卡住. 守卫(`watch`)也在同一台 NX30Pro 上与设备上已安装的真实 `tailscaled`(1.104.2-1, OpenWrt 构建)一起测过, 全部在私有网络命名空间里, `tailscaled` 未登录并用 `--state=mem:`, 不连 tailnet, 测试前后主命名空间的快照完全一致: 未登录的 `tailscaled` 也会立刻装上 pref 5210, 5230, 5250, 5270 的规则(IPv4 和 IPv6 各 4 条); 把重叠路由装进真实的 `tailscale0` 后, 守卫补出规则, IPv4 和 IPv6 的规则集合与预期一致, 重叠的本地网段回到代表本地网卡的 tun 设备, 无重叠的网段仍走 `tailscale0`; 规则被清, 重叠路由消失, 重叠路由回来三种情况下 `watch` 都在 7 秒内(对账间隔 5 秒)恢复; `tailscaled` 被 SIGTERM 或 SIGKILL 后路由表 52 随 `tailscale0` 消失而清空, 守卫在 7 秒内删掉自己的规则, 外来的 pref 1295 规则始终不动; `tailscaled --cleanup` 不碰 pref 1295; `tailscaled` 被 SIGKILL 后它自己的 52xx 规则会残留(`tailscale0` 已不存在时 `--cleanup` 也清不掉), 再次启动不会重复. 这几项直接运行 `watch`, 没有经过 3.3 的钩子. `/etc/init.d/network reload`(没有改动配置)在同一台设备上执行了 13 次: 测试用的路由表 52 路由, main 路由和 pref 5270 规则从未消失, pref 1295 测试规则有 1 次约 2 到 3 秒的缺失, 随后被 `watch` 补回, 原因没有查明, 其余 12 次没有任何变化, 详见 `docs/tailscale-network-restart-table52.md` 第 7 节第 2 点. 还没有验证的: 装有本补丁的固件(3.3 的钩子与真实 `tailscaled` 一起), 真实 `tailscaled` 在主网络命名空间里运行时的表现, `network restart` 与规则的交互, 设备上的核对命令见 8.1 第 5 项.

### 3.5 `/etc/config/tailscale`

> 标记: 上游 | 权限: 0644 | conffile

**作用**: UCI 配置. 默认只有 `settings` 一节, 5 个守护进程选项, 由 `/etc/init.d/tailscale` 读取:

| # | 选项 | 默认值 | 含义 |
|---|------|--------|------|
| 1 | `log_stderr` | `1` | 由 procd 把守护进程的 stderr 送入系统日志 |
| 2 | `log_stdout` | `1` | 由 procd 把守护进程的 stdout 送入系统日志 |
| 3 | `port` | `41641` | 监听端口(`--port`) |
| 4 | `state_file` | `/etc/tailscale/tailscaled.state` | 状态文件路径(`--state`) |
| 5 | `fw_mode` | `nftables` | 防火墙后端(环境变量 `TS_DEBUG_FIREWALL_MODE`) |

LuCI 页面保存时还会写入下列选项(静态推断, 取自 `tailscale.js` 的表单定义):

1. 由 `tailscale-settings` 读取: `service_enabled`, `accept_routes`, `advertise_exit_node`, `exit_node_allow_lan_access`, `runwebclient`, `nosnat`, `shields_up`, `ssh`, `dns_mode`, `disable_fw_config`, `enable_relay`, `relay_server_port`, `exit_node`, `advertise_routes`(列表)
2. 只供页面登录用, 守护进程和 `tailscale-settings` 都不读取: `custom_login_url`, `custom_login_AuthKey`. 点 Save & Apply 后, Auth Key 会以明文留在该文件里

**注意**: 固件没有选 `iptables-nft` 和 `iptables-zz-legacy`(三份 `.config-*` 均为 not set), `fw_mode` 实际只能用 `nftables`, 但 LuCI 下拉框里仍有 `iptables`.

### 3.6 `/lib/upgrade/keep.d/tailscale`

> 标记: 上游 | 权限: 0644 | 内容: `/etc/tailscale/` | 由构建系统生成

**作用**: sysupgrade 的保留清单. 刷机时选"保留配置", `/etc/tailscale/`(登录状态 `tailscaled.state`, DERP 地图缓存, DNS 缓存等)会随配置一起保留.

**来源**: 上游 Makefile 没有安装这个文件. 它的 `Package/tailscale/conffiles` 列了 `/etc/config/tailscale` 和 `/etc/tailscale/` 两项, ImmortalWrt 的 `include/package-ipkg.mk` 把其中在包内不是普通文件的条目(这里是目录 `/etc/tailscale/`)写入包内的 `/lib/upgrade/keep.d/<包名>`. 安装固件的设备上已验证: `opkg files tailscale` 有这一项, `tailscale.conffiles` 里只有 `/etc/config/tailscale`, 刷机后 `tailscaled.state` 保留了下来.

## 4. `luci-app-tailscale-community`(Tokisaki-Galaxy)

依赖: `tailscale`(即第 3 节的包), `ip-full`, `luci-base`. 包架构 `all`.

### 4.1 `/www/luci-static/resources/view/tailscale.js`

> 标记: 上游 | 权限: 0644

**作用**: 浏览器端页面代码. 三份配置均为 `CONFIG_LUCI_JSMIN=y`, 安装时会被压缩, 设备上看到的是压缩后的文本. 页面顶部是状态栏(服务状态, 版本, TUN 模式, Tailscale IPv4 和 IPv6, Tailnet 名称), 有健康告警时以通知条显示. 下面是 4 个标签页:

1. 常规设置: 12 个开关/下拉(服务开关, 防火墙模式, 接受路由, 通告出口节点, 允许访问 LAN, Web 界面(5252 端口), 禁用 SNAT, Shields Up, Tailscale SSH, DNS 模式, 禁用防火墙配置, 对端中继), 另有对端中继端口(启用对端中继后显示), 出口节点选择, 通告路由选择, "自动配置防火墙"按钮, 以及 Site-to-Site 和 Exit Node 两段使用说明
2. 账号设置: 登录(在新标签页打开授权链接), 退出(需确认), 自定义控制服务器(Headscale)地址和 Auth Key
3. 设备列表: 对端表格(状态, 主机名, Tailscale IP, 系统, 连接信息(直连地址或中继), 收发流量, 最近在线), 带过滤框(按名称, IP, 系统过滤)
4. 日志: 点 Refresh 后读取 tailscale 相关系统日志, 打开页面时不自动加载

页面每 10 秒刷新一次状态栏和设备表. 浏览器(不是路由器)会访问 `https://controlplane.tailscale.com/derpmap/default`, 把中继区域显示成名称, 结果缓存在浏览器 localStorage 7 天.

### 4.2 `/usr/share/luci/menu.d/luci-app-tailscale-community.json`

> 标记: 上游+补丁 | 权限: 0644

**作用**: 菜单注册, 把页面 `view/tailscale` 挂到 LuCI 菜单.

**补丁**: 上游挂在 `admin/vpn/tailscale`(VPN 菜单, `order` 90), 项目改为 `admin/services/tailscale`(服务菜单, 见 `3.feeds-after-script.sh` 的 `# luci-app-tailscale-community` 段), 并删掉 `order`, 让它按名称排序(见同文件的 `# 菜单顺序` 段).

### 4.3 `/usr/share/rpcd/acl.d/luci-app-tailscale-community.json`

> 标记: 上游 | 权限: 0644

**作用**: 权限声明, 限定 LuCI 能调用 ubus 对象 `tailscale` 的哪些方法, 以及能否读写 UCI `tailscale`:

1. 读: `get_status`, `get_settings`, `get_subroutes`, `get_logs`, `get_firewall_status`, 以及 UCI `tailscale`
2. 写: `do_login`, `do_logout`, `setup_firewall`, `set_service_enabled`, 以及 UCI `tailscale`

### 4.4 `/usr/share/rpcd/ucode/tailscale.uc`

> 标记: 上游 | 权限: 0755

**作用**: rpcd 的 ucode 插件, 注册 ubus 对象 `tailscale`, 是网页和系统之间的后端. 9 个方法:

1. `get_status`: 执行 `tailscale status --json`, 返回状态(running/logout/not_installed), 版本, 健康告警, 本机 IP, tailnet 名称, 对端列表
2. `get_settings`: 从状态文件(`state_file`)读出守护进程当前偏好, 用来预填表单
3. `do_login`: 后台执行 `tailscale login`(可带 `--login-server`, `--auth-key`), 最多等 30 秒取回授权链接
4. `do_logout`: 执行 `tailscale logout`
5. `get_subroutes`: 执行 `ip -j route`, 列出本机直连的 IPv4 子网, 供选择通告
6. `setup_firewall`: 用 UCI 建 `network.tailscale` 接口(设备 `tailscale0`), 防火墙区域 `tailscale`(masq, mtu_fix)和转发(lan 到 tailscale, tailscale 到 lan, tailscale 到 wan). 有改动时提交, 并在后台启动 `/usr/libexec/tailscale-setup-firewall`
7. `get_firewall_status`: 读 `/var/run/tailscale-fwsetup.status`, 页面每 2 秒轮询, 最长 30 秒
8. `set_service_enabled`: 只创建或删除标记文件 `/var/run/tailscale-settings/disable-requested`, 真正的停止由 `tailscale-settings` 在重载时执行
9. `get_logs`: 执行 `logread -l <行数, 默认 200>`, 再用 `grep -i tailscale` 过滤

**运行依赖**: `rpcd-mod-ucode`, `ucode-mod-fs`, `ucode-mod-uci`, `ip-full`, 三份配置均已选上.

### 4.5 `/etc/init.d/tailscale-settings`

> 标记: 上游 | 权限: 0755 | START=99, STOP=10

**作用**: 设置应用器. 开机以及 UCI `tailscale` 变化时(`procd_add_reload_trigger`)运行:

1. 把 LuCI 选项转成 `tailscale set` 参数: `--accept-routes`, `--advertise-exit-node`, `--exit-node`, `--exit-node-allow-lan-access`, `--advertise-routes`, `--ssh`, `--accept-dns`, `--shields-up`, `--webclient`, `--snat-subnet-routes`, `--hostname`, `--relay-server-port`, `--netfilter-mode`
2. 按 `dns_mode` 在 dnsmasq 增删转发 `/.ts.net/100.100.100.100`(`openwrt_forward` 添加, `magicdns` 删除, `disabled` 不动)
3. 按 `service_enabled` 对 `/etc/init.d/tailscale` 执行 enable/start 或 stop/disable
4. `port`, `state_file`, `fw_mode`, 日志开关变化时重启守护进程

### 4.6 `/usr/libexec/tailscale-setup-firewall`

> 标记: 上游 | 权限: 0755

**作用**: "自动配置防火墙"的后台执行者(参数为 run-id). 加锁 `/var/run/tailscale-fwsetup.lock.d`, 依次执行 `/etc/init.d/network reload` 和 `/etc/init.d/firewall reload`, 把进度(`running`, `done`, `failed`, `busy`)写入 `/var/run/tailscale-fwsetup.status`. 单独拆成脚本, 是为了让 RPC 先返回, 避免 reload 网络时掐断正在处理的请求(反向代理, 或经 Tailscale 访问 LuCI).

### 4.7 `/etc/init.d/tailscale-boot-gate`

> 标记: 项目 | 权限: 0755 | START=70 | 源文件: `feeds-patch/luci-app-tailscale-community/tailscale-boot-gate.init`

**作用**: 每次开机(早于 `S80tailscale`)读 `service_enabled`. 值为 0 且 `/etc/rc.d/S80tailscale` 链接还在时, 删掉这个链接, 这次开机的 S80 就不会启动 `tailscaled`; 值为 1 或选项不存在时什么也不做. 只删链接, 不停止进程, 不改配置. 只实现 `boot()`, 只在开机时执行; 手动 `start` / `restart` 和 opkg 安装后的 `start` 都是空操作, 手动验证用 `/etc/init.d/tailscale-boot-gate boot`.

**设计要点**:

1. 为什么需要: `tailscale` 包的 init 脚本没有"是否自启"的开关(见 3.3). `tailscale-settings` 在 LuCI 里关闭服务时会 disable 这个链接, 但链接被新镜像重新带来(例如刷机保留配置后)时, 它不会再执行. 需要有东西在 S80 之前读 `service_enabled`
2. 为什么是独立脚本: `service_enabled` 是 LuCI 应用的选项, 读它的逻辑放在 `luci-app-tailscale-community` 里, `tailscale` 包的 init 脚本不含这段逻辑(它只被追加了启停 `tailscale-subnet-guard` 的两个钩子, 见 3.3)
3. 为什么早于 80 就有效: procd 开机时先列出所有 `/etc/rc.d/S*`, 再逐个顺序执行(同一时刻只跑一个), 执行那一刻才按路径启动. S70 先删掉链接, 轮到 S80 时路径已不存在, 启动失败并被跳过(依据 procd 源码 `rcS.c`)
4. 重新开启: 在 LuCI 打开服务后, `tailscale-settings` 会 enable 并启动 `tailscale`, 链接随之恢复
5. 安装方式: `3.feeds-after-script.sh` 用 `install -m 0755` 放进包的 `root/etc/init.d/`, `luci.mk` 随包安装, 镜像构建时由 `default_postinst` 生成 `S70tailscale-boot-gate` 链接

## 5. `luci-i18n-tailscale-community-zh-cn`(同一来源)

依赖: `luci-app-tailscale-community`.

### 5.1 `/usr/lib/lua/luci/i18n/community.zh-cn.lmo`

> 标记: 上游 | 由 `po/zh_Hans/community.po` 经 `po2lmo` 编译

**作用**: 简体中文翻译. LuCI 按当前语言加载 `/usr/lib/lua/luci/i18n/` 下的 `*.zh-cn.lmo`, 页面文本据此显示中文.

### 5.2 `/etc/uci-defaults/luci-i18n-tailscale-community-zh-cn`

> 标记: 上游 | 由 `luci.mk` 生成

**作用**: 首次开机执行一次 `uci set luci.languages.zh_cn='简体中文 (Chinese Simplified)'; uci commit luci`, 成功后自动删除.

不进固件: es, pl, zh_Hant 翻译和 `.pot` 模板(`.config-*` 未选).

## 6. 不在包原始文件里的文件

### 6.1 镜像构建时生成

1. `/etc/rc.d/S80tailscale`: 开机启动链接, 指向 `/etc/init.d/tailscale`
2. `/etc/rc.d/S99tailscale-settings`, `/etc/rc.d/K10tailscale-settings`: 开机启动和停止链接, 指向 `/etc/init.d/tailscale-settings`
3. `/etc/rc.d/S70tailscale-boot-gate`: 开机启动链接, 指向 `/etc/init.d/tailscale-boot-gate`
4. `/usr/lib/opkg/info/<包名>.*`: 三个包各自的 opkg 元数据(`.control`, `.list`, `.conffiles` 等). `tailscale.conffiles` 只含 `/etc/config/tailscale`, `/etc/tailscale/` 由 `/lib/upgrade/keep.d/tailscale`(见 3.6)保留, 两者用于 sysupgrade 保留配置和登录状态

前三项由镜像构建时的 `default_postinst` 对包内 init 脚本执行 enable 生成. `tailscale-subnet-guard` 没有 START/STOP, 对它执行 enable 返回 1(返回值被忽略, 不影响构建), 所以没有开机链接, 见 3.4.

### 6.2 运行后才出现(不在固件里)

1. `/etc/tailscale/tailscaled.state`: 登录状态和节点密钥
2. `/var/run/tailscale/tailscaled.sock`: 守护进程本地 API 套接字
3. 网卡 `tailscale0`
4. `/var/run/tailscale-settings/`: `daemon`, `enabled`, `dns_mode`, `disable-requested`(tmpfs, 重启清空)
5. `/var/run/tailscale-fwsetup.status` 和 `/var/run/tailscale-fwsetup.lock.d/`: "自动配置防火墙"的进度和锁
6. `tailscale-subnet-guard` 的常驻进程(`/etc/init.d/tailscale-subnet-guard watch`, 由 procd 托管), 随 `tailscale` 启停
7. 内核里 pref 1295 的 `to <本地网段>` ip rule(重启清空): 只在接收的子网与本地网段重叠时存在, 见 3.4

### 6.3 运行后会被修改的系统配置

1. `/etc/config/network`: "自动配置防火墙"创建 `tailscale` 接口(`tailscale-subnet-guard` 的规则是运行时 ip rule, 不写这个文件)
2. `/etc/config/firewall`: "自动配置防火墙"创建 `tailscale` 区域和 3 条转发
3. `/etc/config/dhcp`: `dns_mode` 为 `openwrt_forward` 时, 给 dnsmasq 的 `server` 列表加 `/.ts.net/100.100.100.100`, 切到 `magicdns` 时删除

### 6.4 包目录里有但不安装

1. `tailscale`: `README.md`, `FORK.md`, `test.sh`, `Makefile`(仅构建用)
2. `luci-app-tailscale-community`: `Makefile`, `po/` 下的源文件

## 7. 文件之间的关系

1. 页面操作: `tailscale.js` → rpcd 的 `tailscale.uc`(权限由 ACL JSON 限定)→ `/usr/sbin/tailscale` → `tailscaled`
2. 保存设置: `tailscale.js` 写 UCI `/etc/config/tailscale` → 触发 `tailscale-settings` 重载 → `tailscale set ...`
3. 守护进程启动参数: `/etc/config/tailscale` → `/etc/init.d/tailscale` → `tailscaled`
4. 网络层: `tailscale.init` 的钩子带动 `tailscale-subnet-guard` 启停, 它常驻对账, 读路由表 52 和 main 表, 增删 pref 1295 的 ip rule(不写 `/etc/config/network`); "自动配置防火墙"写 `network`/`firewall` 后由 `tailscale-setup-firewall` 重载
5. 开机自启: `tailscale-boot-gate`(S70)读 UCI `service_enabled`, 为 0 就删掉 `/etc/rc.d/S80tailscale` → procd 依次执行 S 链接, 跳过已不存在的 S80 → `tailscale` 不启动

## 8. 需要留意与验证

### 8.1 设备上核对

```sh
# 1. 三个包各自安装的文件, 应与 2.2 文件总表一致
opkg files tailscale
opkg files luci-app-tailscale-community
opkg files luci-i18n-tailscale-community-zh-cn

# 2. 开机链接, 预期 4 个: S70tailscale-boot-gate, S80tailscale, S99tailscale-settings, K10tailscale-settings
#    (service_enabled=0 时开机会删掉 S80tailscale, 只剩 3 个; tailscale-subnet-guard 没有开机链接)
ls -l /etc/rc.d/ | grep tailscale

# 3. 执行权限, 预期 -rwxr-xr-x
ls -l /usr/libexec/tailscale-setup-firewall

# 4. UPX 压缩, 输出 0 表示未压缩
grep -c 'UPX!' /usr/sbin/tailscaled

# 5. tailscale-subnet-guard(见 3.3 和 3.4; 替身服务的测试见 3.4 的验证, 装有本补丁的固件上还没有核对过)
#    5.1 tailscale 运行时应有一个常驻的 watch 进程, 停止 tailscale 后消失(BusyBox 的 ps 经管道输出时按 78 列截断, 会截掉进程名, 所以要加 ww)
ps ww | grep '[t]ailscale-subnet-guard'
#    5.2 pref 1295 的规则: 接收的子网与本地网段没有重叠时为空, 有重叠时每个被覆盖的本地网段一条
ip -4 rule show | grep '^1295:'
ip -6 rule show | grep '^1295:'
#    5.3 增删记录, 形如 "add rule: to 192.168.1.0/24"
logread -e tailscale-subnet-guard
#    5.4 tailscale 运行时手动执行动作应在几秒内返回(stop 和 restart 会多等 1 秒), 退出码为 0(卡住不动时按 Ctrl+C 中断, 说明 watch 没有释放 procd 的锁)
/etc/init.d/tailscale-subnet-guard restart; echo $?
#    5.5 停止 tailscale 的命令返回时(它会多等约 1 秒), pref 1295 的 to <网段> 规则应已消失
/etc/init.d/tailscale stop
ip -4 rule show | grep '^1295:'
ip -6 rule show | grep '^1295:'
```
