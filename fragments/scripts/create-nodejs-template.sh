#!/bin/bash
# 创建包含 Node.js 的 E2B 模板
# 用于支持 Fragments 的 Next.js 开发功能

set -e

# 加载环境变量配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCLOUD_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [ -f "$PCLOUD_ROOT/config/env.sh" ]; then
    source "$PCLOUD_ROOT/config/env.sh"
fi

# 设置路径（使用环境变量或默认值）
E2B_STORAGE_PATH="${E2B_STORAGE_PATH:-$PCLOUD_ROOT/../e2b-storage}"

echo "=========================================="
echo "  创建 Node.js E2B 模板"
echo "=========================================="
echo ""

# 配置
BASE_TEMPLATE="base"
NEW_TEMPLATE_NAME="base-nodejs"
STORAGE_PATH="$E2B_STORAGE_PATH/e2b-template-storage"

# 检查是否有 base 模板
echo "1. 检查 base 模板..."
BASE_BUILD_ID=$(curl -s -H "X-API-Key: e2b_53ae1fed82754c17ad8077fbc8bcdd90" \
  "http://localhost:3000/templates/${BASE_TEMPLATE}" | jq -r '.builds[0].id // empty')

if [ -z "$BASE_BUILD_ID" ]; then
  echo "❌ 未找到 base 模板"
  exit 1
fi

echo "✓ 找到 base 模板: $BASE_BUILD_ID"
echo ""

# 检查 rootfs 文件
ROOTFS_PATH="${STORAGE_PATH}/${BASE_BUILD_ID}/rootfs.ext4"
if [ ! -f "$ROOTFS_PATH" ]; then
  echo "❌ rootfs 文件不存在: $ROOTFS_PATH"
  exit 1
fi

echo "✓ rootfs 文件存在"
echo ""

# 创建新的 build ID
NEW_BUILD_ID=$(uuidgen)
NEW_TEMPLATE_DIR="${STORAGE_PATH}/${NEW_BUILD_ID}"

echo "2. 创建新模板目录..."
echo "   新 Build ID: $NEW_BUILD_ID"
sudo mkdir -p "$NEW_TEMPLATE_DIR"

# 复制 rootfs
echo ""
echo "3. 复制 rootfs 文件..."
sudo cp "$ROOTFS_PATH" "${NEW_TEMPLATE_DIR}/rootfs.ext4"
echo "✓ rootfs 已复制"

# 挂载 rootfs
echo ""
echo "4. 挂载 rootfs..."
sudo mkdir -p /mnt/e2b-rootfs
sudo mount -o loop "${NEW_TEMPLATE_DIR}/rootfs.ext4" /mnt/e2b-rootfs
echo "✓ rootfs 已挂载到 /mnt/e2b-rootfs"

# 安装 Node.js
echo ""
echo "5. 安装 Node.js 18.x..."
sudo chroot /mnt/e2b-rootfs /bin/bash -c "
  set -e
  export DEBIAN_FRONTEND=noninteractive

  # 更新包列表
  apt-get update -qq

  # 安装必要的依赖
  apt-get install -y -qq curl ca-certificates gnupg

  # 添加 NodeSource 仓库
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -

  # 安装 Node.js
  apt-get install -y -qq nodejs

  # 验证安装
  node --version
  npm --version

  # 清理
  apt-get clean
  rm -rf /var/lib/apt/lists/*
"

echo "✓ Node.js 安装完成"

# 验证安装
echo ""
echo "6. 验证 Node.js 安装..."
NODE_VERSION=$(sudo chroot /mnt/e2b-rootfs node --version)
NPM_VERSION=$(sudo chroot /mnt/e2b-rootfs npm --version)
echo "   Node.js: $NODE_VERSION"
echo "   npm: $NPM_VERSION"

# 卸载 rootfs
echo ""
echo "7. 卸载 rootfs..."
sudo sync
sudo umount /mnt/e2b-rootfs
echo "✓ rootfs 已卸载"

# 创建 metadata.json
echo ""
echo "8. 创建 metadata.json..."
cat > /tmp/metadata.json << EOF
{
  "templateID": "${NEW_TEMPLATE_NAME}",
  "buildID": "${NEW_BUILD_ID}",
  "aliases": ["${NEW_TEMPLATE_NAME}"],
  "cpuCount": 2,
  "memoryMB": 512,
  "diskSizeMB": 1024,
  "public": true,
  "description": "Base template with Node.js 18.x and npm for web development"
}
EOF

sudo cp /tmp/metadata.json "${NEW_TEMPLATE_DIR}/metadata.json"
sudo chown primihub:primihub "${NEW_TEMPLATE_DIR}/metadata.json"
echo "✓ metadata.json 已创建"

# 清理缓存
echo ""
echo "9. 清理模板缓存..."
sudo rm -rf "$E2B_STORAGE_PATH/e2b-chunk-cache/*"
sudo rm -rf "$E2B_STORAGE_PATH/e2b-template-cache/*"
echo "✓ 缓存已清理"

echo ""
echo "=========================================="
echo "  ✅ 模板创建完成！"
echo "=========================================="
echo ""
echo "新模板信息:"
echo "  模板 ID: ${NEW_TEMPLATE_NAME}"
echo "  Build ID: ${NEW_BUILD_ID}"
echo "  位置: ${NEW_TEMPLATE_DIR}"
echo ""
echo "下一步:"
echo "  1. 重启 orchestrator 服务以加载新模板"
echo "  2. 更新 Fragments 配置使用新模板:"
echo "     'nextjs-developer-dev': '${NEW_TEMPLATE_NAME}'"
echo ""
