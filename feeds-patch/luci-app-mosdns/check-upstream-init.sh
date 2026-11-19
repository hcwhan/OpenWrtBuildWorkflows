#!/bin/bash
set -euo pipefail

# 构建时校验上游 init 脚本满足 anti-pollution.uc 的假设, 不满足时构建失败, 路由器上的脚本不会遇到它无法处理的配置.
# 用法: check-upstream-init.sh <init 脚本>
# init 脚本里每个 plugin 的生成代码以 "# plugin: <tag>" 注释开头, 到下一个 "# plugin:" 注释之前结束, 比较时忽略缩进.

INIT="${1:?usage: check-upstream-init.sh <init script>}"

fail() {
  echo "ERROR: $1 in $INIT; upstream changed, review anti-pollution.uc" >&2
  exit 1
}

# 输出 plugin 的生成代码, 去掉每行的缩进.
plugin_block() {
  awk -v tag="$1" '/^\t# plugin: / { on = ($3 == tag) } on { sub(/^[ \t]+/, ""); print }' "$INIT"
}

# require_lines <tag> <行>...: 这些行在 plugin 的生成代码里连续出现.
require_lines() {
  local tag="$1"
  shift
  local want
  want=$(printf '%s\n' "$@")
  plugin_block "$tag" | WANT="$want" awk '
    BEGIN { text = "\n" }
    { text = text $0 "\n" }
    END { exit index(text, "\n" ENVIRON["WANT"] "\n") == 0 }
  ' || fail "plugin $tag: lines not found: $(printf '%s' "$want" | tr '\n' '|')"
}

# plugin 在 init 脚本里的行号.
plugin_line() {
  awk -v tag="$1" '/^\t# plugin: / && $3 == tag { print NR; exit }' "$INIT"
}

# require_before <被引用的 tag> <引用者 tag>: mosdns 按顺序初始化 plugin, 被引用的 plugin 必须定义在前面.
require_before() {
  local dep user
  dep=$(plugin_line "$1")
  user=$(plugin_line "$2")
  if [ -z "$dep" ] || [ -z "$user" ] || [ "$dep" -ge "$user" ]; then
    fail "plugin $1 is not defined before $2"
  fi
}

# 脚本引用的 plugin 必须存在.
for tag in geoip_cn forward_local forward_remote_upstream has_resp_sequence; do
  require_lines "$tag" "json_add_string \"tag\" \"$tag\""
done

# 脚本改写的 sequence, fallback 的类型.
for tag in query_is_local_domain query_is_ddns_domain query_is_whitelist_domain query_is_reject_domain main_sequence; do
  require_lines "$tag" "json_add_string \"tag\" \"$tag\"" 'json_add_string "type" "sequence"'
done
require_lines apple_domain_fallback 'json_add_string "tag" "apple_domain_fallback"' 'json_add_string "type" "fallback"'

# 强制使用 forward_local 的三条规则, 脚本把它们的 exec 改为 china_fallback.
require_lines query_is_local_domain 'json_add_string "matches" "qname \$geosite_cn"' 'json_add_string "exec" "\$forward_local"'
require_lines query_is_ddns_domain 'json_add_string "matches" "qname \$ddnslist"' 'json_add_string "exec" "\$forward_local"'
require_lines query_is_whitelist_domain 'json_add_string "matches" "qname \$whitelist"' 'json_add_string "exec" "\$forward_local"'

# Apple 的次选, 脚本把它改为 forward_remote_upstream.
require_lines apple_domain_fallback 'json_add_string "secondary" "forward_xinfeng_udp"'

# 开启「禁用 RR Type 65」时生成的规则, 脚本把它移到 main_sequence 里, 应答改为 reject 0.
require_lines query_is_reject_domain 'json_add_string "matches" "qtype 65"' 'json_add_string "exec" "reject 3"'

# hosts 之后紧跟 jump has_resp_sequence, 脚本把 type 65 规则插在这两条之后.
require_lines main_sequence 'json_add_string "exec" "\$hosts"' 'json_close_object' 'json_add_object' 'json_add_string "exec" "jump has_resp_sequence"'

# 脚本新增的 plugin 不能和上游已有的重名.
for tag in poison_ip any_ip china_ip_check china_fallback; do
  if grep -qF "json_add_string \"tag\" \"$tag\"" "$INIT"; then
    fail "plugin $tag already exists"
  fi
done

# 定义顺序: china_fallback 引用 geoip_cn, forward_local, forward_remote_upstream, 它被插在最先使用它的 sequence 之前.
for dep in geoip_cn forward_local forward_remote_upstream; do
  for user in query_is_local_domain query_is_ddns_domain query_is_whitelist_domain; do
    require_before "$dep" "$user"
  done
done
require_before forward_remote_upstream apple_domain_fallback
require_before has_resp_sequence main_sequence
