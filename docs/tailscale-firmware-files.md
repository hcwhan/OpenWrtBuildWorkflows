
# 固件中的 Tailscale 相关文件清单

编译完成后, `tailscale`(GuNanOvO)和 `luci-app-tailscale-community`(Tokisaki-Galaxy)两个来源在固件里提供的文件, 以及每个文件的功能和作用.

## 1. 说明

1. 范围: `build_AX3600`, `build_NX30Pro`, `build_x86` 三个工作流, 三个目标的文件清单相同
2. 依据: 上游 Makefile 与源文件, 本项目补丁脚本, 三份 `.config-*`. 8.1 的部分项在安装固件的设备上核对过, 静态推断的内容已单独标注
3. 整理日期: 2026-10-25
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
| 3 | `/etc/init.d/tailscale` | 0755 | 上游 | 守护进程的 procd 启动脚本 |
| 4 | `/etc/init.d/tailscale-ip-rules` | 0755 | 项目 | 开机补 ip rule, 防子网劫持 |
| 5 | `/etc/config/tailscale` | 0644 | 上游 | UCI 配置 |
| 6 | `/lib/upgrade/keep.d/tailscale` | 0644 | 上游 | sysupgrade 保留清单, 内容为 `/etc/tailscale/` |
| 7 | `/www/luci-static/resources/view/tailscale.js` | 0644 | 上游 | LuCI 页面前端 |
| 8 | `/usr/share/luci/menu.d/luci-app-tailscale-community.json` | 0644 | 上游+补丁 | 菜单注册 |
| 9 | `/usr/share/rpcd/acl.d/luci-app-tailscale-community.json` | 0644 | 上游 | 权限声明 |
| 10 | `/usr/share/rpcd/ucode/tailscale.uc` | 0755 | 上游 | 后端, ubus 对象 `tailscale` |
| 11 | `/etc/init.d/tailscale-settings` | 0755 | 上游+补丁 | 把 LuCI 设置应用到 tailscale |
| 12 | `/usr/libexec/tailscale-setup-firewall` | 0755 | 上游 | "自动配置防火墙"的后台执行者 |
| 13 | `/etc/init.d/tailscale-boot-gate` | 0755 | 项目 | 开机时按 `service_enabled` 决定 tailscale 是否自启 |
| 14 | `/usr/lib/lua/luci/i18n/community.zh-cn.lmo` | - | 上游 | 简体中文翻译 |
| 15 | `/etc/uci-defaults/luci-i18n-tailscale-community-zh-cn` | - | 上游 | 首次开机登记语言名 |

权限为 `-` 的两个文件由 `luci.mk` 在构建时生成. 第 6 项由 ImmortalWrt 的构建系统生成, 不是上游 Makefile 安装的, 见 3.6.

## 3. `tailscale` 包(GuNanOvO)

依赖: `ca-bundle`, `kmod-tun`(均来自 ImmortalWrt 自身).

### 3.1 `/usr/sbin/tailscaled`

> 标记: 上游+补丁 | 权限: 0755

**作用**: 守护进程本体, 已去符号(`-s -w`), 并内置命令行(构建标签 `ts_include_cli`). 负责创建 `tailscale0` 网卡, 连接控制服务器, 与对端建立 WireGuard 隧道(含 NAT 穿透和 DERP 中继), 写 nftables 规则和路由, 通过 unix socket 提供本地 API.

**补丁**: 构建标签在上游 14 个的基础上追加 `ts_omit_flashappliance`, 共 15 个(`feeds-patch/tailscale/omit-flashappliance.patch`, 由 `feeds-insert-script.sh` 的 `# tailscale` 段应用). 原因: 仅用 `ts_omit_clientupdate` 时, flash-appliance 的命令行子命令仍会链接 `tailscale.com/clientupdate`, 使 `CanAutoUpdate()` 保持为 true, tailscaled 启动时无法清除已保存的 `AutoUpdate.Apply=true`.

**补丁(版本串)**: 版本串由 `1.104.2-1 (OpenWrt-UPX)` 改为 `1.104.2-1 (OpenWrt)`, 包描述 `TITLE` 里的 `(UPX Compressed)` 一并去掉(`feeds-patch/tailscale/remove-upx-labels.patch`, 由 `feeds-insert-script.sh` 的 `# tailscale` 段应用). 原因: 这两处是上游写死的字样, 而本项目构建并未压缩.

