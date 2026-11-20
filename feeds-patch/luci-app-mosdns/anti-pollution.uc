#!/usr/bin/env ucode

// 改写 /etc/init.d/mosdns 生成的配置, 使国内 DNS(forward_local)返回的污染 IP 不会到达客户端.
// 用法: anti-pollution.uc <配置文件>. 由 init 脚本在生成配置之后调用, 配置每次启动都会重新生成.
//
// 改写内容:
// 1. geosite_cn, ddnslist, whitelist 域名改走 china_fallback: forward_local 的应答命中 poison_ip, 或含 IP 且不在 geoip_cn 内时丢弃, 回落到 forward_remote_upstream. 不含 IP 的应答保留.
// 2. 其余使用 forward_local 的 sequence(fallback 与 Apple 的主选), 在其后加一步: 应答命中 poison_ip 时丢弃. 丢弃后主流程继续走后面的分支.
// 3. Apple 域名的次选由 forward_xinfeng_udp 改为 forward_remote_upstream, 主选超过 500 ms 未应答时采用次选的应答.
// 4. 开启「禁用 RR Type 65」时, init 脚本在 query_is_reject_domain 里生成 type 65 规则, 位置在 Apple, ddnslist, whitelist 分支之后. 把该规则移到 main_sequence 中 hosts 之后, 应答由 reject 3 改为 reject 0(空应答), 这些分支不会再转发 type 65 查询. 选项关闭时不改动. resp_ip 不检查 HTTPS 记录里的 IP hint.
//
// 改写点在配置里找不到时报错退出, 配置文件保持原样.

'use strict';

import { readfile, writefile, rename } from 'fs';

// 落在 CN 地址段内的已知污染 IP. 它们能通过 geoip_cn 校验, 拦不住, 所以单独列出.
// 在 CN 地址段外的污染 IP 由 geoip_cn 校验拦截, 不需要列在这里.
//
// 来源: 维基学院「防火长城域名服务器缓存污染IP列表」
//       https://zh.wikiversity.org/wiki/防火长城域名服务器缓存污染IP列表
// 筛选: 取该页面 IPv4 列表(739 个)里落在 geoip_cn 内的全部地址, 共 5 个.
// 版本: 2026-09-13 的修订(IPv4 部分自 2024-04-06 起未变), 2026-11-20 核对.
//
// IPv6: 同一页面的 IPv6 列表(454 个, 都在 2001::/32 和 2a03:2880::/32 内)
//       没有落在 geoip_cn 内的地址, 所以这里只有 IPv4.
const POISON_IPS = [ '118.184.26.113', '118.184.78.78', '118.193.202.219', '118.193.240.37', '118.193.240.41' ];

// 强制使用国内 DNS 的 sequence 及其规则的匹配条件.
const FORCE_LOCAL = {
	query_is_local_domain: 'qname $geosite_cn',
	query_is_ddns_domain: 'qname $ddnslist',
	query_is_whitelist_domain: 'qname $whitelist'
};

function fail(msg) {
	warn(`anti-pollution: ${msg}\n`);
	exit(1);
}

function plugin_index(plugins, tag) {
	for (let i = 0; i < length(plugins); i++)
		if (plugins[i].tag == tag)
			return i;

	fail(`plugin ${tag} not found`);
}

function plugin_of(plugins, tag) {
	return plugins[plugin_index(plugins, tag)];
}

// 返回 sequence 中第一条 exec 等于给定值的规则的下标.
function rule_index(plugin, exec) {
	for (let i = 0; i < length(plugin.args); i++)
		if (plugin.args[i].exec == exec)
			return i;

	fail(`rule "${exec}" not found in ${plugin.tag}`);
}

const file = ARGV[0];
if (!file)
	fail('usage: anti-pollution.uc <config file>');

const raw = readfile(file);
if (raw == null)
	fail(`cannot read ${file}`);

const cfg = json(raw);
if (type(cfg) != 'object' || type(cfg.plugins) != 'array')
	fail(`${file} is not a mosdns config`);

const plugins = cfg.plugins;

// 已经改写过的配置不再处理.
for (let i = 0; i < length(plugins); i++)
	if (plugins[i].tag == 'china_fallback')
		exit(0);

