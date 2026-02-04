# 在新服务器上恢复 E2B 环境

## 备份信息

**最新备份：** `e2b-primihub-20260204_165440.tar.gz`
- **大小：** 80M (83,495,830 bytes)
- **位置：** `oss://primihub/backup/e2b/`
- **备份时间：** 2026-02-04 16:57:58
- **MD5：** CEEEB31823E1D342A0581B86F1391CFC

## 备份内容

- PostgreSQL e2b 数据库 (96K)
- 配置文件和 Nomad jobs (6个)
- 二进制文件：api (72M), orchestrator (96M), envd (15M)
- Firecracker 和内核文件
- E2B 模板 (metadata + rootfs)

## 前置要求

### 1. 安装基础依赖

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y postgresql-client docker.io jq wget curl

# 安装 Go (如需编译)
wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc
```

### 2. 安装 ossutil

```bash
# 下载 ossutil
wget https://gosspublic.alicdn.com/ossutil/1.7.19/ossutil64 -O ~/bin/ossutil
chmod +x ~/bin/ossutil

# 配置 OSS 访问
ossutil config
# 输入：
# - Endpoint: oss-cn-hangzhou.aliyuncs.com (根据实际区域)
# - AccessKeyID: 你的 AccessKey ID
# - AccessKeySecret: 你的 AccessKey Secret
```

### 3. 安装 Nomad

```bash
# 下载 Nomad
wget https://releases.hashicorp.com/nomad/1.7.3/nomad_1.7.3_linux_amd64.zip
unzip nomad_1.7.3_linux_amd64.zip
sudo mv nomad /usr/local/bin/
```

## 快速恢复步骤

### 方法一：使用自动恢复脚本（推荐）

```bash
# 1. 克隆或下载 infra 仓库
git clone <your-repo-url> /mnt/data1/pcloud/infra
cd /mnt/data1/pcloud/infra/local-deploy

# 2. 自动恢复最新备份（无交互）
./backup-e2b.sh --restore-latest
```

### 方法二：手动恢复

#### 步骤 1: 下载备份

```bash
# 创建工作目录
mkdir -p /tmp/e2b-restore
cd /tmp/e2b-restore

# 下载最新备份
ossutil cp oss://primihub/backup/e2b/e2b-primihub-20260204_165440.tar.gz ./

# 解压
tar -xzf e2b-primihub-20260204_165440.tar.gz
```

#### 步骤 2: 恢复数据库

```bash
# 启动 PostgreSQL (如果使用 Docker)
docker run -d --name postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  postgres:15

# 等待数据库启动
sleep 10

# 创建数据库
PGPASSWORD=postgres psql -h 127.0.0.1 -U postgres -c "CREATE DATABASE e2b;"

# 恢复数据库
PGPASSWORD=postgres pg_restore -h 127.0.0.1 -U postgres -d e2b -c db/e2b.dump
```

#### 步骤 3: 恢复配置文件

```bash
# 创建目录结构
mkdir -p /mnt/data1/pcloud/infra/local-deploy/{jobs,scripts}

# 恢复配置
cp config/.env.local /mnt/data1/pcloud/infra/local-deploy/
cp config/nomad-dev.hcl /mnt/data1/pcloud/infra/local-deploy/
cp config/jobs/*.hcl /mnt/data1/pcloud/infra/local-deploy/jobs/
cp config/scripts/*.sh /mnt/data1/pcloud/infra/local-deploy/scripts/
chmod +x /mnt/data1/pcloud/infra/local-deploy/scripts/*.sh
```

#### 步骤 4: 恢复二进制文件

```bash
# 创建目录
mkdir -p /mnt/data1/pcloud/infra/packages/{api,orchestrator,envd}/bin

# 恢复二进制
cp bin/api /mnt/data1/pcloud/infra/packages/api/bin/
cp bin/orchestrator /mnt/data1/pcloud/infra/packages/orchestrator/bin/
cp bin/envd /mnt/data1/pcloud/infra/packages/envd/bin/

# 设置执行权限
chmod +x /mnt/data1/pcloud/infra/packages/*/bin/*
```

#### 步骤 5: 恢复 Firecracker 和内核

```bash
# Firecracker
mkdir -p /mnt/data1/pcloud/infra/packages/fc-versions/builds
cp -r fc/* /mnt/data1/pcloud/infra/packages/fc-versions/builds/
chmod +x /mnt/data1/pcloud/infra/packages/fc-versions/builds/*/firecracker

# 内核
mkdir -p /mnt/data1/pcloud/infra/packages/fc-kernels
cp -r kernels/* /mnt/data1/pcloud/infra/packages/fc-kernels/
```

#### 步骤 6: 恢复模板

```bash
# 创建存储目录
sudo mkdir -p /home/primihub/e2b-storage/e2b-template-storage

# 恢复模板 metadata
for tdir in templates/*/; do
    build_id=$(basename "$tdir")
    sudo mkdir -p "/home/primihub/e2b-storage/e2b-template-storage/$build_id"
    sudo cp "$tdir"/* "/home/primihub/e2b-storage/e2b-template-storage/$build_id/"
done

# 下载 rootfs 文件（如果有）
# 注意：rootfs 文件单独存储在 OSS 的 rootfs/ 目录下
for tdir in templates/*/; do
    build_id=$(basename "$tdir")
    if [ -f "$tdir/rootfs.md5" ]; then
        echo "下载 $build_id 的 rootfs..."
        ossutil cp "oss://primihub/backup/e2b/rootfs/${build_id}.ext4.gz" "/tmp/${build_id}.ext4.gz"
        gunzip -c "/tmp/${build_id}.ext4.gz" | sudo tee "/home/primihub/e2b-storage/e2b-template-storage/$build_id/rootfs.ext4" > /dev/null
        rm -f "/tmp/${build_id}.ext4.gz"
    fi
