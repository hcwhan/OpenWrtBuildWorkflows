
# 2.feeds-insert-script.sh 和 3.feeds-after-script.sh 共用的函数, 由它们 source 引入, 不要直接执行.

# 应用补丁: apply_patch <目标目录> <补丁文件>, 禁止模糊匹配, 上下文与上游不匹配时让构建失败.
apply_patch() {
  patch -p1 -F0 --no-backup-if-mismatch -d "$1" < "$2" || {
    echo "ERROR: $(basename "$2") does not apply to $1; upstream changed, review the patch" >&2
    exit 1
  }
}
