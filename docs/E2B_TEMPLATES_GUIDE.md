# E2B 模板指南

> 更新时间: 2026-01-16

本文档记录 E2B 沙箱系统中的模板情况，包括已构建模板、源码定义和创建方法。

---

## 一、已构建模板清单

### 存储位置

```
/mnt/sdb/e2b-storage/e2b-template-storage/
```

### 模板列表

| # | 模板 ID | Build ID | rootfs 大小 | 状态 | 说明 |
|---|---------|----------|-------------|------|------|
| 1 | `base-template-000-0000-0000-000000000001` | `9ac9c8b9-9b8b-476c-9238-8266af308c32` | 1.0 GB | ✅ 正常 | 基础模板 |
| 2 | `desktop-template-000-0000-0000-000000000001` | `8f9398ba-14d1-469c-aa2e-169f890a2520` | 3.0 GB | ✅ 正常 | 桌面环境模板 |
| 3 | `code-interpreter-v1` | `15dc8110-c9da-49a7-96f9-d221e06425c8` | 1.0 GB | ✅ 正常 | Python 代码解释器 |
| 4 | `code-interpreter-v1` | `c0de1a73-7000-4000-a000-000000000001` | 符号链接 | ⚠️ 别名 | 链接到 base 模板 |

### 模板配置

所有模板使用统一的底层配置：

```json
{
  "kernelVersion": "vmlinux-5.10.223",
  "firecrackerVersion": "v1.12.1_d990331",
  "envdVersion": "0.2.0"
}
```

---

## 二、数据库注册信息

模板在 PostgreSQL 数据库 `e2b` 中注册：

| 模板 ID | 公开 | 构建数 | 创建时间 |
|---------|------|--------|----------|
| `code-interpreter-v1` | ✅ | 1 | 2026-01-12 |
| `desktop-template-000-0000-0000-000000000001` | ✅ | 1 | 2026-01-11 |
| `base` | ✅ | 1 | 2026-01-11 |

查询命令：
```bash
PGPASSWORD=postgres psql -h 127.0.0.1 -U postgres -d e2b \
  -c "SELECT id, public, build_count, created_at FROM envs ORDER BY created_at DESC;"
```

---

## 三、模板源码定义

### 1. 代码解释器模板

**位置**: `infra/templates/code-interpreter-local/`

```
code-interpreter-local/
├── template.py              # E2B SDK 模板定义
├── create_template.sh       # 构建脚本 v1
├── create_template_v2.sh    # 构建脚本 v2
├── create_template_v3.sh    # 构建脚本 v3
├── create_template_v4.sh    # 构建脚本 v4 (最新)
├── requirements.txt         # Python 依赖
├── server/                  # FastAPI 服务器
├── startup_scripts/         # 启动脚本
├── jupyter_server_config.py # Jupyter 配置
└── start-up.sh              # 启动入口
```

**功能**:
- Python/Jupyter 代码执行环境
- 支持多种 Kernel (Python, R, JavaScript, Deno, Bash, Java)
- 内置 FastAPI 服务器

### 2. Web 应用模板 (Fragments)

**位置**: `infra/fragments/sandbox-templates/`

| 模板 | 基础镜像 | 主要依赖 | 状态 |
|------|----------|----------|------|
| **gradio-developer** | Python 3.9 | gradio, pandas, numpy, matplotlib | 📝 源码就绪 |
| **nextjs-developer** | Node 24 | Next.js 14.2.33, shadcn UI | 📝 源码就绪 |
| **streamlit-developer** | Python 3.9 | streamlit | 📝 源码就绪 |
| **vue-developer** | Node 24 | Nuxt, Vue | 📝 源码就绪 |

> ⚠️ 这些模板有源码定义，但尚未构建到 e2b-template-storage

---

## 四、模板结构说明

### 存储结构

每个已构建的模板在存储中的结构：

```
e2b-template-storage/{build-id}/
├── metadata.json     # 模板元数据
└── rootfs.ext4       # 文件系统镜像 (1-3GB)
```

### metadata.json 示例

```json
{
  "kernelVersion": "vmlinux-5.10.223",
  "firecrackerVersion": "v1.12.1_d990331",
  "buildID": "9ac9c8b9-9b8b-476c-9238-8266af308c32",
  "templateID": "base-template-000-0000-0000-000000000001"
}
```

---

## 五、创建模板方法

### 方法1: 使用 build-template 工具

```bash
# 位置: infra/packages/orchestrator/bin/build-template
./build-template \
  -template=my-template-id \
  -build=my-build-uuid \
  -kernel=vmlinux-5.10.223 \
  -firecracker=v1.12.1_d990331
```

### 方法2: 使用自动构建脚本

```bash
# 位置: infra/local-deploy/scripts/build-template-auto.sh
./build-template-auto.sh
```

自动化流程：
1. 检查基础设施 (PostgreSQL)
2. 准备内核文件
3. 拉取 Docker 镜像
4. 创建 ext4 文件系统
5. 导出容器到 rootfs
6. 生成 metadata.json

### 方法3: 编写 template.ts 定义

```typescript
// infra/fragments/sandbox-templates/my-template/template.ts
import { Template, wait_for_url } from '@anthropic/sdk'

export default Template()
  .from_image("python:3.12")           // 基础镜像
  .apt_install(["git", "curl"])        // 系统包
  .pip_install("pandas numpy")         // Python包
  .npm_install("typescript")           // Node包
  .copy("./app", "/app")               // 复制文件
  .set_start_cmd(
    "python /app/server.py",
    wait_for_url("http://localhost:8000/health")
  )
```

### 方法4: 使用 create_template.sh 脚本

```bash
cd infra/templates/code-interpreter-local
./create_template_v4.sh
```

---

## 六、模板维护

### 查看模板状态

```bash
# 列出所有模板目录
ls -la /mnt/sdb/e2b-storage/e2b-template-storage/

# 查看模板元数据
cat /mnt/sdb/e2b-storage/e2b-template-storage/{build-id}/metadata.json

# 查看数据库记录
PGPASSWORD=postgres psql -h 127.0.0.1 -U postgres -d e2b \
  -c "SELECT * FROM envs;"
```

### 清理无效模板

```bash
# 删除空目录或无效构建
rm -rf /mnt/sdb/e2b-storage/e2b-template-storage/{invalid-build-id}
```

### 备份模板

```bash
# 备份 rootfs
cp rootfs.ext4 rootfs.ext4.backup-$(date +%Y%m%d)
```

---

## 七、缓存目录

| 目录 | 用途 |
|------|------|
| `e2b-template-storage/` | 模板主存储 |
| `e2b-template-cache/` | 模板读缓存 |
| `e2b-chunk-cache/` | 内存/快照块缓存 |
| `e2b-sandbox-cache/` | 沙箱实例缓存 |
| `e2b-build-cache/` | 构建过程缓存 |

---

## 八、相关文档

- [E2B 集成指南](../../docs/E2B_INTEGRATION_GUIDE.md)
- [E2B 架构设计](../../docs/ARCHITECTURE_E2B_INTEGRATION.md)
- [E2B Desktop 集成](../../docs/E2B_DESKTOP_INTEGRATION_SUMMARY.md)
- [VM 故障排除](../local-deploy/E2B_VM_TROUBLESHOOTING.md)

---

## 九、统计信息

| 类别 | 数量 | 说明 |
|------|------|------|
| **已构建可用** | 3 个 | base, desktop, code-interpreter |
| **源码待构建** | 4 个 | gradio, nextjs, streamlit, vue |
| **总存储占用** | ~5 GB | 不含备份 |