**压缩**: 上游 Makefile 只在 `$(TOPDIR)/upx/upx` 存在时才用 UPX 压缩, ImmortalWrt 23.05 和本项目 CI 都没有提供, 所以未压缩. 安装固件的设备上已验证, 见 8.1.

### 3.2 `/usr/sbin/tailscale`

> 标记: 上游 | 类型: 符号链接, 指向 `tailscaled`

**作用**: 同一个二进制以 `tailscale` 名字调用时进入命令行模式(`status`, `login`, `logout`, `set`, `get` 等). LuCI 后端 `tailscale.uc` 和 `tailscale-settings` 都通过它操作守护进程.

### 3.3 `/etc/init.d/tailscale`

> 标记: 上游 | 权限: 0755 | START=80

**作用**: procd 服务脚本. 启动前和停止时执行 `tailscaled --cleanup`; 读取 `/etc/config/tailscale` 后拼出 `tailscaled --port <port> --state <state_file>`; 用环境变量 `TS_DEBUG_FIREWALL_MODE` 传入防火墙模式; 设置 `TS_NO_LOGS_NO_SUPPORT=true` 关闭日志上传; 异常退出自动重启(respawn).

**自启**: 脚本里没有"是否自启"的配置项, 自启只取决于镜像构建时由 `default_postinst` 生成的 `/etc/rc.d/S80tailscale` 链接. 本项目不改这个脚本, 开机时是否保留这个链接由 `luci-app-tailscale-community` 里新增的 `tailscale-boot-gate`(见 4.7)按 `service_enabled` 决定.

### 3.4 `/etc/init.d/tailscale-ip-rules`

> 标记: 项目 | 权限: 0755 | START=15 | 源文件: `feeds-patch/tailscale/tailscale-ip-rules.init`

**作用**: 每次开机(早于 `S20network`)向 `/etc/config/network` 补 6 个 netifd `rule`/`rule6` 配置节, 已存在的不改. 目的: 对端通告的子网与本地 LAN 重叠时, 防止路由表 52 劫持 LAN 流量.

1. pref 1295: 先查 main 表(忽略默认路由), 本地具体路由优先(配置节 `tailscale_local_first`, `tailscale_local_first6`)
2. pref 1290: tailnet 地址段 `100.64.0.0/10` 和 `fd7a:115c:a1e0::/48` 固定走表 52(配置节 `tailscale_tailnet_pin`, `tailscale_tailnet_pin6`)
3. pref 1285: tailscaled 自己发出的包(fwmark `0x80000/0xff0000`)走 main 表(配置节 `tailscale_bypass`, `tailscale_bypass6`)

**设计要点**:

1. 用 netifd 配置节, 不直接调用 `ip rule`: netifd 每次启动都会清空所有 ip rule, 直接添加的规则在网络重启后会丢失
2. 用 init 脚本, 不用 `/etc/uci-defaults`: uci-defaults 成功后会被删除, 只执行一次, `/etc/config/network` 被不含这些配置节的旧备份覆盖后无法补回
3. 要关闭规则请设 `option disabled '1'`; 直接删配置节会在下次开机被补回

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

**补丁**: 上游挂在 `admin/vpn/tailscale`(VPN 菜单, `order` 90), 项目改为 `admin/services/tailscale`(服务菜单, 见 `feeds-after-script.sh` 的 `# luci-app-tailscale-community` 段), 并删掉 `order`, 让它按名称排序(见同文件的 `# 菜单顺序` 段).

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

> 标记: 上游+补丁 | 权限: 0755 | START=99, STOP=10

**作用**: 设置应用器. 开机以及 UCI `tailscale` 变化时(`procd_add_reload_trigger`)运行:

