#!/bin/bash
# build-template运行脚本
# 需要sudo权限

set -e

echo "======================================================================="
echo "  运行 build-template 创建 E2B 模板"
echo "======================================================================="
echo ""

# 设置环境变量
export STORAGE_PROVIDER=Local
export ARTIFACTS_REGISTRY_PROVIDER=Local
export LOCAL_TEMPLATE_STORAGE_BASE_PATH=/home/primihub/e2b-storage/e2b-template-storage
export BUILD_CACHE_BUCKET_NAME=/home/primihub/e2b-storage/e2b-build-cache
export TEMPLATE_CACHE_DIR=/home/primihub/e2b-storage/e2b-template-cache
export POSTGRES_CONNECTION_STRING="postgresql://postgres:postgres@localhost:5432/postgres?sslmode=disable"

# 参数
BUILD_ID="9ac9c8b9-9b8b-476c-9238-8266af308c32"
TEMPLATE_ID="base"
KERNEL_VERSION="vmlinux-5.10.223"
FIRECRACKER_VERSION="v1.12.1_d990331"

echo "配置信息:"
echo "  Build ID: $BUILD_ID"
echo "  Template ID: $TEMPLATE_ID"
echo "  Kernel: $KERNEL_VERSION"
echo "  Firecracker: $FIRECRACKER_VERSION"
echo ""
echo "存储路径:"
echo "  Template Storage: $LOCAL_TEMPLATE_STORAGE_BASE_PATH"
echo "  Template Cache: $TEMPLATE_CACHE_DIR"
echo "  Build Cache: $BUILD_CACHE_BUCKET_NAME"
echo ""

# 检查工具是否存在
if [ ! -f "./bin/build-template" ]; then
    echo "❌ 错误: build-template 工具不存在"
    exit 1
fi

echo "开始构建模板..."
echo "注意: 此过程可能需要5-10分钟，请耐心等待"
echo ""

# 运行build-template
./bin/build-template \
  -build="$BUILD_ID" \
  -template="$TEMPLATE_ID" \
  -kernel="$KERNEL_VERSION" \
  -firecracker="$FIRECRACKER_VERSION"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ 模板构建成功！"
    echo ""
    echo "模板文件位置:"
    echo "  $LOCAL_TEMPLATE_STORAGE_BASE_PATH/$BUILD_ID/"
    ls -lh "$LOCAL_TEMPLATE_STORAGE_BASE_PATH/$BUILD_ID/" 2>/dev/null || echo "  (需要sudo权限查看)"
else
    echo ""
    echo "❌ 模板构建失败，退出码: $EXIT_CODE"
    exit $EXIT_CODE
fi