// 1. 强制使用国内 DNS 的域名改走 china_fallback. 先于第 2 步, 使这些规则不再含 forward_local, 不需要单独的污染 IP 校验.
const force_local_tags = keys(FORCE_LOCAL);
for (let i = 0; i < length(force_local_tags); i++) {
	const tag = force_local_tags[i];
	const seq = plugin_of(plugins, tag);
	const rule = seq.args[rule_index(seq, '$forward_local')];
	if (rule.matches != FORCE_LOCAL[tag])
		fail(`${tag} does not match ${FORCE_LOCAL[tag]}`);
	rule.exec = '$china_fallback';
}

// 2. 其余使用 forward_local 的 sequence, 在其后丢弃命中 poison_ip 的应答.
for (let p = 0; p < length(plugins); p++) {
	if (plugins[p].type != 'sequence')
		continue;

	const args = plugins[p].args;
	for (let i = 0; i < length(args); i++) {
		if (args[i].exec == '$forward_local') {
			splice(args, i + 1, 0, { matches: 'resp_ip $poison_ip', exec: 'drop_resp' });
			i++;
		}
	}
}

// 3. Apple 域名的次选改为远程 DNS, 主选的等待时限(threshold, 毫秒)设为 500.
const apple = plugin_of(plugins, 'apple_domain_fallback');
if (apple.args.secondary != 'forward_xinfeng_udp')
	fail('apple_domain_fallback secondary is not forward_xinfeng_udp');
apple.args.secondary = 'forward_remote_upstream';
apple.args.threshold = 500;

// 4. 开启「禁用 RR Type 65」时, type 65 规则移到 main_sequence 中 hosts 与其后的 has_resp_sequence 跳转之后, 应答改为 reject 0.
const reject_rules = plugin_of(plugins, 'query_is_reject_domain').args;
let type65_at = -1;
for (let i = 0; i < length(reject_rules); i++) {
	if (reject_rules[i].matches == 'qtype 65') {
		type65_at = i;
		break;
	}
}

if (type65_at >= 0) {
	if (reject_rules[type65_at].exec != 'reject 3')
		fail('query_is_reject_domain: qtype 65 rule is not reject 3');

	const main = plugin_of(plugins, 'main_sequence');
	const hosts = rule_index(main, '$hosts');
	if (hosts + 1 >= length(main.args) || main.args[hosts + 1].exec != 'jump has_resp_sequence')
		fail('main_sequence: hosts is not followed by jump has_resp_sequence');

	splice(reject_rules, type65_at, 1);
	splice(main.args, hosts + 2, 0,
		{ matches: 'qtype 65', exec: 'reject 0' },
		{ exec: 'jump has_resp_sequence' });
}

// 新增的 plugin. tag 必须定义在引用它的 plugin 之前.
splice(plugins, plugin_index(plugins, 'geoip_cn') + 1, 0,
	{ tag: 'poison_ip', type: 'ip_set', args: { ips: POISON_IPS } },
	{ tag: 'any_ip', type: 'ip_set', args: { ips: [ '0.0.0.0/0', '::/0' ] } });

// china_ip_check 和 china_fallback 放在最先引用 china_fallback 的 plugin 之前, 它们依赖的 plugin 必须在更前面.
let china_at = length(plugins);
for (let i = 0; i < length(force_local_tags); i++) {
	const at = plugin_index(plugins, force_local_tags[i]);
	if (at < china_at)
		china_at = at;
}

const china_deps = [ 'poison_ip', 'any_ip', 'geoip_cn', 'forward_local', 'forward_remote_upstream' ];
for (let i = 0; i < length(china_deps); i++)
	if (plugin_index(plugins, china_deps[i]) > china_at)
		fail(`${china_deps[i]} is defined after the plugins using china_fallback`);

splice(plugins, china_at, 0,
	{ tag: 'china_ip_check', type: 'sequence', args: [
		{ exec: '$forward_local' },
		{ matches: 'resp_ip $poison_ip', exec: 'drop_resp' },
		{ matches: [ 'resp_ip $any_ip', '!resp_ip $geoip_cn' ], exec: 'drop_resp' }
	] },
	{ tag: 'china_fallback', type: 'fallback', args: {
		primary: 'china_ip_check',
		secondary: 'forward_remote_upstream',
		threshold: 1000,
		always_standby: false
	} });

const tmp = `${file}.tmp`;
if (writefile(tmp, sprintf('%.J\n', cfg)) == null || !rename(tmp, file))
	fail(`cannot write ${file}`);

print('anti-pollution: applied\n');
