#!/bin/bash
set -euo pipefail

WORKFLOW_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")" && pwd)}"

# files 复制开始
# 把 files/common 和 files/dev-<设备名> 复制到构建树的 files/, 构建时打进固件根文件系统.
# <设备名> 取自 CONFIG_FILE(.config-<设备名>)的后缀.
DEVICE_DIR="${CONFIG_FILE:?CONFIG_FILE is not set}"
DEVICE_DIR="dev-${DEVICE_DIR#.config-}"
for dir in common "$DEVICE_DIR"; do
  if [ ! -d "$WORKFLOW_ROOT/files/$dir" ]; then
    echo "ERROR: $WORKFLOW_ROOT/files/$dir not found" >&2
    exit 1
  fi
done
mkdir -p files
cp -a "$WORKFLOW_ROOT/files/common/." files/
cp -a "$WORKFLOW_ROOT/files/$DEVICE_DIR/." files/
find files -name .gitkeep -delete
# files 复制结束
