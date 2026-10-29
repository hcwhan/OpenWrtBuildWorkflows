
# 固件中的 Tailscale 相关文件清单

编译完成后, `tailscale`(GuNanOvO)和 `luci-app-tailscale-community`(Tokisaki-Galaxy)在固件里提供的文件, 以及每个文件的作用.

## 1. 说明

1. 范围: 所有构建目标的清单相同, 各目标的 `.config-*` 里这三个包均为 `=y`
2. 版本: `tailscale` 固定为 GuNanOvO/openwrt-tailscale 标签 `v1.104.4`(编译 tailscale/tailscale `v1.104.4`); `luci-app-tailscale-community` 跟随 Tokisaki-Galaxy `master`(未固定), 清单随上游变化
3. 标记: `上游` 原样, `补丁` 上游文件被本项目脚本修改, `项目` 本项目新增

## 2. 总览

### 2.1 包与来源

| # | 包 | 来源 | 依赖 |
|---|----|------|------|
| 1 | `tailscale` | [GuNanOvO/openwrt-tailscale](https://github.com/GuNanOvO/openwrt-tailscale) | `ca-bundle`, `kmod-tun`, `ip-full` |
| 2 | `luci-app-tailscale-community`(架构 `all`) | [Tokisaki-Galaxy/luci-app-tailscale-community](https://github.com/Tokisaki-Galaxy/luci-app-tailscale-community) | `tailscale`, `ip-full`, `luci-base` |
| 3 | `luci-i18n-tailscale-community-zh-cn` | 同 2, 只构建简体中文 | `luci-app-tailscale-community` |

上游 `tailscale` 只依赖 `ca-bundle` 和 `kmod-tun`, `ip-full` 由 `tailscale-subnet-guard-install.patch` 加到 `DEPENDS` 末尾. 固件里 `/sbin/ip` 指向 `/usr/libexec/ip-full`. BusyBox 自带的 `ip` 没有 `monitor` 子命令(`tailscale-subnet-guard`, 下称守卫, 用它监听变化)和 `-j` 选项(`get_subroutes` 用它), 且 `ip -6 route show table 52` 输出为空, 没有 ip-full 时守卫的 IPv6 对账会静默不生效.

### 2.2 文件总表

| # | 路径 | 权限 | 标记 | 作用 |
|---|------|------|------|------|
| 1 | `/usr/sbin/tailscaled` | 0755 | 上游+补丁 | 守护进程, 内置命令行 |
| 2 | `/usr/sbin/tailscale` | 符号链接 | 上游 | 命令行入口, 指向 `tailscaled` |
| 3 | `/etc/init.d/tailscale` | 0755 | 上游+补丁 | 守护进程的 procd 启动脚本 |
| 4 | `/etc/init.d/tailscale-subnet-guard` | 0755 | 项目 | 守卫: 随 tailscale 启停, 按需增删 ip rule, 防子网劫持 |
| 5 | `/etc/config/tailscale` | 0644 | 上游 | UCI 配置 |
| 6 | `/lib/upgrade/keep.d/tailscale` | 0644 | 上游 | sysupgrade 保留清单, 内容为 `/etc/tailscale/`. 不是上游 Makefile 安装的, 由构建系统根据 `conffiles` 生成 |
| 7 | `/www/luci-static/resources/view/tailscale.js` | 0644 | 上游+补丁 | LuCI 页面前端 |
| 8 | `/usr/share/luci/menu.d/luci-app-tailscale-community.json` | 0644 | 上游+补丁 | 菜单注册, 补丁见表后 |
| 9 | `/usr/share/rpcd/acl.d/luci-app-tailscale-community.json` | 0644 | 上游 | 权限声明 |
| 10 | `/usr/share/rpcd/ucode/tailscale.uc` | 0755 | 上游+补丁 | 后端, ubus 对象 `tailscale` |
| 11 | `/etc/init.d/tailscale-settings` | 0755 | 上游+补丁 | 把 LuCI 设置应用到 tailscale |
| 12 | `/usr/libexec/tailscale-setup-firewall` | 0755 | 上游 | "自动配置防火墙"的后台执行者 |
| 13 | `/etc/init.d/tailscale-boot-gate` | 0755 | 项目 | 开机时按 `service_enabled` 决定 tailscale 是否自启 |
| 14 | `/usr/lib/lua/luci/i18n/community.zh-cn.lmo` | 0644 | 上游 | 简体中文翻译, `luci.mk` 构建时生成 |
| 15 | `/etc/uci-defaults/luci-i18n-tailscale-community-zh-cn` | 0644 | 上游 | 首次开机登记语言名, 成功后自动删除, `luci.mk` 构建时生成 |

第 8 项的补丁: 上游挂在 `admin/vpn/tailscale`(`order` 90), 项目改为 `admin/services/tailscale` 并删掉 `order` 让它按名称排序(见 `3.feeds-after-script.sh` 的 `# luci-app-tailscale-community` 和 `# 菜单顺序` 段).

## 3. `tailscale` 包(GuNanOvO)

### 3.1 补丁

补丁在 `feeds-patch/tailscale/`, 由 `2.feeds-insert-script.sh` 的 `# tailscale` 段按下面的顺序应用, 上下文与上游不匹配时构建失败. 构建结果: `tailscaled` 已去符号(`-s -w`), 内置命令行(构建标签 `ts_include_cli`), 不做 UPX 压缩, 版本串 `1.104.4-1 (OpenWrt)`.

1. `build-depends-golang-host`: 加 `PKG_BUILD_DEPENDS:=golang/host`, 使用 feeds 里的 Go, 不用 CI 主机上的 Go
2. `remove-upx-labels`: 版本串 `1.104.4-1 (OpenWrt-UPX)` 改为 `1.104.4-1 (OpenWrt)`, 去掉 `TITLE` 里的 `(UPX Compressed)`. 上游 Makefile 只在 `$(TOPDIR)/upx/upx` 存在时才压缩, 本项目的构建不提供该文件, 二进制不含 `UPX!` 标记
3. `remove-maintainer-export`: 删除 `Package/tailscale/install` 里把 `tailscaled` 复制到 `$(TOPDIR)/bin/packages/<arch>/base` 的 5 行(上游为自己的仓库保留的副本)
4. `tailscale-subnet-guard-install`: `DEPENDS` 加 `ip-full`, 并把守卫脚本安装为 `/etc/init.d/tailscale-subnet-guard`(应用前先把 `tailscale-subnet-guard.init` 复制到包的 `files/`)
5. `tailscale-subnet-guard-service-hooks`: 给 `/etc/init.d/tailscale` 加 `service_started`, `service_stopped` 钩子

### 3.2 `/etc/init.d/tailscale`

procd 服务脚本, START=80, 没有 STOP. 启动前和停止时执行 `tailscaled --cleanup`, 设置 `TS_NO_LOGS_NO_SUPPORT=true` 关闭日志上传. 异常退出自动重启, 连续失败后 procd 放弃, 需要 `/etc/init.d/tailscale restart`.

1. 钩子: `service_started`, `service_stopped` 分别执行守卫的 `start`, `stop`. `rc.common` 在 `start`, `stop`, `restart` 和开机的 `boot` 时调用钩子(`restart` 时守卫换新进程号); procd 自动重启崩溃的 `tailscaled` 时不调用, 守卫保持原状
2. 自启: 脚本没有"是否自启"的开关, 只取决于镜像构建时生成的 `/etc/rc.d/S80tailscale` 链接. `tailscale-settings` 关闭服务时会 disable 它, 但新镜像会重新带来这个链接(例如刷机保留配置后), 所以由 `tailscale-boot-gate`(见 4.3)在开机时按 `service_enabled` 决定是否保留
3. 对运行中的服务执行 `start`: 先执行 `tailscaled --cleanup`, 进程不重启, `tailscale0` 的 tailnet 地址, table 52 的 IPv4 路由, netfilter 的 `ts-*` 链被清掉, 内核路径不通, `restart` 恢复(见 `tailscale-network-restart-table52.md` 4.2)

### 3.3 `/etc/init.d/tailscale-subnet-guard`

项目新增, 源文件 `feeds-patch/tailscale/tailscale-subnet-guard.init`. 无 START, 不生成开机链接.

**作用**: `tailscale` 运行期间, 只有接收到的子网与本地网段重叠时才添加 ip rule, 防止路由表 52(pref 5270)劫持本地网段的流量; 重叠消失或 `tailscale` 停止时删除. 每个被覆盖的本地网段一条, IPv4 和 IPv6 各自独立:

`pref 1295 to <本地网段> lookup main suppress_prefixlength 0`

即先查 main 表并忽略其默认路由, 使该网段的具体本地路由优先于路由表 52. 规则是运行时的 ip rule, 不写入 `/etc/config/network`, LuCI 里看不到.

**运行方式**:

1. 启停: 由 3.2 的钩子随 `tailscale` 启停, 开机时不单独启动, 也可以手动执行 `/etc/init.d/tailscale-subnet-guard start|stop|restart`. `stop` 返回时规则已消失
2. 对账: `start` 让 procd 托管常驻进程 `watch`, 它用 `ip monitor route rule` 监听路由和规则的变化, 按路由表 52 和 main 的现状补缺删多, 1 秒内的变化合并成一次, 另每 60 秒兜底对账一次. 常驻对账是因为 netifd 启动时会清空所有 ip rule, `tailscaled` 只恢复自己 pref 范围内的规则. 每次增删记一条系统日志, 标签 `tailscale-subnet-guard`
3. 保活: procd 的 `respawn` 为 threshold 3600, timeout 5, retry 5. `watch` 被杀死后约 5 秒拉起, 3600 秒内被杀死第 6 次后 procd 放弃, 不再对账, 已有规则留在内核里. 放弃后单独 `start` 会重新拉起进程, 但不清零失败计数, `stop` 再 `start`(`restart`, `tailscale restart`)才清零

**判定**(IPv4 和 IPv6 各自独立):

1. 接收路由 R: 路由表 52 里的路由, 不含默认路由, 特殊路由(`throw`/`blackhole`/`unreachable`/`prohibit`)以及 tailnet 地址段(`100.64.0.0/10`, `fd7a:115c:a1e0::/48`)内的路由
2. 本地网段 L: main 表里的非默认路由, 不含特殊路由, 也不含前缀短于 IPv4 /8 或 IPv6 /16 的(如 OpenVPN 的拆分默认路由 `0.0.0.0/1` 加 `128.0.0.0/1`: `suppress_prefixlength 0` 抑制不了 /1, 加规则会把 tailnet 的流量也抢到 main)
3. L 与任一 R 相等或互相包含, 就对该 L 加规则. 规则的 `to` 是 L 本身(不是 R, 也不是交集), 所以 L 越宽规则越宽: main 里有 `10.0.0.0/8` 这类宽静态路由时, 落在其中的 R 整段用不上
4. 只处理 pref 1295 里形如 `from all to <网段> lookup main suppress_prefixlength 0` 的规则, 不动其他规则

### 3.4 `/etc/config/tailscale`

UCI 配置(conffile), 出厂只有 `settings` 一节, 5 个守护进程选项, 由 `/etc/init.d/tailscale` 读取:

1. `log_stderr`, `log_stdout`(默认 `1`): 是否由 procd 把守护进程的 stderr, stdout 送入系统日志. tailscaled 的日志全部写 stderr(系统日志里为 `daemon.err`), `log_stderr` 为 0 时系统日志里没有它的日志
2. `port`(默认 `41641`): 监听端口(`--port`)
3. `state_file`(默认 `/etc/tailscale/tailscaled.state`): 状态文件路径(`--state`)
4. `fw_mode`(默认 `nftables`): 防火墙后端(环境变量 `TS_DEBUG_FIREWALL_MODE`)

LuCI 页面保存时还会写入 `tailscale-settings` 读取的选项(如 `service_enabled`, `dns_mode`), 以及只供页面登录用的 `custom_login_url`, `custom_login_AuthKey`: Auth Key 以明文留在该文件里, `tailscaled` 和 `tailscale-settings` 都不读取它们.

**注意**: 固件没有选 `iptables-nft` 和 `iptables-zz-legacy`, 设备上没有 `iptables`, `ip6tables` 命令, `fw_mode` 只能用 `nftables`, 但 LuCI 下拉框里仍有 `iptables`. 选 `iptables` 时 tailscaled 启动即以退出码 1 退出, procd 放弃重试后服务停止, 守卫进程仍在运行, 把 `fw_mode` 改回 `nftables` 不会自动拉起 tailscaled, 需要 `/etc/init.d/tailscale restart`.

## 4. `luci-app-tailscale-community`(Tokisaki-Galaxy)

### 4.1 `/usr/share/rpcd/ucode/tailscale.uc`

rpcd 的 ucode 插件, 注册 ubus 对象 `tailscale`, 是网页和系统之间的后端, 9 个方法:

1. 读取类: `get_status`, `get_settings`, `get_subroutes`, `get_logs`, `get_firewall_status`. 其中 `get_subroutes` 执行 `ip -j route`(需要 ip-full), 返回 main 表里 IPv4 `scope link` 的网段, 作为"通告路由"的可选项
2. 登录类: `do_login` 只在状态为 `logout` 时执行, `do_logout` 只在状态为 `running` 时执行, 其他状态返回 error
3. `set_service_enabled`: 参数 `enabled` 只能是 `0` 或 `1`, 其他值返回 error. `0` 创建停用请求标记 `/var/run/tailscale-settings/disable-requested`, `1` 删除标记. 不启停进程, 不改 UCI, 真正的停止由 `tailscale-settings` 在重载时执行
4. `setup_firewall`: 用 UCI 补齐 `network.tailscale` 接口(`proto none`, 设备 `tailscale0`, 已存在但设备不是 `tailscale0` 时改成 `tailscale0`), 防火墙区域 `tailscale`(masq, mtu_fix; 已存在时只补 `network` 引用)和 3 条转发(lan 到 tailscale, tailscale 到 lan, tailscale 到 wan), 只补缺失的. 配置齐全时返回 `Tailscale firewall/interface already configured.`, 不启动后台脚本; 有缺失项时提交, 写 `/var/run/tailscale-fwsetup.status`, 再在后台启动 `/usr/libexec/tailscale-setup-firewall`. 该脚本依次执行 `/etc/init.d/network reload` 和 `/etc/init.d/firewall reload`, 单独拆成脚本是为了让 RPC 先返回, 避免 reload 网络时掐断正在处理的请求

**补丁** `import-fs-rename`(在 `feeds-patch/luci-app-tailscale-community/`, 由 `3.feeds-after-script.sh` 的 `# luci-app-tailscale-community` 段应用, 上下文与上游不匹配时构建失败): `fs` 的导入列表里加上 `rename`. 上游的 `setup_firewall` 调用了 `rename` 但没导入, 在 `'use strict'` 下抛出 `access to undeclared variable rename`; 有缺失项时 UCI 已提交, RPC 返回 `error`, 后台脚本没有启动, `network` 和 `firewall` 没有重载.

**补丁** `setup-firewall-status-error-message`(在 `feeds-patch/luci-app-tailscale-community/`, 由 `3.feeds-after-script.sh` 的 `# luci-app-tailscale-community` 段应用, 上下文与上游不匹配时构建失败): `setup_firewall` 写不了状态文件 `/var/run/tailscale-fwsetup.status` 时, 返回的 `error` 改为说明配置已提交但未应用. 这个出口在 UCI 提交之后, 后台脚本没有启动, 上游的消息却是 `Configuration was not changed.`. 再次执行时配置已齐全, 直接返回(见第 4 点), 不会补做重载.

### 4.2 `/etc/init.d/tailscale-settings`

START=99, STOP=10. 开机以及 UCI `tailscale` 变化时运行:

1. 把 LuCI 选项转成 `tailscale set` 参数, tailscaled 没有运行时跳过. 已保存的 `AutoUpdate.Apply=true` 使 `tailscale set` 报 `Auto-update support is disabled in this build` 时, 先执行 `tailscale set --auto-update=false` 再重试
2. 按 `dns_mode` 在 dnsmasq 增删 `.ts.net` 转发(见 5 第 4 点); `fw_mode`, `port`, `state_file`, `log_stdout`, `log_stderr` 变化时重启守护进程(日志 `Daemon options changed, restarting tailscale`), 其他选项变化不重启
3. 按 `service_enabled` 启停:
   1. 为 1: 只有 tailscaled 未运行且上一次应用的值为 0 才执行 enable 再 start. tailscaled 在运行时不动进程, 也不重新生成 `S80tailscale` 链接(对运行中的服务执行 `start` 会清掉内核状态, 见 3.2 第 3 点). 上一次的值已是 1 时, 手工停止或崩溃的 tailscaled 不会被拉起
   2. 为 0: 存在停用请求标记(RPC `set_service_enabled` 创建, 页面的"保存并应用"会调用它, 见 4.4)才执行 stop 再 disable. 没有标记(手工编辑配置)只执行 disable, 进程继续运行. 上一次的值已是 0 时什么也不做

**补丁** `tailscale-settings-reset-hostname-netfilter`(在 `feeds-patch/luci-app-tailscale-community/`, 由 `3.feeds-after-script.sh` 的 `# luci-app-tailscale-community` 段应用, 上下文与上游不匹配时构建失败): 改为每次都传 `--hostname` 和 `--netfilter-mode`. 上游只在 `hostname` 非空, `disable_fw_config` 勾选时才传, 而 `tailscale set` 只改传入的参数, 没传的保持 tailscaled 已保存的值, 所以:

1. 勾选 `disable_fw_config` 再取消勾选: `NetfilterMode` 一直是 `off`(0), tailscaled 不再写自己的 netfilter 规则(命令行提示 `netfilter=off; configure iptables yourself.`). 页面上看起来已恢复
2. 手工设置 `hostname` 后再删掉这个 UCI 选项: 已保存的主机名不会清除, 节点继续用旧主机名

### 4.3 `/etc/init.d/tailscale-boot-gate`

项目新增, START=70, 源文件 `feeds-patch/luci-app-tailscale-community/tailscale-boot-gate.init`, 由 `3.feeds-after-script.sh` 用 `install -m 0755` 放进包的 `root/etc/init.d/`, `luci.mk` 随包安装.

**作用**: 每次开机(早于 `S80tailscale`)读 `service_enabled`: 值为 0 且 `/etc/rc.d/S80tailscale` 链接还在时, 删掉这个链接并记录日志 `service_enabled=0, removed boot link of tailscale`, 这次开机的 S80 就不会启动 `tailscaled`; 值为 1 或选项不存在时什么也不做. 只删链接, 不停止进程, 不改配置. 只实现 `boot()`, 手动 `start`/`stop`/`restart`/`reload` 是空操作, 手动触发判定用 `/etc/init.d/tailscale-boot-gate boot`.

**原理**: procd 开机时先列出所有 `/etc/rc.d/S*`, 再逐个顺序执行, 执行那一刻才按路径启动. S70 删掉链接后, 轮到 S80 时路径已不存在, 启动失败并被跳过.

### 4.4 `/www/luci-static/resources/view/tailscale.js`

LuCI 页面前端, 来自上游. "保存并应用"由 `handleSaveApply` 处理, 依次执行:

1. `map.save()`: 解析表单, 把改动暂存到设备的 UCI 变更列表(尚未提交)
2. RPC `set_service_enabled`: 按 `service_enabled` 的新值创建或删除停用请求标记(见 4.1 第 3 点). 失败时只在控制台记一条告警, 不中断后面的步骤
3. `ui.changes.apply`: LuCI 的标准应用流程(带回滚保护), 提交后触发 `tailscale-settings` 重载(见 4.2)

**补丁** `save-apply-set-service-enabled`(在 `feeds-patch/luci-app-tailscale-community/`, 由 `3.feeds-after-script.sh` 的 `# luci-app-tailscale-community` 段应用, 上下文与上游不匹配时构建失败): 修正第 2 步里的两处错误. 上游的这两处错误让 `set_service_enabled` 的请求始终无效, 在 LuCI 里把服务从启用改为停用时, 停用请求标记不会创建, 重载时只 disable 开机自启, `tailscaled` 继续运行(日志 `service_enabled=0 for the first time, disabling autostart only`), 与页面上该选项的说明(禁用后服务会被停止)不符:

1. 读取时机: 上游在 `map.save()` 之前用 `uci.get()` 读 `service_enabled`. 表单的值要等 `map.save()` 解析表单时才写进 uci 模型, 此前读到的是上一次保存的值: 从启用改为停用时读到 `1`, 请求的是"启用"; 从停用改为启用时读到 `0`, 请求的是"停用". 补丁改为在 `map.save()` 的回调里读(表单解析之后, 暂存的修改发给设备之前)
2. 参数形状: RPC 声明为 `params: ['enabled']`, 调用时按位置把第一个实参作为 `enabled` 的值. 上游传的是对象 `{ enabled: '0' }`, ubus 收到的是 `{"enabled": {"enabled": "0"}}`, 而后端声明 `enabled` 是字符串, ubus 在参数校验阶段就返回状态码 2(`Invalid argument`), 请求到不了后端的处理函数. 声明里没有 `reject: true`, 状态码 2 被当作普通返回值, 第 2 步的 `catch` 不会触发, 页面没有任何提示. 补丁改为直接传字符串 `'0'` 或 `'1'`

两处单独修都不够: 只修第 1 点时请求的形状仍然无效; 只修第 2 点时, 从启用改为停用传的是 `'1'`, 从停用改为启用传的是 `'0'`. 从停用改为启用在补丁前不受影响: 重载时 `service_enabled` 已是 `1`, 无论有没有标记, 都会先清掉标记再启动(见 4.2 第 3 点).

## 5. 运行时产生和修改的内容

1. 镜像构建时生成的 `/etc/rc.d/` 开机链接(`default_postinst` 对包内 init 脚本执行 enable): `S70tailscale-boot-gate`, `S80tailscale`, `S99tailscale-settings`, `K10tailscale-settings`. 守卫没有 START/STOP, 没有开机链接
2. 状态文件: `/etc/tailscale/`(随 sysupgrade 保留)下的 `tailscaled.state`(登录状态和节点密钥), `derpmap.cached.json`, `dns-cache/`, `profile-data/`; `/var/run`(tmpfs, 重启清空)下的 `tailscale/`, `tailscale-settings/`(最近一次应用的选项记录和停用请求标记), `tailscale-fwsetup.status` 和 `tailscale-fwsetup.lock.d/`(进度和锁)
3. 内核里由 tailscaled 写入的 `tailscale0` 网卡, table 52 路由, pref 5210 到 5270 的 ip rule, tailnet 地址, netfilter 的 `ts-*` 链(见 `tailscale-network-restart-table52.md`), 以及守卫的常驻进程和 pref 1295 的 ip rule
4. 被修改的系统配置: `/etc/config/network` 和 `/etc/config/firewall`(见 4.1 的 `setup_firewall`); `dns_mode` 为 `openwrt_forward` 时在 `/etc/config/dhcp` 给 dnsmasq 的 `server` 列表加 `/.ts.net/100.100.100.100`, 切到 `magicdns` 时删除, 为 `disabled` 时保持现状; `tailscale-settings` 和 `tailscale-boot-gate` 增删 `/etc/rc.d/S80tailscale`

## 6. 设备上核对

```sh
# 1. 三个包安装的文件, 与 2.2 文件总表一致
opkg files tailscale
opkg files luci-app-tailscale-community
opkg files luci-i18n-tailscale-community-zh-cn

# 2. 开机链接 4 个: S70tailscale-boot-gate, S80tailscale, S99tailscale-settings, K10tailscale-settings
#    (service_enabled=0 时开机会删掉 S80tailscale, 只剩 3 个)
ls -l /etc/rc.d/ | grep tailscale

# 3. 执行权限 -rwxr-xr-x, 未被 UPX 压缩(输出 0), /sbin/ip 指向 /usr/libexec/ip-full
ls -l /usr/libexec/tailscale-setup-firewall
grep -c 'UPX!' /usr/sbin/tailscaled
ls -l /sbin/ip

# 4. 守卫
#    4.1 tailscale 运行时有常驻的 watch 进程, 停止后消失(ps 要加 ww, 否则 BusyBox 会截断进程名)
ps ww | grep '[t]ailscale-subnet-guard'
#    4.2 pref 1295 规则: 无重叠时为空, 有重叠时每个被覆盖的本地网段一条, tailscale stop 返回后也为空
ip -4 rule show | grep '^1295:'
ip -6 rule show | grep '^1295:'
#    4.3 增删记录, 形如 "add rule: to 192.168.1.0/24"
logread -e tailscale-subnet-guard
#    4.4 手动 restart 在数秒内返回, 退出码为 0(卡住说明 watch 没有释放 procd 的锁, 按 Ctrl+C 中断)
/etc/init.d/tailscale-subnet-guard restart; echo $?
```