1. 把 LuCI 选项转成 `tailscale set` 参数: `--accept-routes`, `--advertise-exit-node`, `--exit-node`, `--exit-node-allow-lan-access`, `--advertise-routes`, `--ssh`, `--accept-dns`, `--shields-up`, `--webclient`, `--snat-subnet-routes`, `--hostname`, `--relay-server-port`, `--netfilter-mode`
2. 按 `dns_mode` 在 dnsmasq 增删转发 `/.ts.net/100.100.100.100`(`openwrt_forward` 添加, `magicdns` 删除, `disabled` 不动)
3. 按 `service_enabled` 对 `/etc/init.d/tailscale` 执行 enable/start 或 stop/disable
4. `port`, `state_file`, `fw_mode`, 日志开关变化时重启守护进程

**补丁**: 一处, 写成一个补丁放在 `feeds-patch/luci-app-tailscale-community/`, 由 `feeds-after-script.sh` 的 `# luci-app-tailscale-community` 段用 `patch -p1 -F0` 应用, 上下文与上游不匹配时构建失败:

1. `skip-apply-when-not-running.patch`(`apply_settings`): 在 `config_load tailscale` 之后加判断, `tailscaled` 没在运行时跳过 `tailscale set`, 日志写 `tailscale is not running, skip applying settings`. 原因: `tailscale set` 需要守护进程在运行, `service_enabled` 为 0 时开机不会启动 tailscaled, 无条件的 `apply_settings` 必然失败, 日志里会出现 `Failed to apply settings (exit code: 1)`. 按守护进程是否在运行判断, 不依赖 `service_enabled`, 守护进程因其他原因没起来时也一并跳过

### 4.6 `/usr/libexec/tailscale-setup-firewall`

> 标记: 上游 | 权限: 0755

**作用**: "自动配置防火墙"的后台执行者(参数为 run-id). 加锁 `/var/run/tailscale-fwsetup.lock.d`, 依次执行 `/etc/init.d/network reload` 和 `/etc/init.d/firewall reload`, 把进度(`running`, `done`, `failed`, `busy`)写入 `/var/run/tailscale-fwsetup.status`. 单独拆成脚本, 是为了让 RPC 先返回, 避免 reload 网络时掐断正在处理的请求(反向代理, 或经 Tailscale 访问 LuCI).

### 4.7 `/etc/init.d/tailscale-boot-gate`

> 标记: 项目 | 权限: 0755 | START=70 | 源文件: `feeds-patch/luci-app-tailscale-community/tailscale-boot-gate.init`

**作用**: 每次开机(早于 `S80tailscale`)读 `service_enabled`. 值为 0 且 `/etc/rc.d/S80tailscale` 链接还在时, 删掉这个链接, 这次开机的 S80 就不会启动 `tailscaled`; 值为 1 或选项不存在时什么也不做. 只删链接, 不停止进程, 不改配置. 只实现 `boot()`, 只在开机时执行; 手动 `start` / `restart` 和 opkg 安装后的 `start` 都是空操作, 手动验证用 `/etc/init.d/tailscale-boot-gate boot`.

**设计要点**:

1. 为什么需要: `tailscale` 包的 init 脚本没有"是否自启"的开关(见 3.3). `tailscale-settings` 在 LuCI 里关闭服务时会 disable 这个链接, 但链接被新镜像重新带来(例如刷机保留配置后)时, 它不会再执行. 需要有东西在 S80 之前读 `service_enabled`
2. 为什么是独立脚本, 不补丁 `tailscale.init`: `service_enabled` 是 LuCI 应用的选项, 读它的逻辑放在 `luci-app-tailscale-community` 里, `tailscale` 包保持原样
3. 为什么早于 80 就有效: procd 开机时先列出所有 `/etc/rc.d/S*`, 再逐个顺序执行(同一时刻只跑一个), 执行那一刻才按路径启动. S70 先删掉链接, 轮到 S80 时路径已不存在, 启动失败并被跳过(依据 procd 源码 `rcS.c`)
4. 重新开启: 在 LuCI 打开服务后, `tailscale-settings` 会 enable 并启动 `tailscale`, 链接随之恢复
5. 安装方式: `feeds-after-script.sh` 用 `install -m 0755` 放进包的 `root/etc/init.d/`, `luci.mk` 随包安装, 镜像构建时由 `default_postinst` 生成 `S70tailscale-boot-gate` 链接

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
2. `/etc/rc.d/S15tailscale-ip-rules`: 开机启动链接, 指向 `/etc/init.d/tailscale-ip-rules`
3. `/etc/rc.d/S99tailscale-settings`, `/etc/rc.d/K10tailscale-settings`: 开机启动和停止链接, 指向 `/etc/init.d/tailscale-settings`
4. `/etc/rc.d/S70tailscale-boot-gate`: 开机启动链接, 指向 `/etc/init.d/tailscale-boot-gate`
5. `/usr/lib/opkg/info/<包名>.*`: 三个包各自的 opkg 元数据(`.control`, `.list`, `.conffiles` 等). `tailscale.conffiles` 只含 `/etc/config/tailscale`, `/etc/tailscale/` 由 `/lib/upgrade/keep.d/tailscale`(见 3.6)保留, 两者用于 sysupgrade 保留配置和登录状态