done

# 设置权限
sudo chown -R $(whoami):$(whoami) /home/primihub/e2b-storage
```

#### 步骤 7: 创建存储目录结构

```bash
sudo mkdir -p /home/primihub/e2b-storage/{e2b-template-cache,e2b-chunk-cache,e2b-build-cache,e2b-fc-vm,e2b-orchestrator,e2b-sandbox-cache,e2b-snapshot-cache,nomad-local}
sudo chown -R $(whoami):$(whoami) /home/primihub/e2b-storage
```

## 启动服务

### 1. 启动基础设施

```bash
cd /mnt/data1/pcloud/infra/local-deploy

# 启动 PostgreSQL, Redis, ClickHouse (如果使用 Docker Compose)
docker compose up -d
```

### 2. 启动 Nomad

```bash
# 启动 Nomad 服务器
./scripts/start-nomad.sh

# 等待 Nomad 启动
sleep 10
```

### 3. 部署 E2B 服务

```bash
# 部署 Orchestrator
nomad job run jobs/orchestrator.hcl

# 部署 API
nomad job run jobs/api.hcl

# 检查服务状态
nomad job status orchestrator
nomad job status api
```

## 验证恢复

### 1. 检查服务状态

```bash
# 检查 Nomad jobs
nomad job status

# 检查 Orchestrator 日志
ALLOC_ID=$(nomad job allocs orchestrator | grep running | head -1 | awk '{print $1}')
nomad alloc logs $ALLOC_ID orchestrator

# 检查 API 日志
ALLOC_ID=$(nomad job allocs api | grep running | head -1 | awk '{print $1}')
nomad alloc logs $ALLOC_ID api
```

### 2. 测试 API

```bash
# 健康检查
curl http://localhost:3000/health

# 创建测试 sandbox
curl -X POST http://localhost:3000/sandboxes \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-api-key" \
  -d '{
    "templateID": "base",
    "timeout": 300
  }'
```

### 3. 测试 Fragments 预览

```bash
# 启动 Fragments (如果需要)
cd /mnt/data1/pcloud/infra/fragments
npm run dev

# 测试预览功能
curl -X POST http://localhost:3001/api/sandbox \
  -H "Content-Type: application/json" \
  -d '{
    "fragment": {
      "template": "code-interpreter-v1",
      "code": "print(\"Hello World\")"
    }
  }'
```

## 故障排查

### 问题：Orchestrator 启动失败

**检查日志：**
```bash
nomad job status orchestrator
ALLOC_ID=$(nomad job allocs orchestrator | head -2 | tail -1 | awk '{print $1}')
nomad alloc logs $ALLOC_ID orchestrator 2>&1
```

**常见原因：**
1. Firecracker 权限不足 → 检查 sudo 配置
2. 模板目录不存在 → 确认 `/home/primihub/e2b-storage/e2b-template-storage` 存在
3. 数据库连接失败 → 检查 PostgreSQL 是否运行

### 问题：模板加载失败

**检查模板：**
```bash
ls -lh /home/primihub/e2b-storage/e2b-template-storage/
```

**验证模板完整性：**
```bash
for tdir in /home/primihub/e2b-storage/e2b-template-storage/*/; do
    build_id=$(basename "$tdir")
    echo "检查 $build_id:"
    ls -lh "$tdir"
    [ -f "$tdir/metadata.json" ] && echo "  ✓ metadata.json" || echo "  ✗ metadata.json 缺失"
    [ -f "$tdir/rootfs.ext4" ] && echo "  ✓ rootfs.ext4" || echo "  ✗ rootfs.ext4 缺失"
done
```

### 问题：API 无法连接 Orchestrator

**检查网络：**
```bash
# 检查 Orchestrator gRPC 端口
netstat -tlnp | grep 5008

# 测试连接
curl http://localhost:5008/health
```

## 定期备份

在新服务器上设置定期备份：

```bash
# 添加到 crontab
crontab -e

# 每天凌晨 2 点执行增量备份
0 2 * * * /mnt/data1/pcloud/infra/local-deploy/backup-e2b.sh >> /var/log/e2b-backup.log 2>&1

# 每周日凌晨 3 点执行完整备份
0 3 * * 0 /mnt/data1/pcloud/infra/local-deploy/backup-e2b.sh --full >> /var/log/e2b-backup.log 2>&1
```

## 相关文档

- **备份脚本：** `/mnt/data1/pcloud/infra/local-deploy/backup-e2b.sh`
- **恢复脚本：** `/mnt/data1/pcloud/infra/local-deploy/scripts/restore-templates-from-oss.sh`
- **主文档：** `/mnt/data1/pcloud/infra/CLAUDE.md`

## 支持

如有问题，请查看：
1. Nomad 日志：`nomad job status <job-name>`
2. 系统日志：`journalctl -u nomad`
3. 备份日志：`/var/log/e2b-backup.log`
