
# 固件中的 Tailscale 相关文件清单

编译完成后, `tailscale`(GuNanOvO)和 `luci-app-tailscale-community`(Tokisaki-Galaxy)两个来源在固件里提供的文件, 以及每个文件的作用.

## 1. 说明

1. 范围: 所有构建目标的文件清单相同
2. 来源: 上游 Makefile 与源文件, 本项目补丁脚本, 各目标的 `.config-*`
3. 版本: `tailscale` 固定为 GuNanOvO/openwrt-tailscale 标签 `v1.104.2`(编译 tailscale/tailscale `v1.104.2`); `luci-app-tailscale-community` 跟随 Tokisaki-Galaxy `master`(未固定), 文件清单随上游变化
4. 标记: `上游` 原样, `补丁` 上游文件被本项目脚本修改, `项目` 本项目新增
5. 权限: `tailscale` 包由 Makefile 的 `$(INSTALL_BIN)`/`$(INSTALL_DATA)` 决定, LuCI 应用由 `luci.mk` 用 `cp -pR` 安装, 沿用上游仓库的 git 权限, 语言包的两个文件由 `luci.mk` 生成, 权限为 0644

## 2. 总览

### 2.1 包与来源

| # | 包 | 来源 | 依赖 | 文件数 |
|---|----|------|------|--------|
| 1 | `tailscale` | [GuNanOvO/openwrt-tailscale](https://github.com/GuNanOvO/openwrt-tailscale) | `ca-bundle`, `kmod-tun`, `ip-full` | 6 |
| 2 | `luci-app-tailscale-community`(架构 `all`) | [Tokisaki-Galaxy/luci-app-tailscale-community](https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community) | `tailscale`, `ip-full`, `luci-base` | 7 |
| 3 | `luci-i18n-tailscale-community-zh-cn` | 同 2, 只构建简体中文 | `luci-app-tailscale-community` | 2 |

合计 15 个文件(含 1 个符号链接). 各目标的 `.config-*` 里这三个包均为 `=y`. 上游 `tailscale` 只依赖 `ca-bundle` 和 `kmod-tun`, `ip-full` 由 `tailscale-subnet-guard-install.patch` 加到 `DEPENDS` 末尾: 固件里 `/sbin/ip` 指向 `/usr/libexec/ip-full`, BusyBox 自带的 `ip` 没有 `monitor` 子命令(3.3 的守卫用它监听变化)和 `-j` 选项(4.1 的 `get_subroutes` 用它), `ip -6 route show table 52` 的输出为空: 3.3 的 IPv6 对账要靠 ip-full 的 `table` 过滤, 没有它 IPv6 对账会静默不生效.

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
| 14 | `/usr/lib/lua/luci/i18n/community.zh-cn.lmo` | 0644 | 上游 | 简体中文翻译 |
| 15 | `/etc/uci-defaults/luci-i18n-tailscale-community-zh-cn` | 0644 | 上游 | 首次开机登记语言名 |

第 14, 15 项由 `luci.mk` 在构建时生成. 第 6 项由 ImmortalWrt 的构建系统生成, 不是上游 Makefile 安装的, 见 2.3.

### 2.3 其他文件的说明

2.2 的"作用"列之外需要补充的文件(3.1 到 4.2 单独说明的除外):

1. `/lib/upgrade/keep.d/tailscale`: 刷机选"保留配置"时, `/etc/tailscale/` 随 sysupgrade 保留(`tailscaled.state`, `derpmap.cached.json`, `dns-cache/`, `profile-data/`), `/etc/config/tailscale` 同样保留. 上游 Makefile 没有安装它: ImmortalWrt 的构建系统把 `conffiles` 里的目录条目写入包内的 `/lib/upgrade/keep.d/<包名>`
2. `/www/luci-static/resources/view/tailscale.js`: 状态栏下有 4 个标签页(常规设置, 账号设置, 设备列表, 日志). 浏览器(不是路由器)会访问 `https://controlplane.tailscale.com/derpmap/default` 把中继区域显示成名称
3. `/usr/share/luci/menu.d/luci-app-tailscale-community.json`: 补丁: 上游挂在 `admin/vpn/tailscale`(`order` 90), 项目改为 `admin/services/tailscale`(见 `3.feeds-after-script.sh` 的 `# luci-app-tailscale-community` 段), 并删掉 `order` 让它按名称排序(见同文件的 `# 菜单顺序` 段)
4. `/etc/init.d/tailscale-settings`: START=99, STOP=10. 开机以及 UCI `tailscale` 变化时运行:
   1. 把 LuCI 选项转成 `tailscale set` 参数: `dns_mode` 为 `magicdns` 时 `--accept-dns=true`, 其他值为 `false`; `nosnat` 取反成 `--snat-subnet-routes`; 选了出口节点时 `advertise_exit_node` 不生效, 并固定允许访问 LAN; `--relay-server-port` 只在 tailscale 版本不低于 1.90.5 时传入. tailscaled 没有运行时跳过, 日志为 `tailscale is not running, skip applying settings`. 已保存的 `AutoUpdate.Apply=true` 使 `tailscale set` 报 `Auto-update support is disabled in this build` 时, 先执行 `tailscale set --auto-update=false` 再重试
   2. 按 `dns_mode` 在 dnsmasq 增删 `.ts.net` 转发(见 5.3)
   3. `fw_mode`, `port`, `state_file`, `log_stdout`, `log_stderr` 变化时记录 `Daemon options changed, restarting tailscale` 并重启守护进程, 其他选项变化不重启
   4. 按 `service_enabled` 启停: 为 1 时, 只有 tailscaled 未运行且上一次应用的值为 0 才执行 enable 加 start; tailscaled 在运行时不动进程, 也不重新生成 `S80tailscale` 链接; 上一次的值已是 1 时, 手工停止或崩溃的 tailscaled 不会被拉起. 为 0 时, 存在停用请求标记(RPC `set_service_enabled` 创建)才执行 stop 加 disable; 没有标记(手工编辑配置)只执行 disable, 进程继续运行; 上一次的值已是 0 时什么也不做
   5. 不对运行中的 tailscaled 执行 `start`: `/etc/init.d/tailscale start` 会先执行 `tailscaled --cleanup`, 进程不重启, 节点仍回答 `tailscale status` 和 `tailscale ping`, 内核里没有可用状态(见 3.2 第 4 项)
5. `/usr/libexec/tailscale-setup-firewall <run-id>`: 加锁(目录 `/var/run/tailscale-fwsetup.lock.d`)后依次执行 `/etc/init.d/network reload` 和 `/etc/init.d/firewall reload`, 完成后删除锁. 进度写入 `/var/run/tailscale-fwsetup.status`, 共 4 行: 状态, 步骤, 消息, run-id. 状态有 `queued`(由 RPC 写入), `running`, `done`, `failed`(重载返回非 0, 或进程被终止), `busy`(已有锁且持有不超过 300 秒, 不执行重载); 锁超过 300 秒, 或没有有效的时间戳文件, 视为过期并接管. 单独拆成脚本, 是为了让 RPC 先返回, 避免 reload 网络时掐断正在处理的请求
6. `/etc/uci-defaults/luci-i18n-tailscale-community-zh-cn`: 首次开机执行一次 `uci set luci.languages.zh_cn='简体中文 (Chinese Simplified)'; uci commit luci`, 成功后自动删除

## 3. `tailscale` 包(GuNanOvO)

补丁文件在 `feeds-patch/tailscale/`, 由 `2.feeds-insert-script.sh` 的 `# tailscale` 段按下面的顺序应用: `build-depends-golang-host`, `omit-flashappliance`, `remove-upx-labels`, `remove-maintainer-export`, `tailscale-subnet-guard-install`, `tailscale-subnet-guard-service-hooks`. 补丁的上下文与上游不匹配时构建失败.

### 3.1 `/usr/sbin/tailscaled`

守护进程本体, 已去符号(`-s -w`), 内置命令行(构建标签 `ts_include_cli`), 不做 UPX 压缩, 版本串为 `1.104.2-1 (OpenWrt)`.

1. 补丁 `omit-flashappliance.patch`: 构建标签在上游 14 个的基础上追加 `ts_omit_flashappliance`. 仅用 `ts_omit_clientupdate` 时, flash-appliance 的命令行子命令仍会链接 `tailscale.com/clientupdate`, 使 `CanAutoUpdate()` 保持为 true, tailscaled 启动时无法清除已保存的 `AutoUpdate.Apply=true`
2. 补丁 `remove-upx-labels.patch`: 版本串 `1.104.2-1 (OpenWrt-UPX)` 改为 `1.104.2-1 (OpenWrt)`, 并去掉 `TITLE` 里的 `(UPX Compressed)`. 这是上游写死的字样, 上游 Makefile 只在 `$(TOPDIR)/upx/upx` 存在时才压缩, 本项目的构建不提供该文件, 二进制不含 `UPX!` 标记(见第 7 节)
3. 补丁 `build-depends-golang-host.patch`: Makefile 加 `PKG_BUILD_DEPENDS:=golang/host`, 先构建 `golang/host`, 使 tailscale 使用 feeds 里的 Go, 而不是 CI 主机上的 Go. 只影响构建
4. 补丁 `remove-maintainer-export.patch`: 删除 `Package/tailscale/install` 里把 `tailscaled` 复制到 `$(TOPDIR)/bin/packages/<arch>/base` 的 5 行(3 行注释, `mkdir -p` 和 `$(CP)`), 这是上游为自己的仓库保留二进制副本而写的. 只影响构建

### 3.2 `/etc/init.d/tailscale`

procd 服务脚本, START=80, 没有 STOP. 启动前和停止时执行 `tailscaled --cleanup`; 设置 `TS_NO_LOGS_NO_SUPPORT=true` 关闭日志上传; 异常退出自动重启, 连续失败后 procd 放弃, 需要 `/etc/init.d/tailscale restart`.

1. 补丁 `tailscale-subnet-guard-service-hooks.patch`: 追加 `service_started` 和 `service_stopped` 两个钩子, 分别执行 `tailscale-subnet-guard` 的 `start` 和 `stop`, 使两者同启同停. `rc.common` 在 `start`, `stop`, `restart` 和开机的 `boot` 时调用钩子(`restart` 时守卫换新进程号), procd 自动重启崩溃的 `tailscaled` 时不调用: 守卫在运行时保持原进程, 已被停止时不会被拉起
2. 自启: 脚本里没有"是否自启"的开关, 只取决于镜像构建时生成的 `/etc/rc.d/S80tailscale` 链接. 补丁不涉及自启, 开机时是否保留这个链接由 `tailscale-boot-gate`(见 4.2)按 `service_enabled` 决定
3. 日志: `log_stdout`, `log_stderr` 控制 procd 是否把进程的 stdout, stderr 送入系统日志. tailscaled 的日志全部写 stderr(系统日志里为 `daemon.err`), `log_stderr` 为 0 时系统日志里没有 tailscaled 的日志, `log_stdout` 不影响它
4. 对运行中的服务执行 `start`: 先执行 `tailscaled --cleanup`, 进程不重启, `tailscale0` 的 tailnet 地址, table 52 的 IPv4 路由, netfilter 的 `ts-*` 链被清掉, 内核路径不通, `restart` 恢复(见 `docs/tailscale-network-restart-table52.md` 4.2)

### 3.3 `/etc/init.d/tailscale-subnet-guard`

项目新增, 源文件 `feeds-patch/tailscale/tailscale-subnet-guard.init`. 无 START, 不生成开机链接.

**作用**: `tailscale` 运行期间, 只有接收到的子网与本地网段重叠时才添加 ip rule, 防止路由表 52(pref 5270)劫持本地网段的流量; 重叠消失或 `tailscale` 停止时删除. 每个被覆盖的本地网段一条, IPv4 和 IPv6 各自独立:

`pref 1295 to <本地网段> lookup main suppress_prefixlength 0`

即先查 main 表并忽略其默认路由, 使该网段的具体本地路由优先于路由表 52. 规则是运行时的 ip rule, 不写入 `/etc/config/network`, LuCI 里看不到.

**运行方式**:

1. 启停: 由 3.2 的钩子随 `tailscale` 启停, 开机时不单独启动, 也可以手动执行 `/etc/init.d/tailscale-subnet-guard start|stop|restart`
2. 对账: `start` 让 procd 托管常驻进程(`/etc/init.d/tailscale-subnet-guard watch`), 它用 `ip monitor route rule` 监听路由和规则的变化, 按路由表 52 和 main 的现状补缺删多. 1 秒内的变化合并成一次, 所以增删约延迟 1 到 2 秒, 被劫持的窗口(重叠路由出现到规则出现)约 1 秒; 另每 60 秒兜底对账一次. 每次增删记一条系统日志, 标签 `tailscale-subnet-guard`, 内容为 `add rule: to <网段>` 或 `del rule: to <网段>`
3. 启动: `start` 先清掉旧的 `ip monitor` 子进程, 再对账一轮, 清掉过期规则; 运行中的 `ip monitor` 恰好 1 个
4. 停止: `stop` 先等 1 秒让进行中的对账结束(procd 只给 `watch` 主进程发 SIGTERM 且不等它退出), 再删除全部 pref 1295 的 `to <网段>` 规则并结束 `ip monitor`. `stop` 返回时规则已消失, `restart` 在数秒内返回, 退出码为 0
5. 保活: procd 的 `respawn` 参数为 threshold 3600, timeout 5, retry 5. `watch` 进程被杀死后约 5 秒被拉起; 3600 秒内被杀死第 6 次后 procd 放弃拉起, 之后不再对账, 已有规则留在内核里. 放弃后单独 `start` 重新拉起进程但不清零失败计数, `stop` 加 `start`(`restart`, `tailscale restart`)清零
6. 与其他操作的关系: `tailscaled --cleanup` 不删除 pref 1295 规则; `network restart` 期间 netifd 清空全部 ip rule, table 52 为空时重叠消失, 规则被删除且守卫进程不变, `tailscale restart` 恢复路由后规则约 1 秒补回(见 `docs/tailscale-network-restart-table52.md`); 对端路由持续反复增删(每秒一次, 或每 2 秒一次 50 对突发)时, 守卫按 1 秒窗口合并变化, CPU 占用低, 日志只记录实际的规则增删, 进程不崩溃

**判定**(IPv4 和 IPv6 各自独立):

1. 接收路由 R: 路由表 52 里的路由, 不含默认路由, 特殊路由(`throw`/`blackhole`/`unreachable`/`prohibit`)以及 tailnet 地址段(`100.64.0.0/10`, `fd7a:115c:a1e0::/48`)内的路由
2. 本地网段 L: main 表里的非默认路由, 不含特殊路由, 也不含前缀短于 IPv4 /8 或 IPv6 /16 的(如 OpenVPN 的拆分默认路由 `0.0.0.0/1` 加 `128.0.0.0/1`: `suppress_prefixlength 0` 抑制不了 /1, 加规则会把 tailnet 的流量也抢到 main)
3. L 与任一 R 相等或互相包含, 就对该 L 加规则. 规则的 `to` 是 L 本身(不是 R, 也不是交集), 所以 L 越宽规则越宽: main 里有 `10.0.0.0/8` 这类宽静态路由时, 落在其中的 R 整段用不上
4. 只处理 pref 1295 里形如 `from all to <网段> lookup main suppress_prefixlength 0` 的规则, 不动其他规则

**设计要点**:

1. 常驻对账而不是只加一次: netifd 启动时会清空所有 ip rule, `tailscaled` 只恢复自己 pref 范围内的规则, 接收的子网也会随对端变化
2. 按网段添加: 只影响目的地落在被覆盖本地网段内的包, main 里其他目的地的路由判定不变

### 3.4 `/etc/config/tailscale`

UCI 配置(conffile). 出厂只有 `settings` 一节, 5 个守护进程选项, 由 `/etc/init.d/tailscale` 读取:

1. `log_stderr`, `log_stdout`(默认 `1`): 由 procd 把守护进程的 stderr, stdout 送入系统日志
2. `port`(默认 `41641`): 监听端口(`--port`)
3. `state_file`(默认 `/etc/tailscale/tailscaled.state`): 状态文件路径(`--state`)
4. `fw_mode`(默认 `nftables`): 防火墙后端(环境变量 `TS_DEBUG_FIREWALL_MODE`)

LuCI 页面保存时还会写入 `service_enabled`, `accept_routes`, `advertise_exit_node`, `exit_node_allow_lan_access`, `runwebclient`, `nosnat`, `shields_up`, `ssh`, `dns_mode`, `disable_fw_config`, `enable_relay`, `relay_server_port`, `exit_node`, `advertise_routes`(列表)等由 `tailscale-settings` 读取的选项, 以及只供页面登录用的 `custom_login_url`, `custom_login_AuthKey`(点 Save & Apply 后 Auth Key 会以明文留在该文件里, `tailscaled` 和 `tailscale-settings` 都不读取它们). `hostname` 由 `tailscale-settings` 读取, 页面没有对应的表单项.

**注意**: 固件没有选 `iptables-nft` 和 `iptables-zz-legacy`, 设备上没有 `iptables`, `ip6tables` 命令, `fw_mode` 只能用 `nftables`, 但 LuCI 下拉框里仍有 `iptables`. 选 `iptables` 时 tailscaled 启动即以退出码 1 退出, procd 放弃重试后服务停止, 守卫进程仍在运行, 把 `fw_mode` 改回 `nftables` 不会自动拉起 tailscaled, 需要 `/etc/init.d/tailscale restart`.

## 4. `luci-app-tailscale-community`(Tokisaki-Galaxy)

### 4.1 `/usr/share/rpcd/ucode/tailscale.uc`

rpcd 的 ucode 插件, 注册 ubus 对象 `tailscale`, 是网页和系统之间的后端, 9 个方法:

1. 读取类:
   1. `get_status`: 执行 `tailscale status --json`, 返回运行状态(`running`, `logout`, `not_installed`, 其他情况为空), 版本, 健康信息, 本机地址, 对端列表
   2. `get_settings`: 从 `state_file` 指向的状态文件读出当前配置, 再加上 UCI 的 `dns_mode` 和 `fw_mode`
   3. `get_subroutes`: 执行 `ip -j route`(需要 ip-full), 返回 main 表里 IPv4 `scope link` 的网段, 作为"通告路由"的可选项
   4. `get_logs`: 执行 `logread -l <行数, 默认 200>`, 只保留含 `tailscale` 的行
   5. `get_firewall_status`: 读 `/var/run/tailscale-fwsetup.status`, 返回 `state`, `step`, `message`, `run_id`, 没有状态文件时返回 `idle`
2. `do_login`, `do_logout`: `do_login` 只在状态为 `logout` 时后台执行 `tailscale login`(可带 `--login-server`, `--auth-key`), 30 秒内取回登录 URL, 其他状态返回 error; `do_logout` 只在状态为 `running` 时执行 `tailscale logout`, 其他状态返回 error
3. `set_service_enabled`: 参数 `enabled` 只能是 `0` 或 `1`, 其他值返回 error. `0` 创建标记文件 `/var/run/tailscale-settings/disable-requested` 并返回 `armed: true`, `1` 删除标记文件并返回 `armed: false`. 不启停进程, 不改 UCI, 真正的停止由 `tailscale-settings` 在重载时执行
4. `setup_firewall`: 用 UCI 补齐 `network.tailscale` 接口(`proto none`, 设备 `tailscale0`, 已存在但设备不是 `tailscale0` 时改成 `tailscale0`), 防火墙区域 `tailscale`(masq, mtu_fix; 已存在时只补 `network` 引用)和 3 条转发(lan 到 tailscale, tailscale 到 lan, tailscale 到 wan), 只补缺失的. 配置齐全时返回 `Tailscale firewall/interface already configured.`, 不启动后台脚本; 有缺失项时提交, 写 `/var/run/tailscale-fwsetup.status`, 再在后台启动 `/usr/libexec/tailscale-setup-firewall`

`setup_firewall` 写状态文件时调用 `rename`, 而 `tailscale.uc` 只从 `fs` 导入了 `access`, `popen`, `readfile`, `writefile`, `unlink`, 没有 `rename`, 抛出 `access to undeclared variable rename`. 结果: 有缺失项时 UCI 已提交, RPC 立即返回 `error`, 后台脚本没有启动, `network` 和 `firewall` 没有重载, 没有状态文件. 手动完成需要执行 `/etc/init.d/network reload` 和 `/etc/init.d/firewall reload`. 在 `import` 里加上 `rename` 即可修复.

### 4.2 `/etc/init.d/tailscale-boot-gate`

项目新增, 源文件 `feeds-patch/luci-app-tailscale-community/tailscale-boot-gate.init`, START=70.

**作用**: 每次开机(早于 `S80tailscale`)读 `service_enabled`: 值为 0 且 `/etc/rc.d/S80tailscale` 链接还在时, 删掉这个链接并记录日志 `service_enabled=0, removed boot link of tailscale`, 这次开机的 S80 就不会启动 `tailscaled`; 值为 1 或选项不存在时什么也不做. 只删链接, 不停止进程, 不改配置. 只实现 `boot()`, 手动 `start`/`stop`/`restart`/`reload` 是空操作, 手动验证用 `/etc/init.d/tailscale-boot-gate boot`.

**设计要点**:

1. 为什么需要: `tailscale` 包的 init 脚本没有"是否自启"的开关(见 3.2). `tailscale-settings` 在 LuCI 里关闭服务时会 disable 链接, 但链接被新镜像重新带来(例如刷机保留配置后)时不会再执行, 需要有东西在 S80 之前读 `service_enabled`. 逻辑放在 `luci-app-tailscale-community` 里, 因为 `service_enabled` 是 LuCI 应用的选项
2. 为什么早于 80 就有效: procd 开机时先列出所有 `/etc/rc.d/S*`, 再逐个顺序执行, 执行那一刻才按路径启动. S70 先删掉链接, 轮到 S80 时路径已不存在, 启动失败并被跳过. 这次开机没有 `tailscaled` 进程, 没有 `tailscale0` 设备, 没有 table 52 和 5270 规则
3. 重新开启: 在 LuCI 打开服务后, `tailscale-settings` 会 enable 并启动 `tailscale`, 链接随之恢复(tailscaled 已在运行时只更新记录, 不重新生成链接)
4. 安装: `3.feeds-after-script.sh` 用 `install -m 0755` 放进包的 `root/etc/init.d/`, `luci.mk` 随包安装

## 5. 不在包原始文件里的文件

### 5.1 镜像构建时生成

`/etc/rc.d/` 下的开机链接, 由 `default_postinst` 对包内 init 脚本执行 enable 生成: `S80tailscale`, `S99tailscale-settings`, `K10tailscale-settings`, `S70tailscale-boot-gate`. `tailscale-subnet-guard` 没有 START/STOP, 所以没有开机链接, 见 3.3.

### 5.2 运行后才出现(不在固件里)

1. 状态与网卡: `/etc/tailscale/tailscaled.state`(登录状态和节点密钥), `/etc/tailscale/` 下的 `derpmap.cached.json`, `dns-cache/`, `profile-data/`, 网卡 `tailscale0`
2. `/var/run` 下的临时文件(tmpfs, 重启清空): `tailscale/tailscaled.sock`(守护进程本地 API 套接字), `tailscale-settings/`(`daemon`: 守护进程选项指纹, `enabled`, `dns_mode`: 最近一次应用的值, `disable-requested`: 停用请求标记), `tailscale-fwsetup.status` 和 `tailscale-fwsetup.lock.d/`("自动配置防火墙"的进度和锁)
3. `tailscale-subnet-guard` 的常驻进程, 以及内核里 pref 1295 的 `to <本地网段>` ip rule, 见 3.3
4. 内核里的 table 52 路由, pref 5210 到 5270 的 ip rule, `tailscale0` 上的 tailnet 地址, netfilter 的 `ts-*` 链, 由 tailscaled 写入, 见 `docs/tailscale-network-restart-table52.md`

### 5.3 运行后会被修改的系统配置

1. `/etc/config/network`: "自动配置防火墙"创建 `tailscale` 接口
2. `/etc/config/firewall`: "自动配置防火墙"创建 `tailscale` 区域和 3 条转发
3. `/etc/config/dhcp`: `dns_mode` 为 `openwrt_forward` 时, 给 dnsmasq 的 `server` 列表加 `/.ts.net/100.100.100.100`, 切到 `magicdns` 时删除, 为 `disabled` 时保持现状(dnsmasq 仍负责解析)
4. `/etc/rc.d/S80tailscale`: `tailscale-settings` 的 enable/disable 和 `tailscale-boot-gate` 的删除操作

## 6. 文件之间的关系

1. 页面操作: `tailscale.js` → rpcd 的 `tailscale.uc`(权限由 ACL JSON 限定)→ `/usr/sbin/tailscale` → `tailscaled`
2. 保存设置: `tailscale.js` 写 UCI `/etc/config/tailscale` → 触发 `tailscale-settings` 重载 → `tailscale set ...`, 守护进程选项变化时再 `/etc/init.d/tailscale restart`
3. 守护进程启动参数: `/etc/config/tailscale` → `/etc/init.d/tailscale` → `tailscaled`
4. 网络层: `tailscale.init` 的钩子带动 `tailscale-subnet-guard` 启停, 它常驻对账, 读路由表 52 和 main 表, 增删 pref 1295 的 ip rule; "自动配置防火墙"写 `network`/`firewall` 后由 `tailscale-setup-firewall` 重载
5. 开机自启: `tailscale-boot-gate`(S70)读 UCI `service_enabled`, 为 0 就删掉 `/etc/rc.d/S80tailscale` → procd 依次执行 S 链接, 跳过已不存在的 S80 → `tailscale` 不启动

## 7. 设备上核对

```sh
# 1. 三个包安装的文件, 与 2.2 文件总表一致
opkg files tailscale
opkg files luci-app-tailscale-community
opkg files luci-i18n-tailscale-community-zh-cn

# 2. 开机链接, 4 个: S70tailscale-boot-gate, S80tailscale, S99tailscale-settings, K10tailscale-settings
#    (service_enabled=0 时开机会删掉 S80tailscale, 只剩 3 个; tailscale-subnet-guard 没有开机链接)
ls -l /etc/rc.d/ | grep tailscale

# 3. 执行权限, -rwxr-xr-x
ls -l /usr/libexec/tailscale-setup-firewall

# 4. UPX 压缩, 输出 0 表示未压缩
grep -c 'UPX!' /usr/sbin/tailscaled

# 5. ip 命令, /sbin/ip 指向 /usr/libexec/ip-full
ls -l /sbin/ip

# 6. tailscale-subnet-guard(见 3.2 和 3.3)
#    6.1 tailscale 运行时有常驻的 watch 进程, 停止后消失(ps 要加 ww, 否则 BusyBox 会截断进程名)
ps ww | grep '[t]ailscale-subnet-guard'
#    6.2 pref 1295 规则: 无重叠时为空, 有重叠时每个被覆盖的本地网段一条
ip -4 rule show | grep '^1295:'
ip -6 rule show | grep '^1295:'
#    6.3 增删记录, 形如 "add rule: to 192.168.1.0/24"
logread -e tailscale-subnet-guard
#    6.4 手动 restart 在数秒内返回, 退出码为 0(卡住说明 watch 没有释放 procd 的锁, 按 Ctrl+C 中断)
/etc/init.d/tailscale-subnet-guard restart; echo $?
#    6.5 stop 返回时(会多等约 1 秒)规则已消失
/etc/init.d/tailscale stop
ip -4 rule show | grep '^1295:'
ip -6 rule show | grep '^1295:'
```