前四项由镜像构建时的 `default_postinst` 对包内 init 脚本执行 enable 生成.

### 6.2 运行后才出现(不在固件里)

1. `/etc/tailscale/tailscaled.state`: 登录状态和节点密钥
2. `/var/run/tailscale/tailscaled.sock`: 守护进程本地 API 套接字
3. 网卡 `tailscale0`
4. `/var/run/tailscale-settings/`: `daemon`, `enabled`, `dns_mode`, `disable-requested`(tmpfs, 重启清空)
5. `/var/run/tailscale-fwsetup.status` 和 `/var/run/tailscale-fwsetup.lock.d/`: "自动配置防火墙"的进度和锁

### 6.3 运行后会被修改的系统配置

1. `/etc/config/network`: `tailscale-ip-rules` 补 6 个 ip rule 配置节; "自动配置防火墙"创建 `tailscale` 接口
2. `/etc/config/firewall`: "自动配置防火墙"创建 `tailscale` 区域和 3 条转发
3. `/etc/config/dhcp`: `dns_mode` 为 `openwrt_forward` 时, 给 dnsmasq 的 `server` 列表加 `/.ts.net/100.100.100.100`, 切到 `magicdns` 时删除

### 6.4 包目录里有但不安装

1. `tailscale`: `README.md`, `FORK.md`, `test.sh`, `Makefile`(仅构建用)
2. `luci-app-tailscale-community`: `Makefile`, `po/` 下的源文件

## 7. 文件之间的关系

1. 页面操作: `tailscale.js` → rpcd 的 `tailscale.uc`(权限由 ACL JSON 限定)→ `/usr/sbin/tailscale` → `tailscaled`
2. 保存设置: `tailscale.js` 写 UCI `/etc/config/tailscale` → 触发 `tailscale-settings` 重载 → `tailscale set ...`
3. 守护进程启动参数: `/etc/config/tailscale` → `/etc/init.d/tailscale` → `tailscaled`
4. 网络层: `tailscale-ip-rules` 开机写 `/etc/config/network` 的 ip rule; "自动配置防火墙"写 `network`/`firewall` 后由 `tailscale-setup-firewall` 重载
5. 开机自启: `tailscale-boot-gate`(S70)读 UCI `service_enabled`, 为 0 就删掉 `/etc/rc.d/S80tailscale` → procd 依次执行 S 链接, 跳过已不存在的 S80 → `tailscale` 不启动

## 8. 需要留意与验证

### 8.1 设备上核对

```sh
# 1. 三个包各自安装的文件, 应与 2.2 文件总表一致
opkg files tailscale
opkg files luci-app-tailscale-community
opkg files luci-i18n-tailscale-community-zh-cn

# 2. 开机链接, 预期 5 个: S15tailscale-ip-rules, S70tailscale-boot-gate, S80tailscale, S99tailscale-settings, K10tailscale-settings
#    (service_enabled=0 时开机会删掉 S80tailscale, 只剩 4 个)
ls -l /etc/rc.d/ | grep tailscale

# 3. 执行权限, 预期 -rwxr-xr-x
ls -l /usr/libexec/tailscale-setup-firewall

# 4. UPX 压缩, 输出 0 表示未压缩(见 3.1, 旧固件上实测为 0, tailscaled 为 26596696 字节)
grep -c 'UPX!' /usr/sbin/tailscaled
```
